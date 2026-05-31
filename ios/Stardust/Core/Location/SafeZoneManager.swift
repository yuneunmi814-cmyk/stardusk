import CoreLocation

final class SafeZoneManager {
    static let shared = SafeZoneManager()

    // 서버와 동일 상수
    private let safeRadiusM = 200.0
    private let gridM = 80.0
    private let metersPerDegLat = 111_320.0

    private let store = UserDefaults.standard
    private let key = "stardust.safezones.v1"

    struct Zone: Codable { let name: String; let lat: Double; let lng: Double }

    // MARK: 최초 1회 저장 (집/회사)
    func saveZones(_ zones: [Zone]) {
        if let data = try? JSONEncoder().encode(zones) { store.set(data, forKey: key) }
    }
    var zones: [Zone] {
        guard let data = store.data(forKey: key),
              let z = try? JSONDecoder().decode([Zone].self, from: data) else { return [] }
        return z
    }
    var hasCompletedSetup: Bool { store.bool(forKey: "stardust.safezone.setupDone") }
    func markSetupComplete() { store.set(true, forKey: "stardust.safezone.setupDone") }

    // MARK: 현재 좌표가 어떤 Safe Zone 200m 이내인지
    private func nearestZone(to c: CLLocationCoordinate2D) -> Zone? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return zones.first { z in
            here.distance(from: CLLocation(latitude: z.lat, longitude: z.lng)) <= safeRadiusM
        }
    }

    /// Safe Zone 안이면 격자 스냅으로 흐리게, 아니면 원본 그대로.
    func obfuscateIfNeeded(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard nearestZone(to: c) != nil else { return c }   // 밖이면 그대로
        let gridLat = gridM / metersPerDegLat
        let gridLng = gridM / (metersPerDegLat * max(cos(c.latitude * .pi / 180), 1e-6))
        return CLLocationCoordinate2D(
            latitude:  (c.latitude  / gridLat).rounded() * gridLat,
            longitude: (c.longitude / gridLng).rounded() * gridLng
        )
    }
}
