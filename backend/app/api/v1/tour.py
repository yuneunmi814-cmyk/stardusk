# 경로: backend/app/api/v1/tour.py
# 관광지 조회/검색 라우터 — 하이브리드 위치 탐색의 백엔드.
#  - GET /api/v1/tour/spots   : 기준 위경도 + 반경으로 주변 명소(지도 마커/거리순)
#  - GET /api/v1/tour/search  : 키워드 + 지역(시·도/시·군·구) 필터 통합 검색(리스트 탐색)
#  - GET /api/v1/tour/regions : 지역 필터용 시·도 → 시·군·구 목록
#
# PostGIS ST_DWithin/ST_Distance(geography 캐스팅, 미터 단위)로 GIST 인덱스를 탄다.
# 인증: Bearer 토큰 필요(get_current_user).

from fastapi import APIRouter, Body, Depends, HTTPException, Query, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.core.validation import ensure_korea_coords
from app.db.session import get_session
from app.schemas.tour import (
    RegionGroup,
    RegionsResponse,
    SpotDetailData,
    SpotDetailResponse,
    SwipeData,
    SwipeRequest,
    SwipeResponse,
    TourSearchData,
    TourSearchResponse,
    TourSpotOut,
    TourSpotsResponse,
)
from app.services import taste as taste_service
from app.services.tour_sync import fetch_overview

router = APIRouter(prefix="/tour", tags=["tour"])

# KTO 데이터에 관광지/문화시설로 느슨하게 분류돼 섞여 들어오는 관변·행정 시설을
# 이름으로 제외한다(시청·노인회·복지관 등). POSIX 정규식, spot_name !~ 로 사용.
_CIVIC_NAME_RX = (
    "(시청|군청|구청|도청|행정복지센터|주민센터|행정센터|면사무소|읍사무소|동사무소|"
    "보건소|보건지소|우체국|경찰서|파출소|지구대|소방서|세무서|등기소|교육청|법원|"
    "노인회|부녀회|청년회|번영회|자치회|협회|지회|연합회|복지관|행정역사관|"
    # 자연·쉼이 아닌 도심/시설/문화(사찰·치유의숲·휴양림은 유지)
    "상권|민화마을|문화유산|유산단지|교육장|수련원|연수원)"
)

# 입력 점은 ST_MakePoint(경도, 위도) → SRID 4326. 거리는 geography 캐스팅으로 미터.
_NEARBY_SQL = text(
    """
    SELECT
        content_id AS tour_id,
        spot_name, region, address, image_url, label, popularity_score,
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
      AND (cat1 = 'A01' OR (content_type_id = '12' AND (cat1 IS NULL OR cat1 = '')))  -- 자연(A01) + 분류 공백 관광지(해변·해맞이공원 등 cat 누락분 포함). 문화시설/숙박/음식/쇼핑/축제 제외
      AND spot_name !~ '""" + _CIVIC_NAME_RX + """'      -- 시청·노인회 등 관변/행정 시설 이름 제외
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
        label=row.get("label"),
        popularity_score=row.get("popularity_score"),
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


@router.get(
    "/deck",
    response_model=TourSpotsResponse,
    summary="개인화 큐레이션 덱(취향 학습 반영)",
)
async def get_personalized_deck(
    latitude: float = Query(..., description="기준 위도", examples=[37.7914]),
    longitude: float = Query(..., description="기준 경도", examples=[128.9194]),
    radius: int = Query(5000, ge=1, le=50000, description="반경(m), 최대 50km"),
    limit: int = Query(20, ge=1, le=100),
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TourSpotsResponse:
    """'내 주변 별 탐색' 덱. 같은 반경 후보를 deck_rank(거리+취향 일치)로 재정렬해
    사용자 성향에 맞는 카드를 최상단에 배치한다(§3.6③)."""
    ensure_korea_coords(latitude, longitude)
    rows = await taste_service.personalized_deck(
        session, user["user_id"],
        latitude=latitude, longitude=longitude, radius=radius, limit=limit,
    )
    return TourSpotsResponse(data=[_row_to_spot(r, with_distance=True) for r in rows])


@router.post("/swipe", response_model=SwipeResponse, summary="스와이프 학습(Like/Pass/Refresh)")
async def record_swipe(
    payload: SwipeRequest = Body(...),
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> SwipeResponse:
    """카드 스와이프를 취향 학습에 반영한다(§3.6②). Refresh 는 '판단 보류'로 학습 제외."""
    try:
        result = await taste_service.apply_swipe(
            session, user["user_id"], payload.tour_id, payload.action
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "code": "INVALID_SWIPE_ACTION", "message": str(e)},
        )
    return SwipeResponse(data=SwipeData(**result))


_SAVED_SQL = text(
    """
    SELECT ts.content_id AS tour_id, ts.spot_name, ts.region, ts.address, ts.image_url,
           ts.label, ts.popularity_score,
           ST_Y(ts.location) AS latitude, ST_X(ts.location) AS longitude,
           NULL::double precision AS distance_meters
    FROM saved_spots s
    JOIN tour_spots ts ON ts.content_id = s.content_id
    WHERE s.user_id = :uid
    ORDER BY s.saved_at DESC;
    """
)


@router.get("/saved", response_model=TourSpotsResponse, summary="저장(라이크)한 명소 목록")
async def get_saved_spots(
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TourSpotsResponse:
    rows = (await session.execute(_SAVED_SQL, {"uid": user["user_id"]})).mappings().all()
    return TourSpotsResponse(data=[_row_to_spot(r, with_distance=False) for r in rows])


@router.delete("/saved/{content_id}", response_model=TourSpotsResponse, summary="저장 해제")
async def unsave_spot(
    content_id: str,
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TourSpotsResponse:
    await session.execute(
        text("DELETE FROM saved_spots WHERE user_id = :uid AND content_id = :cid;"),
        {"uid": user["user_id"], "cid": content_id},
    )
    await session.commit()
    rows = (await session.execute(_SAVED_SQL, {"uid": user["user_id"]})).mappings().all()
    return TourSpotsResponse(data=[_row_to_spot(r, with_distance=False) for r in rows])


@router.get("/{content_id}/detail", response_model=SpotDetailResponse, summary="명소 상세설명(도슨트)")
async def get_spot_detail(
    content_id: str,
    _user: dict = Depends(get_current_user),
) -> SpotDetailResponse:
    """도슨트(설명 듣기)용 상세설명. 한국관광공사 detailCommon2 의 overview 를
    HTML 제거 후 반환한다(앱이 음성으로 읽어줌). 없으면 overview=null."""
    overview = await fetch_overview(content_id)
    return SpotDetailResponse(data=SpotDetailData(content_id=content_id, overview=overview))


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

    # 관광지·문화시설·축제·여행코스·레포츠만 (숙박/쇼핑/음식점 제외) + 관변·행정 시설 이름 제외
    where: list[str] = [
        "(cat1 = 'A01' OR (content_type_id = '12' AND (cat1 IS NULL OR cat1 = '')))",  # 자연(A01) + 분류 공백 관광지
        f"spot_name !~ '{_CIVIC_NAME_RX}'",
    ]
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
               label, popularity_score,
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
