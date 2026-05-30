# 경로: backend/app/db/models.py
# SQLModel ORM 모델 정의.
#  - tour_spots:        한국관광공사 OpenAPI 를 정규화해 캐싱하는 관광지 테이블. (Phase 2)
#  - user_trips:        하나의 여정(별자리 1개 단위) 메타 + 누적 경로(LineString). (Phase 3)
#  - trip_coordinates:  여정 중 수집된 실시간 GPS 좌표(Point)를 시간순으로 저장. (Phase 3)
#  - stars:             하늘 정화 시점에 생성되는 별(위치 + 대표 감정색). (Phase 4)
#  - sky_captures:      촬영 하늘 이미지 + 색 분석 결과(팔레트/메타). stars 와 1:1. (Phase 4)
#  - location/path 는 PostGIS Geometry(SRID 4326). 실제 테이블/인덱스는 Alembic
#    마이그레이션이 PostGIS 확장과 함께 생성하므로, 여기선 spatial_index=False
#    로 두어 메타데이터가 인덱스를 중복 생성하지 않게 한다.

import uuid
from datetime import datetime
from typing import Any, Optional

from geoalchemy2 import Geometry
from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CHAR,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlmodel import Field, SQLModel


class TourSpot(SQLModel, table=True):
    __tablename__ = "tour_spots"

    id: Optional[int] = Field(
        default=None,
        sa_column=Column(BigInteger, primary_key=True, autoincrement=True),
    )

    # 한국관광공사 콘텐츠 고유 ID (UPSERT 기준 키)
    content_id: str = Field(
        sa_column=Column(String(20), unique=True, index=True, nullable=False)
    )
    content_type_id: Optional[str] = Field(
        default=None, sa_column=Column(String(10))
    )

    spot_name: str = Field(sa_column=Column(String(200), nullable=False))
    region: Optional[str] = Field(default=None, sa_column=Column(String(60)))
    address: Optional[str] = Field(default=None, sa_column=Column(String(300)))

    area_code: Optional[str] = Field(default=None, sa_column=Column(String(10)))
    sigungu_code: Optional[str] = Field(default=None, sa_column=Column(String(10)))
    cat1: Optional[str] = Field(default=None, sa_column=Column(String(10)))
    cat2: Optional[str] = Field(default=None, sa_column=Column(String(10)))
    cat3: Optional[str] = Field(default=None, sa_column=Column(String(10)))

    tel: Optional[str] = Field(default=None, sa_column=Column(String(60)))
    image_url: Optional[str] = Field(default=None, sa_column=Column(Text))

    # PostGIS Point (위경도, SRID 4326)
    location: Any = Field(
        default=None,
        sa_column=Column(
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=False,
        ),
    )

    created_at: Optional[datetime] = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), server_default=func.now()),
    )
    updated_at: Optional[datetime] = Field(
        default=None,
        sa_column=Column(
            DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
        ),
    )


class UserTrip(SQLModel, table=True):
    """하나의 여정(별자리 단위). 누적 경로는 path(LineString)에 캐싱한다."""

    __tablename__ = "user_trips"

    id: Optional[int] = Field(
        default=None,
        sa_column=Column(BigInteger, primary_key=True, autoincrement=True),
    )
    # NOTE: 인증(Phase 1)이 아직 mock 이라 users 테이블이 없으므로 FK 제약은 두지 않는다.
    #       users 테이블 도입 시 ForeignKey("users.id") 로 승격.
    user_id: uuid.UUID = Field(
        sa_column=Column(PG_UUID(as_uuid=True), index=True, nullable=False)
    )

    region: Optional[str] = Field(default=None, sa_column=Column(String(40)))
    constellation_name: Optional[str] = Field(default=None, sa_column=Column(String(60)))

    # 누적 동선(좌표 2개 이상일 때만 채워짐). 좌표 1개면 NULL.
    path: Any = Field(
        default=None,
        sa_column=Column(
            Geometry(geometry_type="LINESTRING", srid=4326, spatial_index=False),
            nullable=True,
        ),
    )
    distance_meters: int = Field(default=0, sa_column=Column(Integer, nullable=False, server_default="0"))
    point_count: int = Field(default=0, sa_column=Column(Integer, nullable=False, server_default="0"))

    status: str = Field(default="active", sa_column=Column(String(12), nullable=False, server_default="active"))
    started_at: Optional[datetime] = Field(
        default=None, sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    ended_at: Optional[datetime] = Field(default=None, sa_column=Column(DateTime(timezone=True)))
    updated_at: Optional[datetime] = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now()),
    )


