import SwiftUI

@main
struct StardustApp: App {
    @StateObject private var session = SessionStore()   // 토큰은 Keychain 에 보관

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    // 1) Keychain 에 저장돼 있던 토큰을 API 액터에 주입(자동 로그인)
                    await session.bootstrap()
                    // 2) 최초 1회 Safe Zone 온보딩
                    if session.isAuthenticated, !SafeZoneManager.shared.hasCompletedSetup {
                        session.showSafeZoneSetup = true
                    }
                }
                .sheet(isPresented: $session.showSafeZoneSetup) {
                    SafeZoneSetupView()      // §3.2 — 완료 시 hasCompletedSetup = true
                }
        }
    }
}

/// 인증 상태에 따라 로그인/메인을 가르는 루트.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        if session.isAuthenticated {
            TrendingFeedView()           // §5.5 무대(피드)
        } else {
            LoginView()                  // Sign in with Apple → session.login(...)
        }
    }
}
