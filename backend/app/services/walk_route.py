# 경로: backend/app/services/walk_route.py
# 도보 경로 안내 — TMAP(SK 오픈 API) 보행자 경로 연동 + 직선 폴백.
#
# 엔드포인트: POST https://apis.openapi.sk.com/tmap/routes/pedestrian?version=1
# 요청/응답 좌표계 WGS84GEO. 응답은 GeoJSON FeatureCollection 으로
# Point(회전지점: turnType·description)와 LineString(구간: distance)이 교차한다.
#
# 반환 형태(라우터/클라이언트 공용):
#   {source, total_m, eta_min, path: [{lat,lng}...], steps: [{lat,lng,distance_m,turn,instruction}...]}
# TMAP_APP_KEY 미설정/호출 실패 시 출발→도착 직선 1구간으로 폴백한다(source="straight").
# 외부 키 없이도 앱의 길찾기 버튼이 항상 동작하게 하는 안전망이다.

from __future__ import annotations

import logging
import math

import httpx

from app.core.config import settings
from app.services.geo import haversine_m

logger = logging.getLogger("walk_route")

_ENDPOINT = "https://apis.openapi.sk.com/tmap/routes/pedestrian"

# 도보 ETA 폴백 속도 — 일반 보행 4km/h(분당 67m). TMAP totalTime 이 있으면 그걸 쓴다.
_WALK_M_PER_MIN = 67.0

# TMAP turnType → 좌/우/직진 3분류. 미정/기타는 직진으로 폴백.
_LEFT_CODES = {12, 16, 17}   # 좌회전, 8시·10시 방향 좌회전
_RIGHT_CODES = {13, 18, 19}  # 우회전, 2시·4시 방향 우회전


def _turn_from_code(turn_type: int | None) -> str:
    if turn_type in _LEFT_CODES:
        return "left"
    if turn_type in _RIGHT_CODES:
        return "right"
    return "straight"


def eta_min_from_distance(total_m: float) -> int:
    return max(1, math.ceil(total_m / _WALK_M_PER_MIN))


def parse_pedestrian(data: dict) -> dict:
    """TMAP 보행자 응답(GeoJSON)을 공용 경로 dict 로 변환 (네트워크 불필요·순수).

    - steps: 회전지점 단위. distance_m 은 직전 지점부터의 구간 거리,
      instruction 은 TMAP description("○○를 따라 120m 이동" 등 한국어 안내문).
    - path: 모든 LineString 좌표를 이어 붙인 폴리라인(순서 보존).
    - total_m/eta_min: 첫 피처 properties 의 totalDistance/totalTime 우선,
      없으면 구간 합산/보행속도로 계산.
    """
    steps: list[dict] = []
    path: list[dict] = []
    accum = 0.0
    seg_total = 0.0
    total_m: float | None = None
    total_sec: float | None = None

    for feat in data.get("features", []):
        geom = feat.get("geometry", {})
        props = feat.get("properties", {})
        gtype = geom.get("type")

        # 총거리/총시간은 출발 피처 properties 에 실려 온다.
        if total_m is None and props.get("totalDistance") is not None:
            total_m = float(props["totalDistance"])
        if total_sec is None and props.get("totalTime") is not None:
            total_sec = float(props["totalTime"])

        if gtype == "LineString":
            d = float(props.get("distance", 0) or 0)
            accum += d
            seg_total += d
            for c in geom.get("coordinates", []):
                try:
                    path.append({"lat": float(c[1]), "lng": float(c[0])})
                except (TypeError, ValueError, IndexError):
                    continue
        elif gtype == "Point":
            point_type = props.get("pointType")
            coords = geom.get("coordinates", [None, None])
            lng, lat = coords[0], coords[1]
            if point_type == "S":
                accum = 0.0  # 출발점 — 단계 없음, 거리 누적만 리셋
                continue
            steps.append(
                {
                    "lat": float(lat),
                    "lng": float(lng),
                    "distance_m": round(accum),
                    "turn": _turn_from_code(props.get("turnType")),
                    "instruction": (props.get("description") or "").strip(),
                }
            )
            accum = 0.0

    total = float(total_m if total_m is not None else seg_total)
    eta = (
        max(1, math.ceil(total_sec / 60.0))
        if total_sec
        else eta_min_from_distance(total)
    )
    return {
        "source": "tmap",
        "total_m": round(total),
        "eta_min": eta,
        "path": path,
        "steps": steps,
    }


def straight_route(
    from_lat: float, from_lng: float, to_lat: float, to_lng: float
) -> dict:
    """직선 폴백 — 키 미설정/외부 실패 시에도 거리·방향·ETA 안내는 유지한다."""
    total = haversine_m(from_lat, from_lng, to_lat, to_lng)
    return {
        "source": "straight",
        "total_m": round(total),
        "eta_min": eta_min_from_distance(total),
        "path": [
            {"lat": from_lat, "lng": from_lng},
            {"lat": to_lat, "lng": to_lng},
        ],
        "steps": [
            {
                "lat": to_lat,
                "lng": to_lng,
                "distance_m": round(total),
                "turn": "straight",
                "instruction": "목적지 방향으로 이동하세요",
            }
        ],
    }


async def fetch_walk_route(
    from_lat: float, from_lng: float, to_lat: float, to_lng: float
) -> dict:
    """도보 경로 조회. TMAP 우선, 키 미설정/실패 시 직선 폴백(예외 없음)."""
    if not settings.TMAP_APP_KEY:
        return straight_route(from_lat, from_lng, to_lat, to_lng)
    body = {
        "startX": str(from_lng),
        "startY": str(from_lat),
        "endX": str(to_lng),
        "endY": str(to_lat),
        "reqCoordType": "WGS84GEO",
        "resCoordType": "WGS84GEO",
        "startName": "출발",
        "endName": "도착",
    }
    headers = {"appKey": settings.TMAP_APP_KEY, "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(
                _ENDPOINT, params={"version": "1"}, json=body, headers=headers
            )
            resp.raise_for_status()
            route = parse_pedestrian(resp.json())
            if not route["path"]:
                raise ValueError("TMAP 응답에 경로 없음")
            return route
    except Exception as exc:  # noqa: BLE001 — 어떤 실패든 직선 폴백으로 길찾기는 살린다
        logger.error("TMAP 보행자 경로 실패, 직선 폴백: %s", exc)
        return straight_route(from_lat, from_lng, to_lat, to_lng)
