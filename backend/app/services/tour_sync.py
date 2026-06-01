# 경로: backend/app/services/tour_sync.py
# 한국관광공사 OpenAPI 수집·정화 배치 (Phase 2)
#  - 강원도(areaCode=32) 지역기반 관광정보를 페이지네이션으로 전량 수집
#  - 위치기반 관광정보(on-demand 캐시 보강용) 함수도 함께 제공
#  - 정규화 후 tour_spots 테이블에 content_id 기준 UPSERT (중복 없음)
#
# 단독 실행:
#   cd backend
#   python -m app.services.tour_sync                 # 강원 전역 동기화
#   python -m app.services.tour_sync --area 32 --pages 5
#
# APScheduler/cron 에서 run_area_sync() 를 일배치로 호출하면 된다.

from __future__ import annotations

import argparse
import asyncio
import logging
import re

import httpx
from sqlalchemy import text
from tenacity import retry, stop_after_attempt, wait_exponential

from app.core.config import settings
from app.db.session import AsyncSessionLocal

logger = logging.getLogger("tour_sync")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# 공통 요청 파라미터 (KorService2)
_COMMON_PARAMS = {
    "serviceKey": settings.KTO_SERVICE_KEY,   # data.go.kr 에서 발급받은 '디코딩' 키
    "MobileOS": "ETC",
    "MobileApp": "STARDUST",
    "_type": "json",
}

# content_id 기준 UPSERT. location 은 ST_MakePoint(lng, lat) → SRID 4326.
_UPSERT_SQL = text(
    """
    INSERT INTO tour_spots (
        content_id, content_type_id, spot_name, region, address,
        area_code, sigungu_code, cat1, cat2, cat3, tel, image_url,
        readcount, location, created_at, updated_at
    ) VALUES (
        :content_id, :content_type_id, :spot_name, :region, :address,
        :area_code, :sigungu_code, :cat1, :cat2, :cat3, :tel, :image_url,
        :readcount, ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326), now(), now()
    )
    ON CONFLICT (content_id) DO UPDATE SET
        content_type_id = EXCLUDED.content_type_id,
        spot_name       = EXCLUDED.spot_name,
        region          = EXCLUDED.region,
        address         = EXCLUDED.address,
        area_code       = EXCLUDED.area_code,
        sigungu_code    = EXCLUDED.sigungu_code,
        cat1            = EXCLUDED.cat1,
        cat2            = EXCLUDED.cat2,
        cat3            = EXCLUDED.cat3,
        tel             = EXCLUDED.tel,
        image_url       = EXCLUDED.image_url,
        readcount       = EXCLUDED.readcount,
        location        = EXCLUDED.location,
        updated_at      = now();
    """
)

# §3.6① 성향 라벨링 재계산:
#   시군구(sigungu_code) 단위 readcount 백분위(PERCENT_RANK)로 popularity_score 산출,
#   θ_hot(상위 분위 임계값) 이상이면 'hotplace', 아니면 'secret'.
#   → 지역별 분포로 정규화하므로 '강원도 기준 핫플'을 공정하게 라벨링한다.
_RELABEL_SQL = text(
    """
    WITH ranked AS (
        SELECT
            id,
            PERCENT_RANK() OVER (
                PARTITION BY COALESCE(sigungu_code, '_')
                ORDER BY COALESCE(readcount, 0)
            ) AS pr
        FROM tour_spots
    )
    UPDATE tour_spots t
    SET popularity_score = r.pr,
        label = CASE WHEN r.pr >= :theta_hot THEN 'hotplace' ELSE 'secret' END,
        updated_at = now()
    FROM ranked r
    WHERE r.id = t.id;
    """
)

# 시군구 내 상위 (1 - θ) 비율을 'hotplace'로 본다. 0.70 → 상위 30%.
THETA_HOT = 0.70


# ---------------------------------------------------------------------------
# 1) OpenAPI 호출
# ---------------------------------------------------------------------------
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=8))
async def _call(client: httpx.AsyncClient, operation: str, params: dict) -> dict:
    """KorService2 오퍼레이션 호출 + 결과코드 검증 + 재시도."""
    url = f"{settings.KTO_BASE_URL}/{operation}"
    resp = await client.get(url, params={**_COMMON_PARAMS, **params}, timeout=15.0)
    resp.raise_for_status()
    payload = resp.json()

    # data.go.kr 공통 에러는 최상위 resultCode 로(예: 잘못된 파라미터/미등록 키),
    # 정상 응답은 response.header.resultCode 로 온다. 둘 다 검사해 조용한 0건을 막는다.
    _ok = ("0000", "00", None)
    top_code = payload.get("resultCode")
    if top_code not in _ok:
        raise RuntimeError(f"KTO API error: {top_code} {payload.get('resultMsg')}")
    header = payload.get("response", {}).get("header", {})
    if header.get("resultCode") not in _ok:
        raise RuntimeError(f"KTO API error: {header.get('resultCode')} {header.get('resultMsg')}")
    return payload.get("response", {}).get("body", {})


