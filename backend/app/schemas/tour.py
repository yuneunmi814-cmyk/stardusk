# 경로: backend/app/schemas/tour.py
# 관광지 조회/검색 API 응답 스키마
#  - TourSpotOut: 지도 마커 + 리스트 행 + 장소 카드가 공유하는 단일 모델(이미지/주소 포함)
#  - 하이브리드 탐색: 내 주변(거리순) / 통합 검색(키워드·지역 필터)

from pydantic import BaseModel, Field


class TourSpotOut(BaseModel):
    tour_id: str = Field(..., description="한국관광공사 콘텐츠 ID")
    spot_name: str
    region: str | None = None
    address: str | None = None
    image_url: str | None = Field(default=None, description="대표 이미지(firstimage)")
    latitude: float
    longitude: float
    distance_meters: int | None = Field(
        default=None, description="기준 위치로부터의 거리(m). 기준 좌표가 없으면 null."
    )
    # §3.6 성향 라벨링 — 'hotplace'(인기 핫플) / 'secret'(숨겨진 명소) / null(미라벨)
    label: str | None = Field(default=None, description="성향 라벨(hotplace/secret)")
    popularity_score: float | None = Field(
        default=None, description="시군구 내 readcount 백분위(0.0~1.0)"
    )


class TourSpotsResponse(BaseModel):
    status: str = "success"
    data: list[TourSpotOut]


class TourSearchData(BaseModel):
    total: int
    items: list[TourSpotOut]


class TourSearchResponse(BaseModel):
    status: str = "success"
    data: TourSearchData


class RegionGroup(BaseModel):
    province: str = Field(..., description="시/도 (예: 강원특별자치도)")
    cities: list[str] = Field(default_factory=list, description="시/군/구 목록")


class RegionsResponse(BaseModel):
    status: str = "success"
    data: list[RegionGroup]


# ---- §3.6 스와이프 학습 ----
class SwipeRequest(BaseModel):
    tour_id: str = Field(..., description="스와이프한 명소의 콘텐츠 ID")
    action: str = Field(..., description="like | pass | refresh", examples=["like"])


class SwipeData(BaseModel):
    taste_score: float = Field(
        ..., description="갱신된 취향 스코어 0(숨은 명소 선호)~1(핫플 선호)"
    )
    learned: bool = Field(..., description="학습 반영 여부(Refresh 는 false)")
    spot_label: str | None = Field(default=None, description="스와이프한 명소의 라벨")


class SwipeResponse(BaseModel):
    status: str = "success"
    data: SwipeData
