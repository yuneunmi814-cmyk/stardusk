# 경로: backend/app/services/obfuscate.py
# Safe Zone 좌표 난독화 (위치정보법 컴플라이언스 · 설계서 5장 / 기초 뼈대)
#
# 목적: 사용자가 지정한 거주지 반경(기본 200m) 안의 좌표는 정밀 좌표를 그대로
#       노출하지 않고, 격자(grid)로 스냅해 '흐릿하게' 만들어 주거지 추적을 방지한다.
#
# 현재는 뼈대 단계:
#   - load_safe_zone(user_id) 는 아직 사용자 프로필 저장소가 없어 None 을 반환한다.
#   - users/safe_zone 테이블이 도입되면 load_safe_zone 만 실제 구현으로 교체하면 된다.
#   - obfuscate_path() 는 safe_center 가 None 이면 좌표를 그대로 통과시킨다(무해).

from __future__ import annotations

import math
import uuid

EARTH_RADIUS_M = 6_371_000.0
DEFAULT_SAFE_RADIUS_M = 200.0   # 설계서: 거주지 반경 200m
DEFAULT_GRID_M = 80.0           # 난독화 격자 크기(클수록 더 흐릿)


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 좌표 간 거리(m)."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def _snap(value: float, grid_deg: float) -> float:
    """좌표를 격자 간격으로 스냅(반올림)."""
    return round(value / grid_deg) * grid_deg


def obfuscate_point(
    lat: float,
    lng: float,
    safe_center: tuple[float, float] | None = None,
    radius_m: float = DEFAULT_SAFE_RADIUS_M,
    grid_m: float = DEFAULT_GRID_M,
) -> tuple[float, float, bool]:
    """단일 좌표 난독화. 반환: (lat, lng, obfuscated)."""
    if safe_center is None:
        return lat, lng, False

    clat, clng = safe_center
    if haversine_m(lat, lng, clat, clng) > radius_m:
        return lat, lng, False

    # Safe Zone 내부 → 격자 스냅으로 흐리게 (경도 격자는 위도에 따라 보정)
    grid_lat = grid_m / 111_320.0
    grid_lng = grid_m / (111_320.0 * max(math.cos(math.radians(lat)), 1e-6))
    return _snap(lat, grid_lat), _snap(lng, grid_lng), True


def obfuscate_path(
    coords: list[dict],
    safe_center: tuple[float, float] | None = None,
    radius_m: float = DEFAULT_SAFE_RADIUS_M,
) -> list[dict]:
    """좌표 리스트(dict: latitude/longitude/...)에 난독화를 일괄 적용.

    각 항목에 'obfuscated' 플래그를 추가해 반환한다.
    """
    out: list[dict] = []
    for c in coords:
        lat, lng, blurred = obfuscate_point(c["latitude"], c["longitude"], safe_center, radius_m)
        out.append({**c, "latitude": lat, "longitude": lng, "obfuscated": blurred})
    return out


async def load_safe_zone(user_id: uuid.UUID | str) -> tuple[float, float] | None:
    """사용자의 Safe Zone 중심 좌표를 조회한다.

    TODO(차기 Phase): users/user_settings 테이블에서 거주지 중심 좌표를 읽어온다.
    현재는 저장소가 없어 None(난독화 비활성) 반환.
    """
    return None
