# 쉼표(Comma) · Android (Kotlin + Jetpack Compose)

iOS와 **동일한 백엔드**(`https://stardust-api-ts8t.onrender.com/api/v1`)를 호출하는 네이티브 안드로이드 클라이언트.
백엔드/데이터/필터(자연 한정)는 그대로 재사용하며, UI만 Compose로 새로 구현했습니다.

## 현재 구현 (MVP 스캐폴드)
- 게스트 로그인(익명 토큰) → 자동 진입
- 탐색: Google Map + 현위치 기준 **주변 자연 명소 마커** (한국 밖이면 강릉 폴백)
- 저장: 라이크한 곳 목록 + 하트로 저장 해제
- 초원 테마(라이트/다크) · 쉼표 브랜드

## 빌드 방법 (Android Studio 필요)
1. **Android Studio**(Koala 이상)로 `android/` 폴더 열기 → Gradle sync(필요 SDK 자동 설치).
2. **Google Maps API 키 발급**(Google Cloud Console → Maps SDK for Android) 후,
   `android/local.properties` 에 추가:
   ```
   MAPS_API_KEY=YOUR_ANDROID_MAPS_KEY
   ```
   (이 파일은 `.gitignore` 처리되어 커밋되지 않습니다)
3. 기기/에뮬레이터 선택 후 **Run**.
   - 에뮬레이터는 Google **Play 포함** 이미지를 사용하세요(Maps 필요).
   - 위치 테스트: 에뮬레이터 위치를 한국(예: 37.7519, 128.8761)으로 설정.

## 다음 단계 (iOS 기능 동등화 로드맵)
- [ ] 큐레이션 카드(스와이프 라이크/패스) — `tour/deck` + `tour/swipe`
- [ ] 길찾기: 카카오맵/네이버지도/구글맵 **인텐트 핸드오프**
- [ ] 안내 듣기: Android `TextToSpeech`(ko-KR) + `tour/{id}/detail`
- [ ] Google 로그인(Credential Manager) · 설정/회원탈퇴 화면
- [ ] 토큰 만료 401 자동 복구(게스트 재발급) 인터셉터
- [ ] KTO 워터마크 크롭(이미지 좌상단 확대)

## 구조
```
android/
├── settings.gradle.kts · build.gradle.kts · gradle.properties
└── app/
    ├── build.gradle.kts            # 의존성(Compose · Maps · Retrofit · Coil)
    └── src/main/
        ├── AndroidManifest.xml     # 위치/인터넷 권한 · Maps 키 placeholder
        ├── res/values/             # strings(앱이름 '쉼표') · themes
        └── java/app/stardust/comma/
            ├── CommaApp.kt · MainActivity.kt
            ├── data/Api.kt         # Retrofit 서비스 + DTO(snake_case)
            ├── data/Session.kt     # 토큰/게스트 로그인/Retrofit 싱글톤
            └── ui/                 # theme · LoginScreen · ExploreScreen · SavedScreen
```

> 빌드는 Android SDK/Studio 환경에서 수행합니다(이 저장소에는 SDK가 포함되지 않음).
> applicationId `app.stardust.comma` — Google Play 등록 시 사용.
