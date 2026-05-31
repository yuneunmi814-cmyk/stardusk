# 경로: backend/app/api/v1/tour.py
# 관광지 조회/검색 라우터 — 하이브리드 위치 탐색의 백엔드.
#  - GET /api/v1/tour/spots   : 기준 위경도 + 반경으로 주변 명소(지도 마커/거리순)
#  - GET /api/v1/tour/search  : 키워드 + 지역(시·도/시·군·구) 필터 통합 검색(리스트 탐색)
#  - GET /api/v1/tour/regions : 지역 필터용 시·도 → 시·군·구 목록
#
# PostGIS ST_DWithin/ST_Distance(geography 캐스팅, 미터 단위)로 GIST 인덱스를 탄다.
# 인증: Bearer 토큰 필요(get_current_user).

from fastapi import APIRouter, Depends, Query
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.core.validation import ensure_korea_coords
from app.db.session import get_session
from app.schemas.tour import (
    RegionGroup,
    RegionsResponse,
    TourSearchData,
    TourSearchResponse,
    TourSpotOut,
    TourSpotsResponse,
)

router = APIRouter(prefix="/tour", tags=["tour"])

# 입력 점은 ST_MakePoint(경도, 위도) → SRID 4326. 거리는 geography 캐스팅으로 미터.
_NEARBY_SQL = text(
    """
    SELECT
        content_id AS tour_id,
        spot_name, region, address, image_url,
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


def _row_to_spot(row, *, with_distance: bool) -> TourSpotOut:
    return TourSpotOut(
        tour_id=row["tour_id"],
        spot_name=row["spot_name"],
        region=row["region"],
        address=row["address"],
        image_url=row["image_url"],
        latitude=round(row["latitude"], 6),
        longitude=round(row["longitude"], 6),
        distance_meters=(
            round(row["distance_meters"])
            if with_distance and row["distance_meters"] is not None
            else None
        ),
    )


@router.get("/spots", response_model=TourSpotsResponse, summary="내 주변 명소(지도 마커)")
async def get_nearby_spots(
    latitude: float = Query(..., description="기준 위도", examples=[37.7914]),
    longitude: float = Query(..., description="기준 경도", examples=[128.9194]),
    radius: int = Query(3000, ge=1, le=50000, description="반경(m), 최대 50km"),
    limit: int = Query(100, ge=1, le=300),
    _user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TourSpotsResponse:
    ensure_korea_coords(latitude, longitude)
    rows = (
        await session.execute(
            _NEARBY_SQL, {"lng": longitude, "lat": latitude, "radius": radius, "limit": limit}
        )
    ).mappings().all()
    return TourSpotsResponse(data=[_row_to_spot(r, with_distance=True) for r in rows])


@router.get("/search", response_model=TourSearchResponse, summary="통합 검색(키워드+지역 필터)")
async def search_spots(
    keyword: str | None = Query(None, description="관광지명 검색어"),
    province: str | None = Query(None, description="시/도 (예: 강원특별자치도)"),
    city: str | None = Query(None, description="시/군/구 (예: 강릉시)"),
    latitude: float | None = Query(None, description="거리 계산용 기준 위도(선택)"),
    longitude: float | None = Query(None, description="거리 계산용 기준 경도(선택)"),
    limit: int = Query(30, ge=1, le=100),
    offset: int = Query(0, ge=0),
    _user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TourSearchResponse:
    has_origin = latitude is not None and longitude is not None
    if has_origin:
        ensure_korea_coords(latitude, longitude)

    where: list[str] = []
    params: dict = {"limit": limit, "offset": offset}

    if keyword:
        where.append("spot_name ILIKE :kw")
        params["kw"] = f"%{keyword.strip()}%"
    if province:
        where.append("region ILIKE :province")
        params["province"] = f"{province.strip()}%"
    if city:
        where.append("region ILIKE :city")
        params["city"] = f"%{city.strip()}%"

    where_sql = ("WHERE " + " AND ".join(where)) if where else ""

    # 거리 컬럼 + 정렬: 기준 좌표가 있으면 거리순, 없으면 이름순.
    if has_origin:
        dist_select = (
            "ST_Distance(location::geography, "
            "ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography) AS distance_meters"
        )
        order_sql = "ORDER BY distance_meters ASC"
        params["lng"] = longitude
        params["lat"] = latitude
    else:
        dist_select = "NULL::double precision AS distance_meters"
        order_sql = "ORDER BY spot_name ASC"

    list_sql = text(
        f"""
        SELECT content_id AS tour_id, spot_name, region, address, image_url,
               ST_Y(location) AS latitude, ST_X(location) AS longitude,
               {dist_select}
        FROM tour_spots
        {where_sql}
        {order_sql}
        LIMIT :limit OFFSET :offset;
        """
    )
    count_sql = text(f"SELECT COUNT(*) FROM tour_spots {where_sql};")

    rows = (await session.execute(list_sql, params)).mappings().all()
    total = (await session.execute(count_sql, params)).scalar() or 0

    items = [_row_to_spot(r, with_distance=has_origin) for r in rows]
    return TourSearchResponse(data=TourSearchData(total=int(total), items=items))


_REGIONS_SQL = text(
    """
    SELECT DISTINCT region
    FROM tour_spots
    WHERE region IS NOT NULL AND region <> ''
    ORDER BY region ASC;
    """
)


@router.get("/regions", response_model=RegionsResponse, summary="지역 필터 목록(시·도/시·군·구)")
async def list_regions(
    _user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> RegionsResponse:
    rows = (await session.execute(_REGIONS_SQL)).all()

    # region 문자열 "강원특별자치도 강릉시" → province / city 로 분해해 그룹화.
    grouped: dict[str, list[str]] = {}
    for (region,) in rows:
        parts = region.split()
        if not parts:
            continue
        province = parts[0]
        city = parts[1] if len(parts) > 1 else ""
        bucket = grouped.setdefault(province, [])
        if city and city not in bucket:
            bucket.append(city)

    data = [
        RegionGroup(province=p, cities=sorted(c)) for p, c in sorted(grouped.items())
    ]
    return RegionsResponse(data=data)
