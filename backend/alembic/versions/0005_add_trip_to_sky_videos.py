# 경로: backend/alembic/versions/0005_add_trip_to_sky_videos.py
"""add trip_id to sky_videos (영상 ↔ 여정 연결, Phase 6.1)

Revision ID: 0005
Revises: 0004
Create Date: 2026-05-31
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "ALTER TABLE sky_videos "
        "ADD COLUMN IF NOT EXISTS trip_id BIGINT "
        "REFERENCES user_trips(id) ON DELETE SET NULL;"
    )
    op.execute("CREATE INDEX IF NOT EXISTS idx_sky_videos_trip ON sky_videos (trip_id);")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_sky_videos_trip;")
    op.execute("ALTER TABLE sky_videos DROP COLUMN IF EXISTS trip_id;")
