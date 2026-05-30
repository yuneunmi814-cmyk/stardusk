# 경로: backend/app/api/v1/galaxy.py
# 은하수 조회 / my-galaxy 집계 라우터 (Phase 5)
#  GET /api/v1/stars/my-galaxy?trip_id=...
#    - trip_id 가 있으면 그 여정의 별만, 없으면 사용자의 전체 별 자취를 조회
#    - captured_at(촬영 시각) 오름차순 = '자취가 그려진 순서'
#    - 서버가 bounds(min/max 위경도)와 0~1 정규화 좌표(x_norm/y_norm)를 미리 계산
#      → 프런트는 화면 크기만 곱하면 즉시 별/별자리 선을 렌더할 수 있다.
#    - region + 별 개수 + 대표 감정으로 constellation_name 자동 생성
#
# 인증: Bearer 토큰 필요. 본인 별만 조회.

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_session
from app.schemas.galaxy import (
    GalaxyBounds,
    MyGalaxyData,
    MyGalaxyResponse,
    StarTrailPoint,
)
from app.services.constellation import (
    generate_constellation_name,
    pick_dominant_emotion,
)
from app.services.obfuscate import haversine_m, load_safe_zone, obfuscate_point

router = APIRouter(prefix="/stars", tags=["galaxy"])


# --- SQL ---------------------------------------------------------------------
# 사용자의 별 자취(시간순). trip_id 가 주어지면 해당 여정만 필터.
_SELECT_STARS = text(
    """
    SELECT
        s.id          AS star_id,
        s.trip_id     AS trip_id,
        ST_Y(s.location) AS lat,
        ST_X(s.location) AS lng,
        s.sky_color_hex  AS sky_color_hex,
        s.emotion_label  AS emotion_label,
        s.captured_at    AS captured_at
    FROM stars s
    WHERE s.user_id = :user_id
      AND (:trip_id IS NULL OR s.trip_id = :trip_id)
    ORDER BY s.captured_at ASC, s.id ASC;
    """
)

# 여정 존재 + 소유자 + 메타(지역/이름) 조회
_SELECT_TRIP = text(
    "SELECT user_id, region, constellation_name FROM user_trips WHERE id = :trip_id;"
)

# 전체 자취 조회 시 대표 지역 추정:
#   별 → (여정 region) 또는 (관광지 region) 을 모아 최빈값을 고른다.
_SELECT_REGION = text(
    """
    SELECT region, count(*) AS c FROM (
        SELECT ut.region
        FROM stars s JOIN user_trips ut ON s.trip_id = ut.id
        WHERE s.user_id = :user_id AND ut.region IS NOT NULL AND ut.region <> ''
        UNION ALL
        SELECT ts.region
        FROM stars s JOIN tour_spots ts ON s.tour_id = ts.content_id
        WHERE s.user_id = :user_id AND ts.region IS NOT NULL AND ts.region <> ''
    ) r
    GROUP BY region
    ORDER BY c DESC, region ASC
    LIMIT 1;
    """
)


def _normalize(value: float, lo: float, hi: float) -> float:
    """value 를 [lo, hi] 기준 0~1 로 정규화. 범위가 0이면 0.5(중앙)."""
    span = hi - lo
    if span <= 0:
        return 0.5
    return round((value - lo) / span, 4)


