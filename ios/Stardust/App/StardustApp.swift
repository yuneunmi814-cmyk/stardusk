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
                // Google 로그인 리디렉트 콜백(GIDClientID 는 Info.plist 에서 자동 로드)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

/// 로그인 → 메인 탭(탐색·저장). 위치는 탐색탭에서 자동 취득하고,
/// '변경'을 누를 때만 위치 설정 지도를 전체화면으로 띄운다.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appLocation: AppLocation
    @State private var tab = 0   // 탐색 기본 선택

    var body: some View {
        if !session.isAuthenticated {
            LoginView()                       // 소셜 로그인 / 게스트 둘러보기
        } else {
            TabView(selection: $tab) {
                ExploreView()                 // 메인 홈 — 주변 관광지 탐색
                    .tabItem { Label("탐색", systemImage: "map.fill") }
                    .tag(0)
                SavedView()                   // 라이크(찜)한 관광지 모음
                    .tabItem { Label("저장", systemImage: "heart.fill") }
                    .tag(1)
            }
            .tint(Color.meadowDeep)
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
