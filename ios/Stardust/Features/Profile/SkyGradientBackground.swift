import SwiftUI

/// 그러데이션 위로 빛무리가 천천히 흐르고, 별이 깜빡이는 '살아있는' 하늘 배경.
struct SkyGradientBackground: View {
    let mood: SkyMood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                mood.gradient.ignoresSafeArea()

                // 천천히 떠다니는 빛무리(하늘이 숨 쉬는 느낌)
                RadialGradient(
                    colors: [mood.stops.first!.opacity(0.0),
                             mood.accent.opacity(0.30)],
                    center: UnitPoint(x: 0.5 + 0.22 * sin(t * 0.12),
                                      y: 0.34 + 0.14 * cos(t * 0.09)),
                    startRadius: 8, endRadius: 460
                )
                .blendMode(.plusLighter)
                .ignoresSafeArea()

                StarfieldOverlay(date: timeline.date,
                                 bright: mood.prefersBrightStars)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Canvas 로 그린 가벼운 별 입자(60개) — 각자 다른 위상으로 반짝인다.
struct StarfieldOverlay: View {
    let date: Date
    var bright: Bool = true

    private struct Star { let x, y, r: CGFloat; let phase: Double }
    private let stars: [Star] = (0..<60).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...1),
             r: .random(in: 0.6...1.9), phase: .random(in: 0...(2 * .pi)))
    }

    var body: some View {
        Canvas { ctx, size in
            let t = date.timeIntervalSinceReferenceDate
            let baseAlpha = bright ? 0.9 : 0.35
            for s in stars {
                let twinkle = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * 1.5 + s.phase))
                let d = s.r * 2
                let rect = CGRect(x: s.x * size.width, y: s.y * size.height, width: d, height: d)
                ctx.opacity = twinkle * baseAlpha
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
        .blendMode(.screen)
    }
}
