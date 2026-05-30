# 경로: backend/app/main.py
# FastAPI 앱 진입점. 미들웨어 설정 + 라우터 등록 + 헬스체크.
#
# 실행:
#   cd backend
#   uvicorn app.main:app --reload
# 문서:
#   http://127.0.0.1:8000/docs   (Swagger UI)

import asyncio
import contextlib
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1 import auth, galaxy, galaxy_community, stars, tour, trip
from app.core.config import settings
from app.services.live_session import run_session_gc_loop

logger = logging.getLogger("stardust")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """앱 수명주기 동안 죽은 라이브 세션을 주기적으로 청소하는 백그라운드 태스크 운영.

    (대안: APScheduler AsyncIOScheduler 로 cleanup_stale_sessions 를 interval job 등록)
    """
    gc_task = asyncio.create_task(run_session_gc_loop())
    logger.info("live-session GC 루프 시작")
    try:
        yield
    finally:
        gc_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await gc_task
        logger.info("live-session GC 루프 종료")


app = FastAPI(
    title=settings.APP_NAME,
    version="0.1.0",
    description="STARDUST(별의 자취) - 위치 기반 힐링 관광 서비스 백엔드 API",
    debug=settings.DEBUG,
    lifespan=lifespan,
)

# --- CORS ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 라우터 등록 (Phase 별로 여기에 추가) ---
app.include_router(auth.router, prefix=settings.API_V1_PREFIX)
app.include_router(tour.router, prefix=settings.API_V1_PREFIX)            # Phase 2
app.include_router(trip.router, prefix=settings.API_V1_PREFIX)            # Phase 3
app.include_router(stars.router, prefix=settings.API_V1_PREFIX)          # Phase 4
app.include_router(galaxy.router, prefix=settings.API_V1_PREFIX)         # Phase 5
app.include_router(galaxy_community.router, prefix=settings.API_V1_PREFIX)  # Phase 6


# --- 헬스체크 ---
@app.get("/health", tags=["system"], summary="헬스체크")
async def health() -> dict:
    return {"status": "ok", "app": settings.APP_NAME, "env": settings.APP_ENV}


@app.get("/", tags=["system"], summary="루트")
async def root() -> dict:
    return {"message": "STARDUST API · 당신이 머문 자리마다 별이 뜹니다.", "docs": "/docs"}
