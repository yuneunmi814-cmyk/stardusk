# STARDUST · 별의 자취

> **당신이 머문 자리마다 별이 뜹니다.**
>
> GPS와 '하늘'을 매개로, 과시형 SNS 없이 지역 관광지에 존재의 흔적(별·별자리)을 남기는
> 감성 라이프로그 · 힐링 관광 iOS 앱.

**2026 관광데이터 활용 공모전 — ① 웹·앱 개발 부문** 출품작 · **강원도 지역 특화 서비스**

---

## 🌌 서비스 개요

여행지를 걷다 멈춰 고개를 들어 하늘을 담으면, 그 좌표에 나만의 **별(Star)** 이 생깁니다.
하루의 동선은 선으로 이어져 **별자리(여정)** 가 되고, 집으로 돌아오면 그날의 하늘빛으로
물든 나만의 **은하수**를 감상합니다. 좋아요·팔로워·자랑이 아니라, *머문 자리*가 콘텐츠입니다.

- **데이터 출처:** 한국관광공사 국문 관광정보 OpenAPI(위치기반 관광정보 조회)를 핵심 데이터로 활용
- **특화 지역:** 강원특별자치도(areaCode=32) — 강릉·평창 등 명소를 정화 스팟으로 매핑
- **핵심 가치:** 텍스트 입력 0, 과시 0 — 위치와 하늘색만으로 완성되는 비교 없는 기록

## ✨ 주요 기능

| 영역 | 기능 |
|------|------|
| **온보딩/인증** | Apple 로그인(서버 측 토큰 검증), 약관 분리 동의, 위치·알림 권한 안내 |
| **하이브리드 탐색** | 스카이 뷰 홈 / 일반 지도 / 리스트 탐색, 반경 기반 주변 명소(PostGIS) |
| **원버튼 큐레이션** | 카드 3단 액션(패스 · 새로고침 · 라이크)으로 고민 없이 목적지 선택 |
| **취향 학습(개인화)** | 인기도 라벨링(핫플/숨은 명소) + 스와이프 EWMA 학습 → `deck_rank` 개인화 정렬 |
| **하늘 담기 · 별 생성** | 카메라로 하늘 촬영/영상 → 대표 감정색(Hex) 추출 → 좌표에 별 생성 |
| **별자리 · 은하수** | 여정 동선을 LineString으로 누적, 3D 은하수 감상 |
| **트렌딩 피드** | 실시간 동시 접속 + 강원 가중치 정렬의 자동재생 하늘 영상 피드 |

> 데모용 인터랙티브 화면 흐름은 [`STARDUST_프로토타입_시뮬레이션.html`](./STARDUST_프로토타입_시뮬레이션.html) 로 미리 볼 수 있습니다.

## 🏗 기술 스택

- **iOS (Frontend):** SwiftUI · MapKit · CoreLocation · AVFoundation, iOS 17+
- **Backend:** FastAPI(Python 3.11) · SQLModel · Alembic · asyncpg
- **DB/Storage:** Supabase — PostgreSQL + **PostGIS**(지오쿼리), Storage(하늘 미디어)
- **인증:** Sign in with Apple → 서버 JWKS 검증 → 내부 JWT(iOS Keychain 보관)
- **이미지/영상 분석:** Pillow · NumPy · scikit-learn(KMeans 대표색) · imageio-ffmpeg

## 📁 저장소 구조

```
.
├── ios/                     # SwiftUI 앱 (XcodeGen 기반, project.yml → .xcodeproj 생성)
│   ├── Stardust/
│   │   ├── App/             # 진입점 · 로그인
│   │   ├── Core/            # 네트워킹 · 위치 · 세션(Keychain)
│   │   ├── Features/        # 탐색 · 촬영 · 피드 · 내비 · 프로필
│   │   └── Resources/       # Info.plist · Assets · entitlements
│   └── Config/              # Debug/Release xcconfig (API 호스트 분리)
├── backend/                 # FastAPI 백엔드
│   ├── app/
│   │   ├── api/v1/          # auth · tour · trip · stars · galaxy · community
│   │   ├── services/        # 취향 학습 · 색추출 · 관광데이터 동기화 등
│   │   ├── db/ · schemas/ · core/
│   ├── alembic/             # DB 마이그레이션
│   ├── Dockerfile · render.yaml   # 컨테이너/배포
│   └── pyproject.toml
└── *.md                     # 기획서 · PRD · 아키텍처 · iOS 연동 가이드
```

## 🚀 로컬 실행

### 1) 백엔드

```bash
cd backend
cp .env.example .env          # 값 채우기 (아래 환경변수 참고)
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
alembic upgrade head          # 스키마 생성 (PostGIS 필요)
uvicorn app.main:app --reload # http://127.0.0.1:8000/docs
```

또는 Docker로:

```bash
docker build -t stardust-api ./backend
docker run --env-file backend/.env -p 8000:8000 stardust-api
```

### 2) iOS

```bash
cd ios
xcodegen generate             # project.yml → Stardust.xcodeproj
open Stardust.xcodeproj        # Xcode 15+ / iOS 17 SDK
```

- Debug 빌드는 `http://localhost:8000/api/v1`, Release 빌드는 운영 호스트를 바라봅니다
  (`ios/Config/{Debug,Release}.xcconfig` 에서 설정).

## 🔑 환경변수 (`backend/.env`)

`.env.example` 을 복사해 채웁니다. **`.env` 와 모든 시크릿은 절대 커밋하지 않습니다.**

| 키 | 설명 |
|----|------|
| `DATABASE_URL` | Supabase Postgres 연결 문자열(`postgresql+asyncpg://...`) |
| `JWT_SECRET` | 내부 JWT 서명 키(운영 시 강력한 무작위 값) |
| `APPLE_BUNDLE_ID` | Apple identity_token 검증용(= `app.stardust.ios`) |
| `SUPABASE_URL` / `SUPABASE_*_KEY` | Storage 및 키(서비스 롤 키는 **서버 전용**) |
| `KTO_SERVICE_KEY` | 한국관광공사 OpenAPI 서비스 키(서버 전용) |

## 🔐 보안 · 개인정보

- 모든 통신 HTTPS(TLS). 내부 JWT는 iOS **Keychain**에 보관.
- 하늘 미디어 업로드 시 **EXIF 위치정보 제거** 후 전송.
- 한국관광공사 서비스 키·Supabase 서비스 롤 키는 **서버에서만** 사용(클라이언트 미노출, iOS는 ANON 키).
- 위치/카메라/마이크 권한은 사용 목적에 한해 최소 수집, 약관 분리 동의.

## 📄 라이선스

[MIT](./LICENSE)

---

<sub>STARDUST는 2026 관광데이터 활용 공모전 출품을 위해 개발되었습니다. 관광지 데이터는 한국관광공사 OpenAPI를 출처로 합니다.</sub>
