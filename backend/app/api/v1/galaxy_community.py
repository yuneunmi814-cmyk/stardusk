# 경로: backend/app/api/v1/galaxy_community.py
# setlog 실시간 공유 / 라이브 세션 라우터 (Phase 6)
#  POST /api/v1/community/rooms/{sky_video_id}/join       : 하늘방 입장(세션 생성 + 동접/참여자 반환)
#  POST /api/v1/community/rooms/{sky_video_id}/heartbeat  : 생존 신호(세션 갱신)
#  POST /api/v1/community/rooms/{sky_video_id}/leave      : 하늘방 퇴장(세션 제거)
#  GET  /api/v1/community/trending                        : 핫트렌드 피드(동접 + 강원 가중치)
#
# "우리는 서로 다른 공간에 있어도, 같은 시간대 같은 하늘 아래에 머문다."
# 인증: 모든 엔드포인트 Bearer 토큰 필요.

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_session
from app.schemas.community import (
    HeartbeatData,
    HeartbeatResponse,
    ParticipantProfile,
    RoomJoinData,
    RoomJoinResponse,
    RoomLeaveData,
    RoomLeaveResponse,
    TrendingData,
    TrendingItem,
    TrendingResponse,
)
from app.services.live_session import (
    ALIVE_WINDOW_SEC,
    broadcast_room_event,
)

router = APIRouter(prefix="/community", tags=["community"])

# 강원도(areaCode=32) 가산점: 동접 수에 더해지는 '상단 우선' 가중치.
#   최종 점수 = live_users_count + (강원이면 _GANGWON_BOOST)
#   → 강원 영상이 강하게 상단으로 올라오되, 압도적으로 핫한 타 지역 방도 묻히지 않게 한다.
_GANGWON_BOOST = 50


# --- SQL ---------------------------------------------------------------------
_VIDEO_EXISTS = text("SELECT 1 FROM sky_videos WHERE id = :vid;")

# 입장: 세션 생성(중복 입장이면 하트비트만 갱신)
_UPSERT_SESSION = text(
    """
    INSERT INTO live_sessions (sky_video_id, user_id, joined_at, last_heartbeat)
    VALUES (:vid, :uid, now(), now())
    ON CONFLICT (sky_video_id, user_id)
    DO UPDATE SET last_heartbeat = now()
    RETURNING joined_at;
    """
)

# 생존 신호: 하트비트 갱신(없으면 0행)
_TOUCH_SESSION = text(
    """
    UPDATE live_sessions SET last_heartbeat = now()
    WHERE sky_video_id = :vid AND user_id = :uid
    RETURNING id;
    """
)

_DELETE_SESSION = text(
    "DELETE FROM live_sessions WHERE sky_video_id = :vid AND user_id = :uid;"
)

# 방의 '살아있는' 동시 접속자 수
_COUNT_ALIVE = text(
    """
    SELECT count(*) FROM live_sessions
    WHERE sky_video_id = :vid
      AND last_heartbeat > now() - make_interval(secs => :alive);
    """
)

# 방에 함께 있는 유저 + 각자의 '마지막 별' 색/감정(아바타 프로필)
_PARTICIPANTS = text(
    """
    SELECT
        ls.user_id   AS user_id,
        ls.joined_at AS joined_at,
        st.sky_color_hex AS avatar_color,
        st.emotion_label AS emotion_label
    FROM live_sessions ls
    LEFT JOIN LATERAL (
        SELECT s.sky_color_hex, s.emotion_label
        FROM stars s
        WHERE s.user_id = ls.user_id
        ORDER BY s.captured_at DESC
        LIMIT 1
    ) st ON true
    WHERE ls.sky_video_id = :vid
      AND ls.last_heartbeat > now() - make_interval(secs => :alive)
    ORDER BY ls.joined_at ASC
    LIMIT :limit;
    """
)

# 트렌딩: 동접 + 강원(area_code=32) 가중치 정렬
_TRENDING = text(
    """
    WITH alive AS (
        SELECT sky_video_id, count(*) AS live_count
        FROM live_sessions
        WHERE last_heartbeat > now() - make_interval(secs => :alive)
        GROUP BY sky_video_id
    )
    SELECT
        sv.id            AS sky_video_id,
        sv.user_id       AS user_id,
        sv.tour_id       AS tour_id,
        ts.region        AS region,
        ts.spot_name     AS spot_name,
        sv.video_url     AS video_url,
        sv.thumbnail_url AS thumbnail_url,
        sv.sky_color_hex AS sky_color_hex,
        sv.emotion_label AS emotion_label,
        ST_Y(sv.geom)    AS latitude,
        ST_X(sv.geom)    AS longitude,
        COALESCE(a.live_count, 0) AS live_users_count,
        (ts.area_code = :area_code) AS is_gangwon,
        sv.created_at    AS created_at
    FROM sky_videos sv
    LEFT JOIN tour_spots ts ON sv.tour_id = ts.content_id
    LEFT JOIN alive a       ON a.sky_video_id = sv.id
    ORDER BY
        (COALESCE(a.live_count, 0)
            + CASE WHEN ts.area_code = :area_code THEN :boost ELSE 0 END) DESC,
        sv.created_at DESC
    LIMIT :limit OFFSET :offset;
    """
)


