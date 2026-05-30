# 경로: backend/app/core/validation.py
# 입력 방어(보안) 공통 유틸 — 좌표 유효성 + 업로드 파일 매직 넘버 검증.
#  악의적/잘못된 입력이 들어와도 서버가 500 으로 터지지 않고 일관된 400 JSON 으로
#  되돌려주도록, 모든 업로드/좌표 엔드포인트가 이 모듈을 공유한다.
#
# 핵심:
#   ensure_valid_coords(lat, lng)          : 전세계 위경도 범위 + NaN/Inf 방어
#   ensure_korea_coords(lat, lng)          : 대한민국 영토(서비스 지역) 범위 검증
#   ensure_video_magic(raw, content_type)  : 영상 파일 매직 넘버 검증(위장 파일 차단)
#   ensure_image_magic(raw, content_type)  : 이미지 파일 매직 넘버 검증
#   sniff_video_container / sniff_image_format : 순수 시그니처 판별(예외 없음)

from __future__ import annotations

import math

from fastapi import HTTPException, status


def _bad_request(code: str, message: str) -> HTTPException:
    """프로젝트 공통 에러 envelope 로 400 을 만든다."""
    return HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail={"status": "error", "code": code, "message": message},
    )


# ---------------------------------------------------------------------------
# 1) 좌표 검증
# ---------------------------------------------------------------------------
# 대한민국 영토(부속 도서 포함) 를 넉넉히 감싸는 바운딩 박스.
#   - 위도: 마라도(33.06) ~ 강원 최북단(38.6) → 패딩 포함 32.5 ~ 39.0
#   - 경도: 백령도/가거도(124.6) ~ 독도(131.87) → 패딩 포함 124.0 ~ 132.5
# 이 박스를 벗어나면 일본/중국/공해 등 '서비스 영역 밖'으로 간주한다.
KOREA_LAT_MIN = 32.5
KOREA_LAT_MAX = 39.0
KOREA_LNG_MIN = 124.0
KOREA_LNG_MAX = 132.5


def is_finite_coord(value: float) -> bool:
    """NaN / +-Inf 같은 비정상 부동소수 방어."""
    return isinstance(value, (int, float)) and math.isfinite(value)


def ensure_valid_coords(latitude: float, longitude: float) -> None:
    """전세계 위경도 범위(±90 / ±180) + 유한값 검증. 위반 시 400 INVALID_LOCATION."""
    if not (is_finite_coord(latitude) and is_finite_coord(longitude)):
        raise _bad_request("INVALID_LOCATION", "잘못된 위치 정보 좌표입니다.")
    if not (-90.0 <= latitude <= 90.0 and -180.0 <= longitude <= 180.0):
        raise _bad_request("INVALID_LOCATION", "잘못된 위치 정보 좌표입니다.")


def is_in_korea(latitude: float, longitude: float) -> bool:
    """좌표가 대한민국 서비스 영역 바운딩 박스 안인지(유한값 가정 아님)."""
    if not (is_finite_coord(latitude) and is_finite_coord(longitude)):
        return False
    return (
        KOREA_LAT_MIN <= latitude <= KOREA_LAT_MAX
        and KOREA_LNG_MIN <= longitude <= KOREA_LNG_MAX
    )


def ensure_korea_coords(latitude: float, longitude: float) -> None:
    """범위 + 한국 영토 검증을 한 번에. 위반 시 400.

    - 형식/범위 오류  → INVALID_LOCATION
    - 한국 밖 좌표    → OUT_OF_SERVICE_AREA
    """
    ensure_valid_coords(latitude, longitude)
    if not is_in_korea(latitude, longitude):
        raise _bad_request(
            "OUT_OF_SERVICE_AREA",
            "대한민국 영토 밖의 좌표입니다. STARDUST 는 국내(강원) 여행을 위한 서비스예요.",
        )


