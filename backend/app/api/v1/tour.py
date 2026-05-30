# 경로: backend/app/api/v1/tour.py
# 관광지 조회 라우터 (Phase 2)
#  - GET /api/v1/tour/spots : 현재 위경도 + 반경으로 근처 정화 스팟 조회
#  - PostGIS ST_DWithin 으로 GIST 인덱스를 타며, 거리는 geography 캐스팅으로 미터 단위 계산.
#
# 인증: 설계서/명세서 기준 Bearer 토큰 필요(get_current_user).

from fastapi import APIRouter, Depends, Query
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.core.validation import ensure_korea_coords
from app.db.session import get_session
from app.schemas.tour import TourSpotOut, TourSpotsResponse

router = APIRouter(prefix="/tour", tags=["tour"])

# geography 캐스팅으로 미터 단위 ST_DWithin/ST_Distance 사용.
# 입력 점은 ST_MakePoint(경도, 위도) → SRID 4326.
_NEARBY_SQL = text(
    """
    SELECT
        content_id AS tour_id,
        spot_name,
        region,
        ST_Y(location) AS latitude,
        ST_X(location) AS longitude,
        ST_Distance(
            location::geography,
            ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
        ) AS distance_meters
    FROM tour_spots
    WHERE ST_DWithin(
        location::geography,
        ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,
        :radius
    )
    ORDER BY distance_meters ASC
    LIMIT :limit;
    """
)


@router.get("/spots", response_model=TourSpotsResponse, summary="내 주변 정화 스팟 조회")
async def get_nearby_spots(
    latitude: float = Query(..., description="현재 위도", examples=[37.7914]),
    longitude: float = Query(..., description="현재 경도", examples=[128.9194]),
    radius: int = Query(1000, ge=1, le=20000, description="반경(m), 최대 20km"),
    limit: int = Query(50, ge=1, le=200),
    _user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TourSpotsResponse:
    # 좌표 유효성 검증 (범위 + NaN/Inf + 대한민국 영토 범위)
    ensure_korea_coords(latitude, longitude)

    result = await session.execute(
        _NEARBY_SQL, {"lng": longitude, "lat": latitude, "radius": radius, "limit": limit}
    )
    rows = result.mappings().all()

    spots = [
        TourSpotOut(
            tour_id=row["tour_id"],
            spot_name=row["spot_name"],
            region=row["region"],
            latitude=round(row["latitude"], 6),
            longitude=round(row["longitude"], 6),
            distance_meters=round(row["distance_meters"]),
        )
        for row in rows
    ]
    return TourSpotsResponse(data=spots)
