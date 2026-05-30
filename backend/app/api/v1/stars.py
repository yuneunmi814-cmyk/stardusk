# 경로: backend/app/api/v1/stars.py
# 정화 미션 완료 / 별 생성 라우터 (Phase 4)
#  POST /api/v1/stars (multipart):
#    이미지 + 위경도 + (trip_id, tour_id) 수신
#    → EXIF 위치정보 제거 + 색 분석(상단 절반 대표색/팔레트/감정 라벨)
#    → Supabase Storage 업로드(로컬 폴백)
#    → stars + sky_captures 트랜잭션 저장
#    → '별이 탄생한' 결과 JSON 반환
#
# 인증: Bearer 토큰 필요.

import json
import uuid

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.core.validation import ensure_image_magic, ensure_korea_coords
from app.db.session import get_session
from app.schemas.star import PaletteColor, StarCreateResponse, StarData
from app.services.color_extract import ImageDecodeError, process_sky_image
from app.services.storage import build_object_path, upload_image

router = APIRouter(prefix="/stars", tags=["stars"])

_MAX_IMAGE_BYTES = 12 * 1024 * 1024  # 12MB

_INSERT_STAR = text(
    """
    INSERT INTO stars (user_id, trip_id, tour_id, location, sky_color_hex, emotion_label, captured_at)
    VALUES (
        :user_id, :trip_id, :tour_id,
        ST_SetSRID(ST_MakePoint(:lng, :lat), 4326),
        :sky_color_hex, :emotion_label, now()
    )
    RETURNING id, captured_at;
    """
)

_INSERT_CAPTURE = text(
    """
    INSERT INTO sky_captures (
        star_id, storage_path, width, height,
        dominant_hex, palette, brightness, sky_score, exif_stripped
    ) VALUES (
        :star_id, :storage_path, :width, :height,
        :dominant_hex, CAST(:palette AS JSONB), :brightness, :sky_score, true
    );
    """
)

# trip_id 소유자 검증용
_TRIP_OWNER = text("SELECT user_id FROM user_trips WHERE id = :trip_id;")


@router.post(
    "",
    response_model=StarCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="하늘 촬영 → 색상 추출 → 별 생성",
)
async def create_star(
    image: UploadFile = File(..., description="촬영한 하늘 이미지"),
    latitude: float = Form(..., description="별이 찍힐 위도", examples=[37.7725]),
    longitude: float = Form(..., description="별이 찍힐 경도", examples=[128.9478]),
    trip_id: int | None = Form(None, description="연결할 여정 ID(선택)"),
    tour_id: str | None = Form(None, description="관광공사 콘텐츠 ID(선택)"),
    user: dict = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> StarCreateResponse:
    # 1) 좌표 검증 (전세계 범위 + NaN/Inf + 대한민국 영토 범위)
    ensure_korea_coords(latitude, longitude)

    # 2) 이미지 수신/검증 — Content-Type(1차) → 크기 → 매직 넘버(2차, 위장 차단)
    if image.content_type and not image.content_type.startswith("image/"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"status": "error", "code": "INVALID_IMAGE",
                    "message": "이미지 파일만 업로드할 수 있습니다."},
        )
    raw = await image.read()
    if not raw:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"status": "error", "code": "EMPTY_IMAGE", "message": "이미지가 비어 있습니다."},
        )
    if len(raw) > _MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={"status": "error", "code": "IMAGE_TOO_LARGE", "message": "이미지가 너무 큽니다(최대 12MB)."},
        )
    # 확장자/Content-Type 만 이미지인 척하는 위장 파일을 매직 넘버로 차단.
    ensure_image_magic(raw, image.content_type)

    # 3) trip_id 가 있으면 소유자 검증
    if trip_id is not None:
        row = (await session.execute(_TRIP_OWNER, {"trip_id": trip_id})).first()
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"status": "error", "code": "TRIP_NOT_FOUND", "message": "여정을 찾을 수 없습니다."},
            )
        if str(row[0]) != str(user["user_id"]):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={"status": "error", "code": "FORBIDDEN", "message": "본인의 여정만 연결할 수 있습니다."},
            )

    # 4) EXIF 제거 + 색/팔레트/감정 추출 (1회 디코드)
    try:
        result = process_sky_image(raw)
    except ImageDecodeError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"status": "error", "code": "IMAGE_DECODE_ERROR", "message": "이미지를 해석할 수 없습니다."},
        )

    # 5) 스토리지 업로드 (EXIF 제거된 정규화 JPEG)
    object_path = build_object_path()
    image_url = await upload_image(result["jpeg_bytes"], object_path, "image/jpeg")

    # 6) stars + sky_captures 저장 (단일 트랜잭션)
    palette_full = {
        "dominant": result["dominant_hex"],
        "emotion_label": result["emotion_label"],
        "colors": result["palette"],
    }
    star_row = (await session.execute(_INSERT_STAR, {
        "user_id": uuid.UUID(user["user_id"]),
        "trip_id": trip_id,
        "tour_id": tour_id,
        "lng": longitude,
        "lat": latitude,
        "sky_color_hex": result["dominant_hex"],
        "emotion_label": result["emotion_label"],
    })).first()
    star_id, captured_at = star_row[0], star_row[1]

    await session.execute(_INSERT_CAPTURE, {
        "star_id": star_id,
        "storage_path": object_path,
        "width": result["width"],
        "height": result["height"],
        "dominant_hex": result["dominant_hex"],
        "palette": json.dumps(palette_full, ensure_ascii=False),
        "brightness": result["brightness"],
        "sky_score": result["sky_score"],
    })
    await session.commit()

    # 7) 결과 반환 (별 탄생 JSON)
    return StarCreateResponse(
        data=StarData(
            star_id=star_id,
            trip_id=trip_id,
            tour_id=tour_id,
            latitude=round(latitude, 6),
            longitude=round(longitude, 6),
            sky_color_hex=result["dominant_hex"],
            emotion_label=result["emotion_label"],
            palette=[PaletteColor(**c) for c in result["palette"]],
            brightness=result["brightness"],
            sky_score=result["sky_score"],
            image_url=image_url,
            captured_at=captured_at,
        )
    )
