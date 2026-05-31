import CoreLocation

/// 업로드 시점의 현재 좌표를 '한 번만' 얻는 가벼운 래퍼.
/// 사용자에게는 아무 입력도 요구하지 않는다 — 위치는 자동, 그 뒤 Safe Zone 난독화(§3)가 보호.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorization: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private var pending: [CheckedContinuation<CLLocationCoordinate2D, Error>] = []

    enum LocationError: Error { case denied, unavailable }

    override init() {
        self.authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestWhenInUse() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 현재 좌표 1회 요청. 권한이 없으면 요청 후 콜백을 기다린다.
    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        switch authorization {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        return try await withCheckedThrowingContinuation { cont in
            pending.append(cont)
            manager.requestLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        authorization = m.authorizationStatus
        if authorization == .denied || authorization == .restricted {
            resume(throwing: LocationError.denied)
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else {
            resume(throwing: LocationError.unavailable); return
        }
        resume(returning: coord)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        resume(throwing: error)
    }

    private func resume(returning coord: CLLocationCoordinate2D) {
        let conts = pending; pending.removeAll()
        conts.forEach { $0.resume(returning: coord) }
    }

    private func resume(throwing error: Error) {
        let conts = pending; pending.removeAll()
        conts.forEach { $0.resume(throwing: error) }
    }
}
