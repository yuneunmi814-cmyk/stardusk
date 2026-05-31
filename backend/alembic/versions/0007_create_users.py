# 경로: backend/alembic/versions/0007_create_users.py
"""users 테이블 (Phase 1 소셜 로그인 — Apple/Google 실제 연동)

Revision ID: 0007
Revises: 0006
Create Date: 2026-05-31
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            user_id        UUID PRIMARY KEY,
            provider       VARCHAR(16)  NOT NULL,
            provider_sub   VARCHAR(255) NOT NULL,
            email          VARCHAR(320),
            nickname       VARCHAR(60)  NOT NULL,
            created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
            last_login_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
            CONSTRAINT uq_user_provider_sub UNIQUE (provider, provider_sub)
        );
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS users;")
