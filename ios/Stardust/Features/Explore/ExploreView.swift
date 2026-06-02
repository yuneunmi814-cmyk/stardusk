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
    @AppStorage("didPrimeLocation") private var didPrime = false
    @State private var showPriming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            mapArea
        }
        // 권한 안내(priming)를 한 번 보여준 뒤에 위치를 요청한다.
        .task {
            if didPrime { appLocation.autoLocate() } else { showPriming = true }
        }
        .overlay { if showPriming { primingCard } }
        // 좌표가 갱신될 때마다 주변 명소 재로딩 + 지도 재중심.
        .task(id: "\(appLocation.coordinate.latitude),\(appLocation.coordinate.longitude)") {
            recenter()
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
            Image(systemName: "location.fill").font(.footnote).foregroundStyle(Color(hex: "#5794E4"))
            Text(appLocation.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
            Button { appLocation.reopenSetup() } label: {
                Text("변경").font(.caption.weight(.semibold))
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(.systemGray5), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("메뉴")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
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
                    Image(systemName: "moon.stars.fill").font(.title2)
                    Text("이 지역은 아직 준비 중이에요").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 14).padding(.horizontal, 18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
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
                Text("내 주변 관광지 탐색").font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24).frame(height: 54)
            .background(Color(hex: "#5794E4").opacity(0.95), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Color(hex: "#5794E4").opacity(0.5), radius: 12, y: 4)
        }
    }

    private func recenter() {
        camera = .region(MKCoordinateRegion(
            center: appLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))
    }

    // 위치 권한 안내(priming) — iOS 시스템 팝업 전에 맥락을 먼저 설명.
    private var primingCard: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(Color(hex: "#5794E4"))
                Text("내 주변 관광지를 찾을게요").font(.headline)
                Text("현재 위치를 기준으로 가까운 명소를 보여드려요.\n위치 권한을 허용해 주세요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    didPrime = true
                    showPriming = false
                    appLocation.autoLocate()       // 이제 iOS 권한 팝업
                } label: {
                    Text("허용하고 시작").font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Color(hex: "#5794E4"), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 36)
        }
    }
}

/// 지도 마커 — HTML 별처럼 작은 빛나는 점. 선택 시 커진다.
struct StarDot: View {
    var selected: Bool
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "#5794E4").opacity(0.35))
                .frame(width: selected ? 26 : 18, height: selected ? 26 : 18).blur(radius: 4)
            Circle().fill(.white)
                .frame(width: selected ? 12 : 8, height: selected ? 12 : 8)
                .overlay(Circle().stroke(Color(hex: "#5794E4"), lineWidth: selected ? 2 : 1))
                .shadow(color: Color(hex: "#5794E4").opacity(0.8), radius: selected ? 6 : 3)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: spot.imageURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [Color(hex: "#8FBEF0"), Color(hex: "#CFE5FB")],
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
                Text(spot.spotName).font(.headline).lineLimit(1)
                if let addr = spot.address ?? spot.region {
                    Label(addr, systemImage: "mappin").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button {
                    showHandoff = true
                } label: {
                    Label("여기로 길안내", systemImage: "location.north.line.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color(hex: "#5794E4"), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
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
