import Foundation

/// 앱 전역 환경 설정.
/// ⚠️ 출시 전: 백엔드 배포 후 실제 API 호스트로 교체한다.
///   (디버그/릴리스 분리가 필요하면 xcconfig 또는 Info.plist 값으로 주입)
enum AppConfig {
    /// 백엔드 Base URL — `https://<배포 호스트>/api/v1`
    static let apiBaseURL = URL(string: "https://api.stardust.app/api/v1")!
}
