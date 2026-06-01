import SwiftUI

/// HTML 프로토타입과 동일한 밤하늘 배경 — 정적 그러데이션 + 잔잔히 깜빡이는 별.
/// (이전의 '떠다니는 빛무리'는 산만해서 제거했다.)
struct SkyGradientBackground: View {
    let mood: SkyMood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { timeline in
            ZStack {
                mood.gradient.ignoresSafeArea()
                StarfieldOverlay(date: timeline.date, bright: mood.prefersBrightStars)
                    .ignoresSafeArea()
            }
        }
    }
}

/// HTML `.starfield` 재현 — 별 34개를 화면 상단 70% 영역에 흩뿌리고,
/// 각자 3초 주기(랜덤 위상)로 은은하게 깜빡인다.
///   opacity .15 ↔ .95 / scale .7 ↔ 1.25  (HTML @keyframes tw 와 동일)
struct StarfieldOverlay: View {
    let date: Date
    var bright: Bool = true

    private struct Star { let x, y: CGFloat; let delay: Double }
    // HTML seedStars(): 34개, left 0~100%, top 0~70%, animationDelay 0~3s
    private let stars: [Star] = (0..<34).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...0.7), delay: .random(in: 0...3))
    }

    var body: some View {
        Canvas { ctx, size in
            let t = date.timeIntervalSinceReferenceDate
            let dim = bright ? 1.0 : 0.55          // 밝은 무드가 아니면 살짝 어둡게
            for s in stars {
                // 3초 주기 ease-in-out: p 0→0.5→1 동안 f 가 0→1→0
                let p = ((t + s.delay).truncatingRemainder(dividingBy: 3)) / 3
                let f = 0.5 - 0.5 * cos(2 * .pi * p)
                let opacity = (0.15 + 0.80 * f) * dim
                let scale = 0.7 + 0.55 * f
                let d = 2.0 * scale                // HTML 별 크기 2px
                let rect = CGRect(x: s.x * size.width - d / 2,
                                  y: s.y * size.height - d / 2, width: d, height: d)
                ctx.opacity = opacity
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}
