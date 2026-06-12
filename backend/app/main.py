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

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

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
    # debug=False 고정: Starlette ServerErrorMiddleware 가 클라이언트로 '스택 트레이스'를
    # 그대로 덤프하지 못하게 막는다(민감정보·내부구조 노출 차단). 미처리 예외는 아래
    # @app.exception_handler(Exception) 가 일관된 500 JSON 으로 응답하고, 상세는 로그로만 남긴다.
    # (settings.DEBUG 는 DB echo 등 서버 내부 동작 제어용으로만 사용)
    debug=False,
    lifespan=lifespan,
)

# --- 전역 예외 핸들러 -------------------------------------------------------
# 기존 엔드포인트는 HTTPException(detail={status,code,message}) 형태로 에러를 던지고
# FastAPI 가 이를 {"detail": {...}} 로 응답한다. 아래 핸들러도 동일하게 detail 로
# 감싸 클라이언트(iOS) 파싱 계약을 깨지 않으면서, 422 와 미처리 500 을 방어한다.
def _error_body(code: str, message: str, **extra) -> dict:
    return {"detail": {"status": "error", "code": code, "message": message, **extra}}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """타입 불일치/필드 누락 등 요청 검증 실패 → 기본 422 대신 일관된 400 envelope."""
    errors = [
        {"field": ".".join(str(p) for p in e.get("loc", [])), "reason": e.get("msg", "")}
        for e in exc.errors()
    ]
    return JSONResponse(
        status_code=status.HTTP_400_BAD_REQUEST,
        content=_error_body("VALIDATION_ERROR", "요청 형식이 올바르지 않습니다.", errors=errors),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """미처리 예외 catch-all → 500 스택/내부 메시지가 그대로 새어나가지 않도록 방어.

    내부 상세는 서버 로그에만 남기고, 클라이언트에는 일반화된 메시지만 돌려준다.
    """
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=_error_body("INTERNAL_ERROR", "일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요."),
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
    """가벼운 DB 핑(SELECT 1) 포함 — keepalive 워크플로가 이 엔드포인트만 쳐도
    Render(웹)와 Supabase(DB, 무료 플랜 1주 미사용 시 일시정지) 둘 다 깨어 있게 한다.
    DB가 죽어도 200을 유지(payload의 db로 보고) — Render 헬스체크가 재시작 루프를
    돌지 않도록."""
    db = "ok"
    try:
        from sqlalchemy import text as sa_text

        from app.db.session import AsyncSessionLocal

        async with AsyncSessionLocal() as session:
            await asyncio.wait_for(session.execute(sa_text("SELECT 1")), timeout=5.0)
    except Exception:  # noqa: BLE001 — 헬스체크는 어떤 DB 장애에도 200 유지
        db = "unreachable"
    return {"status": "ok", "app": settings.APP_NAME, "env": settings.APP_ENV, "db": db}


@app.get("/", tags=["system"], summary="루트")
async def root() -> dict:
    return {"message": "STARDUST API · 당신이 머문 자리마다 별이 뜹니다.", "docs": "/docs"}