def _items(body: dict) -> list[dict]:
    """응답 body 에서 item 리스트를 안전하게 추출(0건/단건 모두 처리)."""
    items = body.get("items")
    if not items:  # "" 또는 None → 0건
        return []
    item = items.get("item", [])
    return item if isinstance(item, list) else [item]


# ---------------------------------------------------------------------------
# 2) 정규화 (외부 필드 → 내부 스키마)
# ---------------------------------------------------------------------------
def _region_from_addr(addr: str | None) -> str | None:
    """주소 앞 두 토큰을 지역명으로 사용. 예) '강원특별자치도 강릉시 ...' → '강원특별자치도 강릉시'."""
    if not addr:
        return None
    parts = addr.split()
    return " ".join(parts[:2]) if parts else None


def _normalize(item: dict) -> dict | None:
    """관광공사 item → tour_spots 컬럼 dict. 좌표 없는 항목은 제외(None)."""
    try:
        lng = float(item.get("mapx"))   # mapx = 경도(longitude)
        lat = float(item.get("mapy"))   # mapy = 위도(latitude)
    except (TypeError, ValueError):
        return None
    if not (124.0 <= lng <= 132.0 and 33.0 <= lat <= 39.0):  # 한반도 범위 밖 좌표 제거
        return None

    # readcount(조회수) — 인기도 라벨링의 원천. 누락/비정상 값은 0으로.
    try:
        readcount = int(float(item.get("readcount") or 0))
        if readcount < 0:
            readcount = 0
    except (TypeError, ValueError):
        readcount = 0

    addr = item.get("addr1") or None
    return {
        "content_id": str(item.get("contentid")),
        "content_type_id": str(item.get("contenttypeid")) if item.get("contenttypeid") else None,
        "spot_name": (item.get("title") or "").strip() or "이름 미상",
        "region": _region_from_addr(addr),
        "address": addr,
        "area_code": str(item.get("areacode")) if item.get("areacode") else None,
        "sigungu_code": str(item.get("sigungucode")) if item.get("sigungucode") else None,
        "cat1": item.get("cat1") or None,
        "cat2": item.get("cat2") or None,
        "cat3": item.get("cat3") or None,
        "tel": (item.get("tel") or "").strip() or None,
        "image_url": item.get("firstimage") or None,
        "readcount": readcount,
        "longitude": lng,
        "latitude": lat,
    }


# ---------------------------------------------------------------------------
# 3) UPSERT
# ---------------------------------------------------------------------------
async def _upsert(rows: list[dict]) -> int:
    if not rows:
        return 0
    async with AsyncSessionLocal() as session:
        for row in rows:
            await session.execute(_UPSERT_SQL, row)
        await session.commit()
    return len(rows)


async def recompute_labels(theta_hot: float = THETA_HOT) -> int:
    """시군구별 readcount 백분위로 popularity_score/label 을 일괄 재계산한다.

    동기화(UPSERT) 직후 호출. 추천 시점에는 라벨이 미리 계산돼 있어 추가 연산이 없다.
    반환값: 라벨이 갱신된 행 수.
    """
    async with AsyncSessionLocal() as session:
        result = await session.execute(_RELABEL_SQL, {"theta_hot": theta_hot})
        await session.commit()
        updated = result.rowcount or 0
    logger.info("🏷️  성향 라벨 재계산 완료: %s건 (θ_hot=%.2f)", updated, theta_hot)
    return updated


