import SwiftUI
import MapKit
import CoreLocation

/// 위치 설정 — 배달앱식 직관 위치 지정.
/// ① 구동 시 현재 GPS 로 자동 지정 ② 도로명/건물명 검색 ③ 지도에서 핀 이동 → "해당 위치로 시작하기".
@available(iOS 17.0, *)
struct LocationSetupView: View {
    @EnvironmentObject private var appLocation: AppLocation
    @StateObject private var locationProvider = LocationProvider()
    @StateObject private var search = AddressSearchModel()

    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: AppLocation.gangneung,
                            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    @State private var centerCoord = AppLocation.gangneung
    @State private var placeName = "현재 위치"
    @State private var didAutoLocate = false

    private let geocoder = CLGeocoder()

    var body: some View {
        ZStack(alignment: .top) {
            // 지도 (중앙 고정 핀 방식)
            Map(position: $camera) { UserAnnotation() }
                .mapControls { MapUserLocationButton(); MapCompass() }
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    centerCoord = ctx.region.center
                    reverseGeocode(centerCoord)
                }
                .ignoresSafeArea(edges: .bottom)

            centerPin

            VStack(spacing: 0) {
                searchBar
                if !search.results.isEmpty { searchResults }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            bottomConfirm
        }
        .task {
            guard !didAutoLocate else { return }
            didAutoLocate = true
            locationProvider.requestWhenInUse()
            if let c = try? await locationProvider.currentCoordinate() {
                moveCamera(to: c)
                reverseGeocode(c)
            }
        }
    }

    // MARK: 중앙 핀

    private var centerPin: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white, Color(hex: "#5794E4"))
                .shadow(radius: 4)
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color(hex: "#5794E4"))
                .offset(y: -4)
            Spacer().frame(height: UIScreen.main.bounds.height * 0.5)
        }
        .allowsHitTesting(false)
    }

    // MARK: 검색

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("도로명·건물명으로 검색", text: $search.query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { search.run() }
            if !search.query.isEmpty {
                Button { search.clear() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.results) { item in
                Button {
                    moveCamera(to: item.coordinate)
                    placeName = item.title
                    search.clear()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                        if let sub = item.subtitle {
                            Text(sub).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                }
                Divider()
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }

    // MARK: 하단 확정

    private var bottomConfirm: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Color(hex: "#5794E4"))
                    Text(placeName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                }
                Button {
                    appLocation.update(coordinate: centerCoord, name: placeName)
                    appLocation.confirm()
                } label: {
                    Text("해당 위치로 시작하기")
                        .font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color(hex: "#5794E4"), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }

    // MARK: 헬퍼

    private func moveCamera(to c: CLLocationCoordinate2D) {
        centerCoord = c
        withAnimation(.easeInOut) {
            camera = .region(MKCoordinateRegion(
                center: c, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        }
    }

    private func reverseGeocode(_ c: CLLocationCoordinate2D) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(
            CLLocation(latitude: c.latitude, longitude: c.longitude)
        ) { placemarks, _ in
            guard let p = placemarks?.first else { return }
            let parts = [p.locality, p.subLocality ?? p.thoroughfare, p.name]
                .compactMap { $0 }
            let name = parts.isEmpty ? "선택한 위치" : parts.prefix(2).joined(separator: " ")
            DispatchQueue.main.async { self.placeName = name }
        }
    }
}

/// MKLocalSearch 기반 주소/장소 검색.
@MainActor
final class AddressSearchModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [Result] = []

    struct Result: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String?
        let coordinate: CLLocationCoordinate2D
    }

    func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        // 강원 중심으로 우선 검색
        req.region = MKCoordinateRegion(
            center: AppLocation.gangneung,
            span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2))
        MKLocalSearch(request: req).start { [weak self] resp, _ in
            guard let self else { return }
            let items = (resp?.mapItems ?? []).prefix(6).map { item -> Result in
                Result(title: item.name ?? "이름 없음",
                       subtitle: item.placemark.title,
                       coordinate: item.placemark.coordinate)
            }
            Task { @MainActor in self.results = Array(items) }
        }
    }

    func clear() { query = ""; results = [] }
}