# ---------------------------------------------------------------------------
# 2) 업로드 파일 매직 넘버(시그니처) 검증
# ---------------------------------------------------------------------------
# ISO Base Media File Format(MP4/MOV/M4V/3GP 등) 은 offset 4 에 'ftyp' 박스가 온다.
# 단, HEIC/AVIF 같은 '이미지' 도 같은 컨테이너를 쓰므로 brand 로 구분해 영상에서 제외한다.
_HEIF_IMAGE_BRANDS = {
    b"heic", b"heix", b"heim", b"heis", b"hevm", b"hevs",
    b"mif1", b"msf1", b"avif", b"avis",
}

# 최소 시그니처 판별에 필요한 헤더 바이트 수.
_SNIFF_MIN_BYTES = 16


def sniff_video_container(raw: bytes) -> str | None:
    """영상 컨테이너 시그니처를 판별해 종류 문자열을 반환(아니면 None)."""
    if len(raw) < _SNIFF_MIN_BYTES:
        return None
    head = raw[:_SNIFF_MIN_BYTES]

    # ISO BMFF: [size:4]['ftyp'][brand:4]
    if head[4:8] == b"ftyp":
        brand = head[8:12]
        if brand in _HEIF_IMAGE_BRANDS:
            return None  # HEIC/AVIF 등 '이미지' → 영상 아님
        return "mp4"     # mp4 / mov(qt) / m4v / 3gp 계열
    # Matroska / WebM (EBML)
    if head[0:4] == b"\x1a\x45\xdf\xa3":
        return "webm"
    # AVI (RIFF....AVI )
    if head[0:4] == b"RIFF" and head[8:12] == b"AVI ":
        return "avi"
    # FLV
    if head[0:3] == b"FLV":
        return "flv"
    # Ogg(Theora 등)
    if head[0:4] == b"OggS":
        return "ogg"
    # MPEG-PS / MPEG-TS
    if head[0:3] == b"\x00\x00\x01":
        return "mpeg"
    if head[0:1] == b"\x47":  # TS sync byte
        return "mpegts"
    return None


def sniff_image_format(raw: bytes) -> str | None:
    """이미지 시그니처를 판별해 포맷 문자열을 반환(아니면 None)."""
    if len(raw) < 12:
        return None
    head = raw[:16]
    if head[0:3] == b"\xff\xd8\xff":
        return "jpeg"
    if head[0:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if head[0:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    if head[0:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    if head[0:2] in (b"MM", b"II"):  # TIFF (HEIC 원본 일부 변환 대비)
        return "tiff"
    if head[4:8] == b"ftyp" and head[8:12] in _HEIF_IMAGE_BRANDS:
        return "heif"
    if head[0:2] == b"BM":
        return "bmp"
    return None


def ensure_video_magic(raw: bytes, content_type: str | None = None) -> str:
    """업로드 바이트가 '진짜 영상'인지 매직 넘버로 검증.

    - 시그니처 미일치 → 400 UNSUPPORTED_VIDEO_FORMAT (확장자/Content-Type 위장 차단)
    반환: 판별된 컨테이너 종류 문자열.
    """
    kind = sniff_video_container(raw)
    if kind is None:
        raise _bad_request(
            "UNSUPPORTED_VIDEO_FORMAT",
            "지원하지 않는 영상 형식입니다. MP4/MOV 등 표준 동영상 파일을 올려주세요.",
        )
    return kind


def ensure_image_magic(raw: bytes, content_type: str | None = None) -> str:
    """업로드 바이트가 '진짜 이미지'인지 매직 넘버로 검증.

    - 시그니처 미일치 → 400 UNSUPPORTED_IMAGE_FORMAT
    반환: 판별된 포맷 문자열.
    """
    fmt = sniff_image_format(raw)
    if fmt is None:
        raise _bad_request(
            "UNSUPPORTED_IMAGE_FORMAT",
            "지원하지 않는 이미지 형식입니다. JPG/PNG/HEIC 등 표준 이미지를 올려주세요.",
        )
    return fmt
