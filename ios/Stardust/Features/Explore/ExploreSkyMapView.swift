import SwiftUI
import CoreLocation

/// [지도로 탐색]의 '스카이 뷰' — 우주 그리드 밤하늘.
/// 내 위치가 중심 별이 되고, 주변 OpenAPI 관광지가 별자리 마커로 치환된다.
/// 명소를 고르면 중심 → 명소로 점선 '경로 그리기' 궤도가 이어지고,
/// 하단 중앙 [하늘 마주하기] 버튼으로 촬영에 진입한다.
struct ExploreSkyMapView: View {
    let spots: [TourSpot]
    let center: CLLocationCoordinate2D
    @Binding var selectedSpot: TourSpot?
    /// 하단 메인 버튼 — 원버튼 큐레이션 시트 호출.
    var onExplore: () -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let origin = CGPoint(x: size.width / 2, y: size.height * 0.46)
            let placed = Self.project(spots: spots, center: center, origin: origin, size: size)

            ZStack {
                CosmicGridBackground()

                // 경로 그리기 — 선택된 명소까지 별자리를 따라 점선 궤도
                if let sel = selectedSpot,
                   let target = placed.first(where: { $0.spot.id == sel.id }) {
                    OrbitPath(from: origin, to: target.point)
                }

                // 주변 명소 = 별자리 마커
                ForEach(placed, id: \.spot.id) { item in
                    SkySpotMarker(spot: item.spot, selected: selectedSpot?.id == item.spot.id) {
                        withAnimation(.spring) { selectedSpot = item.spot }
                    }
                    .position(item.point)
                }

                // 내 위치 = 중심 별
                CenterStar().position(origin)

                // 하단 중앙 [내 주변 별 탐색] — 원버튼 큐레이션
                VStack {
                    Spacer()
                    ExploreNearbyButton(action: onExplore).padding(.bottom, 28)
                }
            }
        }
    }

    // MARK: 등거리 투영(중심 기준 상대 좌표 → 화면 좌표, 북쪽이 위)

    private struct Placed { let spot: TourSpot; let point: CGPoint }

    private static func project(spots: [TourSpot],
                                center: CLLocationCoordinate2D,
                                origin: CGPoint,
                                size: CGSize) -> [Placed] {
        guard !spots.isEmpty else { return [] }
        let cosLat = cos(center.latitude * .pi / 180)
        let vecs: [(TourSpot, CGFloat, CGFloat)] = spots.map { s in
            let dx = CGFloat(s.longitude - center.longitude) * CGFloat(cosLat)
            let dy = CGFloat(s.latitude - center.latitude)
            return (s, dx, dy)
        }
        let maxR = max(vecs.map { hypot($0.1, $0.2) }.max() ?? 0.0001, 0.0001)
        let radius = min(size.width, size.height) * 0.34
        return vecs.map { (s, dx, dy) in
            let px = origin.x + dx / maxR * radius
            let py = origin.y - dy / maxR * radius
            return Placed(spot: s, point: CGPoint(x: px, y: py))
        }
    }
}

// MARK: - 우주 그리드 배경

private struct CosmicGridBackground: View {
    // 홈은 HTML sky-grid 처럼 차분하게 — 깜빡이지 않는 아주 옅은 고정 별만.
    private static let dots: [(x: CGFloat, y: CGFloat, r: CGFloat, a: Double)] =
        (0..<16).map { _ in
            (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1),
             CGFloat.random(in: 0.6...1.1), Double.random(in: 0.18...0.42))
        }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#0B1026"), Color(hex: "#111A33"), Color(hex: "#090D1C")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GridLines().stroke(Color.white.opacity(0.055), lineWidth: 0.6).ignoresSafeArea()
            Canvas { ctx, size in
                for s in Self.dots {
                    let d = s.r * 2
                    let rect = CGRect(x: s.x * size.width - d / 2,
                                      y: s.y * size.height - d / 2, width: d, height: d)
                    ctx.opacity = s.a
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

private struct GridLines: Shape {
    var spacing: CGFloat = 34
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x <= rect.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: rect.height)); x += spacing }
        var y: CGFloat = 0
        while y <= rect.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: rect.width, y: y)); y += spacing }
        return p
    }
}

// MARK: - 경로 궤도(점선)

private struct OrbitPath: View {
    let from: CGPoint
    let to: CGPoint
    var body: some View {
        Path { p in p.move(to: from); p.addLine(to: to) }
            .stroke(Color(hex: "#8FBEF0").opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 7]))
            .shadow(color: Color(hex: "#5794E4").opacity(0.6), radius: 4)
            .allowsHitTesting(false)
    }
}

// MARK: - 중심 별(내 위치)

private struct CenterStar: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "#8FBEF0").opacity(0.25))
                .frame(width: pulse ? 66 : 46, height: pulse ? 66 : 46).blur(radius: 8)
            Circle().fill(.white).frame(width: 16, height: 16)
                .shadow(color: Color(hex: "#5794E4"), radius: 10)
        }
        .overlay(alignment: .bottom) {
            Text("내 위치").font(.caption2).foregroundStyle(.white.opacity(0.8)).offset(y: 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - 명소 별자리 마커

private struct SkySpotMarker: View {
    let spot: TourSpot
    let selected: Bool
    var tap: () -> Void
    var body: some View {
        Button(action: tap) {
            VStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: selected ? 18 : 13))
                    .foregroundStyle(.white, Color(hex: "#5794E4"))
                    .shadow(color: Color(hex: "#5794E4").opacity(0.85), radius: selected ? 8 : 4)
                Text(spot.spotName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).fixedSize()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 내 주변 별 탐색 버튼(원버튼 큐레이션 호출)

private struct ExploreNearbyButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.headline)
                Text("내 주변 관광지 찾기").font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22).frame(height: 52)
            .background(Color(hex: "#5794E4").opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Color(hex: "#5794E4").opacity(0.5), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}
