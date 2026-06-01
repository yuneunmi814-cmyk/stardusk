# STARDUST · iOS 출시 가이드 (Archive → App Store 제출)

Xcode에서 빌드를 아카이브해 App Store Connect에 업로드하고 심사 제출하기까지의 전 과정.
메타데이터 텍스트는 [`APP_STORE_METADATA.md`](./APP_STORE_METADATA.md) 참고.

---

## 0. 사전 점검

- [ ] Apple Developer Program 가입 완료
- [ ] App Store Connect에 앱 레코드 생성됨(Bundle ID `app.stardust.ios`)
- [ ] Xcode에 Apple ID 로그인: **Xcode → Settings → Accounts → (+) Apple ID 추가**
- [ ] 백엔드 Live + 데이터 시딩 완료(릴리스 빌드는 운영 서버를 바라봄)
- [ ] 프로젝트 생성: 터미널에서
  ```bash
  cd ios && xcodegen generate && open Stardust.xcodeproj
  ```

> 릴리스 빌드 API 호스트는 `ios/Config/Release.xcconfig`(현재 `stardust-api-ts8t.onrender.com`).
> 네이버 로그인까지 쓰려면 `ios/Config/Secrets.xcconfig`가 로컬에 있어야 함(없으면 네이버만 비활성).

## 1. 빌드 대상(Destination)을 기기로

Xcode 상단 스킴 옆 기기 선택을 **`Any iOS Device (arm64)`** 로 변경.
(시뮬레이터로는 아카이브 불가)

## 2. 아카이브

- 메뉴 **Product → Archive**
- 빌드가 끝나면 **Organizer** 창이 자동으로 열림(안 열리면 Window → Organizer)
- 서명은 자동(Automatic). `DEVELOPMENT_TEAM = DA6448DUH9` 가 설정돼 있어 Xcode가
  배포 인증서/프로비저닝을 자동 생성·관리함.

## 3. 업로드 (Distribute App)

1. Organizer에서 방금 만든 아카이브 선택 → **Distribute App**
2. **App Store Connect** 선택 → Next
3. **Upload** 선택 → Next
4. 옵션은 기본값(Upload your app's symbols 체크 권장) → Next
5. 서명: **Automatically manage signing** → Next
6. **Upload** → 완료까지 수 분

> 업로드 후 App Store Connect에서 빌드가 **"처리 중(Processing)"** 상태로 뜸(약 15~30분).
> 처리 완료되면 버전에 빌드를 붙일 수 있음.

## 4. App Store Connect — 버전 정보 입력

**My Apps → STARDUST → (iOS 앱) → 1.0 버전 준비** 화면에서:

- **스크린샷**(아래 5번) 업로드
- **프로모션 텍스트 / 설명 / 키워드 / 지원 URL / 마케팅 URL** → `APP_STORE_METADATA.md` 복붙
- **빌드**: 처리 완료된 빌드 선택(+ 버튼)
- **연령 등급**: 설문 답변(`APP_STORE_METADATA.md` 7번). UGC 항목 "예" → 신고/차단 구현됨
- **저작권**: `2026 eunmi yun`
- **카테고리**: 여행

## 5. 스크린샷 준비

App Store는 **6.9"(또는 6.7") iPhone** 스크린샷이 필수(최소 1장, 권장 3~5장).

시뮬레이터로 캡처:
```bash
# 6.9" 기기로 실행 (Xcode 상단에서 iPhone 16 Pro Max 선택 후 Run)
# 앱에서 원하는 화면 이동 후:
#   시뮬레이터 메뉴 → File → Save Screen  (또는 ⌘S)
# 저장 위치: 데스크탑
```
권장 화면: ① 스카이 뷰 홈 ② 명소 큐레이션 카드 ③ 별자리/은하수 ④ 하늘 담기 ⑤ 무대(피드).

> 시뮬레이터 로그인: Apple 로그인은 시뮬레이터에 Apple ID 로그인(Settings 앱) 후 사용 가능.
> 카메라가 필요한 화면은 실기기가 더 자연스러움.

## 6. App Privacy (앱 개인정보 보호)

App Store Connect → **앱 개인정보 보호 → 시작하기** → `APP_STORE_METADATA.md` 8번 표대로:
- 이메일·사용자ID·정확한 위치·사진/영상·오디오·이용기록 = **수집 / 앱 기능 / 사용자 연결 / 추적 아니오**
- 개인정보 처리방침 URL: `https://yuneunmi814-cmyk.github.io/stardusk/privacy.html`

## 7. 심사 정보 + 제출

- **심사 메모(App Review Notes)**: `APP_STORE_METADATA.md` 9번 복붙(백그라운드 위치 소명·테스트 계정·데이터 출처).
- **연락처 정보**: 이름/전화/이메일(yuneunmi814@gmail.com).
- **수출 규정(Export Compliance)**: Info.plist에 `ITSAppUsesNonExemptEncryption=false` 가 있어
  자동 처리됨(표준 HTTPS만 사용 → 면제).
- 상단 **"심사를 위해 추가" / Submit for Review** 클릭.

---

## 자주 나는 오류 & 해결

| 증상 | 해결 |
|------|------|
| **No accounts / 서명 실패** | Xcode → Settings → Accounts에 Apple ID 추가. 타깃 Signing & Capabilities에서 Team = eunmi yun(DA6448DUH9) 확인 |
| **"Failed to create provisioning profile"** | Signing & Capabilities에서 *Automatically manage signing* 체크. Bundle ID가 `app.stardust.ios`(App ID 등록값)와 일치하는지 확인 |
| **"Cannot add Sign in with Apple capability"** | App ID(개발자 콘솔)에 Sign in with Apple이 켜져 있어야 함(이미 등록). Xcode가 자동 동기화 |
| **"Provisioning profile doesn't include signing certificate"** | Settings → Accounts → Manage Certificates에서 Apple Distribution 인증서 생성, 또는 자동관리에 맡기고 재시도 |
| **Archive 메뉴 비활성** | Destination이 시뮬레이터면 비활성 → **Any iOS Device** 선택 |
| **업로드 후 빌드 안 보임** | 처리(Processing)에 15~30분 소요. 메일로 처리 완료/오류 통지 옴 |
| **"Missing Info.plist key (권한 설명)"** | NSLocation*/NSCamera/NSMicrophone 설명 모두 포함됨(Info.plist). 누락 메시지 시 해당 키 확인 |
| **"Invalid Bundle / Unsupported architecture"** | 보통 SPK 캐시 문제. DerivedData 삭제 후 재아카이브: `rm -rf ~/Library/Developer/Xcode/DerivedData/Stardust-*` |
| **TestFlight 설치 후 네이버만 실패** | 로컬 `Secrets.xcconfig`가 빌드에 포함됐는지 확인(네이버 자격증명 주입). 없으면 네이버 비활성 |

---

## 출시 후
- TestFlight로 본인/지인 기기에 설치해 실사용 테스트(실기기 권장).
- 심사는 보통 24~48시간. 리젝 시 사유에 맞춰 대응(대개 UGC/권한 소명 → 이미 준비됨).
