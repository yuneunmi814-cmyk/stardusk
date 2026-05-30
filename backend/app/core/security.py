# 경로: backend/app/core/security.py
# 내부 JWT 발급 / 검증 + 보호 라우트용 의존성(get_current_user).
# 설계서 Phase 1: 만료 시 401 AUTH_EXPIRED 반환.

from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.core.config import settings

# Swagger UI 에서 Bearer 토큰 입력 가능하게 하는 보안 스키마
_bearer = HTTPBearer(auto_error=False)


def create_access_token(*, user_id: str, nickname: str) -> tuple[str, int]:
    """내부 액세스 토큰 발급. (token, expires_in_seconds) 반환."""
    expires_in = settings.JWT_EXPIRES_MINUTES * 60
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,           # 표준 subject = 유저 식별자
        "nickname": nickname,
        "iat": now,
        "exp": now + timedelta(seconds=expires_in),
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
    return token, expires_in


def decode_access_token(token: str) -> dict:
    """토큰 검증/디코드. 만료/위조 시 401."""
    try:
        return jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "code": "AUTH_EXPIRED",
                    "message": "인증 토큰이 만료되었습니다. 다시 로그인해주세요."},
        )


async def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> dict:
    """보호 라우트 의존성. 헤더의 Bearer 토큰을 검증해 유저 정보를 반환한다.

    사용 예) async def me(user = Depends(get_current_user)): ...
    """
    if creds is None or creds.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "code": "AUTH_REQUIRED",
                    "message": "인증 토큰이 필요합니다."},
        )
    payload = decode_access_token(creds.credentials)
    return {"user_id": payload.get("sub"), "nickname": payload.get("nickname")}
