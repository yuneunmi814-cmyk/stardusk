import SwiftUI

extension Color {
    /// "#5794E4" / "5794E4" → Color (실패 시 fallback)
    init(hex: String, fallback: Color = .blue) {
        var s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = fallback; return }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8)  & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }

    // MARK: 대표색에서 위·아래 톤을 만들어 자연스러운 하늘 결 생성
    func lighter(_ amount: CGFloat) -> Color { adjust(brightness: amount) }
    func darker(_ amount: CGFloat) -> Color { adjust(brightness: -amount) }

    private func adjust(brightness delta: CGFloat) -> Color {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: Double(h), saturation: Double(s),
                     brightness: Double(min(max(b + delta, 0), 1)), opacity: Double(a))
        #else
        return self
        #endif
    }
}
