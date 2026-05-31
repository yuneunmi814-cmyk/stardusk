import SwiftUI
import CoreLocation

/// 하이브리드 탐색의 '기준 위치'. 앱 구동 시 GPS 로 자동 지정되지만,
/// 사용자가 검색/핀 이동으로 직접 바꿔 '해당 위치로 시작하기' 할 수 있다.
@MainActor
final class AppLocation: ObservableObject {
    /// 탐색 기준 좌표(확정 전엔 GPS 또는 기본값).
    @Published var coordinate: CLLocationCoordinate2D
    /// 화면에 표시할 위치명(역지오코딩 또는 검색 결과명).
    @Published var displayName: String = "현재 위치"
    /// "해당 위치로 시작하기" 를 눌러 메인으로 진입했는지.
    @Published private(set) var isConfirmed = false

    /// 기본 카메라: 강원 강릉(서비스 주무대).
    static let gangneung = CLLocationCoordinate2D(latitude: 37.7519, longitude: 128.8761)

    init() {
        self.coordinate = AppLocation.gangneung
    }

    /// 위치 설정 화면에서 좌표/이름을 갱신(미확정 상태 유지).
    func update(coordinate: CLLocationCoordinate2D, name: String?) {
        self.coordinate = coordinate
        if let name, !name.isEmpty { self.displayName = name }
    }

    /// 이 위치로 탐색 시작.
    func confirm() { isConfirmed = true }

    /// 메인에서 위치를 다시 바꾸고 싶을 때 설정 화면으로 복귀.
    func reopenSetup() { isConfirmed = false }
}
