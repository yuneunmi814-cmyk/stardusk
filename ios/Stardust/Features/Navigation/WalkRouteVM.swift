import MapKit

@MainActor
final class WalkRouteVM: ObservableObject {
    @Published var route: MKRoute?
    @Published var headlineStep: String = ""      // "북동쪽으로 230m 직진 후 우회전"
    @Published var remainingText: String = ""     // "243m · 도보 3분"

    func computeWalk(from: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) async {
        let req = MKDirections.Request()
        req.source      = MKMapItem(placemark: .init(coordinate: from))
        req.destination = MKMapItem(placemark: .init(coordinate: dest))
        req.transportType = .walking                // ← 도보 모드
        req.requestsAlternateRoutes = false
        do {
            let resp = try await MKDirections(request: req).calculate()
            guard let r = resp.routes.first else { return }
            self.route = r
            // 거리/시간 요약
            let m = Int(r.distance.rounded())
            let min = max(1, Int((r.expectedTravelTime / 60).rounded()))
            self.remainingText = (m >= 1000 ? String(format: "%.1fkm", Double(m)/1000) : "\(m)m") + " · 도보 \(min)분"
            // 다음 의미 있는 한 구간만 노출(첫 step 은 종종 빈 안내라 건너뜀)
            self.headlineStep = r.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "목적지 방향으로 이동하세요"
        } catch {
            self.headlineStep = ""    // 실패해도 앱은 거리/방향만으로 안내 가능 → 외부 맵 버튼이 안전망
        }
    }
}
