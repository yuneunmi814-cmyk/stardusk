import SwiftUI
import GoogleSignIn
import KakaoSDKCommon
import KakaoSDKAuth

@main
struct StardustApp: App {
    @StateObject private var session = SessionStore()      // 토큰은 Keychain 에 보관
    @StateObject private var appLocation = AppLocation()   // 탐색 기준 위치(하이브리드)

    init() {
        // 카카오 SDK 초기화(네이티브 앱 키 — 클라이언트 내장 식별자)
        KakaoSDK.initSDK(appKey: "c5b7d136888b761bd4218b2414a04f37")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(appLocation)
                .task {
                    // Keychain 에 저장돼 있던 토큰을 API 액터에 주입(자동 로그인)
                    await session.bootstrap()
                }
                // 소셜 로그인 리디렉트 콜백(카카오톡 앱 ↔ Google). GIDClientID 는
                // Info.plist 에서 자동 로드.
                .onOpenURL { url in
                    if AuthApi.isKakaoTalkLoginUrl(url) {
                        _ = AuthController.handleOpenUrl(url: url)
                    } else if url.scheme == "stardust" {
                        NaverLoginManager.shared.handleURL(url)   // 네이버 콜백
                    } else {
                        GIDSignIn.sharedInstance.handle(url)      // Google 콜백
                    }
                }
        }
    }
}

/// 인증 → 위치 설정 → 메인(탐색/무대/담기) 순으로 가르는 루트.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appLocation: AppLocation

    var body: some View {
        if !session.isAuthenticated {
            LoginView()                       // Sign in with Apple → session.login(...)
        } else if !appLocation.isConfirmed {
            LocationSetupView()               // 현재 위치 자동 + 직접 수정 → "해당 위치로 시작하기"
        } else {
            TabView {
                ExploreView()                 // 하이브리드 탐색(지도/리스트 듀얼 탭)
                    .tabItem { Label("탐색", systemImage: "map.fill") }
                TrendingFeedView()            // 무대(피드)
                    .tabItem { Label("무대", systemImage: "sparkles") }
                CaptureFlowView()             // 입력 Zero 3단 촬영 루프
                    .tabItem { Label("담기", systemImage: "camera.fill") }
            }
            .tint(.white)
        }
    }
}
