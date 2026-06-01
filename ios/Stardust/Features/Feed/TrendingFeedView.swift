import SwiftUI

@MainActor
final class TrendingFeedViewModel: ObservableObject {
    @Published private(set) var items: [TrendingItem] = []
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private let api = StardustAPI.shared
    private let pageSize = 20
    private var canLoadMore = true

    /// 첫 진입/당겨서 새로고침.
    func refresh() async {
        canLoadMore = true
        await load(reset: true)
    }

    /// 마지막 셀이 보이면 다음 페이지.
    func loadMoreIfNeeded(current item: TrendingItem) async {
        guard let last = items.last, last.id == item.id, canLoadMore, !isLoading else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let offset = reset ? 0 : items.count
            let page = try await api.fetchTrending(limit: pageSize, offset: offset)
            if reset { items = page } else { items.append(contentsOf: page) }
            if page.count < pageSize { canLoadMore = false }
            errorText = nil
        } catch let e as StardustError {
            errorText = e.errorDescription
        } catch {
            errorText = "피드를 불러오지 못했어요."
        }
    }

    // MARK: UGC 모더레이션 — 신고/차단 후 피드에서 즉시 제거
    func report(_ item: TrendingItem, reason: String) async {
        do {
            try await api.reportVideo(skyVideoId: item.skyVideoId, reason: reason)
            items.removeAll { $0.id == item.id }
            errorText = nil
        } catch {
            errorText = "신고에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    func block(_ item: TrendingItem) async {
        do {
            try await api.blockUser(userId: item.userId)
            items.removeAll { $0.userId == item.userId }   // 그 사용자 콘텐츠 모두 제거
            errorText = nil
        } catch {
            errorText = "차단에 실패했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}

struct TrendingFeedView: View {
    @StateObject private var stage = FeedStageCoordinator()
    @StateObject private var vm = TrendingFeedViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(vm.items) { item in
                    AutoplayVideoCell(video: item)
                        .environmentObject(stage)
                        .overlay(alignment: .topLeading) { metaBadge(item) }
                        .overlay(alignment: .topTrailing) { moderationMenu(item) }
                        .padding(.horizontal, 16)
                        .task { await vm.loadMoreIfNeeded(current: item) }
                }
                if vm.isLoading {
                    ProgressView().tint(.white).padding(.vertical, 24)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .refreshable { await vm.refresh() }     // 당겨서 새로고침
        .overlay { if let err = vm.errorText, vm.items.isEmpty { errorState(err) } }
        .task { if vm.items.isEmpty { await vm.refresh() } }
    }

    // 명소명/지역 + 동시 접속자 배지 (서버가 좌표로 매핑해 준 값)
    @ViewBuilder
    private func metaBadge(_ item: TrendingItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let spot = item.spotName ?? item.region {
                Label(spot, systemImage: item.isGangwon ? "mountain.2.fill" : "mappin")
                    .font(.caption2.bold())
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            if item.liveUsersCount > 0 {
                Label("\(item.liveUsersCount)명이 같은 하늘 아래", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(26)
    }

    // 신고/차단 메뉴 (App Store Guideline 1.2 — UGC 모더레이션)
    @ViewBuilder
    private func moderationMenu(_ item: TrendingItem) -> some View {
        Menu {
            Menu("신고하기", systemImage: "flag") {
                Button("스팸 또는 광고", role: .destructive) {
                    Task { await vm.report(item, reason: "spam") }
                }
                Button("부적절한 콘텐츠", role: .destructive) {
                    Task { await vm.report(item, reason: "inappropriate") }
                }
                Button("불쾌감을 주는 표현", role: .destructive) {
                    Task { await vm.report(item, reason: "offensive") }
                }
                Button("폭력적·위험한 콘텐츠", role: .destructive) {
                    Task { await vm.report(item, reason: "violence") }
                }
                Button("기타", role: .destructive) {
                    Task { await vm.report(item, reason: "other") }
                }
            }
            Button("이 사용자 차단", systemImage: "person.slash", role: .destructive) {
                Task { await vm.block(item) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline).foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(22)
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.rain").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
            Text(message).foregroundStyle(.white.opacity(0.8))
            Button("다시 시도") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
