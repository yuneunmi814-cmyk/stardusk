# 경로: backend/app/api/v1/auth.py
# 인증 라우터 (Phase 1 뼈대)
#  - POST /api/v1/auth/login : 소셜 identity_token 검증 → 유저 UPSERT → 내부 JWT 발급
#  - GET  /api/v1/auth/me    : 발급된 토큰으로 본인 확인 (보호 라우트 동작 검증용)
#
# TODO(Phase 1 완성 시):
#   1) verify_social_token() 안의 실제 검증 로직 구현
#      - Google: tokeninfo/JWKS 로 aud=GOOGLE_CLIENT_ID 검증
#      - Apple : appleid JWKS 로 서명/aud=APPLE_BUNDLE_ID/iss 검증
#   2) upsert_user() 를 실제 DB(users 테이블, SQLModel 세션)로 교체

import uuid

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import create_access_token, get_current_user
from app.schemas.auth import LoginData, LoginRequest, LoginResponse

router = APIRouter(prefix="/auth", tags=["auth"])


# ---------------------------------------------------------------------------
# 내부 헬퍼 (현재는 뼈대 = mock. Phase 1에서 실제 구현으로 교체)
# ---------------------------------------------------------------------------
async def verify_social_token(provider: str, identity_token: str) -> dict:
    """소셜 ID 토큰을 검증하고 표준화된 사용자 클레임을 반환한다.

    반환 예: {"subject": "google-uid-123", "email": "...", "name": "..."}
    실패 시 401 을 던진다.
    """
    if not identity_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "code": "INVALID_TOKEN",
                    "message": "유효하지 않은 인증 토큰입니다."},
        )
    # --- 실제 구현 전 임시 처리: 토큰 자체를 식별자로 사용 ---
    return {"subject": f"{provider}:{identity_token[:24]}", "name": None}


async def upsert_user(*, subject: str, nickname: str | None) -> dict:
    """users 테이블에 유저를 생성하거나 조회한다.

    Phase 1: 실제 DB 연동으로 교체. 현재는 결정적 UUID 를 생성해 mock 반환.
    """
    user_id = str(uuid.uuid5(uuid.NAMESPACE_URL, subject))
    return {"user_id": user_id, "nickname": nickname or "이름 없는 여행자"}


# ---------------------------------------------------------------------------
# 엔드포인트
# ---------------------------------------------------------------------------
@router.post("/login", response_model=LoginResponse, summary="소셜 로그인 및 JWT 발급")
async def login(body: LoginRequest) -> LoginResponse:
    claims = await verify_social_token(body.provider, body.identity_token)
    user = await upsert_user(subject=claims["subject"], nickname=body.nickname)

    access_token, expires_in = create_access_token(
        user_id=user["user_id"], nickname=user["nickname"]
    )

    return LoginResponse(
        data=LoginData(
            user_id=user["user_id"],
            nickname=user["nickname"],
            access_token=access_token,
            expires_in=expires_in,
        )
    )


@router.get("/me", summary="현재 토큰의 유저 정보(보호 라우트 검증용)")
async def me(current_user: dict = Depends(get_current_user)) -> dict:
    return {"status": "success", "data": current_user}
