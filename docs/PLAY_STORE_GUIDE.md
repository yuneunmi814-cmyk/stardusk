# 쉼표 · Google Play 출시 가이드 (Android)

서명된 App Bundle(.aab) 빌드 → Google Play Console 등록 → 심사 제출까지의 전 과정.
공개 노출 텍스트(설명·키워드 등)는 iOS와 공유하므로 [`APP_STORE_METADATA.md`](./APP_STORE_METADATA.md)를 그대로 재사용합니다.

> 패키지(applicationId): **`app.stardust.comma`** · 표시 이름: **쉼표** · 첫 버전: **1.0 (versionCode 1)**

---

## 0. 사전 점검

- [ ] **Google Play 개발자 계정**($25 1회 등록비) 생성 완료
- [ ] 백엔드 Live + 데이터 시딩 완료 (릴리스도 동일 운영 서버 `stardust-api-ts8t.onrender.com`를 바라봄)
- [ ] `android/local.properties`에 키 존재(빌드에 주입됨, git 미추적):
  ```properties
  MAPS_API_KEY=AIza...
  GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com
  sdk.dir=/Users/<you>/Library/Android/sdk
  ```
- [ ] Android Studio 설치(빌드용 JDK = 내장 JBR 사용)

---

## 1. 릴리스 서명 키스토어 만들기 (최초 1회)

> ⚠️ **키스토어 파일(.jks)과 비밀번호는 절대 잃어버리면 안 됩니다.** 분실 시 같은 앱으로 업데이트 불가.
> git에 **커밋 금지**(`*.keystore`, `*.jks`는 `.gitignore`에 이미 제외). 비밀번호도 코드/저장소에 넣지 마세요.

```bash
# Android Studio의 JDK로 keytool 실행
KT="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
"$KT" -genkeypair -v \
  -keystore ~/comma-release.jks \
  -alias comma -keyalg RSA -keysize 2048 -validity 10000
# → 키스토어 비밀번호, 키 비밀번호, 이름/조직 입력 (직접 입력하세요)
```

`android/keystore.properties` 생성(이 파일도 git 미추적 — 아래 4번에서 제외 처리):
```properties
storeFile=/Users/<you>/comma-release.jks
storePassword=<키스토어 비밀번호>
keyAlias=comma
keyPassword=<키 비밀번호>
```

### build.gradle.kts 서명 설정(아직 없다면 추가)
`android/app/build.gradle.kts`의 `android { }` 안에:
```kotlin
val keystoreProps = rootProject.file("keystore.properties").let { f ->
    if (f.exists()) java.util.Properties().apply { f.inputStream().use { load(it) } } else null
}
signingConfigs {
    if (keystoreProps != null) create("release") {
        storeFile = file(keystoreProps.getProperty("storeFile"))
        storePassword = keystoreProps.getProperty("storePassword")
        keyAlias = keystoreProps.getProperty("keyAlias")
        keyPassword = keystoreProps.getProperty("keyPassword")
    }
}
buildTypes {
    release {
        isMinifyEnabled = false
        if (keystoreProps != null) signingConfig = signingConfigs.getByName("release")
    }
}
```

> **Play 앱 서명(권장):** 위 키는 *업로드 키*가 되고, Play가 최종 배포 서명을 관리합니다.
> 업로드 후 Play Console → **설정 → 앱 무결성**에서 Google이 관리하는 **앱 서명 인증서의 SHA-1**을 확인해
> 아래 7번(OAuth·Maps)에 등록합니다.

---

## 2. 릴리스 App Bundle(.aab) 빌드

```bash
cd android
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew :app:bundleRelease
# 산출물: app/build/outputs/bundle/release/app-release.aab
```
- [ ] 빌드 성공, `app-release.aab` 생성 확인
- [ ] (선택) 로컬 설치 테스트는 `./gradlew :app:assembleRelease`로 .apk 생성 후 `adb install`

---

## 3. Play Console — 앱 만들기 & 스토어 등록정보

**Play Console → 앱 만들기**
- 앱 이름: `쉼표 - 가까운 자연으로`  · 기본 언어: 한국어 · 앱/무료 · 무료

**스토어 등록정보(기본 스토어 등록정보)** — 메타데이터 문서에서 복사:
| 항목 | 값/출처 |
|------|--------|
| 앱 이름 (≤30자) | `쉼표 - 가까운 자연으로` |
| 간단한 설명 (≤80자) | `잠시 멈추어, 숨을 고르다 — 한 번의 터치로 가장 가까운 고요한 자연으로` |
| 자세한 설명 (≤4000자) | `APP_STORE_METADATA.md` §4 앱 설명 그대로 |
| 앱 아이콘 (512×512 PNG) | 아래 4번에서 생성 |
| 그래픽 이미지(피처) 1024×500 | 아래 4번에서 생성 |
| 휴대전화 스크린샷(2~8장) | `android/screenshots/` (1080×2400) |

> 카테고리: **여행 및 지역**(Travel & Local). 태그에 힐링/자연/산책 등 선택.

---

## 4. 그래픽 자산 (아이콘 512 · 피처 그래픽 1024×500)

