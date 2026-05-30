# 경로: backend/app/services/live_session.py
# 라이브 세션(하늘방) 유지/청소 + Supabase Realtime 브로드캐스트 (Phase 6)
#
# 구성:
#   - HEARTBEAT_TTL_SEC / ALIVE_WINDOW_SEC : '살아있는' 세션 판정 기준
#   - cleanup_stale_sessions(session)      : 하트비트 끊긴 죽은 세션 일괄 삭제(GC)
#   - run_session_gc_loop()                : APScheduler/lifespan 에서 돌릴 주기 청소 루프
#   - broadcast_room_event(...)            : Realtime 채널로 입장/퇴장/카운트 변화 푸시
#
# 설계 메모(실시간 동작 흐름):
#   1) iOS 는 방 입장 시 Supabase Realtime 의 Presence 채널 `room:<sky_video_id>` 를 구독.
#   2) 서버는 live_sessions 를 '권위 있는 카운트 소스'로 유지(트렌딩 정렬·집계용).
#   3) live_sessions 는 Realtime Publication 에 포함(0004 마이그레이션) → INSERT/DELETE 가
#      postgres_changes 로 클라이언트에 자동 전파(화면 새로고침 불필요).
#   4) 추가로 서버가 broadcast_room_event 로 '의미 있는 이벤트'(누가 들어옴/나감, 현재 N명)를
#      직접 푸시 → iOS 가 토스트/햅틱으로 즉시 표현.

from __future__ import annotations

import asyncio
import logging

import httpx
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.session import AsyncSessionLocal

logger = logging.getLogger("stardust.live")

# 하트비트가 이 시간(초) 이상 끊기면 '죽은 세션'으로 간주.
HEARTBEAT_TTL_SEC = 30
# 동시 접속자 카운트 시 '살아있다'고 인정할 윈도우(초). TTL 과 동일하게 둔다.
ALIVE_WINDOW_SEC = HEARTBEAT_TTL_SEC
# 백그라운드 청소 주기(초).
GC_INTERVAL_SEC = 15


_CLEANUP = text(
    """
    DELETE FROM live_sessions
    WHERE last_heartbeat < now() - make_interval(secs => :ttl)
    RETURNING sky_video_id;
    """
)


async def cleanup_stale_sessions(
    session: AsyncSession, ttl_sec: int = HEARTBEAT_TTL_SEC
) -> list[str]:
    """하트비트가 끊긴 죽은 세션을 삭제하고, 영향받은 방 ID 목록을 반환한다."""
    rows = (await session.execute(_CLEANUP, {"ttl": ttl_sec})).fetchall()
    await session.commit()
    return [str(r[0]) for r in rows]


async def run_session_gc_loop(interval_sec: int = GC_INTERVAL_SEC) -> None:
    """주기적으로 죽은 세션을 청소하는 백그라운드 루프.

    main.py 의 lifespan 에서 asyncio.create_task 로 띄우거나,
    APScheduler(AsyncIOScheduler)의 interval job 으로 cleanup_stale_sessions 를 등록해도 된다.
    """
    while True:
        try:
            async with AsyncSessionLocal() as session:
                purged_rooms = await cleanup_stale_sessions(session)
            if purged_rooms:
                logger.info("live-session GC: %d개 방에서 죽은 세션 정리", len(set(purged_rooms)))
                # 청소로 카운트가 변한 방들에 갱신 신호를 보낸다(중복 제거).
                for room_id in set(purged_rooms):
                    await broadcast_room_event(room_id, "presence_sync", {"reason": "gc"})
        except Exception:  # noqa: BLE001 - 루프는 어떤 예외에도 죽지 않아야 한다
            logger.exception("live-session GC loop 오류")
        await asyncio.sleep(interval_sec)


async def broadcast_room_event(
    sky_video_id: str,
    event: str,
    payload: dict,
) -> None:
    """Supabase Realtime 채널 `room:<id>` 로 서버발(Server-side) 브로드캐스트.

    iOS 는 이 채널을 구독해 'A님이 도착했어요', '지금 1,204명이 함께 봐요' 같은
    이벤트를 받아 즉시 토스트/햅틱으로 표현한다.

    Supabase 미설정(로컬)이면 조용히 통과(no-op). 실패해도 본 요청을 막지 않는다(best-effort).
    """
    if not (settings.SUPABASE_URL and settings.SUPABASE_SERVICE_ROLE_KEY):
        return

    url = f"{settings.SUPABASE_URL}/realtime/v1/api/broadcast"
    headers = {
        "apikey": settings.SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }
    body = {
        "messages": [
            {
                "topic": f"room:{sky_video_id}",
                "event": event,                # 예: "user_joined" / "user_left" / "presence_sync"
                "payload": payload,            # 예: {"live_users_count": 1204, "user_id": "..."}
            }
        ]
    }
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(url, json=body, headers=headers)
            resp.raise_for_status()
    except Exception:  # noqa: BLE001 - 브로드캐스트 실패가 API 응답을 막으면 안 된다
        logger.warning("Realtime broadcast 실패 (room=%s, event=%s)", sky_video_id, event)
