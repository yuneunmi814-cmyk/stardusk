import SwiftUI

/// 원버튼 큐레이션 시트 — 주변 OpenAPI 관광지를 한 장씩 카드로 제시하고
/// [패스 / 새로고침 / 라이크] 3단 액션으로 고민 없이 목적지를 고른다.
/// 라이크 시 onLike(spot)로 알려, 홈(스카이 뷰)에 경로 궤도를 활성화한다.
struct SpotCurationSheet: View {
    let spots: [TourSpot]
    var onLike: (TourSpot) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 8)

            if spots.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                    Text("주변에 추천할 명소가 없어요").foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                let spot = spots[min(index, spots.count - 1)]
                Text("내 주변, 이 별은 어때요?")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                card(spot)
                actions(for: spot)
            }
        }
        .padding(.bottom, 24)
        .presentationDragIndicator(.hidden)
    }

    // MARK: 명소 카드

    private func card(_ spot: TourSpot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: spot.imageURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [Color(hex: "#8FBEF0"), Color(hex: "#CFE5FB")],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 200).frame(maxWidth: .infinity).clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(spot.spotName).font(.title3.weight(.bold)).lineLimit(1)
                if let addr = spot.address ?? spot.region {
                    Label(addr, systemImage: "mappin").font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                if let d = spot.distanceText {
                    Label(d, systemImage: "figure.walk").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 18)
        .id(spot.id) // 카드 교체 시 트랜지션
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity))
    }

    // MARK: 3단 액션

    private func actions(for spot: TourSpot) -> some View {
        HStack(spacing: 26) {
            curationButton("패스", "xmark", Color(.systemGray)) { dismiss() }
            curationButton("새로고침", "arrow.clockwise", Color(hex: "#8FBEF0")) {
                withAnimation(.spring) { index = (index + 1) % spots.count }
            }
            curationButton("라이크", "heart.fill", Color(hex: "#5794E4")) {
                onLike(spot); dismiss()
            }
        }
    }

    private func curationButton(_ label: String, _ icon: String, _ color: Color,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 60, height: 60)
                    Image(systemName: icon).font(.title2).foregroundStyle(color)
                }
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
