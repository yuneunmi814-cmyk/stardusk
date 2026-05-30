# 경로: backend/app/api/v1/trip.py
# 실시간 동선 수집 라우터 (Phase 3)
#  - POST /api/v1/trip                  : 여정 시작(좌표 업로드에 쓸 trip_id 발급)
#  - POST /api/v1/trip/coordinates      : GPS 좌표 배열 Bulk Insert + 동선/거리 갱신
#  - GET  /api/v1/trip/{trip_id}/path   : 누적 경로를 LineString 으로 조회(+Safe Zone 난독화)
#  - PATCH /api/v1/trip/{trip_id}/complete : 여정 종료
#
# 인증: 모든 엔드포인트 Bearer 토큰 필요. 본인 여정만 접근 가능.

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.core.validation import is_in_korea
from app.db.session import get_session
from app.schemas.trip import (
    Bounds,
    CoordinatesUpload,
    PathPoint,
    TripCreateData,
    TripCreateRequest,
    TripCreateResponse,
    TripPathData,
    TripPathResponse,
    UploadData,
    UploadResponse,
)
from app.services.obfuscate import load_safe_zone, obfuscate_path

router = APIRouter(prefix="/trip", tags=["trip"])


# --- SQL ---------------------------------------------------------------------
_INSERT_TRIP = text(
    """
    INSERT INTO user_trips (user_id, region, constellation_name, status, started_at)
    VALUES (:user_id, :region, :constellation_name, 'active', now())
    RETURNING id, status, started_at;
    """
)

_SELECT_TRIP_OWNER = text("SELECT user_id, status FROM user_trips WHERE id = :trip_id;")

_MAX_SEQ = text("SELECT COALESCE(MAX(sequence), 0) FROM trip_coordinates WHERE trip_id = :trip_id;")

# 좌표 1건 INSERT (executemany 로 배치 실행)
_INSERT_COORD = text(
    """
    INSERT INTO trip_coordinates (trip_id, location, accuracy_m, sequence, recorded_at)
    VALUES (
        :trip_id,
        ST_SetSRID(ST_MakePoint(:lng, :lat), 4326),
        :accuracy_m, :sequence, :recorded_at
    );
    """
)

# 좌표 누적 후 여정 집계 갱신(거리=geography 길이, 경로=시간순 LineString)
_REFRESH_TRIP = text(
    """
    UPDATE user_trips ut SET
        point_count     = sub.cnt,
        distance_meters = COALESCE(round(sub.dist)::int, 0),
        path            = CASE WHEN sub.cnt >= 2 THEN sub.line ELSE NULL END,
        updated_at      = now()
    FROM (
        SELECT
            count(*) AS cnt,
            ST_MakeLine(location ORDER BY sequence) AS line,
            ST_Length(ST_MakeLine(location ORDER BY sequence)::geography) AS dist
        FROM trip_coordinates WHERE trip_id = :trip_id
    ) sub
    WHERE ut.id = :trip_id
    RETURNING ut.point_count, ut.distance_meters;
    """
)

_SELECT_TRIP_META = text(
    "SELECT user_id, point_count, distance_meters FROM user_trips WHERE id = :trip_id;"
)

_SELECT_COORDS = text(
    """
    SELECT sequence, ST_Y(location) AS lat, ST_X(location) AS lng, recorded_at
    FROM trip_coordinates
    WHERE trip_id = :trip_id
    ORDER BY sequence ASC;
    """
)

_COMPLETE_TRIP = text(
    "UPDATE user_trips SET status = 'completed', ended_at = now(), updated_at = now() "
    "WHERE id = :trip_id RETURNING id;"
)


# --- 공통 헬퍼 ----------------------------------------------------------------
async def _assert_owner(session: AsyncSession, trip_id: int, user_id: str) -> None:
    """여정 존재 + 소유자 검증. 실패 시 404/403."""
    row = (await session.execute(_SELECT_TRIP_OWNER, {"trip_id": trip_id})).first()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "code": "TRIP_NOT_FOUND", "message": "여정을 찾을 수 없습니다."},
        )
    if str(row[0]) != str(user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"status": "error", "code": "FORBIDDEN", "message": "본인의 여정만 접근할 수 있습니다."},
        )


# --- 엔드포인트 ---------------------------------------------------------------
@router.post("", response_model=TripCreateResponse, status_code=status.HTTP_201_CREATED,
             summary="여정 시작")
