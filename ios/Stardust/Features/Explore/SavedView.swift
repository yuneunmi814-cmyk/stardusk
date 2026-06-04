import SwiftUI
import CoreLocation

/// 저장(라이크) 탭 — 라이크한 관광지를 모아 보고, 길찾기/안내 듣기/저장 해제.
@available(iOS 17.0, *)
struct SavedView: View {
    @StateObject private var docent = DocentSpeaker()
    @State private var spots: [TourSpot] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var handoff: [ExternalMapOption] = []
    @State private var showHandoff = false
    @Environment(\.colorScheme) private var scheme

    private let api = StardustAPI.shared

    var body: some View {
        NavigationStack {
            ZStack {
                MeadowBackground()
                Group {
                    if spots.isEmpty && !isLoading {
                        emptyState
                    } else {
                        List {
                            ForEach(spots) { spot in
                                row(spot)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                            .onDelete { idx in Task { await remove(idx) } }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("저장한 곳")
            .toolbar { if !spots.isEmpty { EditButton() } }   // 여러 개 한 번에 삭제
            .overlay { if isLoading { ProgressView() } }
            .refreshable { await load() }
            .task { await load() }
            .onDisappear { docent.stop() }
            .confirmationDialog("길안내 앱 선택", isPresented: $showHandoff, titleVisibility: .visible) {
                ForEach(handoff) { opt in Button(opt.label) { opt.action() } }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private func row(_ spot: TourSpot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SpotImage(url: spot.imageURL) {
                    LinearGradient(colors: [.meadowHorizon, .meadowSky],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.spotName).font(.headline.weight(.medium)).lineLimit(1)
                        .foregroundStyle(Meadow.textPrimary(scheme))
                    if let addr = spot.address ?? spot.region {
                        Text(addr).font(.caption).foregroundStyle(Meadow.textSecondary(scheme)).lineLimit(1)
                    }
                    if let badge = spot.tasteBadge {
                        Label(badge.text, systemImage: badge.symbol)
                            .font(.caption2.weight(.medium)).foregroundStyle(Color.meadowDeep)
                    }
                }
                Spacer()
                // 채워진 하트 = 저장됨. 탭하면 바로 저장 해제(탐색에서 다시 라이크하면 복구).
                Button { Task { await unsave(spot) } } label: {
                    Image(systemName: "heart.fill")
                        .font(.title3).foregroundStyle(Color.meadowDeep)
                        .padding(8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("저장 해제")
            }
            HStack(spacing: 10) {
                chip("길찾기", "location.north.line.fill") { startNavigation(spot) }
                chip(docent.speakingId == spot.id ? "정지" : "안내 듣기",
                     docent.speakingId == spot.id ? "stop.fill" : "speaker.wave.2.fill") {
                    toggleDocent(spot)
                }
            }
        }
        .meadowCard()
    }

    private func chip(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(Color.meadowDeep.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Color.meadowDeep)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.fill").font(.system(size: 50)).foregroundStyle(Color.meadow)
            Text("저장한 곳이 없어요").font(.headline.weight(.medium))
                .foregroundStyle(Meadow.textPrimary(scheme))
            Text("마음이 머문 쉼표를 라이크(♥)하면 여기에 모여요")
                .font(.subheadline).foregroundStyle(Meadow.textSecondary(scheme)).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { spots = try await api.fetchSavedSpots(); errorText = nil }
        catch { errorText = "저장 목록을 불러오지 못했어요." }
    }

    /// 스와이프/편집 모드 삭제 — 여러 항목 동시 삭제 지원.
    private func remove(_ offsets: IndexSet) async {
        let targets = offsets.map { spots[$0] }
        for spot in targets { try? await api.unsaveSpot(tourId: spot.tourId) }
        do { let updated = try await api.fetchSavedSpots(); withAnimation { spots = updated } }
        catch { errorText = "삭제에 실패했어요." }
    }

    /// 하트 버튼 탭 — 단일 항목 즉시 저장 해제.
    private func unsave(_ spot: TourSpot) async {
        do { let updated = try await api.unsaveSpot(tourId: spot.tourId); withAnimation { spots = updated } }
        catch { errorText = "삭제에 실패했어요." }
    }

    private func startNavigation(_ spot: TourSpot) {
        handoff = ExternalMap.options(
            to: .init(latitude: spot.latitude, longitude: spot.longitude), name: spot.spotName)
        showHandoff = true
    }

    private func toggleDocent(_ spot: TourSpot) {
        if docent.speakingId == spot.id { docent.stop(); return }
        Task {
            let text: String
            if let d = try? await api.fetchSpotDetail(tourId: spot.tourId),
               let ov = d.overview, !ov.isEmpty { text = ov }
            else { text = "\(spot.spotName). \(spot.address ?? spot.region ?? "")에 위치한 관광지입니다." }
            docent.speak(id: spot.id, text: text)
        }
    }
}
