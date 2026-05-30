# [Tech Design] STARDUST · 기능별 아키텍처 및 백엔드 데이터 설계

> 대상 독자: 프론트엔드(iOS) · 백엔드 개발자
> 전제: 본 문서의 시각 프로토타입(`prototype.html`)을 실제 동작 서비스로 구현
> 타깃 플랫폼: **iOS 네이티브 (SwiftUI)** + **Supabase(PostgreSQL/PostGIS)** + **FastAPI BFF**
> 작성일: 2026-05-30

---

## 0. 시스템 한눈에 보기

```
┌─────────────────────────────────────────────────────────┐
│  iOS App (SwiftUI)                                        │
│   • CoreLocation  → GPS 동선 수집                          │
│   • AVFoundation  → 하늘 촬영                              │
│   • Metal/SpriteKit → 오로라 물결·경로 렌더                 │
│   • SceneKit + CoreMotion → 3D 은하수(자이로)              │
└───────────────┬───────────────────────────────────────────┘
                │ HTTPS (TLS 1.3) · JWT Bearer
┌───────────────▼───────────────────────────────────────────┐
│  STARDUST API (FastAPI · BFF/Backend-for-Frontend)        │
│   • Auth  • Trip 수집  • Star 생성  • Galaxy 집계          │
│   • 이미지 색상 추출(Pillow/numpy)  • Safe Zone 난독화      │
└──────┬──────────────────────┬─────────────────────────────┘
       │                      │
┌──────▼────────┐   ┌─────────▼──────────┐   ┌───────────────┐
│ Supabase      │   │ 캐시/동기화         │   │ 한국관광공사   │
│ Postgres+PostGIS│ │ (tour_spots 테이블) │◄──│ OpenAPI        │
│ Storage(이미지) │  │ 일배치 Sync Job     │   │ (위치기반 관광) │
└───────────────┘   └────────────────────┘   └───────────────┘
```

핵심 설계 원칙: **클라이언트는 외부 API를 직접 호출하지 않는다.** 모든 외부 데이터·연산·키는 BFF(FastAPI) 뒤로 숨기고, 앱은 우리 도메인 스키마만 받는다.

---

## 1. 기능별 아키텍처 및 추천 라이브러리

### 1-1. 실시간 경로 그리기 + 오로라 물결 효과

프로토타입은 HTML5 Canvas 2D + `radialGradient` 누적 방식이다. 이 방식은 데모로는 충분하지만, **글로우/블러/물결이 매 프레임 CPU에서 합성**되므로 별·파티클이 수백 개를 넘어가면 60fps가 깨진다. 핵심은 **빛 번짐(bloom)과 흐르는 물결은 GPU 프래그먼트 셰이더로 처리**해야 끊김이 없다는 점이다.

#### 기술 비교 (개념)

| 기술 | 장점 | 단점 | STARDUST 적합도 |
|---|---|---|---|
| **Canvas 2D** | 구현 쉬움, 의존성 없음 | CPU 바운드, glow/blur 비쌈, 파티클 수천 개 불가 | 프로토타입/웹 폴백용 |
| **WebGL(raw)** | 최고 성능, 셰이더 자유 | 보일러플레이트 많음, 러닝커브 | 직접 사용은 비권장 |
| **Pixi.js** | WebGL 배칭, `GlowFilter`/`DisplacementFilter`로 오로라 즉시 구현 | 2D 한정(3D 은하수엔 부족) | **웹 버전이라면 1순위** |
| **Three.js** | 3D 은하수·자이로 시점에 최적 | 2D UI엔 과함 | 웹 3D 모드용 |

> 위 표는 "웹으로 갈 경우"의 정석이다. 우리는 **iOS 네이티브**이므로 아래 네이티브 매핑을 적용한다.

#### iOS 네이티브 권장 스택 (확정)

