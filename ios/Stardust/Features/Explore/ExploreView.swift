import SwiftUI
import MapKit
import CoreLocation

/// 하이브리드 탐색의 메인 컨테이너 — 상단 듀얼 탭(지도로 탐색 / 리스트로 탐색).
@available(iOS 17.0, *)
struct ExploreView: View {
    @EnvironmentObject private var appLocation: AppLocation
    @StateObject private var vm = ExploreViewModel()

    private enum Mode: String, CaseIterable { case map = "지도로 탐색", list = "리스트로 탐색" }
    @State private var mode: Mode = .map
    @State private var showCuration = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("탐색 방식", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.bottom, 8)

            switch mode {
            case .map:
                ExploreMapView(vm: vm) {
                    showCuration = true
                    Task { await vm.loadDeck(center: appLocation.coordinate) }
                }
            case .list: ExploreListView(vm: vm)
            }
        }
        // 진입 시 현재 위치 자동 취득(권한 팝업 포함). 위치 설정 화면을 강제하지 않는다.
        .task { appLocation.autoLocate() }
        // 좌표가 갱신될 때마다(자동 취득/변경) 주변 명소 재로딩.
        .task(id: "\(appLocation.coordinate.latitude),\(appLocation.coordinate.longitude)") {
            await vm.loadMap(center: appLocation.coordinate)
        }
        // 풀스크린 추천 카드 — 탭바는 유지(시트 대신 탭 콘텐츠 위 오버레이).
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("메뉴")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

// MARK: - 지도로 탐색

@available(iOS 17.0, *)
struct ExploreMapView: View {
    @ObservedObject var vm: ExploreViewModel
    @EnvironmentObject private var appLocation: AppLocation
    var onExplore: () -> Void
    @State private var camera: MapCameraPosition = .automatic

    /// [지도로 탐색] 내부 2단 토글 — 화면 스킨만 바뀌고 데이터는 동일하게 싱크.
    /// 스카이 뷰가 앱의 메인 홈 비주얼이므로 기본값으로 고정.
    private enum SkyMode: String, CaseIterable { case sky = "스카이 뷰", realMap = "일반 지도" }
    @State private var skyMode: SkyMode = .sky

    var body: some View {
        VStack(spacing: 8) {
            // 상단 토글: 일반 지도 ↔ 스카이 뷰
            Picker("뷰 전환", selection: $skyMode) {
                ForEach(SkyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .padding(.top, 2)

            ZStack(alignment: .bottom) {
                Group {
                    switch skyMode {
                    case .realMap: realMap
                    case .sky:
                        ExploreSkyMapView(spots: vm.mapSpots,
                                          center: appLocation.coordinate,
                                          selectedSpot: $vm.selectedSpot,
                                          onExplore: onExplore)
                    }
                }
                .transition(.opacity)

                if let spot = vm.selectedSpot {
                    SpotCardView(spot: spot) { withAnimation { vm.selectedSpot = nil } }
                        .padding(.horizontal, 14).padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if vm.mapSpots.isEmpty && !vm.isLoading {
                    VStack(spacing: 6) {
                        Image(systemName: "moon.stars.fill").font(.title2)
                        Text("이 지역은 아직 준비 중이에요").font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.vertical, 14).padding(.horizontal, 18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if vm.isLoading { ProgressView().padding(8).background(.regularMaterial, in: Capsule()) }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: skyMode)
    }

    // 일반 지도 뷰 — 네이티브 현실 지도 + OpenAPI 관광지 마커
    private var realMap: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(vm.mapSpots) { spot in
                Annotation(spot.spotName,
                           coordinate: .init(latitude: spot.latitude, longitude: spot.longitude)) {
                    Button {
                        withAnimation(.spring) { vm.selectedSpot = spot }
                    } label: {
                        Image(systemName: "star.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, Color(hex: "#5794E4"))
                            .shadow(radius: 3)
                            .scaleEffect(vm.selectedSpot == spot ? 1.25 : 1)
                    }
                }
            }
        }
        .mapControls { MapUserLocationButton(); MapCompass() }
        .onAppear { recenter() }
    }

    private func recenter() {
        camera = .region(MKCoordinateRegion(
            center: appLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))
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
                    Label("여기로 길안내", systemImage: "heart.fill")
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
            ForEach(handoffOptions.indices, id: \.self) { i in
                Button(handoffOptions[i].label) { handoffOptions[i].action() }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private var handoffOptions: [(label: String, action: () -> Void)] {
        ExternalMap.openWalking(
            to: .init(latitude: spot.latitude, longitude: spot.longitude),
            name: spot.spotName)
    }
}
