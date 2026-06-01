# 경로: backend/alembic/versions/0008_create_moderation.py
"""UGC 모더레이션 — 콘텐츠 신고(content_reports) + 사용자 차단(user_blocks)

App Store Guideline 1.2(사용자 생성 콘텐츠) 대응: 신고·차단 + 임계 자동 숨김.

Revision ID: 0008
Revises: 0007
Create Date: 2026-06-01
"""
from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 콘텐츠 신고 — (신고자, 영상) 1회만(중복 신고 방지). 같은 영상에 신고가 쌓이면 자동 숨김.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS content_reports (
            id               BIGSERIAL PRIMARY KEY,
            reporter_user_id UUID        NOT NULL,
            sky_video_id     UUID        NOT NULL REFERENCES sky_videos(id) ON DELETE CASCADE,
            reason           VARCHAR(40) NOT NULL,
            detail           TEXT,
            created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_report_once UNIQUE (reporter_user_id, sky_video_id)
        );
        """
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_reports_video ON content_reports (sky_video_id);"
    )

    # 사용자 차단 — 차단자는 피차단자의 콘텐츠를 더 이상 보지 않는다.
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS user_blocks (
            blocker_user_id UUID        NOT NULL,
            blocked_user_id UUID        NOT NULL,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (blocker_user_id, blocked_user_id)
        );
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS user_blocks;")
    op.execute("DROP INDEX IF EXISTS idx_reports_video;")
    op.execute("DROP TABLE IF EXISTS content_reports;")
