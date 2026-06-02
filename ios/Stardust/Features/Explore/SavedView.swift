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

    private let api = StardustAPI.shared

    var body: some View {
        NavigationStack {
            Group {
                if spots.isEmpty && !isLoading {
                    emptyState
                } else {
                    List {
                        ForEach(spots) { spot in row(spot) }
                            .onDelete { idx in Task { await remove(idx) } }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("저장한 곳")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AsyncImage(url: spot.imageURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [Color(hex: "#8FBEF0"), Color(hex: "#CFE5FB")],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(spot.spotName).font(.headline).lineLimit(1)
                    if let addr = spot.address ?? spot.region {
                        Text(addr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let badge = spot.tasteBadge {
                        Label(badge.text, systemImage: badge.symbol)
                            .font(.caption2.weight(.semibold)).foregroundStyle(Color(hex: "#5794E4"))
                    }
                }
                Spacer()
            }
            HStack(spacing: 10) {
                chip("길찾기", "location.north.line.fill") { startNavigation(spot) }
                chip(docent.speakingId == spot.id ? "정지" : "안내 듣기",
                     docent.speakingId == spot.id ? "stop.fill" : "speaker.wave.2.fill") {
                    toggleDocent(spot)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func chip(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(Color(hex: "#5794E4").opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color(hex: "#5794E4"))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.text.square").font(.system(size: 50)).foregroundStyle(.secondary)
            Text("저장한 곳이 없어요").font(.headline)
            Text("탐색에서 마음에 드는 곳을 라이크(♥)하면 여기에 모여요")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { spots = try await api.fetchSavedSpots(); errorText = nil }
        catch { errorText = "저장 목록을 불러오지 못했어요." }
    }

    private func remove(_ offsets: IndexSet) async {
        guard let i = offsets.first, i < spots.count else { return }
        let spot = spots[i]
        do { spots = try await api.unsaveSpot(tourId: spot.tourId) }
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
