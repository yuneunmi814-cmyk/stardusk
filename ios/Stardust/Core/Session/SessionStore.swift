import Foundation

/// 앱 전역 인증 상태. View 는 이걸 @EnvironmentObject 로 구독한다.
/// 토큰은 Keychain 에만 저장하고, 메모리 캐시는 휘발성으로만 들고 있는다.
@MainActor
final class SessionStore: ObservableObject {

    // Keychain 키 (account)
    private enum K {
        static let token = "access_token"
        static let userId = "user_id"
        static let nickname = "nickname"
        static let kind = "auth_kind"   // "guest" | "apple" | "google"
    }

    @Published private(set) var accessToken: String?
    @Published private(set) var userId: String?
    @Published private(set) var nickname: String?
    private var authKind: String?       // 토큰 만료 시 복구 방식 결정에 사용

    var isAuthenticated: Bool { accessToken?.isEmpty == false }

    private let api = StardustAPI.shared

    init() {
        // 앱 재실행 시 Keychain 에서 토큰 복원 (자동 로그인)
        self.accessToken = KeychainStore.get(K.token)
        self.userId = KeychainStore.get(K.userId)
        self.nickname = KeychainStore.get(K.nickname)
        self.authKind = KeychainStore.get(K.kind)
    }

    /// 부팅 시 1회: 저장된 토큰을 API 액터에 주입하고, 401(만료) 자동복구 핸들러를 건다.
    func bootstrap() async {
        await api.setToken(accessToken)
        await api.setReauthHandler { [weak self] in await self?.recoverSession() ?? false }
    }

    /// 토큰 만료(401) 시 호출: 게스트는 새 토큰을 조용히 재발급, 소셜은 세션을 비워 재로그인 유도.
    /// 반환값 true 면 API 가 원요청을 1회 재시도한다.
    func recoverSession() async -> Bool {
        if authKind == "guest" {
            do { try await guestLogin(); return isAuthenticated }
            catch { return false }
        }
        logout()           // 소셜 토큰은 조용히 갱신 불가 → 로그인 화면으로
        return false
    }

    /// Sign in with Apple 등으로 얻은 identityToken 으로 서버 로그인 → 토큰 영구 보관.
    func login(provider: String, identityToken: String, nickname: String? = nil) async throws {
        let auth = try await api.login(provider: provider,
                                       identityToken: identityToken,
                                       nickname: nickname)
        persist(token: auth.accessToken, userId: auth.userId, nickname: auth.nickname, kind: provider)
        await api.setToken(auth.accessToken)
    }

    /// 게스트 둘러보기: 서버에서 익명 토큰을 받아 입장한다(소셜 로그인 불필요).
    func guestLogin() async throws {
        let auth = try await api.guestLogin()
        persist(token: auth.accessToken, userId: auth.userId, nickname: auth.nickname, kind: "guest")
        await api.setToken(auth.accessToken)
    }

    /// 회원 탈퇴: 서버 데이터 파기 후 로컬 세션도 비운다.
    func deleteAccount() async throws {
        try await api.deleteAccount()
        logout()
    }

    /// 로그아웃: 메모리 + Keychain + API 토큰 모두 비운다.
    func logout() {
        KeychainStore.remove(K.token)
        KeychainStore.remove(K.userId)
        KeychainStore.remove(K.nickname)
        KeychainStore.remove(K.kind)
        accessToken = nil
        userId = nil
        nickname = nil
        authKind = nil
        Task { await api.setToken(nil) }
    }

    private func persist(token: String, userId: String, nickname: String, kind: String) {
        KeychainStore.set(token, for: K.token)
        KeychainStore.set(userId, for: K.userId)
        KeychainStore.set(nickname, for: K.nickname)
        KeychainStore.set(kind, for: K.kind)
        self.accessToken = token
        self.userId = userId
        self.nickname = nickname
        self.authKind = kind
    }
}
