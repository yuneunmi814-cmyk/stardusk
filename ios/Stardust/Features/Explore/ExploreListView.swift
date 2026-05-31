import SwiftUI
import CoreLocation

/// 리스트로 탐색 — 상단 [지역 필터(시/도·시/군/구)] + [통합 검색창] + 결과 리스트.
struct ExploreListView: View {
    @ObservedObject var vm: ExploreViewModel
    @EnvironmentObject private var appLocation: AppLocation

    var body: some View {
        VStack(spacing: 10) {
            searchBar
            filterRow

            if vm.isLoading && vm.listItems.isEmpty {
                Spacer(); ProgressView(); Spacer()
            } else if vm.listItems.isEmpty {
                emptyState
            } else {
                List(vm.listItems) { spot in
                    SpotRow(spot: spot)
                        .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .listStyle(.plain)
            }
        }
        .task {
            await vm.loadRegions()
            if vm.listItems.isEmpty { await runSearch() }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("관광지 통합 검색 (예: 경포, 해변, 사찰)", text: $vm.keyword)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if !vm.keyword.isEmpty {
                Button { vm.keyword = ""; Task { await runSearch() } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 4)
    }

    private var filterRow: some View {
        HStack(spacing: 10) {
            // 시/도
            Menu {
                Button("전체") { vm.selectProvince(nil); Task { await runSearch() } }
                ForEach(vm.regions) { r in
                    Button(r.province) { vm.selectProvince(r.province); Task { await runSearch() } }
                }
            } label: {
                filterChip(title: vm.selectedProvince ?? "시/도", active: vm.selectedProvince != nil)
            }

            // 시/군/구 (시/도 선택 시 활성화)
            Menu {
                Button("전체") { vm.selectedCity = nil; Task { await runSearch() } }
                ForEach(vm.cities, id: \.self) { c in
                    Button(c) { vm.selectedCity = c; Task { await runSearch() } }
                }
            } label: {
                filterChip(title: vm.selectedCity ?? "시/군/구", active: vm.selectedCity != nil)
            }
            .disabled(vm.selectedProvince == nil)
            .opacity(vm.selectedProvince == nil ? 0.5 : 1)

            Spacer()
            if vm.listTotal > 0 {
                Text("\(vm.listTotal)곳").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func filterChip(title: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .foregroundStyle(active ? Color.white : Color.primary)
        .background(active ? Color(hex: "#5794E4") : Color(.systemGray6),
                    in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
            Text("조건에 맞는 관광지가 없어요").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func runSearch() async {
        await vm.runSearch(center: appLocation.coordinate)
    }
}

// MARK: - 리스트 행

struct SpotRow: View {
    let spot: TourSpot
    @State private var showHandoff = false

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: spot.imageURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                LinearGradient(colors: [Color(hex: "#8FBEF0"), Color(hex: "#CFE5FB")],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.spotName).font(.callout.weight(.semibold)).lineLimit(1)
                if let addr = spot.address ?? spot.region {
                    Text(addr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let d = spot.distanceText {
                        Label(d, systemImage: "figure.walk").font(.caption2).foregroundStyle(.secondary)
                    }
                    Button { showHandoff = true } label: {
                        Label("길안내", systemImage: "arrow.triangle.turn.up.right.diamond")
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
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