# ---------------------------------------------------------------------------
# 4) 동기화 엔트리포인트
# ---------------------------------------------------------------------------
async def run_area_sync(area_code: str | None = None, num_of_rows: int = 100,
                        max_pages: int | None = None, relabel: bool = True) -> int:
    """지역기반 관광정보(areaBasedList2)를 페이지네이션으로 전량 수집·UPSERT.

    relabel=False 면 성향 라벨 재계산을 건너뛴다(여러 지역 연속 동기화 시,
    마지막에 한 번만 재계산하기 위함).
    """
    area_code = area_code or settings.KTO_DEFAULT_AREA_CODE
    total_saved = 0
    page = 1

    async with httpx.AsyncClient() as client:
        while True:
            body = await _call(
                client,
                "areaBasedList2",
                {
                    "areaCode": area_code,
                    "numOfRows": num_of_rows,
                    "pageNo": page,
                    "arrange": "C",      # C: 등록일순(이미지 포함 우선은 'O')
                },
            )
            items = _items(body)
            if not items:
                break

            rows = [r for r in (_normalize(i) for i in items) if r]
            saved = await _upsert(rows)
            total_saved += saved

            total_count = int(body.get("totalCount", 0))
            logger.info("page=%s fetched=%s saved=%s (누적 %s / 전체 %s)",
                        page, len(items), saved, total_saved, total_count)

            if page * num_of_rows >= total_count:
                break
            if max_pages and page >= max_pages:
                break
            page += 1

    logger.info("✅ area=%s 동기화 완료: %s건 UPSERT", area_code, total_saved)
    # 동기화 직후 성향 라벨(popularity_score/label) 재계산 — 추천 시점 무연산화.
    if relabel:
        await recompute_labels()
    return total_saved


async def fetch_overview(content_id: str) -> str | None:
    """명소 상세설명(detailCommon2 overview)을 가져와 HTML 태그를 제거해 반환.

    도슨트(설명 듣기) — 앱이 이 텍스트를 음성(TTS)으로 읽어준다. 없으면 None.
    """
    async with httpx.AsyncClient() as client:
        body = await _call(client, "detailCommon2", {
            "contentId": content_id,
            "defaultYN": "Y",
            "overviewYN": "Y",
        })
    items = _items(body)
    if not items:
        return None
    raw = items[0].get("overview") or ""
    text = re.sub(r"<[^>]+>", " ", raw)          # HTML 태그 제거
    text = re.sub(r"&[a-zA-Z]+;", " ", text)     # &nbsp; 등 엔티티 제거
    text = re.sub(r"\s+", " ", text).strip()
    return text or None


# 한국관광공사 17개 광역 지역코드 (전국).
ALL_AREA_CODES = [
    "1", "2", "3", "4", "5", "6", "7", "8",
    "31", "32", "33", "34", "35", "36", "37", "38", "39",
]


async def run_all_areas(num_of_rows: int = 100, max_pages: int | None = None) -> int:
    """전국 17개 지역을 순차 동기화하고, 마지막에 성향 라벨을 한 번만 재계산한다."""
    grand_total = 0
    for code in ALL_AREA_CODES:
        try:
            grand_total += await run_area_sync(code, num_of_rows, max_pages, relabel=False)
        except Exception as e:  # 한 지역 실패가 전체를 막지 않도록(예: 일시 오류)
            logger.warning("area=%s 동기화 실패: %s", code, e)
    await recompute_labels()
    logger.info("🌏 전국 동기화 완료: 총 %s건 UPSERT", grand_total)
    return grand_total


async def fetch_location_based(latitude: float, longitude: float, radius: int = 1000,
                               num_of_rows: int = 50) -> int:
    """위치기반 관광정보(locationBasedList2). 캐시 미스 시 on-demand 보강용."""
    async with httpx.AsyncClient() as client:
        body = await _call(
            client,
            "locationBasedList2",
            {
                "mapX": longitude,   # 경도
                "mapY": latitude,    # 위도
                "radius": radius,
                "numOfRows": num_of_rows,
                "pageNo": 1,
                "arrange": "E",      # E: 거리순
            },
        )
        rows = [r for r in (_normalize(i) for i in _items(body)) if r]
        return await _upsert(rows)


def _main() -> None:
    parser = argparse.ArgumentParser(description="STARDUST 관광 데이터 동기화")
    parser.add_argument("--area", default=None, help="areaCode (기본: 강원 32)")
    parser.add_argument("--all", action="store_true", help="전국 17개 지역 전량 동기화")
    parser.add_argument("--rows", type=int, default=100, help="페이지당 건수")
    parser.add_argument("--pages", type=int, default=None, help="최대 페이지(테스트용)")
    args = parser.parse_args()

    if not settings.KTO_SERVICE_KEY:
        raise SystemExit("KTO_SERVICE_KEY 가 비어 있습니다. backend/.env 를 확인하세요.")

    if args.all:
        asyncio.run(run_all_areas(args.rows, args.pages))
    else:
        asyncio.run(run_area_sync(args.area, args.rows, args.pages))


if __name__ == "__main__":
    _main()
