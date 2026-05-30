# 경로: backend/app/services/storage.py
# 이미지 스토리지 업로드 (Supabase Storage REST + 로컬 폴백)
#  - SUPABASE_URL + SERVICE_ROLE_KEY 가 설정되면 Supabase Storage 에 업로드.
#  - 미설정(로컬 개발) 시 backend/_local_storage/ 에 저장해 개발자가 키 없이도 테스트 가능.

from __future__ import annotations

import datetime
import os
import uuid

import httpx

from app.core.config import settings

# 로컬 폴백 저장 위치 (프로젝트 backend/_local_storage)
_LOCAL_DIR = os.path.join(os.getcwd(), "_local_storage")


def build_object_path(prefix: str = "sky", ext: str = "jpg") -> str:
    """스토리지 객체 경로 생성. 예) sky/2026/05/star_<uuid>.jpg"""
    now = datetime.datetime.now(datetime.timezone.utc)
    return f"{prefix}/{now:%Y/%m}/star_{uuid.uuid4().hex}.{ext}"


def _is_supabase_configured() -> bool:
    return bool(settings.SUPABASE_URL and settings.SUPABASE_SERVICE_ROLE_KEY)


async def upload_image(
    data: bytes, object_path: str, content_type: str = "image/jpeg"
) -> str:
    """이미지 바이트를 업로드하고 접근 URL 을 반환한다."""
    if _is_supabase_configured():
        bucket = settings.SUPABASE_STORAGE_BUCKET
        upload_url = f"{settings.SUPABASE_URL}/storage/v1/object/{bucket}/{object_path}"
        headers = {
            "Authorization": f"Bearer {settings.SUPABASE_SERVICE_ROLE_KEY}",
            "Content-Type": content_type,
            "x-upsert": "true",
        }
        async with httpx.AsyncClient() as client:
            resp = await client.post(upload_url, content=data, headers=headers, timeout=30.0)
            resp.raise_for_status()
        # 공개 버킷 기준 공개 URL (비공개면 서명 URL 발급 로직으로 교체)
        return f"{settings.SUPABASE_URL}/storage/v1/object/public/{bucket}/{object_path}"

    # --- 로컬 폴백 ---
    full_path = os.path.join(_LOCAL_DIR, object_path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "wb") as f:
        f.write(data)
    return f"file://{full_path}"
