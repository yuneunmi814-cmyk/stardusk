import UIKit
import MapKit

enum ExternalMap {
    /// 도보 길안내를 외부 앱으로 위임. dest=목적지 좌표, name=표시명.
    static func openWalking(to dest: CLLocationCoordinate2D, name: String) -> [(label: String, action: () -> Void)] {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var out: [(String, () -> Void)] = []

        // 네이버지도: 도보 경로
        if let u = URL(string: "nmap://route/walk?dlat=\(dest.latitude)&dlng=\(dest.longitude)&dname=\(enc)&appname=app.stardust.ios"),
           UIApplication.shared.canOpenURL(u) {
            out.append(("네이버지도", { UIApplication.shared.open(u) }))
        }
        // 카카오맵: 도보 경로(FOOT)
        if let u = URL(string: "kakaomap://route?ep=\(dest.latitude),\(dest.longitude)&by=FOOT"),
           UIApplication.shared.canOpenURL(u) {
            out.append(("카카오맵", { UIApplication.shared.open(u) }))
        }
        // 티맵: 목적지 안내
        if let u = URL(string: "tmap://route?goalname=\(enc)&goalx=\(dest.longitude)&goaly=\(dest.latitude)"),
           UIApplication.shared.canOpenURL(u) {
            out.append(("티맵", { UIApplication.shared.open(u) }))
        }
        // 폴백: 애플 지도(항상 가능)
        out.append(("지도", {
            let item = MKMapItem(placemark: .init(coordinate: dest))
            item.name = name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        }))
        return out
    }
}
