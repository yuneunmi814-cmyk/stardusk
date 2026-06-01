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

    private struct Star { let x, y, r: CGFloat; let phase: Double; let period: Double }
    // 24개, 상단 70%. 별마다 10~14초의 '아주 느린' 주기로 따로따로 깜빡인다.
    private let stars: [Star] = (0..<24).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...0.7),
             r: .random(in: 0.8...1.2),
             phase: .random(in: 0...(2 * .pi)),
             period: .random(in: 10...14))
    }

    var body: some View {
        Canvas { ctx, size in
            let t = date.timeIntervalSinceReferenceDate
            let dim = bright ? 1.0 : 0.6
            for s in stars {
                // 밝기만 아주 천천히(10~14초 주기) 0.30~0.80 사이로. 크기 변화 없음.
                let w = 2 * .pi / s.period
                let f = 0.5 + 0.5 * sin(t * w + s.phase)   // 0~1, 매우 느림
                let opacity = (0.30 + 0.50 * f) * dim
                let d = s.r * 2                              // 고정 크기(펄스 제거)
                let rect = CGRect(x: s.x * size.width - d / 2,
                                  y: s.y * size.height - d / 2, width: d, height: d)
                ctx.opacity = opacity
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }
}
