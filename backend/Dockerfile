# 경로: backend/Dockerfile
# STARDUST 백엔드(FastAPI) 컨테이너 이미지.
#  - python:3.11-slim 기반. Pillow/numpy/scikit-learn/asyncpg 는 manylinux wheel 로 설치되어
#    별도 빌드 도구가 필요 없다. imageio-ffmpeg 가 정적 ffmpeg 바이너리를 동봉한다.
#  - 시작 시 alembic 마이그레이션(옵션) 후 uvicorn 으로 ASGI 앱을 띄운다.
#
# 로컬 빌드/실행:
#   docker build -t stardust-api ./backend
#   docker run --env-file backend/.env -p 8000:8000 stardust-api

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

WORKDIR /srv

# 런타임 라이브러리(대부분 wheel 에 포함되나 안전하게 최소 설치) + 헬스체크용 curl
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 curl \
    && rm -rf /var/lib/apt/lists/*

# 1) 의존성 레이어 캐시: 패키지 메타 + 소스 패키지만 먼저 복사해 설치
COPY pyproject.toml ./
COPY app ./app
RUN pip install .

# 2) 나머지 소스(alembic 마이그레이션, ini, 시작 스크립트 등)
COPY . .

RUN chmod +x docker/start.sh

EXPOSE 8000

# PaaS(Render/Fly/Railway)가 주입하는 $PORT 를 사용. 헬스체크 경로: /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS "http://localhost:${PORT}/health" || exit 1

CMD ["./docker/start.sh"]
