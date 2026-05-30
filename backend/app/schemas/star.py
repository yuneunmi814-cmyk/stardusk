# 경로: backend/app/schemas/star.py
# 별 생성(정화 미션) 응답 스키마 (Phase 4 · API 명세서 3.3)

from datetime import datetime

from pydantic import BaseModel, Field


class PaletteColor(BaseModel):
    hex: str
    ratio: float


class StarData(BaseModel):
    star_id: int
    trip_id: int | None = None
    tour_id: str | None = None
    latitude: float
    longitude: float
    sky_color_hex: str = Field(..., description="대표 감정 색상")
    emotion_label: str | None = None
    palette: list[PaletteColor] = Field(default_factory=list, description="상위 색상 비율")
    brightness: float | None = None
    sky_score: float | None = Field(default=None, description="하늘 가능성 휴리스틱(0~1)")
    image_url: str
    captured_at: datetime


class StarCreateResponse(BaseModel):
    status: str = "success"
    message: str = "당신의 자취가 밤하늘의 별로 기록되었습니다."
    data: StarData