런처 아이콘 원본은 `android/app/src/main/res/mipmap-*/ic_launcher.png`(쉼표 콤마, 초원 그라데이션).
Play용 자산은 별도 규격이 필요:

```bash
# 512 아이콘 (mipmap 원본에서 리사이즈) — sips는 macOS 기본 제공
sips -z 512 512 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png \
     --out android/screenshots/play_icon_512.png
```
- [x] **512×512 아이콘** → `android/screenshots/play_icon_512.png`
- [x] **1024×500 피처 그래픽** → `android/screenshots/play_feature_1024x500.png`
      (초원 그라데이션 + "쉼 표 / 잠시 멈추어, 숨을 고르다". 재생성: `swift /tmp/feature_graphic.swift <out.png>`)

---

## 5. 콘텐츠 등급 (IARC 설문)

대부분 **아니오** → 전체 이용가. (메타데이터 §7과 동일)
- 폭력/성적/욕설/도박/약물 콘텐츠: 없음
- 사용자 생성 콘텐츠/소셜 기능: **없음**
- 위치 공유: 사용자 본인에게만(주변 명소 안내 용도)

---

## 6. 데이터 보안(Data safety) 양식

App Store 개인정보 라벨(§8)과 동일하게 매핑:

| 데이터 | 수집 | 공유 | 용도 | 목적 |
|--------|------|------|------|------|
| 대략/정확한 위치 | 예 | 아니오 | 앱 기능 | 주변 자연 명소 안내(앱 사용 중에만) |
| 이메일 주소 | 예 | 아니오 | 앱 기능/계정 관리 | 소셜 로그인 |
| 이름(닉네임) | 예 | 아니오 | 앱 기능 | 닉네임 표시 |
| 사용자 ID | 예 | 아니오 | 앱 기능/계정 관리 | 계정 식별 |
| 앱 활동(저장·취향) | 예 | 아니오 | 앱 기능 | 저장 목록·추천 정렬 |

- 전송 중 **암호화(HTTPS)** ✔ · 사용자가 **계정·데이터 삭제 요청 가능**(설정 → 회원 탈퇴) ✔
- **추적/광고 목적 사용 없음**, 데이터 브로커 공유 없음.
- 카메라·마이크·사진·연락처: 수집 안 함.

---

## 7. Google 로그인 · 지도 — 릴리스 SHA 등록 (중요)

릴리스 빌드는 **디버그와 다른 서명 인증서**를 씁니다. Google 로그인/지도가 릴리스에서 동작하려면:

1. **릴리스 SHA-1 확인**
   - Play 앱 서명 사용 시: Play Console → **설정 → 앱 무결성 → 앱 서명 키 인증서**의 SHA-1
   - (업로드 키 SHA-1도 함께) `keytool -list -v -keystore ~/comma-release.jks -alias comma`
2. **Google Cloud Console → 사용자 인증 정보**
   - **Android OAuth 클라이언트**: 패키지 `app.stardust.comma` + 위 SHA-1 등록
   - **Maps API 키**: 애플리케이션 제한(Android 앱)에 패키지+SHA-1 추가
3. **Render 환경변수** `GOOGLE_CLIENT_ID`에 iOS + 웹 클라이언트 ID가 콤마로 들어있어야 백엔드 audience 검증 통과
   (게스트 로그인은 SHA 등록과 무관하게 항상 동작)

> 디버그 APK로는 게스트 + (디버그 SHA가 등록된 경우)Google 로그인이 됩니다.
> 릴리스에서 Google 로그인이 막히면 십중팔구 **릴리스 SHA 미등록**입니다.

---

## 8. 출시 트랙 & 제출

1. **테스트 → 내부 테스트** 트랙에 `app-release.aab` 업로드 → 본인 기기로 먼저 검증(권장)
2. 앱 콘텐츠(개인정보처리방침 URL, 광고 여부=없음, 타깃 연령, 데이터 보안, 콘텐츠 등급) 모두 작성
   - 개인정보처리방침 URL: `https://yuneunmi814-cmyk.github.io/stardusk/privacy.html`
3. **프로덕션** 트랙 생성 → 출시 노트(메타데이터 §6) 입력 → 국가(대한민국 등) 선택 → 검토 후 출시
- [ ] 모든 "앱 설정" 작업 ✅ (대시보드 경고 0)
- [ ] 심사 제출

---

## 9. 제출 전 최종 체크

- [ ] `app-release.aab`가 **릴리스 키**로 서명됨
- [ ] versionCode/versionName 확인(업데이트 시 versionCode 증가)
- [ ] 실기기 테스트 통과 → [`ANDROID_DEVICE_TEST_CHECKLIST.md`](./ANDROID_DEVICE_TEST_CHECKLIST.md)
- [ ] 스크린샷 2장 이상, 아이콘 512, 피처 1024×500 업로드
- [ ] 데이터 보안/콘텐츠 등급/개인정보처리방침 URL 작성
- [ ] 릴리스 SHA-1을 OAuth/Maps에 등록(Google 로그인용)

---

<sub>공개 마케팅 텍스트에는 데이터 출처 기관명을 노출하지 않으며, 심사 메모(비공개)에만 명시합니다(메타데이터 §9 재사용).</sub>
