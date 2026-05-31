import SwiftUI

/// 피드 전체에서 '지금 무대 중앙에 가장 가까운 셀'의 id 하나만 활성으로 둔다.
@MainActor
final class FeedStageCoordinator: ObservableObject {
    @Published var activeID: String?

    private var candidates: [String: CGFloat] = [:]   // id → 화면중앙과의 거리
    private var pending = false

    func report(id: String, distanceToCenter: CGFloat?) {
        if let d = distanceToCenter { candidates[id] = d } else { candidates.removeValue(forKey: id) }
        scheduleResolve()
    }

    private func scheduleResolve() {
        guard !pending else { return }
        pending = true
        // 스크롤 중 과도한 갱신 방지(다음 런루프에 1회만 계산)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending = false
            let best = self.candidates.min { $0.value < $1.value }?.key
            if best != self.activeID { self.activeID = best }
        }
    }
}
