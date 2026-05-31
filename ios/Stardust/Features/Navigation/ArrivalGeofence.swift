import CoreLocation
import UserNotifications

final class ArrivalGeofence: NSObject, CLLocationManagerDelegate {
    private let lm = CLLocationManager()

    func arm(at dest: CLLocationCoordinate2D, id: String) {
        lm.delegate = self
        lm.allowsBackgroundLocationUpdates = true     // 백그라운드 도착 감지
        let region = CLCircularRegion(center: dest, radius: 40, identifier: id)
        region.notifyOnEntry = true; region.notifyOnExit = false
        lm.startMonitoring(for: region)
    }

    func locationManager(_ m: CLLocationManager, didEnterRegion r: CLRegion) {
        let c = UNMutableNotificationContent()
        c.title = "✨ 도착했어요"; c.body = "이 자리의 하늘을 담아보세요"; c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: r.identifier, content: c, trigger: nil))
        m.stopMonitoring(for: r)                      // 1회성
    }
}
