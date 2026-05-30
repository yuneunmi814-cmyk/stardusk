# 경로: backend/app/db/session.py
# 비동기 SQLAlchemy 엔진 + 세션 팩토리.
#  - FastAPI 라우터: Depends(get_session) 로 주입
#  - 배치 스크립트: async with AsyncSessionLocal() as s
#
# 엔진은 import 시점에 '생성'만 되고 실제 연결은 첫 쿼리에서 맺어진다(지연 연결).

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings

# DATABASE_URL 예: postgresql+asyncpg://postgres:[PW]@db.xxxx.supabase.co:5432/postgres
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    pool_pre_ping=True,   # 끊긴 커넥션 자동 감지
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI 의존성: 요청 단위 세션을 제공하고 종료 시 정리한다."""
    async with AsyncSessionLocal() as session:
        yield session