| 화면/효과 | 권장 기술 | 이유 |
|---|---|---|
| 배경 별 흐름·반짝임 | **SpriteKit** (`SKEmitterNode`) 또는 `TimelineView` + `Canvas` | 파티클 시스템 내장, 수천 개도 GPU 처리 |
| **오로라 물결 / 경로 발광** | **Metal 프래그먼트 셰이더** (iOS 17+ `View.layerEffect`/`colorEffect` + SkSL 유사 MSL) | 흐르는 물결 = 노이즈 기반 셰이더가 정석. CPU 합성 대비 압도적 성능 |
| 실시간 경로 그리기 | `DragGesture`로 점 수집 → **Catmull-Rom 스플라인** 보간 → `SKShapeNode`/Metal 메쉬 라인 | 손가락 입력을 부드러운 곡선으로, 점은 별 노드로 변환 |
| 별 노드 글로우 | SpriteKit `SKEmitterNode` + additive blend | bloom을 텍스처+가산합성으로 저렴하게 |
| **3D 은하수 (자이로)** | **SceneKit**(`SCNNode` 별 + 라인) + **CoreMotion**(`CMDeviceMotion`) | 기기 기울기 → 카메라 시점, 별/트레일을 3D 공간에 배치 |

**오로라 물결의 핵심 구현 패턴 (어떤 플랫폼이든 동일한 원리):**
경로(LineString)를 따라 폭을 가진 리본 메쉬를 만들고, 그 위에 **시간(`time`) + 좌표를 입력으로 받는 시뮬렉스/펄린 노이즈 프래그먼트 셰이더**를 입혀 색을 흐르게 한다. "물결이 퍼지는" 효과는 경로상의 점에서 발생하는 **링(distance field) 펄스**를 셰이더에서 `sin(dist - time)`으로 그린다. 프로토타입의 `waves[]` radial gradient가 이 셰이더 한 줄로 대체된다.

- 권장 라이브러리: 순수 `MetalKit` + 커스텀 `.metal` 셰이더가 가장 가볍다. 셰이더 작성 난이도를 낮추고 싶으면 **SpriteKit `SKShader`**(셰이더 코드를 SpriteKit에 얹는 방식)를 사용한다.
- CPU에서 점만 수집하고, 보간·발광·물결은 전부 GPU로 넘기는 것이 끊김 없는 60/120fps의 비결.

> **참고(크로스플랫폼 전환 대비):** 추후 Android/웹까지 한 코드로 가려면 `@shopify/react-native-skia`(SkSL 프래그먼트 셰이더)가 위 Metal 셰이더와 거의 1:1로 이식된다. 셰이더 로직을 별도 문자열로 분리해 두면 포팅 비용이 작다.

### 1-2. 한국관광공사 OpenAPI 호출·매핑 아키텍처

직접 호출 금지 이유: ① API 키 노출, ② CORS/요청 제한, ③ 외부 응답 지연이 사용자 화면 지연으로 직결, ④ 응답 포맷(XML/JSON 혼재) 정규화 필요.

**권장: BFF + 로컬 캐시(PostGIS) + 일배치 동기화 하이브리드**

```
[일 1회 배치]  Sync Job ──GET──► 관광공사 OpenAPI(지역기반/위치기반 관광정보)
                  │  강원도 areaCode 필터링 → 정규화 → UPSERT
                  ▼
            tour_spots (PostGIS, GIST 인덱스)
                  ▲
[실시간 요청]  앱 ──GET /tour/spots?lat&lng&radius──► FastAPI
                                                    │ ST_DWithin 공간쿼리(로컬)
                                                    ▼  수 ms 응답
```

- **동기화 잡(Sync Job):** APScheduler(또는 Supabase Edge Function cron)로 매일 새벽 강원도(`areaCode=32`) 관광지를 가져와 `tour_spots`에 UPSERT. 외부 API 변동/장애와 사용자 경험을 분리.
- **실시간 조회:** 앱이 보낸 좌표로 **PostGIS `ST_DWithin`** 반경 쿼리 → 외부 호출 없이 즉시 응답. 캐시 미스(신규 지역)일 때만 on-demand로 외부 호출 후 캐시 채움.
- **호출 클라이언트:** FastAPI에서 `httpx.AsyncClient` + 재시도(tenacity) + 타임아웃. 서비스키는 환경변수/Secret Manager.
- **정규화 계층:** 관광공사 응답 → 내부 `TourSpot` 스키마로 변환하는 adapter를 둬 외부 필드 변경의 충격을 한 곳에 가둔다.

---

## 2. 데이터베이스 및 API 데이터 모델 설계

DB는 Supabase(PostgreSQL) + **PostGIS** 확장 사용. 좌표는 모두 `SRID 4326`.

