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

/// 로그인 → 메인 탭(담기·탐색·피드). 위치는 탐색탭에서 자동 취득하고,
/// '변경'을 누를 때만 위치 설정 지도를 전체화면으로 띄운다.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appLocation: AppLocation
    @State private var tab = 1   // 가운데(탐색) 기본 선택

    var body: some View {
        if !session.isAuthenticated {
            LoginView()                       // 소셜 로그인 / 게스트 둘러보기
        } else {
            TabView(selection: $tab) {
                CaptureFlowView()             // 입력 Zero 촬영 루프
                    .tabItem { Label("담기", systemImage: "camera.fill") }
                    .tag(0)
                ExploreView()                 // 메인 홈 — 하이브리드 탐색
                    .tabItem { Label("탐색", systemImage: "map.fill") }
                    .tag(1)
                TrendingFeedView()            // 피드(다른 여행자들의 하늘)
                    .tabItem { Label("피드", systemImage: "sparkles") }
                    .tag(2)
            }
            .tint(.white)
            // 사용자가 '변경'을 눌렀을 때만 위치 설정 지도를 띄운다.
            .fullScreenCover(isPresented: Binding(
                get: { appLocation.isPickingManually },
                set: { if !$0 { appLocation.confirm() } }
            )) {
                LocationSetupView()
            }
        }
    }
}
