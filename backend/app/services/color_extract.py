# 경로: backend/app/services/color_extract.py
# 하늘빛 색상 추출 + 감정 라벨 매핑 (Phase 4)
#  - Pillow 로 이미지를 디코드(+EXIF 회전 적용 후 EXIF 제거)
#  - '상단 절반(하늘 영역)' 에서 scikit-learn KMeans 로 대표색/팔레트 추출
#  - 대표 Hex → HSV 분석으로 감정 라벨 매핑
#
# 핵심 함수:
#   process_sky_image(raw) -> dict  (정규화 JPEG + 색 분석 결과를 한 번에)
#   classify_emotion(hex)  -> str   (감정 라벨)

from __future__ import annotations

import colorsys
import io

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError
from sklearn.cluster import KMeans


class ImageDecodeError(ValueError):
    """이미지 디코드 실패."""


def _to_hex(rgb: np.ndarray) -> str:
    r, g, b = (int(max(0, min(255, round(float(v))))) for v in rgb[:3])
    return f"#{r:02X}{g:02X}{b:02X}"


def classify_emotion(hex_color: str, brightness: float | None = None) -> str:
    """대표 Hex 색을 HSV 로 분석해 감정 라벨을 반환한다.

    예) 차분한 새벽 / 따뜻한 노을 / 맑은 오후 / 고요한 밤 / 잔잔한 구름 ...
    """
    r = int(hex_color[1:3], 16) / 255.0
    g = int(hex_color[3:5], 16) / 255.0
    b = int(hex_color[5:7], 16) / 255.0
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    hue = h * 360.0

    if v < 0.22:
        return "고요한 밤"
    if s < 0.12:  # 채도 낮음 = 무채색/구름
        return "잔잔한 구름" if v > 0.6 else "흐린 오후"
    if hue >= 330:                    # 분홍·마젠타 계열
        return "분홍빛 여명"
    if hue < 45:                      # 붉은·주황 계열
        return "따뜻한 노을"
    if 45 <= hue < 70:                # 노랑
        return "눈부신 햇살"
    if 70 <= hue < 170:               # 초록
        return "싱그러운 풀빛"
    if 170 <= hue < 200:              # 청록
        return "청량한 물빛"
    if 200 <= hue < 250:              # 파랑
        return "맑은 오후" if v > 0.6 else "깊은 쪽빛"
    return "차분한 새벽"               # 남보라(250~330)


def process_sky_image(raw: bytes, k: int = 3) -> dict:
    """이미지 1회 디코드로 EXIF 제거 + 색 분석 결과를 모두 반환.

    반환:
      jpeg_bytes   : EXIF 제거된 정규화 JPEG 바이트(스토리지 업로드용)
      width/height : 원본 픽셀 크기
      dominant_hex : 상단 절반 대표색
      palette      : [{hex, ratio}] 상위 k개
      brightness   : 0~1 평균 밝기
      sky_score    : 0~1 '하늘 가능성' 휴리스틱
      emotion_label: 감정 라벨
    """
    try:
        img = Image.open(io.BytesIO(raw))
        img = ImageOps.exif_transpose(img)   # EXIF 방향 보정 적용
        img = img.convert("RGB")             # 재인코딩 시 EXIF 미포함 → 위치정보 제거
    except (UnidentifiedImageError, OSError) as exc:
        raise ImageDecodeError("이미지를 해석할 수 없습니다.") from exc

    width, height = img.size

    # EXIF 제거된 정규화 JPEG
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    jpeg_bytes = buf.getvalue()

    # 상단 절반(하늘 영역)만 샘플링 + 다운샘플(연산 비용 절감)
    sky = img.crop((0, 0, width, max(1, height // 2)))
    sky.thumbnail((128, 128))
    arr = np.asarray(sky).reshape(-1, 3).astype(float)

    # KMeans 군집 수는 고유색 수를 넘지 않도록 보정
    unique_colors = np.unique(arr, axis=0).shape[0]
    n_clusters = max(1, min(k, unique_colors))
    km = KMeans(n_clusters=n_clusters, n_init=4, random_state=42).fit(arr)

    counts = np.bincount(km.labels_, minlength=n_clusters).astype(float)
    ratios = counts / counts.sum()
    order = np.argsort(ratios)[::-1]   # 비율 큰 순

    palette = [
        {"hex": _to_hex(km.cluster_centers_[i]), "ratio": round(float(ratios[i]), 3)}
        for i in order
    ]
    dominant_hex = palette[0]["hex"]
    brightness = round(float(arr.mean() / 255.0), 3)

    # 하늘 가능성 휴리스틱: 파랑 우세 or 충분히 밝은 픽셀 비율
    blueish = arr[:, 2] >= arr[:, 0]
    bright = arr.mean(axis=1) > 0.45 * 255
    sky_score = round(float(np.mean(blueish | bright)), 3)

    return {
        "jpeg_bytes": jpeg_bytes,
        "width": width,
        "height": height,
        "dominant_hex": dominant_hex,
        "palette": palette[:k],
        "brightness": brightness,
        "sky_score": sky_score,
        "emotion_label": classify_emotion(dominant_hex, brightness),
    }