### 2-1. 사용자 여정(동선) 데이터 — "별자리 선" 렌더링용

동선은 두 레이어로 나눈다. **`trip_points`(원본 GPS 브레드크럼)** 와 이를 압축·연결한 **`trips`(여정/별자리 단위 + LineString)**. 별자리 "선"은 이 LineString을 그대로 렌더한다.

```sql
-- 여정(별자리 1개 단위 = 하루의 산책/관광 세션)
CREATE TABLE trips (
  id                BIGSERIAL PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  region            VARCHAR(40),                    -- "강원도 강릉시"
  constellation_name VARCHAR(60),                   -- "강릉을 수놓은 영혼의 자리"
  path              GEOMETRY(LineString, 4326),     -- 별자리 선(동선 압축 결과)
  distance_meters   INTEGER DEFAULT 0,
  star_count        INTEGER DEFAULT 0,
  started_at        TIMESTAMPTZ NOT NULL,
  ended_at          TIMESTAMPTZ,
  status            VARCHAR(12) DEFAULT 'active'     -- active | completed
);

-- 원본 GPS 동선 점 (별자리 선 보간 + 거리 계산용)
CREATE TABLE trip_points (
  id           BIGSERIAL PRIMARY KEY,
  trip_id      BIGINT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
  location     GEOMETRY(Point, 4326) NOT NULL,
  accuracy_m   REAL,                                -- GPS 정확도(노이즈 필터링용)
  sequence     INTEGER NOT NULL,                    -- 시간 순서
  recorded_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_trip_points_geom ON trip_points USING GIST (location);
CREATE INDEX idx_trips_path_geom  ON trips USING GIST (path);
```

**렌더링용 JSON (`GET /api/v1/stars/my-galaxy` 확장 응답):**
앱은 위경도를 직접 받아 화면 좌표로 투영하고, `path_normalized`(0~1 정규화 좌표)로 즉시 별자리 선을 그린다.

```json
{
  "status": "success",
  "data": {
    "trip_id": 5821,
    "constellation_name": "강릉을 수놓은 영혼의 자리",
    "region": "강원도 강릉시",
    "total_stars_count": 34,
    "distance_meters": 1240,
    "bounds": { "min_lat": 37.77, "min_lng": 128.89, "max_lat": 37.80, "max_lng": 128.95 },
    "stars_trail": [
      {
        "star_id": 9841,
        "sequence": 1,
        "latitude": 37.7951, "longitude": 128.8964,
        "x_norm": 0.12, "y_norm": 0.88,
        "sky_color_hex": "#FFF6D6",
        "captured_at": "2026-05-30T14:20:11Z"
      },
      {
        "star_id": 9845,
        "sequence": 2,
        "latitude": 37.7725, "longitude": 128.9478,
        "x_norm": 0.74, "y_norm": 0.41,
        "sky_color_hex": "#A1C4FD",
        "captured_at": "2026-05-30T20:35:00Z"
      }
    ],
    "path_line": [[0.12,0.88],[0.31,0.70],[0.74,0.41]]
  }
}
```

> `x_norm/y_norm`과 `path_line`은 서버가 `bounds` 기준으로 미리 0~1 투영해 내려준다 → 앱은 화면 크기만 곱하면 되므로 좌표 변환 로직이 단순해지고, **Safe Zone 난독화**(아래)도 서버에서 일괄 적용 가능.

### 2-2. 하늘 정화 미션 데이터 — 이미지 + 감정 색상

기존 `stars`(별=좌표/대표색)에 **`sky_captures`(이미지·색 분석 메타)** 를 1:1로 분리. 이미지 원본은 **Supabase Storage**에 두고 DB엔 경로만 저장.

