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


# Kakao/Naver 는 JWT(identity_token)가 아니라 OAuth access_token 을 사용한다.
# 클라이언트가 받은 access_token 으로 각 제공자의 사용자정보 API 를 호출해
# '토큰 유효성 + 안정적인 사용자 id' 를 서버에서 직접 확인한다(위변조 불가).
KAKAO_USERINFO_URL = "https://kapi.kakao.com/v2/user/me"
NAVER_USERINFO_URL = "https://openapi.naver.com/v1/nid/me"


async def _get_userinfo(url: str, access_token: str, provider: str) -> dict:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(
                url, headers={"Authorization": f"Bearer {access_token}"}
            )
    except httpx.HTTPError as e:
        raise _auth_error("AUTH_PROVIDER_UNAVAILABLE",
                          "소셜 인증 서버에 연결하지 못했습니다.") from e
    if resp.status_code == 401:
        raise _auth_error("INVALID_TOKEN", f"{provider} 인증 토큰이 유효하지 않습니다.")
    if resp.status_code >= 400:
        raise _auth_error("INVALID_TOKEN", f"{provider} 사용자 정보 조회에 실패했습니다.")
    try:
        return resp.json()
    except ValueError as e:
        raise _auth_error("INVALID_TOKEN", f"{provider} 응답을 해석하지 못했습니다.") from e


async def verify_kakao(access_token: str) -> dict:
    """카카오 access_token 검증 → {"subject", "email", "name"}.

    kapi.kakao.com/v2/user/me 가 200 을 주면 토큰이 유효한 것이며, 안정적 식별자
    인 카카오 회원번호(id)를 subject 로 사용한다.
    """
    if not access_token:
        raise _auth_error("INVALID_TOKEN", "유효하지 않은 인증 토큰입니다.")
    data = await _get_userinfo(KAKAO_USERINFO_URL, access_token, "kakao")
    uid = data.get("id")
    if uid is None:
        raise _auth_error("INVALID_TOKEN", "카카오 사용자 식별자를 확인할 수 없습니다.")
    account = data.get("kakao_account") or {}
    profile = account.get("profile") or {}
    return {"subject": str(uid), "email": account.get("email"),
            "name": profile.get("nickname")}


async def verify_naver(access_token: str) -> dict:
    """네이버 access_token 검증 → {"subject", "email", "name"}.

    openapi.naver.com/v1/nid/me 의 resultcode 가 '00' 이면 유효하며, response.id
    (네이버 회원 고유 식별자)를 subject 로 사용한다.
    """
    if not access_token:
        raise _auth_error("INVALID_TOKEN", "유효하지 않은 인증 토큰입니다.")
    data = await _get_userinfo(NAVER_USERINFO_URL, access_token, "naver")
    if data.get("resultcode") != "00":
        raise _auth_error("INVALID_TOKEN", "네이버 인증 토큰이 유효하지 않습니다.")
    profile = data.get("response") or {}
    uid = profile.get("id")
    if not uid:
        raise _auth_error("INVALID_TOKEN", "네이버 사용자 식별자를 확인할 수 없습니다.")
    return {"subject": str(uid), "email": profile.get("email"),
            "name": profile.get("name") or profile.get("nickname")}


async def verify_social_token(provider: str, identity_token: str) -> dict:
    """provider 별 검증기로 분기. 표준화된 클레임 dict 를 반환한다.

    apple/google 은 identity_token(JWT)을, kakao/naver 는 OAuth access_token 을
    동일한 필드(identity_token)에 담아 전달한다.
    """
    if provider == "apple":
        return await verify_apple(identity_token)
    if provider == "google":
        return await verify_google(identity_token)
    if provider == "kakao":
        return await verify_kakao(identity_token)
    if provider == "naver":
        return await verify_naver(identity_token)
    raise _auth_error("UNSUPPORTED_PROVIDER", f"지원하지 않는 로그인 방식입니다: {provider}")
