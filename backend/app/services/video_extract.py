# 경로: backend/app/services/video_extract.py
# 하늘 영상에서 '첫 프레임'을 순간 포착해 썸네일(JPEG)로 만드는 서비스 (Phase 6.1)
#  - setlog 감성 짧은 하늘 영상 업로드 → 첫 프레임을 뽑아 Phase 4 색상 추출 파이프라인에 투입.
#  - 디코딩 백엔드는 imageio + imageio-ffmpeg(정적 ffmpeg 바이너리 동봉)을 사용해
#    시스템 ffmpeg 설치 없이도 팀원 누구나 바로 돌아가게 한다.
#
# 핵심 함수:
#   extract_first_frame_jpeg(raw, suffix) -> bytes   (첫 프레임 JPEG 바이트)
#
# 반환된 JPEG 바이트는 그대로 color_extract.process_sky_image() 에 넘기면
# 대표 색/팔레트/감정 라벨이 떨어진다(상단 절반 샘플링 K-Means 재사용).

from __future__ import annotations

import io
import os
import tempfile

from PIL import Image


class VideoDecodeError(ValueError):
    """영상 디코드/첫 프레임 추출 실패."""


# 영상 컨테이너 확장자 → 임시파일 suffix 추론용(ffmpeg 가 컨테이너를 인식하도록).
_CONTENT_TYPE_SUFFIX = {
    "video/mp4": ".mp4",
    "video/quicktime": ".mov",
    "video/x-m4v": ".m4v",
    "video/webm": ".webm",
    "video/3gpp": ".3gp",
    "video/x-matroska": ".mkv",
}


def suffix_for(content_type: str | None, filename: str | None) -> str:
    """content_type / 파일명에서 임시파일 확장자를 추론(기본 .mp4)."""
    if content_type and content_type in _CONTENT_TYPE_SUFFIX:
        return _CONTENT_TYPE_SUFFIX[content_type]
    if filename and "." in filename:
        ext = "." + filename.rsplit(".", 1)[-1].lower()
        if 2 <= len(ext) <= 6:
            return ext
    return ".mp4"


def extract_first_frame_jpeg(raw: bytes, suffix: str = ".mp4", quality: int = 90) -> bytes:
    """영상 바이트의 첫 프레임을 JPEG 바이트로 반환한다.

    imageio(ffmpeg)는 파일 경로 기반으로 가장 안정적으로 동작하므로
    임시 파일에 기록 후 첫 프레임만 읽고 즉시 삭제한다.
    """
    try:
        import imageio.v2 as imageio  # 지연 임포트(앱 기동 비용 최소화)
    except ModuleNotFoundError as exc:  # pragma: no cover
        raise VideoDecodeError(
            "영상 디코더가 설치되지 않았습니다. `pip install imageio imageio-ffmpeg` 필요."
        ) from exc

    tmp_path: str | None = None
    reader = None
    try:
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tf:
            tf.write(raw)
            tmp_path = tf.name

        # ffmpeg 플러그인으로 첫 프레임만 디코드
        reader = imageio.get_reader(tmp_path, format="FFMPEG")
        frame = reader.get_data(0)  # numpy ndarray (H, W, 3|4)
    except VideoDecodeError:
        raise
    except Exception as exc:  # 손상/미지원 코덱 등
        raise VideoDecodeError("영상을 해석할 수 없습니다.") from exc
    finally:
        if reader is not None:
            try:
                reader.close()
            except Exception:  # noqa: BLE001
                pass
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ndarray → PIL → JPEG (RGBA 등은 RGB 로 평탄화)
    img = Image.fromarray(frame)
    if img.mode != "RGB":
        img = img.convert("RGB")
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()