```sql
-- 별(자취): 위치 + 대표 하늘빛
CREATE TABLE stars (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trip_id       BIGINT REFERENCES trips(id) ON DELETE SET NULL,
  tour_id       VARCHAR(20),                         -- 관광공사 콘텐츠 ID
  location      GEOMETRY(Point, 4326) NOT NULL,
  sky_color_hex CHAR(7) NOT NULL,                    -- 대표 감정 색 "#A1C4FD"
  emotion_label VARCHAR(20),                         -- 색→감정 매핑 "차분한 새벽"
  captured_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_stars_geom ON stars USING GIST (location);

-- 하늘 촬영 이미지 + 색 분석 결과
CREATE TABLE sky_captures (
  id              BIGSERIAL PRIMARY KEY,
  star_id         BIGINT NOT NULL REFERENCES stars(id) ON DELETE CASCADE,
  storage_path    TEXT NOT NULL,                     -- "sky/2026/05/star_9845.jpg"
  thumb_path      TEXT,
  width           INTEGER,
  height          INTEGER,
  dominant_hex    CHAR(7) NOT NULL,                  -- 추출 대표색
  palette         JSONB,                             -- 상위 N색 + 비율
  brightness      REAL,                              -- 0~1 (정화 톤 보정 참고값)
  sky_score       REAL,                              -- AI: 하늘일 확률(유해/오염 필터)
  exif_stripped   BOOLEAN DEFAULT true,              -- 위치 EXIF 제거 여부(프라이버시)
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

**`palette` JSONB 예시 (KMeans/colorthief 결과):**

```json
{
  "dominant": "#A1C4FD",
  "emotion_label": "차분한 새벽",
  "colors": [
    { "hex": "#A1C4FD", "ratio": 0.52 },
    { "hex": "#C2E9FB", "ratio": 0.27 },
    { "hex": "#DFE9F7", "ratio": 0.21 }
  ],
  "sampled_region": "top_half",
  "extracted_at": "2026-05-30T20:35:00Z"
}
```

**별 생성 요청/응답 (`POST /api/v1/stars`):** 색 추출을 **서버에서** 수행하는 것을 권장(클라이언트 위변조 방지 + 일관된 알고리즘). 앱은 이미지 base64/멀티파트만 올린다.

```jsonc
// Request (multipart 권장: image 파일 + 메타 JSON)
{ "tour_id": "301245", "trip_id": 5821,
  "latitude": 37.7725, "longitude": 128.9478 }    // + image binary

// Response 201
{ "status": "success",
  "message": "당신의 자취가 밤하늘의 별로 기록되었습니다.",
  "data": {
    "star_id": 9845,
    "sky_color_hex": "#A1C4FD",
    "emotion_label": "차분한 새벽",
    "image_url": "https://.../sky/2026/05/star_9845.jpg",
    "captured_at": "2026-05-30T20:35:00Z" } }
