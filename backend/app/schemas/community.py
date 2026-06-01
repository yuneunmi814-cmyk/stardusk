# 경로: backend/app/schemas/community.py
# setlog 실시간 공유 / 라이브 세션 API 스키마 (Phase 6)
#  - 하늘방 입장/퇴장 응답, 동시 접속자 프로필, 트렌딩 피드 아이템.

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.schemas.star import PaletteColor


class ParticipantProfile(BaseModel):
    """방에 함께 있는 유저의 '별자리 프로필'.

    아바타 색/감정은 해당 유저가 마지막으로 남긴 별(stars)의 대표색에서 가져온다.
    (users 테이블 도입 전이므로 nickname 은 토큰에서 아는 본인만 채워질 수 있음)
    """

    user_id: UUID
    nickname: str | None = None
    avatar_color: str | None = Field(default=None, description="최근 별의 하늘색(아바타)")
    emotion_label: str | None = None
    joined_at: datetime


class RoomJoinData(BaseModel):
    sky_video_id: UUID
    live_users_count: int = Field(..., description="현재 같은 하늘 아래 머무는 인원")
    participants: list[ParticipantProfile] = Field(default_factory=list)
    joined_at: datetime
    realtime_channel: str = Field(
        ..., description="iOS 가 구독할 Supabase Realtime 채널명 (예: room:<uuid>)"
    )
    heartbeat_interval_sec: int = Field(
        default=15, description="클라이언트 권장 하트비트 주기(초)"
    )


class RoomJoinResponse(BaseModel):
    status: str = "success"
    message: str = "같은 하늘 아래, 당신이 도착했습니다."
    data: RoomJoinData


class RoomLeaveData(BaseModel):
    sky_video_id: UUID
    live_users_count: int


class RoomLeaveResponse(BaseModel):
    status: str = "success"
    message: str = "당신의 자취가 조용히 흐려졌습니다."
    data: RoomLeaveData


class HeartbeatData(BaseModel):
    sky_video_id: UUID
    live_users_count: int
    alive: bool = True


class HeartbeatResponse(BaseModel):
    status: str = "success"
    data: HeartbeatData


class TrendingItem(BaseModel):
    sky_video_id: UUID
    user_id: UUID
    tour_id: str | None = None
    region: str | None = None
    spot_name: str | None = None
    video_url: str
    thumbnail_url: str | None = None
    sky_color_hex: str
    emotion_label: str | None = None
    latitude: float
    longitude: float
    live_users_count: int = Field(..., description="실시간 동시 접속자 수")
    is_gangwon: bool = Field(default=False, description="강원도(areaCode=32) 여부 — 상단 가중치")
    created_at: datetime


class TrendingData(BaseModel):
    total: int
    items: list[TrendingItem] = Field(default_factory=list)


class TrendingResponse(BaseModel):
    status: str = "success"
    message: str = "지금 가장 많은 사람들이 함께 올려다보는 하늘입니다."
    data: TrendingData


# ---------------------------------------------------------------------------
# 하늘 영상 업로드 (POST /community/videos)
# ---------------------------------------------------------------------------
class SkyVideoData(BaseModel):
    sky_video_id: UUID
    trip_id: int | None = None
    tour_id: str | None = None
    latitude: float
    longitude: float
    video_url: str
    thumbnail_url: str = Field(..., description="첫 프레임 썸네일 URL")
    sky_color_hex: str = Field(..., description="첫 프레임 상단 절반 대표 색상(Phase 4)")
    emotion_label: str | None = None
    palette: list[PaletteColor] = Field(default_factory=list, description="상위 색상 비율")
    brightness: float | None = None
    sky_score: float | None = Field(default=None, description="하늘 가능성 휴리스틱(0~1)")
    created_at: datetime


class SkyVideoCreateResponse(BaseModel):
    status: str = "success"
    message: str = "당신의 하늘이 모두의 밤하늘에 더해졌습니다."
    data: SkyVideoData


# ---- UGC 모더레이션(신고/차단) ----
from typing import Literal  # noqa: E402


class ReportRequest(BaseModel):
    sky_video_id: UUID = Field(..., description="신고할 하늘 영상 ID")
    reason: Literal["spam", "inappropriate", "offensive", "violence", "other"] = Field(
        ..., description="신고 사유"
    )
    detail: str | None = Field(default=None, max_length=500, description="상세(선택)")


class BlockRequest(BaseModel):
    blocked_user_id: UUID = Field(..., description="차단할 사용자 ID")


class SimpleResponse(BaseModel):
    status: str = "success"
    message: str = ""