# --- 공통 헬퍼 ----------------------------------------------------------------
async def _assert_video_exists(session: AsyncSession, sky_video_id: uuid.UUID) -> None:
    exists = (await session.execute(_VIDEO_EXISTS, {"vid": sky_video_id})).first()
    if exists is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "code": "VIDEO_NOT_FOUND",
                    "message": "하늘 영상을 찾을 수 없습니다."},
        )


async def _alive_count(session: AsyncSession, sky_video_id: uuid.UUID) -> int:
    return (await session.execute(
        _COUNT_ALIVE, {"vid": sky_video_id, "alive": ALIVE_WINDOW_SEC}
    )).scalar_one()


# --- 엔드포인트 ---------------------------------------------------------------
@router.post(
    "/rooms/{sky_video_id}/join",
    response_model=RoomJoinResponse,
    summary="하늘방 입장(동시 접속 세션 생성)",
)
async def join_room(
    sky_video_id: uuid.UUID,
    participants_limit: int = Query(default=30, ge=1, le=100, description="반환할 참여자 프로필 수"),
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> RoomJoinResponse:
    await _assert_video_exists(session, sky_video_id)
    user_uuid = uuid.UUID(user["user_id"])

    # 1) 세션 생성/갱신
    joined = (await session.execute(
        _UPSERT_SESSION, {"vid": sky_video_id, "uid": user_uuid}
    )).scalar_one()
    await session.commit()

    # 2) 동접 수 + 참여자 프로필
    count = await _alive_count(session, sky_video_id)
    rows = (await session.execute(
        _PARTICIPANTS, {"vid": sky_video_id, "alive": ALIVE_WINDOW_SEC, "limit": participants_limit}
    )).mappings().all()

    participants = [
        ParticipantProfile(
            user_id=r["user_id"],
            # 본인은 토큰에서 닉네임을 알 수 있다(타인은 users 테이블 도입 전까지 None).
            nickname=user.get("nickname") if str(r["user_id"]) == user["user_id"] else None,
            avatar_color=r["avatar_color"],
            emotion_label=r["emotion_label"],
            joined_at=r["joined_at"],
        )
        for r in rows
    ]

    # 3) 같은 방 사람들에게 '입장' 브로드캐스트(best-effort)
    await broadcast_room_event(
        str(sky_video_id),
        "user_joined",
        {"user_id": user["user_id"], "live_users_count": count},
    )

    return RoomJoinResponse(
        data=RoomJoinData(
            sky_video_id=sky_video_id,
            live_users_count=count,
            participants=participants,
            joined_at=joined,
            realtime_channel=f"room:{sky_video_id}",
        )
    )


@router.post(
    "/rooms/{sky_video_id}/heartbeat",
    response_model=HeartbeatResponse,
    summary="하늘방 생존 신호(하트비트)",
)
async def heartbeat(
    sky_video_id: uuid.UUID,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> HeartbeatResponse:
    user_uuid = uuid.UUID(user["user_id"])
    touched = (await session.execute(
        _TOUCH_SESSION, {"vid": sky_video_id, "uid": user_uuid}
    )).first()

    # 세션이 이미 청소됐다면(오래 끊김) 재입장 처리
    if touched is None:
        await _assert_video_exists(session, sky_video_id)
        await session.execute(_UPSERT_SESSION, {"vid": sky_video_id, "uid": user_uuid})
    await session.commit()

    count = await _alive_count(session, sky_video_id)
    return HeartbeatResponse(
        data=HeartbeatData(sky_video_id=sky_video_id, live_users_count=count)
    )


@router.post(
    "/rooms/{sky_video_id}/leave",
    response_model=RoomLeaveResponse,
    summary="하늘방 퇴장(세션 제거)",
)
async def leave_room(
    sky_video_id: uuid.UUID,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> RoomLeaveResponse:
    user_uuid = uuid.UUID(user["user_id"])
    await session.execute(_DELETE_SESSION, {"vid": sky_video_id, "uid": user_uuid})
    await session.commit()

    count = await _alive_count(session, sky_video_id)
    await broadcast_room_event(
        str(sky_video_id),
        "user_left",
        {"user_id": user["user_id"], "live_users_count": count},
    )
    return RoomLeaveResponse(
        data=RoomLeaveData(sky_video_id=sky_video_id, live_users_count=count)
    )


@router.get(
    "/trending",
    response_model=TrendingResponse,
    summary="핫트렌드 하늘 피드(동접 + 강원 가중치)",
)
async def trending_feed(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TrendingResponse:
    rows = (await session.execute(_TRENDING, {
        "alive": ALIVE_WINDOW_SEC,
        "area_code": "32",          # 강원도
        "boost": _GANGWON_BOOST,
        "limit": limit,
        "offset": offset,
    })).mappings().all()

    items = [
        TrendingItem(
            sky_video_id=r["sky_video_id"],
            user_id=r["user_id"],
            tour_id=r["tour_id"],
            region=r["region"],
            spot_name=r["spot_name"],
            video_url=r["video_url"],
            thumbnail_url=r["thumbnail_url"],
            sky_color_hex=r["sky_color_hex"],
            emotion_label=r["emotion_label"],
            latitude=round(float(r["latitude"]), 6),
            longitude=round(float(r["longitude"]), 6),
            live_users_count=int(r["live_users_count"]),
            is_gangwon=bool(r["is_gangwon"]),
            created_at=r["created_at"],
        )
        for r in rows
    ]
    return TrendingResponse(data=TrendingData(total=len(items), items=items))