class TripCoordinate(SQLModel, table=True):
    """여정 중 수집된 실시간 GPS 좌표(Point). recorded_at/sequence 순으로 정렬해 LineString 구성."""

    __tablename__ = "trip_coordinates"

    id: Optional[int] = Field(
        default=None,
        sa_column=Column(BigInteger, primary_key=True, autoincrement=True),
    )
    trip_id: int = Field(
        sa_column=Column(
            BigInteger,
            ForeignKey("user_trips.id", ondelete="CASCADE"),
            index=True,
            nullable=False,
        )
    )
    location: Any = Field(
        default=None,
        sa_column=Column(
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=False,
        ),
    )
    accuracy_m: Optional[float] = Field(default=None, sa_column=Column(Float))
    sequence: int = Field(sa_column=Column(Integer, nullable=False))
    recorded_at: datetime = Field(sa_column=Column(DateTime(timezone=True), nullable=False))
    created_at: Optional[datetime] = Field(
        default=None, sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )


class Star(SQLModel, table=True):
    """하늘 정화 시점에 특정 좌표에 생성되는 '별'(자취). 대표 감정색을 가진다."""

    __tablename__ = "stars"

    id: Optional[int] = Field(
        default=None,
        sa_column=Column(BigInteger, primary_key=True, autoincrement=True),
    )
    # users 테이블 도입 시 FK 로 승격(Phase 1 mock 상태이므로 현재는 인덱스만).
    user_id: uuid.UUID = Field(
        sa_column=Column(PG_UUID(as_uuid=True), index=True, nullable=False)
    )
    trip_id: Optional[int] = Field(
        default=None,
        sa_column=Column(
            BigInteger, ForeignKey("user_trips.id", ondelete="SET NULL"), index=True
        ),
    )
    tour_id: Optional[str] = Field(default=None, sa_column=Column(String(20)))

    location: Any = Field(
        default=None,
        sa_column=Column(
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=False,
        ),
    )
    sky_color_hex: str = Field(sa_column=Column(CHAR(7), nullable=False))   # "#A1C4FD"
    emotion_label: Optional[str] = Field(default=None, sa_column=Column(String(20)))
    captured_at: Optional[datetime] = Field(
        default=None, sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )


class SkyCapture(SQLModel, table=True):
    """촬영된 하늘 이미지 + 색 분석 결과(팔레트/밝기/메타). stars 와 1:1."""

    __tablename__ = "sky_captures"

    id: Optional[int] = Field(
        default=None,
        sa_column=Column(BigInteger, primary_key=True, autoincrement=True),
    )
    star_id: int = Field(
        sa_column=Column(
            BigInteger,
            ForeignKey("stars.id", ondelete="CASCADE"),
            unique=True,
            nullable=False,
        )
    )
    storage_path: str = Field(sa_column=Column(Text, nullable=False))
    thumb_path: Optional[str] = Field(default=None, sa_column=Column(Text))
    width: Optional[int] = Field(default=None, sa_column=Column(Integer))
    height: Optional[int] = Field(default=None, sa_column=Column(Integer))
    dominant_hex: str = Field(sa_column=Column(CHAR(7), nullable=False))
    # 상위 N색 + 비율 + 감정 라벨 (PostgreSQL JSONB, 다른 DB 폴백 시 JSON)
    palette: Any = Field(
        default=None, sa_column=Column(JSONB().with_variant(JSON, "sqlite"))
    )
    brightness: Optional[float] = Field(default=None, sa_column=Column(Float))
    sky_score: Optional[float] = Field(default=None, sa_column=Column(Float))
    exif_stripped: bool = Field(
        default=True, sa_column=Column(Boolean, nullable=False, server_default="true")
    )
    created_at: Optional[datetime] = Field(
        default=None, sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )


