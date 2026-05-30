# 경로: backend/alembic/versions/0004_create_community_tables.py
"""create sky_videos + live_sessions (setlog 실시간 공유/라이브 세션, Phase 6)

Revision ID: 0004
Revises: 0003
Create Date: 2026-05-31
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # gen_random_uuid() 사용을 위한 확장(이미 있으면 무시)
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto;")

    # 1) sky_videos: setlog 감성 하늘 영상 피드
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS sky_videos (
            id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id       UUID NOT NULL,
            tour_id       VARCHAR(20) REFERENCES tour_spots(content_id) ON DELETE SET NULL,
            video_url     TEXT NOT NULL,
            thumbnail_url TEXT,
            sky_color_hex CHAR(7) NOT NULL,
            emotion_label VARCHAR(20),
            geom          geometry(Point, 4326) NOT NULL,
            created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS idx_sky_videos_geom ON sky_videos USING GIST (geom);")
    op.execute("CREATE INDEX IF NOT EXISTS idx_sky_videos_user ON sky_videos (user_id);")
    op.execute("CREATE INDEX IF NOT EXISTS idx_sky_videos_tour ON sky_videos (tour_id);")
    # 최신순(타임라인) 정렬 가속
    op.execute("CREATE INDEX IF NOT EXISTS idx_sky_videos_created ON sky_videos (created_at DESC);")

    # 2) live_sessions: 실시간 동시 접속 상태(Presence 권위 소스)
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS live_sessions (
            id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            sky_video_id   UUID NOT NULL REFERENCES sky_videos(id) ON DELETE CASCADE,
            user_id        UUID NOT NULL,
            joined_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT uq_live_room_user UNIQUE (sky_video_id, user_id)
        );
        """
    )
    op.execute("CREATE INDEX IF NOT EXISTS idx_live_sessions_user ON live_sessions (user_id);")
    # 방별 '살아있는' 세션 카운트(=동시 접속자 수) 가속: (방, 하트비트) 복합
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_live_room_alive "
        "ON live_sessions (sky_video_id, last_heartbeat);"
    )
    # 죽은 세션 일괄 청소(GC) 가속
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_live_heartbeat ON live_sessions (last_heartbeat);"
    )

    # 3) Supabase Realtime 발행(Publication) 등록 — 화면 새로고침 없이 INSERT/DELETE 전파.
    #    (Supabase 의 기본 발행 이름은 supabase_realtime. 없으면 무시.)
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
                ALTER PUBLICATION supabase_realtime ADD TABLE live_sessions;
                ALTER PUBLICATION supabase_realtime ADD TABLE sky_videos;
            END IF;
        EXCEPTION WHEN duplicate_object THEN
            -- 이미 발행에 포함되어 있으면 무시
            NULL;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS live_sessions;")
    op.execute("DROP TABLE IF EXISTS sky_videos;")
