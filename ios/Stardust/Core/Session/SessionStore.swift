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
    }

    @Published private(set) var accessToken: String?
    @Published private(set) var userId: String?
    @Published private(set) var nickname: String?

    var isAuthenticated: Bool { accessToken?.isEmpty == false }

    private let api = StardustAPI.shared

    init() {
        // 앱 재실행 시 Keychain 에서 토큰 복원 (자동 로그인)
        self.accessToken = KeychainStore.get(K.token)
        self.userId = KeychainStore.get(K.userId)
        self.nickname = KeychainStore.get(K.nickname)
    }

    /// 부팅 시 1회: 저장된 토큰을 API 액터에 주입한다.
    func bootstrap() async {
        await api.setToken(accessToken)
    }

    /// Sign in with Apple 등으로 얻은 identityToken 으로 서버 로그인 → 토큰 영구 보관.
    func login(provider: String, identityToken: String, nickname: String? = nil) async throws {
        let auth = try await api.login(provider: provider,
                                       identityToken: identityToken,
                                       nickname: nickname)
        persist(token: auth.accessToken, userId: auth.userId, nickname: auth.nickname)
        await api.setToken(auth.accessToken)
    }

    /// 로그아웃: 메모리 + Keychain + API 토큰 모두 비운다.
    func logout() {
        KeychainStore.remove(K.token)
        KeychainStore.remove(K.userId)
        KeychainStore.remove(K.nickname)
        accessToken = nil
        userId = nil
        nickname = nil
        Task { await api.setToken(nil) }
    }

    private func persist(token: String, userId: String, nickname: String) {
        KeychainStore.set(token, for: K.token)
        KeychainStore.set(userId, for: K.userId)
        KeychainStore.set(nickname, for: K.nickname)
        self.accessToken = token
        self.userId = userId
        self.nickname = nickname
    }
}
