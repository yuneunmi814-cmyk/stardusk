# 경로: backend/app/schemas/auth.py
# 인증 API 요청/응답 스키마 (API 명세서 3.1 기준)

from typing import Literal

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    """POST /api/v1/auth/login 요청 바디."""
    provider: Literal["apple", "google", "kakao", "naver"] = Field(..., examples=["apple"])
    identity_token: str = Field(
        ...,
        description="소셜 제공자 토큰. apple/google 은 ID 토큰(JWT), "
                    "kakao/naver 는 OAuth access_token 을 담는다.",
    )
    nickname: str | None = Field(default=None, examples=["푸른요정"])


class LoginData(BaseModel):
    user_id: str
    nickname: str
    access_token: str
    expires_in: int = Field(..., description="토큰 유효기간(초)")


class LoginResponse(BaseModel):
    status: str = "success"
    message: str = "인증에 성공했습니다."
    data: LoginData
