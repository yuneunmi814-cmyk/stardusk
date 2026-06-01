import SwiftUI

/// 정적인 밤하늘 배경 — 그러데이션 + 깜빡이지 않는 아주 옅은 고정 별.
/// (반짝임이 산만하다는 피드백 반영 → 트윈클 애니메이션을 완전히 제거)
struct SkyGradientBackground: View {
    let mood: SkyMood

    var body: some View {
        ZStack {
            mood.gradient.ignoresSafeArea()
            StarfieldOverlay(bright: mood.prefersBrightStars).ignoresSafeArea()
        }
    }
}

/// 깜빡이지 않는 고정 별 28개. 각자 고정된 옅은 밝기로 가만히 떠 있다.
struct StarfieldOverlay: View {
    var bright: Bool = true

    private struct Star { let x, y, r: CGFloat; let a: Double }
    private let stars: [Star] = (0..<28).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...0.92),
             r: .random(in: 0.6...1.2), a: .random(in: 0.22...0.55))
    }

    var body: some View {
        Canvas { ctx, size in
            let dim = bright ? 1.0 : 0.6
            for s in stars {
                let d = s.r * 2
                let rect = CGRect(x: s.x * size.width - d / 2,
                                  y: s.y * size.height - d / 2, width: d, height: d)
                ctx.opacity = s.a * dim
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}