@router.get(
    "/my-galaxy",
    response_model=MyGalaxyResponse,
    summary="나의 은하수 조회(정규화 별 자취 + 별자리)",
)
async def get_my_galaxy(
    trip_id: int | None = Query(
        default=None, description="특정 여정의 별만 조회(미지정 시 전체 자취)"
    ),
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> MyGalaxyResponse:
    user_uuid = uuid.UUID(user["user_id"])

    # 1) trip_id 가 있으면 소유자 검증 + 메타 확보
    trip_region: str | None = None
    trip_name: str | None = None
    if trip_id is not None:
        trip = (await session.execute(_SELECT_TRIP, {"trip_id": trip_id})).first()
        if trip is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"status": "error", "code": "TRIP_NOT_FOUND", "message": "여정을 찾을 수 없습니다."},
            )
        if str(trip[0]) != str(user["user_id"]):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={"status": "error", "code": "FORBIDDEN", "message": "본인의 여정만 조회할 수 있습니다."},
            )
        trip_region, trip_name = trip[1], trip[2]

    # 2) 별 자취(시간순) 조회
    rows = (
        await session.execute(_SELECT_STARS, {"user_id": user_uuid, "trip_id": trip_id})
    ).mappings().all()

    # 3) 별이 없으면 빈 은하수 반환
    if not rows:
        region = trip_region
        if region is None:
            reg_row = (await session.execute(_SELECT_REGION, {"user_id": user_uuid})).first()
            region = reg_row[0] if reg_row else None
        name = trip_name or generate_constellation_name(region, 0, None)
        return MyGalaxyResponse(
            message="아직 별이 없어요. 하늘을 마주하고 첫 별을 띄워보세요.",
            data=MyGalaxyData(
                trip_id=trip_id,
                constellation_name=name,
                region=region,
                total_stars_count=0,
            ),
        )

    # 4) Safe Zone 난독화(거주지 보호) → 난독화된 좌표 기준으로 정규화
    safe_center = await load_safe_zone(user["user_id"])
    stars: list[dict] = []
    for r in rows:
        lat, lng, _ = obfuscate_point(r["lat"], r["lng"], safe_center)
        stars.append({
            "star_id": r["star_id"],
            "lat": lat,
            "lng": lng,
            "sky_color_hex": r["sky_color_hex"],
            "emotion_label": r["emotion_label"],
            "captured_at": r["captured_at"],
        })

    # 5) bounds 계산
    lats = [s["lat"] for s in stars]
    lngs = [s["lng"] for s in stars]
    min_lat, max_lat = min(lats), max(lats)
    min_lng, max_lng = min(lngs), max(lngs)
    bounds = GalaxyBounds(min_lat=min_lat, min_lng=min_lng, max_lat=max_lat, max_lng=max_lng)

    # 6) 정규화 좌표 + 누적 직선 거리 + path_line
    trail: list[StarTrailPoint] = []
    path_line: list[list[float]] = []
    distance_m = 0.0
    prev: tuple[float, float] | None = None
    for i, s in enumerate(stars):
        x_norm = _normalize(s["lng"], min_lng, max_lng)
        y_norm = _normalize(s["lat"], min_lat, max_lat)
        trail.append(StarTrailPoint(
            star_id=s["star_id"],
            sequence=i + 1,
            latitude=round(s["lat"], 6),
            longitude=round(s["lng"], 6),
            x_norm=x_norm,
            y_norm=y_norm,
            sky_color_hex=s["sky_color_hex"],
            emotion_label=s["emotion_label"],
            captured_at=s["captured_at"],
        ))
        path_line.append([x_norm, y_norm])
        if prev is not None:
            distance_m += haversine_m(prev[0], prev[1], s["lat"], s["lng"])
        prev = (s["lat"], s["lng"])

    # 7) 지역 결정(여정 > 전체 최빈값) + 별자리 이름 자동 생성
    region = trip_region
    if region is None:
        reg_row = (await session.execute(_SELECT_REGION, {"user_id": user_uuid})).first()
        region = reg_row[0] if reg_row else None

    dominant_emotion = pick_dominant_emotion(s["emotion_label"] for s in stars)
    # 여정에 저장된 이름이 있으면 존중하고, 없으면 자동 생성
    constellation_name = trip_name or generate_constellation_name(
        region, len(stars), dominant_emotion
    )

    return MyGalaxyResponse(
        data=MyGalaxyData(
            trip_id=trip_id,
            constellation_name=constellation_name,
            region=region,
            total_stars_count=len(stars),
            distance_meters=round(distance_m),
            bounds=bounds,
            stars_trail=trail,
            path_line=path_line,
        )
    )
