# 쉼표 · Comma

> **잠시 멈추어, 숨을 고르다.**
>
> 복잡한 계획도 검색도 없이, 지금 내 위치에서 가장 가까운 **고요한 자연**으로
> 한 번에 안내하는 힐링 여행 iOS 앱.

**2026 관광데이터 활용 공모전 — 웹·앱 개발 부문** 출품작

---

## 🌿 서비스 개요

여행은 거창한 것이 아니라, 잠시 멈추어 숨을 고르는 것. **쉼표**는 답답할 때 단 한 번의
터치로, 인적이 드물고 고요한 자연 경관지(숲·강변·해변·계곡·산책로)로 가장 빠르고
조용하게 안내합니다. 북적이는 핫플 대신, 자연과 온전히 나를 분리할 수 있는 곳만 모았습니다.

- **데이터 출처:** 한국관광공사 국문 관광정보 OpenAPI(`areaBasedList2` 전량 수집)
- **콘텐츠 범위:** **자연(cat1=A01) 중심** — 산·계곡·폭포·해변·숲·호수·휴양림 등.
  숙박·쇼핑·음식·축제·관변시설·도심상권은 제외(쉼 컨셉 유지)
- **핵심 가치:** 최소한의 안내 — 길은 정확히, 현장 정보는 덜어내 자연에 집중

## ✨ 주요 기능

| 영역 | 기능 |
|------|------|
| **인증** | Sign in with Apple · Google 로그인(서버 JWKS 검증) · **게스트 둘러보기**(익명 토큰) |
| **탐색(지도)** | 현재 위치 기준 주변 자연 명소 마커(PostGIS 반경 조회), 해외/거부 시 강릉 폴백 |
| **원터치 큐레이션** | 풀스크린 카드 — 라이크/패스 스와이프로 고민 없이 다음 쉼표 선택 |
| **취향 학습** | 인기도 라벨(핫플/숨은 명소) + 스와이프 EWMA 학습 → `deck_rank` 개인화 정렬 |
| **저장(찜)** | 라이크한 곳 모아보기 · 하트/편집/스와이프로 간편 삭제 |
| **길찾기 · 안내 듣기** | 외부 지도 앱 핸드오프 · 명소 설명 음성(TTS 도슨트) |
| **테마** | "광활한 초원" 디자인 토큰(라이트/다크) — `ios/Stardust/Theme/MeadowTheme.swift` |

## 🏗 기술 스택

- **iOS:** SwiftUI · MapKit · CoreLocation · AVSpeechSynthesizer(TTS), iOS 17+
- **Backend:** FastAPI(Python 3.11) · SQLAlchemy · Alembic · asyncpg
- **DB:** Supabase — PostgreSQL + **PostGIS**(ST_DWithin/ST_Distance 반경 조회)
- **인증:** Apple/Google → 서버 JWKS 검증 → 내부 JWT(iOS Keychain). 게스트=익명 토큰
- **배포:** Render(Docker, `/health` 헬스체크) · GitHub Pages(개인정보 처리방침)

## 📁 저장소 구조

```
.
├── ios/                         # SwiftUI 앱 (XcodeGen: project.yml → .xcodeproj)
│   └── Stardust/
│       ├── App/                 # 진입점 · 로그인
│       ├── Core/                # 네트워킹 · 위치 · 세션(Keychain) · UI(SpotImage)
│       ├── Theme/               # MeadowTheme (초원 디자인 토큰)
│       ├── Features/Explore/    # 탐색 지도 · 큐레이션 · 저장 · 위치설정
│       └── Features/Navigation/ # 외부 지도 핸드오프 등
├── backend/                     # FastAPI 백엔드
│   ├── app/api/v1/              # auth · tour
│   ├── app/services/            # taste(취향) · tour_sync(KTO 수집)
│   ├── alembic/                 # DB 마이그레이션
│   └── Dockerfile · render.yaml
├── docs/                        # 개인정보 처리방침 · App Store 메타데이터 · 릴리스 가이드
├── screenshots/                 # 앱 스크린샷
└── .github/workflows/           # tour-sync(데이터 동기화) · keepalive(백엔드 상시 가동)
```

## 🚀 로컬 실행

### 백엔드
```bash
cd backend
cp .env.example .env            # DATABASE_URL · JWT_SECRET · KTO_SERVICE_KEY 등
python -m venv .venv && source .venv/bin/activate
pip install -e .
alembic upgrade head            # 스키마(PostGIS 필요)
uvicorn app.main:app --reload   # http://127.0.0.1:8000/docs
```

데이터 수집(전체 카탈로그 — areacode 공백 명소까지):
```bash
python -m app.services.tour_sync --full
```

### iOS
```bash
cd ios
xcodegen generate               # project.yml → Stardust.xcodeproj
open Stardust.xcodeproj          # Xcode 15+ / iOS 17 SDK
```
Debug 빌드는 운영 호스트(`ios/Config/*.xcconfig`)를 바라봅니다.

## 🔑 환경변수 (`backend/.env`)

`.env` 와 모든 시크릿은 **절대 커밋하지 않습니다.**

| 키 | 설명 |
|----|------|
| `DATABASE_URL` | Supabase Postgres(`postgresql+asyncpg://...`) |
| `JWT_SECRET` | 내부 JWT 서명 키 |
| `APPLE_BUNDLE_ID` / `GOOGLE_CLIENT_ID` | 소셜 토큰 검증용 |
| `KTO_SERVICE_KEY` | 한국관광공사 OpenAPI 키(서버 전용) |
| `SUPABASE_*` | DB/스토리지 키(서비스 롤 키는 서버 전용) |

## 🔐 보안 · 개인정보

- 모든 통신 HTTPS(TLS). 내부 JWT는 iOS **Keychain** 보관.
- 위치는 **앱 사용 중에만** 사용(백그라운드/추적 없음). 카메라·마이크·사진 미사용.
- 한국관광공사 키·Supabase 서비스 롤 키는 **서버에서만** 사용.
- 앱 내 **회원 탈퇴**로 계정·데이터 즉시 파기(App Store Guideline 5.1.1 준수).

## 📄 라이선스

[MIT](./LICENSE)

---

<sub>쉼표(Comma)는 2026 관광데이터 활용 공모전 출품을 위해 개발되었습니다. 관광지 데이터는 한국관광공사 OpenAPI를 출처로 합니다.</sub>
