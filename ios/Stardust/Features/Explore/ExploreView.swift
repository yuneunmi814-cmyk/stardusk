import SwiftUI
import MapKit
import CoreLocation

/// 탐색(홈) — 일반 지도에 주변 관광지 마커를 띄우고,
/// [내 주변 관광지 찾기] 로 풀스크린 추천 카드를 연다.
@available(iOS 17.0, *)
struct ExploreView: View {
    @EnvironmentObject private var appLocation: AppLocation
    @StateObject private var vm = ExploreViewModel()
    @State private var showCuration = false
    @State private var showSettings = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var centeredAt: CLLocationCoordinate2D?   // 마지막으로 지도를 맞춘 좌표
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
            mapArea
        }
        // 진입 시 위치 요청 — iOS 시스템 권한 팝업을 한 번만 띄운다(별도 안내 카드 없음).
        .task { appLocation.autoLocate() }
        // 좌표가 갱신될 때마다 주변 명소 재로딩 + (큰 이동일 때만) 지도 재중심.
        .task(id: "\(appLocation.coordinate.latitude),\(appLocation.coordinate.longitude)") {
            recenterIfNeeded()
            await vm.loadMap(center: appLocation.coordinate)
        }
        // 풀스크린 추천 카드 — 탭바 유지(시트 대신 오버레이).
        .overlay {
            if showCuration {
                SpotCurationView(
                    spots: vm.deckSpots.isEmpty ? vm.mapSpots : vm.deckSpots,
                    vm: vm,
                    onClose: { withAnimation { showCuration = false } },
                    onLike: { liked in vm.selectedSpot = liked }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: 헤더
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill").font(.footnote).foregroundStyle(Color.meadowDeep)
            Text(appLocation.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                .foregroundStyle(Meadow.textPrimary(scheme))
            Button { appLocation.reopenSetup() } label: {
                Text("변경").font(.caption.weight(.medium)).foregroundStyle(Color.meadowDeep)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Meadow.textPrimary(scheme))
                    .frame(width: 38, height: 38)
                    .background(Meadow.surface(scheme), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("메뉴")
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
        .background(Meadow.surface(scheme))
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: 지도 + 하단 컨트롤
    private var mapArea: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera, interactionModes: .all) {
                UserAnnotation()
                ForEach(vm.mapSpots) { spot in
                    Annotation(spot.spotName,
                               coordinate: .init(latitude: spot.latitude, longitude: spot.longitude)) {
                        StarDot(selected: vm.selectedSpot == spot)
                            .onTapGesture { withAnimation(.spring) { vm.selectedSpot = spot } }
                    }
                }
            }
            .mapControls { MapUserLocationButton(); MapCompass() }
            .ignoresSafeArea(edges: .bottom)

            // 선택 명소 카드 / 없으면 [내 주변 관광지 찾기] 버튼
            if let spot = vm.selectedSpot {
                SpotCardView(spot: spot) { withAnimation { vm.selectedSpot = nil } }
                    .padding(.horizontal, 14).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !(vm.mapSpots.isEmpty && !vm.isLoading) {
                exploreButton.padding(.bottom, 24)
            }

            if vm.mapSpots.isEmpty && !vm.isLoading {
                VStack(spacing: 6) {
                    Image(systemName: "leaf.fill").font(.title2).foregroundStyle(Color.meadow)
                    Text("이 지역은 아직 준비 중이에요").font(.subheadline.weight(.medium))
                        .foregroundStyle(Meadow.textPrimary(scheme))
                }
                .padding(.vertical, 16).padding(.horizontal, 20)
                .background(Meadow.surface(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .padding(.bottom, 28)
            }
        }
        .overlay(alignment: .top) {
            if vm.isLoading {
                ProgressView().padding(8).background(.regularMaterial, in: Capsule()).padding(.top, 8)
            }
        }
    }

    private var exploreButton: some View {
        Button {
            showCuration = true
            Task { await vm.loadDeck(center: appLocation.coordinate) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.headline)
                Text("내 주변 자연 탐색").font(.callout.weight(.medium))
            }
            .foregroundStyle(Meadow.onAccent)
            .padding(.horizontal, 24).frame(height: 54)
            .background(Color.meadowAccent, in: Capsule())
            .shadow(color: Color.meadowAccent.opacity(0.45), radius: 12, y: 4)
        }
    }

    /// 지도를 현재 위치로 맞춘다 — 단, 사용자의 줌/이동을 덮어쓰지 않도록
    /// '처음' 또는 '의미 있는 이동(>800m)'일 때만 재중심한다. (GPS 미세 갱신엔 무반응)
    private func recenterIfNeeded() {
        let c = appLocation.coordinate
        if let last = centeredAt {
            let moved = CLLocation(latitude: last.latitude, longitude: last.longitude)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if moved < 800 { return }
        }
        centeredAt = c
        camera = .region(MKCoordinateRegion(
            center: c,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))
    }
}

/// 지도 마커 — HTML 별처럼 작은 빛나는 점. 선택 시 커진다.
struct StarDot: View {
    var selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(Color.meadowDeep.opacity(0.35))
                .frame(width: selected ? 26 : 18, height: selected ? 26 : 18).blur(radius: 4)
            Circle().fill(.white)
                .frame(width: selected ? 12 : 8, height: selected ? 12 : 8)
                .overlay(Circle().stroke(Color.meadowDeep, lineWidth: selected ? 2 : 1))
                .shadow(color: Color.meadowDeep.opacity(0.8), radius: selected ? 6 : 3)
        }
        .animation(.spring(response: 0.3), value: selected)
        .contentShape(Circle())
    }
}

// MARK: - 장소 카드(지도 마커 팝업)

struct SpotCardView: View {
    let spot: TourSpot
    var onClose: () -> Void
    @State private var showHandoff = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                SpotImage(url: spot.imageURL) {
                    LinearGradient(colors: [.meadowHorizon, .meadowSky],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(height: 140).frame(maxWidth: .infinity).clipped()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.white, .black.opacity(0.4))
                        .padding(8)
                }
                if let d = spot.distanceText {
                    Text(d).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(spot.spotName).font(.headline.weight(.medium)).lineLimit(1)
                    .foregroundStyle(Meadow.textPrimary(scheme))
                if let addr = spot.address ?? spot.region {
                    Label(addr, systemImage: "mappin").font(.caption)
                        .foregroundStyle(Meadow.textSecondary(scheme)).lineLimit(1)
                }
                Button {
                    showHandoff = true
                } label: {
                    Label("여기로 길안내", systemImage: "location.north.line.fill")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color.meadowAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Meadow.onAccent)
                }
                .padding(.top, 2)
            }
            .padding(16)
        }
        .background(Meadow.surface(scheme), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .confirmationDialog("길안내 앱 선택", isPresented: $showHandoff, titleVisibility: .visible) {
            ForEach(handoffOptions) { opt in Button(opt.label) { opt.action() } }
            Button("취소", role: .cancel) {}
        }
    }

    private var handoffOptions: [ExternalMapOption] {
        ExternalMap.options(
            to: .init(latitude: spot.latitude, longitude: spot.longitude),
            name: spot.spotName)
    }
}
