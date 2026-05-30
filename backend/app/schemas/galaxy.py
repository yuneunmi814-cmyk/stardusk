# 경로: backend/app/schemas/galaxy.py
# 은하수 조회(my-galaxy) 응답 스키마 (Phase 5 · Tech Design 2-1)
#  - 프런트는 x_norm/y_norm(0~1)에 화면 크기만 곱하면 바로 별을 찍을 수 있다.
#  - path_line 은 시간순 정규화 좌표 배열로, 별과 별을 잇는 선(별자리)을 그릴 때 쓴다.

from datetime import datetime

from pydantic import BaseModel, Field


class GalaxyBounds(BaseModel):
    """지도/캔버스 정규화 기준이 된 위경도 경계."""

    min_lat: float
    min_lng: float
    max_lat: float
    max_lng: float


class StarTrailPoint(BaseModel):
    star_id: int
    sequence: int = Field(..., description="시간순 1-base 순번")
    latitude: float
    longitude: float
    x_norm: float = Field(..., ge=0.0, le=1.0, description="경도 정규화(0=서, 1=동)")
    y_norm: float = Field(..., ge=0.0, le=1.0, description="위도 정규화(0=남, 1=북)")
    sky_color_hex: str
    emotion_label: str | None = None
    captured_at: datetime


class MyGalaxyData(BaseModel):
    trip_id: int | None = Field(default=None, description="특정 여정 조회 시에만 채워짐")
    constellation_name: str
    region: str | None = None
    total_stars_count: int
    distance_meters: int = Field(default=0, description="별 자취(시간순)의 누적 직선 거리")
    bounds: GalaxyBounds | None = None
    stars_trail: list[StarTrailPoint] = Field(default_factory=list)
    path_line: list[list[float]] = Field(
        default_factory=list, description="[[x_norm, y_norm], ...] 시간순 정규화 좌표"
    )


class MyGalaxyResponse(BaseModel):
    status: str = "success"
    message: str = "당신이 머문 자리마다 별이 떠올랐습니다."
    data: MyGalaxyData
