# 경로: backend/app/schemas/tour.py
# 관광지 조회 API 응답 스키마 (API 명세서 3.2 기준)

from pydantic import BaseModel, Field


class TourSpotOut(BaseModel):
    tour_id: str = Field(..., description="한국관광공사 콘텐츠 ID")
    spot_name: str
    region: str | None = None
    latitude: float
    longitude: float
    distance_meters: int = Field(..., description="현재 위치로부터의 거리(m)")


class TourSpotsResponse(BaseModel):
    status: str = "success"
    data: list[TourSpotOut]
