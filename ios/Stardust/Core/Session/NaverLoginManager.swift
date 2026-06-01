import Foundation
import NaverThirdPartyLogin

/// 네이버 로그인(네아로) 래퍼 — 델리게이트 기반 SDK 를 클로저 한 번으로 감싼다.
/// 자격증명(consumerKey/Secret)은 Info.plist(주입: Secrets.xcconfig)에서 읽는다.
/// 성공 시 access_token 을 반환하면, 호출부가 백엔드(provider="naver")로 검증을 보낸다.
final class NaverLoginManager: NSObject, NaverThirdPartyLoginConnectionDelegate {
    static let shared = NaverLoginManager()

    private let connection = NaverThirdPartyLoginConnection.getSharedInstance()!
    private var onResult: ((Result<String, Error>) -> Void)?

    enum NaverLoginError: LocalizedError {
        case notConfigured, noToken
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "네이버 로그인이 설정되어 있지 않아요."
            case .noToken:       return "네이버 로그인 정보를 읽지 못했어요."
            }
        }
    }

    private override init() {
        super.init()
        let info = Bundle.main.infoDictionary
        connection.serviceUrlScheme = "stardust"
        connection.consumerKey = (info?["NAVER_CONSUMER_KEY"] as? String) ?? ""
        connection.consumerSecret = (info?["NAVER_CONSUMER_SECRET"] as? String) ?? ""
        connection.appName = "STARDUST"
        connection.delegate = self
    }

    var isConfigured: Bool {
        !(connection.consumerKey ?? "").isEmpty && !(connection.consumerSecret ?? "").isEmpty
    }

    /// 네이버 로그인 시작. 콜백은 메인 스레드에서 호출된다.
    func login(_ completion: @escaping (Result<String, Error>) -> Void) {
        guard isConfigured else { completion(.failure(NaverLoginError.notConfigured)); return }
        onResult = completion
        // 기존 토큰이 유효하면 정리하고 새로 로그인(계정 전환 대비)
        if connection.isValidAccessTokenExpireTimeNow() {
            connection.requestDeleteToken()
        }
        connection.requestThirdPartyLogin()
    }

    /// onOpenURL 콜백 위임.
    @discardableResult
    func handleURL(_ url: URL) -> Bool {
        connection.receiveAccessToken(url)
        return true
    }

    private func finish(_ result: Result<String, Error>) {
        onResult?(result)
        onResult = nil
    }

    // MARK: NaverThirdPartyLoginConnectionDelegate

    func oauth20ConnectionDidFinishRequestACTokenWithAuthCode() {
        if let token = connection.accessToken, !token.isEmpty {
            finish(.success(token))
        } else {
            finish(.failure(NaverLoginError.noToken))
        }
    }

    func oauth20ConnectionDidFinishRequestACTokenWithRefreshToken() {}

    func oauth20ConnectionDidFinishDeleteToken() {}

    func oauth20Connection(_ oauthConnection: NaverThirdPartyLoginConnection!,
                           didFailWithError error: Error!) {
        finish(.failure(error ?? NaverLoginError.noToken))
    }
}
