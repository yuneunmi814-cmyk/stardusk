import SwiftUI
import CoreLocation

/// 하이브리드 탐색의 '기준 위치'. 권한 요청 + 현재 위치 자동 취득을 직접 수행하고,
/// 사용자가 '변경'을 누르면 위치 설정 화면(LocationSetupView)으로 진입한다.
@MainActor
final class AppLocation: NSObject, ObservableObject {
    /// 탐색 기준 좌표(확정 전엔 GPS 또는 기본값).
    @Published var coordinate: CLLocationCoordinate2D
    /// 화면에 표시할 위치명(역지오코딩 또는 검색 결과명).
    @Published var displayName: String = "현위치"
    /// 탐색을 시작할 위치가 확정됐는지(자동 취득 또는 직접 설정 완료).
    @Published private(set) var isConfirmed = false
    /// 사용자가 '변경'을 눌러 직접 위치를 고르는 중인지(이때만 설정 지도 화면 노출).
    @Published private(set) var isPickingManually = false

    /// 기본 카메라: 강원 강릉(서비스 주무대).
    static let gangneung = CLLocationCoordinate2D(latitude: 37.7519, longitude: 128.8761)

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        self.coordinate = AppLocation.gangneung
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 위치 권한 요청 + 현재 위치 1회 취득 → 확정. 거부/실패 시 기본값으로 확정해 진행.
    func autoLocate() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()   // 권한 팝업
        } else if status == .denied || status == .restricted {
            isConfirmed = true                         // 거부 시 기본값으로 진행
        } else {
            manager.requestLocation()
        }
    }

    /// 위치 설정 화면에서 좌표/이름을 갱신(미확정 상태 유지).
    func update(coordinate: CLLocationCoordinate2D, name: String?) {
        self.coordinate = coordinate
        if let name, !name.isEmpty { self.displayName = name }
    }

    /// 이 위치로 탐색 시작.
    func confirm() {
        isConfirmed = true
        isPickingManually = false
    }

    /// 메인에서 위치를 다시 바꾸고 싶을 때 설정 화면으로 복귀.
    func reopenSetup() {
        isPickingManually = true
        isConfirmed = false
    }
}

extension AppLocation: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.coordinate = c
            self.reverseGeocode(c)
            self.confirm()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in self.isConfirmed = true }   // 실패해도 기본값으로 진행
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.isConfirmed = true                  // 거부 시 기본값으로 진행
            default:
                break
            }
        }
    }

    private func reverseGeocode(_ c: CLLocationCoordinate2D) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(
            CLLocation(latitude: c.latitude, longitude: c.longitude)
        ) { [weak self] placemarks, _ in
            guard let p = placemarks?.first else { return }
            let parts = [p.locality, p.subLocality ?? p.thoroughfare].compactMap { $0 }
            let name = parts.isEmpty ? "현위치" : parts.prefix(2).joined(separator: " ")
            Task { @MainActor in self?.displayName = name }
        }
    }
}
