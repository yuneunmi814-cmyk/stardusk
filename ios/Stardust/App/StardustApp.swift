import SwiftUI
import GoogleSignIn

@main
struct StardustApp: App {
    @StateObject private var session = SessionStore()      // 토큰은 Keychain 에 보관
    @StateObject private var appLocation = AppLocation()   // 탐색 기준 위치(하이브리드)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(appLocation)
                .task {
                    // Keychain 에 저장돼 있던 토큰을 API 액터에 주입(자동 로그인)
                    await session.bootstrap()
                }
                // Google 로그인 리디렉트 콜백 처리(GIDClientID 는 Info.plist 에서 자동 로드)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
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
