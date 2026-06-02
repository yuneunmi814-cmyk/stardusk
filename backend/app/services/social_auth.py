# 경로: backend/app/services/social_auth.py
# 소셜 ID 토큰 검증 — Apple / Google 의 공개키(JWKS)로 서명·발급자·대상을 검증한다.
#
# Apple "Sign in with Apple":
#   - identity_token 은 Apple 이 RS256 으로 서명한 JWT.
#   - 검증: ① Apple JWKS(공개키)로 서명 ② iss = https://appleid.apple.com
#           ③ aud = 우리 앱 Bundle ID(APPLE_BUNDLE_ID) ④ exp 만료
#   - 신뢰 가능한 클레임 sub(=Apple 사용자 고유 ID), email 을 돌려준다.
#
# 클라이언트가 보내온 user_id/email 을 절대 신뢰하지 않는다 — 반드시 토큰 서명으로 확인한다.

from __future__ import annotations

import time

import httpx
from fastapi import HTTPException, status
from jose import jwt
from jose.exceptions import ExpiredSignatureError, JWTError

from app.core.config import settings

APPLE_ISSUER = "https://appleid.apple.com"
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
GOOGLE_ISSUERS = {"https://accounts.google.com", "accounts.google.com"}
GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"

_JWKS_TTL = 3600  # Apple/Google 공개키 캐시(초). 키 회전 주기보다 짧게 둔다.
_jwks_cache: dict[str, tuple[float, dict]] = {}  # url -> (fetched_at, jwks)


def _auth_error(code: str, message: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail={"status": "error", "code": code, "message": message},
    )


async def _get_jwks(url: str) -> dict:
    """JWKS 를 가져온다(짧은 TTL 캐시). 키 회전에 대비해 만료 시 재요청."""
    now = time.monotonic()
    cached = _jwks_cache.get(url)
    if cached and (now - cached[0]) < _JWKS_TTL:
        return cached[1]
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            jwks = resp.json()
    except (httpx.HTTPError, ValueError) as e:
        # 캐시가 있으면 만료됐어도 임시로 재사용(공개키 서버 일시 장애 대비).
        if cached:
            return cached[1]
        raise _auth_error("AUTH_PROVIDER_UNAVAILABLE",
                          "소셜 인증 서버에 연결하지 못했습니다.") from e
    _jwks_cache[url] = (now, jwks)
    return jwks


def _find_key(jwks: dict, kid: str) -> dict | None:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key
    return None


async def _verify_jwt(token: str, *, jwks_url: str, audience: str,
                      issuers: set[str]) -> dict:
    """공통 JWT 검증기 — JWKS 로 서명/aud/iss/exp 를 확인하고 클레임을 반환."""
    if not token:
        raise _auth_error("INVALID_TOKEN", "유효하지 않은 인증 토큰입니다.")
    try:
        header = jwt.get_unverified_header(token)
    except JWTError as e:
        raise _auth_error("INVALID_TOKEN", "인증 토큰 형식이 올바르지 않습니다.") from e

    kid = header.get("kid")
    jwks = await _get_jwks(jwks_url)
    key = _find_key(jwks, kid) if kid else None
    if key is None:
        # 키가 회전됐을 수 있으니 캐시를 무효화하고 한 번 더 시도.
        _jwks_cache.pop(jwks_url, None)
        jwks = await _get_jwks(jwks_url)
        key = _find_key(jwks, kid) if kid else None
    if key is None:
        raise _auth_error("INVALID_TOKEN", "토큰 서명 키를 확인할 수 없습니다.")

    try:
        claims = jwt.decode(
            token,
            key,
            algorithms=[key.get("alg", "RS256")],
            audience=audience,
            options={"verify_at_hash": False},
        )
    except ExpiredSignatureError as e:
        raise _auth_error("AUTH_EXPIRED", "인증 토큰이 만료되었습니다. 다시 로그인해주세요.") from e
    except JWTError as e:
        raise _auth_error("INVALID_TOKEN", "인증 토큰 검증에 실패했습니다.") from e

    if claims.get("iss") not in issuers:
        raise _auth_error("INVALID_TOKEN", "신뢰할 수 없는 토큰 발급자입니다.")

    return claims


async def verify_apple(identity_token: str) -> dict:
    """Apple identity_token 검증 → {"subject", "email", "name": None}."""
    if not settings.APPLE_BUNDLE_ID:
        raise _auth_error("AUTH_NOT_CONFIGURED",
                          "Apple 로그인이 서버에 설정되어 있지 않습니다.")
    claims = await _verify_jwt(
        identity_token,
        jwks_url=APPLE_JWKS_URL,
        audience=settings.APPLE_BUNDLE_ID,
        issuers={APPLE_ISSUER},
    )
    return {"subject": claims["sub"], "email": claims.get("email"), "name": None}


async def verify_google(identity_token: str) -> dict:
    """Google ID 토큰 검증 → {"subject", "email", "name"}."""
    if not settings.GOOGLE_CLIENT_ID:
        raise _auth_error("AUTH_NOT_CONFIGURED",
                          "Google 로그인이 서버에 설정되어 있지 않습니다.")
    claims = await _verify_jwt(
        identity_token,
        jwks_url=GOOGLE_JWKS_URL,
        audience=settings.GOOGLE_CLIENT_ID,
        issuers=GOOGLE_ISSUERS,
    )
    return {"subject": claims["sub"], "email": claims.get("email"),
            "name": claims.get("name")}


async def verify_social_token(provider: str, identity_token: str) -> dict:
    """provider(apple/google) 별 ID 토큰(JWT) 검증기로 분기."""
    if provider == "apple":
        return await verify_apple(identity_token)
    if provider == "google":
        return await verify_google(identity_token)
    raise _auth_error("UNSUPPORTED_PROVIDER", f"지원하지 않는 로그인 방식입니다: {provider}")
