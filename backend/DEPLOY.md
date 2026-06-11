# STARDUST 백엔드 배포 가이드

**구성:** FastAPI 컨테이너(Render) + PostgreSQL·PostGIS·Storage(Supabase)
컨테이너는 `Dockerfile` 로 빌드되며, 시작 시 `docker/start.sh` 가 `alembic upgrade head` →
`uvicorn` 순으로 실행한다. 호스트 비종속이라 Fly.io/Railway/Cloud Run 도 동일하게 가능.

---

## 0. Supabase 프로젝트 (DB·스토리지) — 선행 필수

1. <https://supabase.com> → **New project** (Region: **Northeast Asia (Seoul)** 권장)
2. **Database → Extensions** 에서 `postgis` 검색 → **Enable**
3. **Storage → New bucket** → 이름 `sky`
4. 연결 정보 수집:
   - **Project Settings → Database → Connection Pooler** 의 연결 문자열(Session mode) 복사
     - ⚠️ Render 등 IPv4 환경에선 직접연결(5432)이 안 붙을 수 있으므로 **Pooler** 문자열 권장
     - 앞부분 스킴을 `postgresql://` → **`postgresql+asyncpg://`** 로 변경해서 `DATABASE_URL` 로 사용
   - **Project Settings → API**: `Project URL`, `anon key`, `service_role key`

## 1. Render 서비스 생성

- <https://render.com> → GitHub 로그인 → 이 레포 연결
- **New → Blueprint** (레포의 `backend/render.yaml` 자동 인식)
  - Blueprint 가 루트 render.yaml 만 읽는 경우: **New → Web Service → Docker**,
    Root Directory `backend`, Dockerfile `./Dockerfile`, Health Check Path `/health`

## 2. 환경변수 (Render 대시보드, `sync:false` 시크릿)

| 키 | 값 |
|----|----|
| `DATABASE_URL` | Supabase Pooler 문자열 (`postgresql+asyncpg://...`) |
| `JWT_SECRET` | 강력한 무작위 값 — `python3 -c "import secrets;print(secrets.token_urlsafe(48))"` |
| `APPLE_BUNDLE_ID` | `app.stardust.ios` |
| `SUPABASE_URL` | Supabase Project URL |
| `SUPABASE_ANON_KEY` | anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | service_role key (**서버 전용**) |
| `SUPABASE_STORAGE_BUCKET` | `sky` |
| `KTO_SERVICE_KEY` | 한국관광공사 OpenAPI 서비스 키 |
| `TMAP_APP_KEY` | TMAP(SK open API) 앱 키 — 도보안내 실경로용. 미설정 시 직선 폴백 |
| `CORS_ORIGINS` | `*` (앱 전용이면 무방) |

> `APP_ENV=production`, `DEBUG=false`, `RUN_MIGRATIONS=1`, `WEB_CONCURRENCY=2` 는
> `render.yaml` 에 이미 지정됨.

## 3. 마이그레이션 (자동)

컨테이너 기동 시 `docker/start.sh` 가 `alembic upgrade head` 로 0001~0007 스키마를
생성한다. 별도 작업 불필요. (여러 인스턴스를 동시에 띄울 때만 `RUN_MIGRATIONS=0` 으로
끄고 릴리스 훅에서 1회 실행)

## 4. 헬스 체크

```
GET https://<your-service>.onrender.com/health   →  {"status":"ok", ...}
GET https://<your-service>.onrender.com/docs      →  Swagger UI
```

## 5. 관광 데이터 시딩 (강원도)

탐색/추천이 동작하려면 한국관광공사 데이터를 DB 에 채워야 한다. Render **Shell** 에서:

```bash
# 강원(areaCode=32) 전량 동기화 + 성향 라벨(popularity/label) 자동 재계산
python -m app.services.tour_sync --area 32 --rows 100

# 빠른 테스트(앞 2페이지만):
python -m app.services.tour_sync --area 32 --rows 100 --pages 2
```

- `KTO_SERVICE_KEY` 가 비어 있으면 즉시 종료하며 알려준다.
- 동기화 직후 `recompute_labels()` 가 시군구별 인기도 백분위로 hotplace/secret 라벨을 갱신.
- 데이터 갱신은 주기적으로(예: 주 1회) 다시 실행하면 된다.

## 6. iOS 연결

배포 URL 이 확정되면 `ios/Config/Release.xcconfig` 의 `STARDUST_API_BASE_URL` 을
`https://<your-service>.onrender.com/api/v1` 로 교체한다.

---

## 트러블슈팅

- **DB 연결 실패/타임아웃** → 직접연결(5432) 대신 Supabase **Connection Pooler** 문자열 사용.
- **콜드 스타트(첫 요청 느림)** → Render 무료 플랜은 15분 미사용 시 휴면. 데모 전 `/health` 를
  한 번 호출해 깨워두거나 유료 플랜으로 상향.
- **`gen_random_uuid()` 오류** → PostgreSQL 13+ 코어 내장(Supabase 기본 포함). 구버전이면
  `CREATE EXTENSION IF NOT EXISTS pgcrypto;` 필요.
