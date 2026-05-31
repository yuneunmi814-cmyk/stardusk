# 경로: backend/alembic/versions/0006_add_taste_personalization.py
"""tour_spots 성향 라벨링 컬럼 + user_taste 테이블 (§3.6 개인화 큐레이션)

Revision ID: 0006
Revises: 0005
Create Date: 2026-05-31
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1) tour_spots: 인기도/성향 라벨 컬럼 (배치에서 채움)
    op.execute(
        "ALTER TABLE tour_spots "
        "ADD COLUMN IF NOT EXISTS readcount BIGINT NOT NULL DEFAULT 0;"
    )
    op.execute(
        "ALTER TABLE tour_spots "
        "ADD COLUMN IF NOT EXISTS popularity_score DOUBLE PRECISION;"
    )
    op.execute(
        "ALTER TABLE tour_spots ADD COLUMN IF NOT EXISTS label VARCHAR(10);"
    )
    op.execute("CREATE INDEX IF NOT EXISTS idx_tour_spots_label ON tour_spots (label);")

    # 2) user_taste: 사용자별 취향 스코어(EWMA). user_id 1행 = 현재 취향.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS user_taste (
            user_id      UUID PRIMARY KEY,
            taste_score  DOUBLE PRECISION NOT NULL DEFAULT 0.5,
            like_count   INTEGER NOT NULL DEFAULT 0,
            pass_count   INTEGER NOT NULL DEFAULT 0,
            updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS user_taste;")
    op.execute("DROP INDEX IF EXISTS idx_tour_spots_label;")
    op.execute("ALTER TABLE tour_spots DROP COLUMN IF EXISTS label;")
    op.execute("ALTER TABLE tour_spots DROP COLUMN IF EXISTS popularity_score;")
    op.execute("ALTER TABLE tour_spots DROP COLUMN IF EXISTS readcount;")
