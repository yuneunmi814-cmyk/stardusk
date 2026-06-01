import SwiftUI

/// 그러데이션 위로 빛무리가 천천히 흐르고, 별이 깜빡이는 '살아있는' 하늘 배경.
struct SkyGradientBackground: View {
    let mood: SkyMood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                mood.gradient.ignoresSafeArea()

                // 아주 천천히, 은은하게 흐르는 빛무리(하늘이 숨 쉬는 느낌)
                RadialGradient(
                    colors: [mood.stops.first!.opacity(0.0),
                             mood.accent.opacity(0.16)],
                    center: UnitPoint(x: 0.5 + 0.12 * sin(t * 0.05),
                                      y: 0.32 + 0.08 * cos(t * 0.04)),
                    startRadius: 40, endRadius: 520
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

/// Canvas 로 그린 잔잔한 별 입자 — 별마다 느린 속도로 은은하게 반짝인다.
/// (HTML 프로토타입의 차분한 밤하늘 톤에 맞춰 개수·속도·밝기 흔들림을 낮췄다.)
struct StarfieldOverlay: View {
    let date: Date
    var bright: Bool = true

    private struct Star { let x, y, r: CGFloat; let phase: Double; let speed: Double }
    private let stars: [Star] = (0..<42).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...1),
             r: .random(in: 0.5...1.5), phase: .random(in: 0...(2 * .pi)),
             speed: .random(in: 0.22...0.5))   // 별마다 느린 속도(정신없는 동시 깜빡임 방지)
    }

    var body: some View {
        Canvas { ctx, size in
            let t = date.timeIntervalSinceReferenceDate
            let baseAlpha = bright ? 0.78 : 0.3
            for s in stars {
                // 느리고 잔잔한 깜빡임 — 완전히 꺼지지 않고 0.34~0.90 사이에서 은은하게.
                let twinkle = 0.62 + 0.28 * sin(t * s.speed + s.phase)
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
