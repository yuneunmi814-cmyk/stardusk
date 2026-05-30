# 경로: backend/alembic/versions/0002_create_trip_tables.py
"""create user_trips + trip_coordinates (PostGIS, GIST)

Revision ID: 0002
Revises: 0001
Create Date: 2026-05-30
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1) 여정 메타 테이블 (path: 누적 동선 LineString)
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS user_trips (
            id                 BIGSERIAL PRIMARY KEY,
            user_id            UUID NOT NULL,
            region             VARCHAR(40),
            constellation_name VARCHAR(60),
            path               geometry(LineString, 4326),
            distance_meters    INTEGER NOT NULL DEFAULT 0,
            point_count        INTEGER NOT NULL DEFAULT 0,
            status             VARCHAR(12) NOT NULL DEFAULT 'active',
            started_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
            ended_at           TIMESTAMPTZ,
            updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS idx_user_trips_user ON user_trips (user_id);")
    op.execute("CREATE INDEX IF NOT EXISTS idx_user_trips_path ON user_trips USING GIST (path);")

    # 2) 실시간 GPS 좌표 테이블
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS trip_coordinates (
            id          BIGSERIAL PRIMARY KEY,
            trip_id     BIGINT NOT NULL REFERENCES user_trips(id) ON DELETE CASCADE,
            location    geometry(Point, 4326) NOT NULL,
            accuracy_m  REAL,
            sequence    INTEGER NOT NULL,
            recorded_at TIMESTAMPTZ NOT NULL,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )
    # 공간 인덱스 + 정렬/조회 가속(여정별 시간순)
    op.execute("CREATE INDEX IF NOT EXISTS idx_trip_coords_geom ON trip_coordinates USING GIST (location);")
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_trip_coords_trip_seq "
        "ON trip_coordinates (trip_id, sequence);"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS trip_coordinates;")
    op.execute("DROP TABLE IF EXISTS user_trips;")
