# 경로: backend/app/services/taste.py
# §3.6 · 스와이프 행동을 학습하는 취향 엔진
#  - 성향 라벨(hotplace/secret)은 tour_sync 가 배치로 미리 계산.
#  - 사용자의 Like/Pass 스와이프를 EWMA 로 누적해 taste_score(0..1) 를 갱신(Refresh 제외).
#  - 추천 시점에는 taste_score 를 deck_rank 가중치로 써서 '내 주변 별 탐색' 덱을 재정렬.

from __future__ import annotations

import uuid

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

# ---- 학습/추천 하이퍼파라미터 ----
ALPHA = 0.15          # EWMA 학습률 — 최근 행동에 가중하되 우발적 스와이프엔 둔감
DEFAULT_TASTE = 0.5   # 콜드스타트(중립): 핫플도 숨은 명소도 아님
W_DIST = 0.6          # deck_rank 거리 가중(가까울수록 ↑)
W_TASTE = 0.4         # deck_rank 취향 일치 가중

_GET_TASTE_SQL = text("SELECT taste_score FROM user_taste WHERE user_id = :uid;")
_LABEL_SQL = text("SELECT label FROM tour_spots WHERE content_id = :tour_id;")
# 라이크 시 '저장(찜)' 목록에 추가(중복 무시).
_SAVE_SQL = text(
    """
    INSERT INTO saved_spots (user_id, content_id) VALUES (:uid, :tour_id)
    ON CONFLICT (user_id, content_id) DO NOTHING;
    """
)

# 현재 taste_score 를 Python 에서 계산해 통째로 덮어쓴다(EWMA 는 호출부에서 산출).
_UPSERT_TASTE_SQL = text(
    """
    INSERT INTO user_taste (user_id, taste_score, like_count, pass_count, updated_at)
    VALUES (:uid, :new_score, :like_inc, :pass_inc, now())
    ON CONFLICT (user_id) DO UPDATE SET
        taste_score = :new_score,
        like_count  = user_taste.like_count + :like_inc,
        pass_count  = user_taste.pass_count + :pass_inc,
        updated_at  = now();
    """
)

# 같은 반경 후보를 deck_rank 내림차순으로 정렬해 반환.
#   proximity   = 1 - min(distance/radius, 1)         (가까울수록 1)
#   label_value = hotplace→1.0 / secret→0.0 / 미라벨→0.5(중립)
#   taste_match = 1 - |taste - label_value|           (성향 일치도)
#   deck_rank   = W_DIST·proximity + W_TASTE·taste_match
_DECK_SQL = text(
    """
    WITH nearby AS (
        SELECT
            content_id AS tour_id, spot_name, region, address, image_url,
            label, popularity_score,
            ST_Y(location) AS latitude, ST_X(location) AS longitude,
            ST_Distance(
                location::geography,
                ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
            ) AS distance_meters
        FROM tour_spots
        WHERE ST_DWithin(
            location::geography,
            ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,
            :radius
        )
    )
    SELECT
        tour_id, spot_name, region, address, image_url, label, popularity_score,
        latitude, longitude, distance_meters,
        (
            :w_dist * (1 - LEAST(distance_meters / NULLIF(:radius, 0), 1.0))
            + :w_taste * (
                1 - ABS(:taste - CASE label
                    WHEN 'hotplace' THEN 1.0
                    WHEN 'secret'   THEN 0.0
                    ELSE 0.5 END)
            )
        ) AS deck_rank
    FROM nearby
    ORDER BY deck_rank DESC, distance_meters ASC
    LIMIT :limit;
    """
)


def _label_value(label: str | None) -> float:
    """라벨을 0..1 축으로 매핑. 미라벨은 중립(0.5)."""
    if label == "hotplace":
        return 1.0
    if label == "secret":
        return 0.0
    return 0.5


async def get_taste(session: AsyncSession, user_id: str | uuid.UUID) -> float:
    row = (await session.execute(_GET_TASTE_SQL, {"uid": str(user_id)})).first()
    return float(row[0]) if row else DEFAULT_TASTE


async def apply_swipe(
    session: AsyncSession, user_id: str | uuid.UUID, tour_id: str, action: str
) -> dict:
    """스와이프 1회를 학습에 반영한다.

    - Like(spot):  taste ← (1-α)·taste + α·label_value          (그 성향 쪽으로)
    - Pass(spot):  taste ← (1-α)·taste + α·(1 - label_value)    (반대 성향 쪽으로)
    - Refresh:     '판단 보류' → 학습 제외(현재 스코어만 반환).
    """
    action = (action or "").lower()
    if action == "refresh":
        return {"taste_score": await get_taste(session, user_id), "learned": False,
                "spot_label": None}
    if action not in ("like", "pass"):
        raise ValueError("action must be one of: like, pass, refresh")

    label_row = (await session.execute(_LABEL_SQL, {"tour_id": tour_id})).first()
    label = label_row[0] if label_row else None
    lv = _label_value(label)
    target = lv if action == "like" else (1.0 - lv)

    current = await get_taste(session, user_id)
    new_score = (1 - ALPHA) * current + ALPHA * target
    new_score = min(1.0, max(0.0, new_score))

    await session.execute(
        _UPSERT_TASTE_SQL,
        {
            "uid": str(user_id),
            "new_score": new_score,
            "like_inc": 1 if action == "like" else 0,
            "pass_inc": 1 if action == "pass" else 0,
        },
    )
    if action == "like":   # 라이크 → 저장(찜) 목록에 추가
        await session.execute(_SAVE_SQL, {"uid": str(user_id), "tour_id": tour_id})
    await session.commit()
    return {"taste_score": new_score, "learned": True, "spot_label": label}


async def personalized_deck(
    session: AsyncSession,
    user_id: str | uuid.UUID,
    *,
    latitude: float,
    longitude: float,
    radius: int,
    limit: int,
) -> list[dict]:
    """taste_score 를 반영해 deck_rank 내림차순으로 정렬한 후보를 반환."""
    taste = await get_taste(session, user_id)
    rows = (
        await session.execute(
            _DECK_SQL,
            {
                "lng": longitude,
                "lat": latitude,
                "radius": radius,
                "limit": limit,
                "taste": taste,
                "w_dist": W_DIST,
                "w_taste": W_TASTE,
            },
        )
    ).mappings().all()
    return list(rows)
