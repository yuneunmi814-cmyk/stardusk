# 경로: backend/alembic/versions/0003_create_star_tables.py
"""create stars + sky_captures (PostGIS, GIST, JSONB palette)

Revision ID: 0003
Revises: 0002
Create Date: 2026-05-30
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1) stars: 위치 + 대표 감정색
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS stars (
            id            BIGSERIAL PRIMARY KEY,
            user_id       UUID NOT NULL,
            trip_id       BIGINT REFERENCES user_trips(id) ON DELETE SET NULL,
            tour_id       VARCHAR(20),
            location      geometry(Point, 4326) NOT NULL,
            sky_color_hex CHAR(7) NOT NULL,
            emotion_label VARCHAR(20),
            captured_at   TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS idx_stars_geom ON stars USING GIST (location);")
    op.execute("CREATE INDEX IF NOT EXISTS idx_stars_user ON stars (user_id);")
    op.execute("CREATE INDEX IF NOT EXISTS idx_stars_trip ON stars (trip_id);")

    # 2) sky_captures: 이미지 + 색 분석 결과 (stars 1:1)
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS sky_captures (
            id            BIGSERIAL PRIMARY KEY,
            star_id       BIGINT NOT NULL UNIQUE REFERENCES stars(id) ON DELETE CASCADE,
            storage_path  TEXT NOT NULL,
            thumb_path    TEXT,
            width         INTEGER,
            height        INTEGER,
            dominant_hex  CHAR(7) NOT NULL,
            palette       JSONB,
            brightness    REAL,
            sky_score     REAL,
            exif_stripped BOOLEAN NOT NULL DEFAULT true,
            created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS sky_captures;")
    op.execute("DROP TABLE IF EXISTS stars;")