# ---------------------------------------------------------------------------
# Phase 6 · setlog 실시간 공유 / 라이브 세션
# ---------------------------------------------------------------------------
class SkyVideo(SQLModel, table=True):
    """사용자가 올린 '하늘 영상'(setlog 피드 1건). stars 와 같은 색/감정 메타를 가진다.

    - PK 는 UUID(분산 친화·URL 추측 방지).
    - tour_id 는 tour_spots.content_id(unique) 를 참조(특정 관광지가 아니면 NULL).
    - geom 은 촬영 위치(Point, SRID 4326). 트렌딩/지도 핀 표시에 사용.
    """

    __tablename__ = "sky_videos"

    id: uuid.UUID = Field(
        default_factory=uuid.uuid4,
        sa_column=Column(PG_UUID(as_uuid=True), primary_key=True),
    )
    # users 테이블 도입 시 FK 승격(현재 인증 mock → UUID 인덱스만).
    user_id: uuid.UUID = Field(
        sa_column=Column(PG_UUID(as_uuid=True), index=True, nullable=False)
    )
    tour_id: Optional[str] = Field(
        default=None,
        sa_column=Column(
            String(20),
            ForeignKey("tour_spots.content_id", ondelete="SET NULL"),
            index=True,
        ),
    )

    video_url: str = Field(sa_column=Column(Text, nullable=False))         # HLS(.m3u8) 또는 MP4
    thumbnail_url: Optional[str] = Field(default=None, sa_column=Column(Text))
    sky_color_hex: str = Field(sa_column=Column(CHAR(7), nullable=False))  # Phase 4 추출 색
    emotion_label: Optional[str] = Field(default=None, sa_column=Column(String(20)))

    geom: Any = Field(
        default=None,
        sa_column=Column(
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=False,
        ),
    )
    created_at: Optional[datetime] = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), index=True, server_default=func.now()),
    )


class LiveSession(SQLModel, table=True):
    """실시간 '하늘방' 동시 접속 상태. (sky_video_id, user_id) 1행 = 한 명의 현재 접속.

    Supabase Realtime Presence 와 연동되는 '권위 있는' 서버측 카운트 소스.
    - (sky_video_id, user_id) UNIQUE: 같은 유저가 한 방에 중복 입장하지 않도록.
    - idx_live_room_alive (sky_video_id, last_heartbeat): 방별 '살아있는' 세션 카운트 가속.
    - idx_live_heartbeat (last_heartbeat): 죽은 세션 일괄 청소(GC) 가속.
    """

    __tablename__ = "live_sessions"
    __table_args__ = (
        UniqueConstraint("sky_video_id", "user_id", name="uq_live_room_user"),
        Index("idx_live_room_alive", "sky_video_id", "last_heartbeat"),
        Index("idx_live_heartbeat", "last_heartbeat"),
    )

    id: uuid.UUID = Field(
        default_factory=uuid.uuid4,
        sa_column=Column(PG_UUID(as_uuid=True), primary_key=True),
    )
    sky_video_id: uuid.UUID = Field(
        sa_column=Column(
            PG_UUID(as_uuid=True),
            ForeignKey("sky_videos.id", ondelete="CASCADE"),
            nullable=False,
        )
    )
    user_id: uuid.UUID = Field(
        sa_column=Column(PG_UUID(as_uuid=True), index=True, nullable=False)
    )
    joined_at: Optional[datetime] = Field(
        default=None, sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
    # 클라이언트가 주기적으로 갱신. 일정 시간(기본 30s) 미갱신 시 '죽은 세션'으로 청소.
    last_heartbeat: Optional[datetime] = Field(
        default=None, sa_column=Column(DateTime(timezone=True), server_default=func.now())
    )
