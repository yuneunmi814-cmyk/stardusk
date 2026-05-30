# 경로: backend/alembic/env.py
# Alembic 마이그레이션 실행 환경.
#  - 비동기(asyncpg) URL 을 동기(psycopg2) URL 로 변환해 마이그레이션을 돌린다.
#  - target_metadata 는 SQLModel.metadata (모델 import 로 테이블 등록).

from logging.config import fileConfig

from alembic import context
from sqlalchemy import create_engine, pool

from app.core.config import settings
from app.db import models  # noqa: F401  (모델을 metadata 에 등록)
from sqlmodel import SQLModel

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = SQLModel.metadata


def get_sync_url() -> str:
    """asyncpg URL → psycopg2(동기) URL 로 변환."""
    return settings.DATABASE_URL.replace("+asyncpg", "+psycopg2")


def run_migrations_offline() -> None:
    context.configure(
        url=get_sync_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = create_engine(get_sync_url(), poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
