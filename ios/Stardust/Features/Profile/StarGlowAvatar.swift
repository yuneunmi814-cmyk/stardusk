import SwiftUI

/// 유저가 올려다본 하늘색이 곧 자신의 별빛이 된다.
/// 후광 펄스(숨쉬기) + 오로라 링(회전) + 유리알 하이라이트로 '살아있는 별'을 표현.
struct StarGlowAvatar: View {
    let colorHex: String
    var emotion: String? = nil
    var size: CGFloat = 96

    private var mood: SkyMood { SkyMood.resolve(emotion: emotion, hex: colorHex) }
    @State private var breathe = false
    @State private var spin = false

    var body: some View {
        ZStack {
            // ① 바깥 후광 — 부드럽게 번지며 숨 쉰다
            Circle()
                .fill(mood.accent)
                .frame(width: size, height: size)
                .blur(radius: breathe ? 34 : 22)
                .opacity(breathe ? 0.9 : 0.45)
                .scaleEffect(breathe ? 1.18 : 0.9)

            // ② 오로라 링 — 하늘빛 그러데이션이 천천히 회전
            Circle()
                .strokeBorder(
                    AngularGradient(colors: mood.stops + [mood.stops.first!], center: .center),
                    lineWidth: 6
                )
                .frame(width: size * 1.14, height: size * 1.14)
                .blur(radius: 2)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .opacity(0.85)

            // ③ 본체 — 하늘 그러데이션 오브(아이콘 결)
            Circle()
                .fill(mood.gradient)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                .overlay(
                    // 유리알 하이라이트
                    Circle()
                        .fill(.white.opacity(0.28))
                        .frame(width: size * 0.4, height: size * 0.4)
                        .blur(radius: 6)
                        .offset(x: -size * 0.16, y: -size * 0.2)
                )
                .shadow(color: mood.accent.opacity(0.7), radius: 14)
        }
        .frame(width: size * 1.45, height: size * 1.45)   // 후광 여백 확보
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityLabel(Text(emotion ?? "오늘의 하늘빛"))
    }
}