async def create_trip(
    body: TripCreateRequest,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TripCreateResponse:
    row = (await session.execute(_INSERT_TRIP, {
        "user_id": uuid.UUID(user["user_id"]),
        "region": body.region,
        "constellation_name": body.constellation_name,
    })).first()
    await session.commit()
    return TripCreateResponse(
        data=TripCreateData(trip_id=row[0], status=row[1], started_at=row[2])
    )


@router.post("/coordinates", response_model=UploadResponse, summary="실시간 GPS 좌표 Bulk 업로드")
async def upload_coordinates(
    body: CoordinatesUpload,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UploadResponse:
    await _assert_owner(session, body.trip_id, user["user_id"])

    # 좌표 방어: NaN/Inf 는 Pydantic(ge/le) 에서 걸러지지만, 한국 밖 이상치는 여기서 차단.
    #   GPS 노이즈/스푸핑으로 대한민국 영토 밖 좌표가 섞이면 동선/거리 계산이 오염되므로
    #   배치 전체를 거부하고 어떤 점이 문제인지 알려준다.
    for idx, c in enumerate(body.coordinates):
        if not is_in_korea(c.latitude, c.longitude):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "status": "error",
                    "code": "OUT_OF_SERVICE_AREA",
                    "message": f"{idx}번째 좌표가 대한민국 영토 밖입니다. 국내 좌표만 기록할 수 있어요.",
                },
            )

    # 이어붙일 시작 sequence 계산(기존 최대값 다음부터)
    start_seq = (await session.execute(_MAX_SEQ, {"trip_id": body.trip_id})).scalar_one()

    params = [
        {
            "trip_id": body.trip_id,
            "lng": c.longitude,
            "lat": c.latitude,
            "accuracy_m": c.accuracy_m,
            "sequence": start_seq + i + 1,
            "recorded_at": c.recorded_at,
        }
        for i, c in enumerate(body.coordinates)
    ]

    # Bulk Insert (executemany) → 여정 집계 갱신 → 단일 트랜잭션 커밋
    await session.execute(_INSERT_COORD, params)
    agg = (await session.execute(_REFRESH_TRIP, {"trip_id": body.trip_id})).first()
    await session.commit()

    return UploadResponse(
        data=UploadData(
            trip_id=body.trip_id,
            inserted=len(params),
            point_count=agg[0],
            distance_meters=agg[1],
        )
    )


@router.get("/{trip_id}/path", response_model=TripPathResponse, summary="여정 동선(LineString) 조회")
async def get_trip_path(
    trip_id: int,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TripPathResponse:
    meta = (await session.execute(_SELECT_TRIP_META, {"trip_id": trip_id})).first()
    if meta is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "code": "TRIP_NOT_FOUND", "message": "여정을 찾을 수 없습니다."},
        )
    if str(meta[0]) != str(user["user_id"]):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"status": "error", "code": "FORBIDDEN", "message": "본인의 여정만 접근할 수 있습니다."},
        )

    rows = (await session.execute(_SELECT_COORDS, {"trip_id": trip_id})).mappings().all()

    # Safe Zone 난독화 적용 (현재는 safe_center=None → 그대로 통과)
    safe_center = await load_safe_zone(user["user_id"])
    raw = [
        {"sequence": r["sequence"], "latitude": r["lat"], "longitude": r["lng"],
         "recorded_at": r["recorded_at"]}
        for r in rows
    ]
    obfuscated = obfuscate_path(raw, safe_center=safe_center)

    coordinates = [PathPoint(**c) for c in obfuscated]

    bounds = None
    line_geojson = None
    if coordinates:
        lats = [c.latitude for c in coordinates]
        lngs = [c.longitude for c in coordinates]
        bounds = Bounds(min_lat=min(lats), min_lng=min(lngs), max_lat=max(lats), max_lng=max(lngs))
    if len(coordinates) >= 2:
        line_geojson = {
            "type": "LineString",
            "coordinates": [[c.longitude, c.latitude] for c in coordinates],
        }

    return TripPathResponse(
        data=TripPathData(
            trip_id=trip_id,
            point_count=meta[1],
            distance_meters=meta[2],
            bounds=bounds,
            coordinates=coordinates,
            line_geojson=line_geojson,
        )
    )


@router.patch("/{trip_id}/complete", summary="여정 종료")
async def complete_trip(
    trip_id: int,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    await _assert_owner(session, trip_id, user["user_id"])
    await session.execute(_COMPLETE_TRIP, {"trip_id": trip_id})
    await session.commit()
    return {"status": "success", "message": "여정이 종료되었습니다.", "data": {"trip_id": trip_id}}
