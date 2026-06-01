# 경로: backend/app/api/v1/auth.py
# 인증 라우터 (Phase 1)
#  - POST /api/v1/auth/login : 소셜 identity_token 검증 → 유저 UPSERT → 내부 JWT 발급
#  - GET  /api/v1/auth/me    : 발급된 토큰으로 본인 확인 (보호 라우트 동작 검증용)
#
# 소셜 토큰 검증은 app.services.social_auth 가 Apple/Google 공개키(JWKS)로 수행한다.
# 클라이언트가 보낸 user_id/email 은 신뢰하지 않고, 토큰 서명에서 얻은 sub 만 신뢰한다.

import uuid

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import APIRouter, Depends

from app.core.security import create_access_token, get_current_user
from app.db.session import get_session
from app.schemas.auth import LoginData, LoginRequest, LoginResponse
from app.services.social_auth import verify_social_token

router = APIRouter(prefix="/auth", tags=["auth"])


# provider + provider_sub 로 기존 유저를 찾으면 닉네임/이메일/로그인시각만 갱신하고,
# 없으면 새 user_id(UUID)를 발급해 삽입한다. RETURNING 으로 결과 행을 그대로 받는다.
_UPSERT_USER_SQL = text(
    """
    INSERT INTO users (user_id, provider, provider_sub, email, nickname, created_at, last_login_at)
    VALUES (gen_random_uuid(), :provider, :provider_sub, :email, :nickname, now(), now())
    ON CONFLICT (provider, provider_sub) DO UPDATE SET
        email        = COALESCE(EXCLUDED.email, users.email),
        nickname     = COALESCE(NULLIF(EXCLUDED.nickname, ''), users.nickname),
        last_login_at = now()
    RETURNING user_id, nickname;
    """
)


async def upsert_user(
    session: AsyncSession, *, provider: str, subject: str,
    email: str | None, nickname: str | None,
) -> dict:
    """users 테이블에 멱등 UPSERT. (provider, subject) 가 같으면 동일 user_id 반환."""
    row = (
        await session.execute(
            _UPSERT_USER_SQL,
            {
                "provider": provider,
                "provider_sub": subject,
                "email": email,
                "nickname": (nickname or "").strip() or "이름 없는 여행자",
            },
        )
    ).mappings().first()
    await session.commit()
    return {"user_id": str(row["user_id"]), "nickname": row["nickname"]}


@router.post("/login", response_model=LoginResponse, summary="소셜 로그인 및 JWT 발급")
async def login(
    body: LoginRequest,
    session: AsyncSession = Depends(get_session),
) -> LoginResponse:
    claims = await verify_social_token(body.provider, body.identity_token)
    user = await upsert_user(
        session,
        provider=body.provider,
        subject=claims["subject"],
        email=claims.get("email"),
        nickname=body.nickname or claims.get("name"),
    )

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


@router.post("/guest", response_model=LoginResponse, summary="게스트(비로그인) 둘러보기 토큰")
async def guest_login() -> LoginResponse:
    """로그인 없이 둘러보기 — 임시 익명 사용자에게 내부 JWT 를 발급한다.

    소셜 검증 없이 즉시 발급되며, 매 호출마다 새로운 익명 user_id 를 부여한다.
    탐색/피드 등 읽기 기능을 토큰 기반으로 그대로 이용할 수 있다(기록은 비영구).
    """
    user_id = str(uuid.uuid4())
    nickname = "둘러보는 여행자"
    access_token, expires_in = create_access_token(user_id=user_id, nickname=nickname)
    return LoginResponse(
        data=LoginData(
            user_id=user_id,
            nickname=nickname,
            access_token=access_token,
            expires_in=expires_in,
        )
    )


@router.get("/me", summary="현재 토큰의 유저 정보(보호 라우트 검증용)")
async def me(current_user: dict = Depends(get_current_user)) -> dict:
    return {"status": "success", "data": current_user}
