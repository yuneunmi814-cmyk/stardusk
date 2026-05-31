import Foundation

/// 앱 전역 환경 설정.
/// API 호스트는 빌드 구성(Debug/Release)별로 `Config/*.xcconfig` 에서 정의되어
/// Info.plist 의 `STARDUST_API_BASE_URL` 키로 주입된다.
///   - Debug   → http://localhost:8000/api/v1
///   - Release → https://<운영 호스트>/api/v1  (배포 후 Release.xcconfig 에서 교체)
enum AppConfig {
    /// 백엔드 Base URL. Info.plist 주입값을 읽고, 누락 시 운영 기본값으로 폴백한다.
    static let apiBaseURL: URL = {
        let fallback = URL(string: "https://api.stardust.app/api/v1")!
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "STARDUST_API_BASE_URL") as? String,
            !raw.trimmingCharacters(in: .whitespaces).isEmpty,
            let url = URL(string: raw.trimmingCharacters(in: .whitespaces))
        else {
            return fallback
        }
        return url
    }()
}
