# 경로: backend/alembic/versions/0001_create_tour_spots.py
"""create postgis extension + tour_spots table (GIST index)

Revision ID: 0001
Revises:
Create Date: 2026-05-30
"""
from alembic import op

# revision identifiers, used by Alembic.
revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1) PostGIS 확장 (Supabase 는 extensions 스키마에 설치되어 있을 수 있음)
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis;")

    # 2) tour_spots 테이블 (location: Geometry(Point, 4326))
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS tour_spots (
            id              BIGSERIAL PRIMARY KEY,
            content_id      VARCHAR(20)  NOT NULL,
            content_type_id VARCHAR(10),
            spot_name       VARCHAR(200) NOT NULL,
            region          VARCHAR(60),
            address         VARCHAR(300),
            area_code       VARCHAR(10),
            sigungu_code    VARCHAR(10),
            cat1            VARCHAR(10),
            cat2            VARCHAR(10),
            cat3            VARCHAR(10),
            tel             VARCHAR(60),
            image_url       TEXT,
            location        geometry(Point, 4326) NOT NULL,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )

    # 3) UPSERT 기준 유니크 키 (content_id)
    op.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_tour_spots_content_id "
        "ON tour_spots (content_id);"
    )

    # 4) 공간 인덱스 (ST_DWithin / ST_Distance 반경 조회 가속)
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_tour_spots_geom "
        "ON tour_spots USING GIST (location);"
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS tour_spots;")
    # postgis 확장은 다른 테이블이 의존할 수 있으므로 자동 삭제하지 않음.