```

---

## 3. 단계별 백엔드 구현 로드맵 (FastAPI)

> 권장 스택 사유: **FastAPI(Python)** 는 ① 이미지 색상 추출(Pillow/numpy/scikit-learn) ② 지오 연산(Shapely/GeoAlchemy2) ③ AI 하늘 판별(추후 torch/ONNX) 을 한 언어로 처리하기 좋다. Node(NestJS)도 가능하나, 색·AI 처리에서 Python 생태계가 유리.
> 공통 라이브러리: `fastapi`, `uvicorn`, `httpx`, `python-jose`(JWT), `SQLModel`/`asyncpg`, `GeoAlchemy2`, `Pillow`+`numpy`+`scikit-learn`(KMeans), `tenacity`(재시도), `APScheduler`(배치).

### Phase 0 — 기반 (1주)
- 모노레포/폴더 구성: `backend/`(FastAPI), `ios/`(Xcode), `prototype.html` 유지.
- Supabase 프로젝트 생성, **PostGIS 확장 활성화**, Storage 버킷(`sky`) 생성.
- `.env` 시크릿(관광공사 서비스키, JWT secret, Supabase 키), CI(lint+test).
- **산출물:** 헬스체크 `GET /health`, DB 마이그레이션 도구(Alembic) 셋업.

### Phase 1 — 인증 (0.5주)
- `POST /api/v1/auth/login`: Apple/Google identity_token 검증 → `users` UPSERT → 내부 JWT(1h) 발급.
- JWT 미들웨어(만료 시 `401 AUTH_EXPIRED`).
- **산출물:** 보호 라우트 데코레이터, 토큰 발급/검증 테스트.

### Phase 2 — 관광 데이터 파이프라인 (1주)
- `tour_spots` 테이블 + GIST 인덱스.
- **Sync Job**: 관광공사 위치기반/지역기반 관광정보(강원 `areaCode=32`) → 정규화 → UPSERT (APScheduler 일배치).
- `GET /api/v1/tour/spots?lat&lng&radius`: PostGIS `ST_DWithin`로 반경 조회 + `distance_meters` 계산.
- **산출물:** 강원 관광지가 지도에 핀으로 매핑(프로토타입 스팟 데이터 대체).

### Phase 3 — 여정(동선) 수집 (1주)
- `trips` / `trip_points` 테이블.
- `POST /api/v1/trips`(여정 시작), `POST /api/v1/trips/{id}/points`(GPS 배치 업로드 — 배터리 위해 N초 묶음 전송), `PATCH /api/v1/trips/{id}/complete`.
- 서버에서 노이즈 점 제거(정확도 필터) + `ST_MakeLine`으로 `path` 갱신, 거리 누적.
- **산출물:** 앱이 백그라운드로 동선을 안전하게 적재.

### Phase 4 — 정화 미션 / 별 생성 (1.5주)
- `POST /api/v1/stars`(multipart): 이미지 수신 → **EXIF 위치 제거** → Storage 업로드 → **색 추출**(상단 절반 KMeans 대표색 + 팔레트) → `emotion_label` 매핑 테이블 적용 → `stars`+`sky_captures` 저장.
- 썸네일 생성, base64 대용량 대비 멀티파트 권장.
- **산출물:** 촬영→별 생성 결과 팝업(프로토타입 `finishWithColor`)이 실데이터로 동작.

### Phase 5 — 은하수 조회 / 집계 (1주)
- `GET /api/v1/stars/my-galaxy?trip_id=`: `stars_trail` 시간순 + `bounds` 기준 `x_norm/y_norm` 투영 + `path_line` 생성.
- `constellation_name` 자동 생성 규칙(지역+별 수 기반 카피).
- **산출물:** 3D 은하수/별자리 선 렌더에 필요한 정규화 좌표 제공.

### Phase 6 — 보안·프라이버시·운영 (1주, 일부 병행)
- **Safe Zone 난독화:** 사용자 지정 거주지 반경 200m 내 좌표는 응답 시 그리드 스냅/지터 처리(서버 단). `my-galaxy`에서 흐릿 좌표만 노출.
- RLS(Row Level Security)로 본인 데이터만 조회, 민감 식별자 AES-256 저장, TLS 1.3.
- **유해 이미지 필터:** `sky_score`(하늘 확률) 임계치 미만이면 별 생성 거부(초기엔 휴리스틱: 상단 밝기/하늘색 비율 → 추후 ONNX 분류기).
- 비정상 GPS(순간이동/속도) 핵 탐지, 레이트리밋, 로깅/모니터링.
- **산출물:** 개인정보·위치정보법 컴플라이언스 충족(PRD 6장 연계).

### (선택) Phase 7 — 최적화
- `tour_spots` 응답 Redis 캐시, `my-galaxy` materialized view, 부하 테스트(locust), 이미지 CDN.

---

## 4. 제안 폴더 구조

```
[공모전] 2026 관광데이터 활용 공모전/
├── prototype.html                 # 시각 프로토타입(현행)
├── backend/                       # FastAPI
│   ├── app/
│   │   ├── main.py
│   │   ├── core/        (config, security/jwt)
│   │   ├── db/          (session, models, migrations)
│   │   ├── api/v1/      (auth, tour, trips, stars, galaxy)
│   │   ├── services/    (tour_sync, color_extract, obfuscate)
│   │   └── schemas/     (pydantic I/O)
│   ├── tests/
│   └── pyproject.toml
└── ios/                           # SwiftUI 앱
    ├── Features/ (Map, SkyCapture, Galaxy)
    ├── Render/   (Metal 셰이더 .metal, SpriteKit, SceneKit)
    ├── Sensors/  (CoreLocation, CoreMotion, AVFoundation)
    └── Network/  (APIClient, DTO)
```

---

## 5. 요약 — 핵심 의사결정 3가지
1. **오로라 물결·경로 발광은 CPU 합성이 아니라 GPU 프래그먼트 셰이더(Metal)로.** 점 수집만 CPU, 발광/물결/보간은 GPU.
2. **외부 관광 API는 BFF 뒤 PostGIS 캐시로 분리.** 외부 지연·키 노출·요청제한을 사용자 경험에서 떼어낸다.
3. **하늘빛 색 추출은 서버에서.** 위변조 방지 + 알고리즘 일관성 + 유해 이미지 필터를 한 곳에서.
