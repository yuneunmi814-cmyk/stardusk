# 경로: backend/app/core/config.py
# 환경변수 기반 설정 관리 (Supabase / JWT / 관광공사 OpenAPI 등)
# pydantic-settings 로 .env 를 읽어 타입 검증된 Settings 싱글턴을 제공한다.

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """애플리케이션 전역 설정.

    값은 .env 파일 또는 OS 환경변수에서 주입된다.
    (.env.example 참고하여 backend/.env 를 생성)
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- 앱 메타 ---
    APP_NAME: str = "STARDUST API"
    APP_ENV: str = Field(default="local", description="local | staging | production")
    DEBUG: bool = True
    API_V1_PREFIX: str = "/api/v1"

    # CORS 허용 오리진(쉼표 구분 문자열 → 리스트)
    CORS_ORIGINS: str = "*"

    # --- 데이터베이스 (Supabase / PostgreSQL + PostGIS) ---
    # 예) postgresql+asyncpg://postgres:[PW]@db.xxxx.supabase.co:5432/postgres
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/stardust"

    # --- Supabase (Storage / 키) ---
    SUPABASE_URL: str = ""
    SUPABASE_ANON_KEY: str = ""
    SUPABASE_SERVICE_ROLE_KEY: str = ""   # 서버 전용 (절대 클라이언트 노출 금지)
    SUPABASE_STORAGE_BUCKET: str = "sky"

    # --- 내부 JWT ---
    JWT_SECRET: str = "CHANGE_ME_super_secret_key"   # 운영에선 반드시 교체
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRES_MINUTES: int = 60                    # 토큰 유효기간(설계서: 1시간)

    # --- 소셜 로그인 검증 ---
    GOOGLE_CLIENT_ID: str = ""        # Google ID 토큰 audience 검증용
    APPLE_BUNDLE_ID: str = ""         # Apple identity_token aud 검증용

    # --- 한국관광공사 OpenAPI ---
    KTO_SERVICE_KEY: str = ""         # 발급받은 서비스 키
    KTO_BASE_URL: str = "https://apis.data.go.kr/B551011/KorService2"
    KTO_DEFAULT_AREA_CODE: str = "32" # 강원도 (지역 특화)

    @property
    def cors_origin_list(self) -> list[str]:
        if self.CORS_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    """설정 싱글턴. 의존성 주입(Depends)으로도 사용 가능."""
    return Settings()


settings = get_settings()
