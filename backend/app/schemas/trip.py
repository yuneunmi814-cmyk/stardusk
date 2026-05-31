# 경로: backend/app/schemas/trip.py
# 여정/동선 API 요청·응답 스키마 (Phase 3)

from datetime import datetime

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# 여정 시작/조회
# ---------------------------------------------------------------------------
class TripCreateRequest(BaseModel):
    region: str | None = Field(default=None, examples=["강원도 강릉시"])
    constellation_name: str | None = Field(default=None, examples=["강릉을 수놓은 영혼의 자리"])


class TripCreateData(BaseModel):
    trip_id: int
    status: str
    started_at: datetime


class TripCreateResponse(BaseModel):
    status: str = "success"
    data: TripCreateData


# ---------------------------------------------------------------------------
# 실시간 좌표 업로드 (Bulk)
# ---------------------------------------------------------------------------
class CoordinateIn(BaseModel):
    latitude: float = Field(..., ge=-90, le=90, examples=[37.7951])
    longitude: float = Field(..., ge=-180, le=180, examples=[128.8964])
    recorded_at: datetime = Field(..., description="기기에서 측정된 시각(ISO8601)")
    accuracy_m: float | None = Field(default=None, description="GPS 정확도(m)")


class CoordinatesUpload(BaseModel):
    trip_id: int
    coordinates: list[CoordinateIn] = Field(..., min_length=1, max_length=500)


class UploadData(BaseModel):
    trip_id: int
    inserted: int
    point_count: int
    distance_meters: int


class UploadResponse(BaseModel):
    status: str = "success"
    message: str = "동선 좌표가 기록되었습니다."
    data: UploadData


# ---------------------------------------------------------------------------
# 여정 경로 조회 (LineString)
# ---------------------------------------------------------------------------
class PathPoint(BaseModel):
    sequence: int
    latitude: float
    longitude: float
    recorded_at: datetime


class Bounds(BaseModel):
    min_lat: float
    min_lng: float
    max_lat: float
    max_lng: float


class TripPathData(BaseModel):
    trip_id: int
    point_count: int
    distance_meters: int
    bounds: Bounds | None = None
    coordinates: list[PathPoint]
    line_geojson: dict | None = Field(
        default=None, description="GeoJSON LineString (좌표 2개 이상일 때)"
    )


class TripPathResponse(BaseModel):
    status: str = "success"
    data: TripPathData
