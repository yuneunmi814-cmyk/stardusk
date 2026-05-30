# 경로: backend/app/services/constellation.py
# 별자리 이름(constellation_name) 자동 생성 유틸 (Phase 5)
#  - 지역명 + 별 개수(규모) + 대표 감정을 조합해 '시(詩)적인' 이름을 만든다.
#  - 동일 입력 → 동일 결과(결정적). 별 개수를 시드로 써서 매번 흔들리지 않게 한다.
#
# 예) "강릉을 수놓은 영혼의 자리" / "안목해변에 새겨진 차분한 별자리"
#
# 핵심 함수:
#   pick_dominant_emotion(labels) -> str | None
#   short_region(region)          -> str            ("강원도 강릉시" → "강릉")
#   generate_constellation_name(region, star_count, dominant_emotion) -> str

from __future__ import annotations

from collections import Counter
from collections.abc import Iterable

# 감정 라벨(color_extract.classify_emotion 결과) → 별자리 이름에 쓸 짧은 수식어
_EMOTION_WORD: dict[str, str] = {
    "고요한 밤": "고요한",
    "잔잔한 구름": "잔잔한",
    "흐린 오후": "사색의",
    "분홍빛 여명": "설레는",
    "따뜻한 노을": "따뜻한",
    "눈부신 햇살": "눈부신",
    "싱그러운 풀빛": "싱그러운",
    "청량한 물빛": "청량한",
    "맑은 오후": "맑은",
    "깊은 쪽빛": "깊은",
    "차분한 새벽": "차분한",
}

# 별 개수(규모)별 표현. 자취가 쌓일수록 더 웅장한 어휘로.
#   (최소 개수, 조사, 수식어(동사 관형형), 명사) — 큰 값부터 검사한다.
#   조사: "obj" → 을/를(받침에 따라),  "loc" → 에
#   최종형: "{지역}{조사} {수식어} [{감정}] {명사}"
#     예) "강릉을 수놓은 영혼의 자리", "안목해변에 새겨진 차분한 별자리"
_SCALE_PHRASES: list[tuple[int, str, str, str]] = [
    (30, "obj", "수놓은", "영혼의 자리"),
    (15, "loc", "새겨진", "별자리"),
    (7, "loc", "이어진", "별무리"),
    (3, "obj", "그려낸", "별자리"),
    (1, "loc", "내려앉은", "작은 별"),
]


def pick_dominant_emotion(labels: Iterable[str | None]) -> str | None:
    """감정 라벨 목록에서 가장 자주 등장한 감정을 고른다(동률이면 사전순 안정 정렬)."""
    counter = Counter(label for label in labels if label)
    if not counter:
        return None
    # 빈도 내림차순 → 동률은 라벨 사전순으로 결정적 선택
    return sorted(counter.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]


def short_region(region: str | None) -> str:
    """'강원도 강릉시' → '강릉' 처럼 마지막 행정구역에서 접미사를 떼어 짧게 만든다."""
    if not region or not region.strip():
        return "어딘가"
    last = region.strip().split()[-1]
    for suffix in ("특별자치시", "광역시", "특별시", "자치구", "자치군", "시", "군", "구", "읍", "면", "동"):
        if last.endswith(suffix) and len(last) > len(suffix):
            return last[: -len(suffix)]
    return last


def _scale_phrase(star_count: int) -> tuple[str, str, str]:
    """규모에 맞는 (조사종류, 수식어, 명사) 반환."""
    for threshold, particle, modifier, noun in _SCALE_PHRASES:
        if star_count >= threshold:
            return particle, modifier, noun
    _, particle, modifier, noun = _SCALE_PHRASES[-1]
    return particle, modifier, noun


def generate_constellation_name(
    region: str | None,
    star_count: int,
    dominant_emotion: str | None = None,
) -> str:
    """지역 + 규모 + 감정을 조합한 별자리 이름을 생성한다.

    규칙:
      - 별이 없으면 '아직 뜨지 않은 별자리'
      - 형식: '{지역}{조사} {수식어} [{감정수식어}] {명사}'
        · 조사는 수식어에 맞춰 을/를(목적격) 또는 에(처격)를 자동 선택
        · 감정 수식어는 명사 바로 앞에 끼워 넣는다(없으면 생략)
    예)
      generate_constellation_name("강원도 강릉시", 34, None)
        → "강릉을 수놓은 영혼의 자리"
      generate_constellation_name("안목해변", 18, "차분한 새벽")
        → "안목해변에 새겨진 차분한 별자리"
    """
    if star_count <= 0:
        return "아직 뜨지 않은 별자리"

    place = short_region(region)
    particle, modifier, noun = _scale_phrase(star_count)
    word = _EMOTION_WORD.get(dominant_emotion or "")

    if particle == "obj":
        josa = "을" if _has_final_consonant(place) else "를"
    else:  # "loc"
        josa = "에"

    noun_part = f"{word} {noun}" if word else noun
    return f"{place}{josa} {modifier} {noun_part}"


def _has_final_consonant(word: str) -> bool:
    """한글 마지막 글자의 받침 유무. (을/를 조사 선택용)"""
    if not word:
        return False
    last = word[-1]
    if "가" <= last <= "힣":
        return (ord(last) - 0xAC00) % 28 != 0
    # 한글이 아니면 받침 없음으로 간주
    return False
