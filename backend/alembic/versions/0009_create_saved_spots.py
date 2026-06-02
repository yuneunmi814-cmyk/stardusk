# 경로: backend/alembic/versions/0009_create_saved_spots.py
"""saved_spots — 사용자가 라이크(찜)한 관광지 모음

Revision ID: 0009
Revises: 0008
Create Date: 2026-06-01
"""
from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS saved_spots (
            user_id    UUID        NOT NULL,
            content_id VARCHAR(20) NOT NULL,
            saved_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, content_id)
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_saved_user ON saved_spots (user_id, saved_at DESC);"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS idx_saved_user;")
    op.execute("DROP TABLE IF EXISTS saved_spots;")
