import SwiftUI

// MARK: - 디자인 토큰: "광활한 초원" 자연 컨셉
// 색은 View 에 하드코딩하지 말고 반드시 이 토큰을 통해서만 참조한다.
extension Color {
    static let meadowSky       = Color(red: 0.804, green: 0.918, blue: 0.996) // #CDEAFE
    static let meadowHorizon   = Color(red: 0.659, green: 0.835, blue: 0.635) // #A8D5A2
    static let meadow          = Color(red: 0.486, green: 0.722, blue: 0.486) // #7CB87C
    static let meadowDeep      = Color(red: 0.353, green: 0.620, blue: 0.369) // #5A9E5E
    static let meadowSurface   = Color(red: 0.992, green: 0.984, blue: 0.953) // #FDFBF3
    static let meadowTextPrimary   = Color(red: 0.180, green: 0.290, blue: 0.188) // #2E4A30
    static let meadowTextSecondary = Color(red: 0.420, green: 0.541, blue: 0.431) // #6B8A6E
    static let meadowAccent    = Color(red: 0.910, green: 0.722, blue: 0.294) // #E8B84B
    // 다크(밤의 초원)
    static let meadowNightBg   = Color(red: 0.118, green: 0.200, blue: 0.133) // #1E3322
}

// MARK: - 시맨틱 토큰 (colorScheme 분기)
// 다크에서 초원 톤이 형광색으로 반전되지 않도록, 색을 쓰는 쪽에서 이 헬퍼로 분기한다.
enum Meadow {
    /// 카드/시트 표면색 — 라이트: 크림, 다크: 어두운 초원 표면.
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.157, green: 0.250, blue: 0.176) : .meadowSurface
    }
    /// 본문 텍스트 — 다크에선 크림으로(순수 검정/흰색 금지).
    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .meadowSurface : .meadowTextPrimary
    }
    /// 보조 텍스트.
    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.659, green: 0.745, blue: 0.667) : .meadowTextSecondary
    }
    /// CTA 위에 올리는 글자색(악센트 배경 대비).
    static let onAccent = Color.white
}

// MARK: - 메인 배경 그라데이션 (하늘 → 초원 → 깊은 풀색)
// 다크일 땐 밤의 초원(단색에 가깝게)으로 분기해 형광 반전 방지.
struct MeadowBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if scheme == .dark {
                LinearGradient(
                    colors: [.meadowNightBg, Color(red: 0.078, green: 0.137, blue: 0.090)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [.meadowSky, .meadowHorizon, .meadow, .meadowDeep],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 카드 스타일 (표면 + 옅은 그림자 + 둥근 모서리 20)
struct MeadowCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Meadow.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}
extension View {
    func meadowCard() -> some View { modifier(MeadowCard()) }
}

// MARK: - 주요 버튼(CTA) 스타일 — 악센트 배경 + 흰 글자, 모서리 14
struct MeadowCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Meadow.onAccent)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color.meadowAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
extension ButtonStyle where Self == MeadowCTAStyle {
    static var meadowCTA: MeadowCTAStyle { MeadowCTAStyle() }
}
