#!/usr/bin/env sh
# 경로: backend/docker/start.sh
# 컨테이너 시작 스크립트.
#  1) RUN_MIGRATIONS=1(기본) 이면 alembic upgrade head 로 스키마를 최신화한다.
#     - 마이그레이션은 psycopg2(동기) 드라이버로 돈다(alembic/env.py 가 +asyncpg→+psycopg2 변환).
#     - 여러 인스턴스 동시 기동 시 한 번만 돌리고 싶다면 배포 플랫폼의 release/predeploy
#       훅으로 옮기고, 여기서는 RUN_MIGRATIONS=0 으로 비활성화한다.
#  2) uvicorn 으로 ASGI 앱을 0.0.0.0:$PORT 에 바인딩한다.
set -e

: "${PORT:=8000}"
: "${RUN_MIGRATIONS:=1}"
: "${WEB_CONCURRENCY:=2}"

if [ "$RUN_MIGRATIONS" = "1" ]; then
  echo "[start] alembic upgrade head ..."
  alembic upgrade head
else
  echo "[start] RUN_MIGRATIONS=$RUN_MIGRATIONS — 마이그레이션 건너뜀"
fi

echo "[start] uvicorn :$PORT (workers=$WEB_CONCURRENCY)"
exec uvicorn app.main:app --host 0.0.0.0 --port "$PORT" --workers "$WEB_CONCURRENCY"
