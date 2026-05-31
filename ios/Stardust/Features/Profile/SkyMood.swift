import SwiftUI

// MARK: - 하루의 모든 하늘빛
enum SkyMood {
    case dawn        // 차분한 새벽 — 남보라→라벤더→연분홍
    case rosyDawn    // 분홍빛 여명 — 로즈→피치
    case clearDay    // 맑은 오후 — 청량한 하늘
    case sunshine    // 눈부신 햇살 — 하늘→레몬
    case sunset      // 따뜻한 노을 — 보라→주황→살구
    case night       // 고요한 밤 — 짙은 남색
    case deepBlue    // 깊은 쪽빛
    case clouds      // 잔잔한 구름 — 화이트→연하늘
    case overcast    // 흐린 오후 — 그레이
    case greenery    // 싱그러운 풀빛
    case aqua        // 청량한 물빛
    case custom([Color])

    /// 감정 라벨 우선 → 없으면 대표색에서 톤을 뽑아 그러데이션 구성.
    static func resolve(emotion: String?, hex: String) -> SkyMood {
        switch emotion {
        case "차분한 새벽":   return .dawn
        case "분홍빛 여명":   return .rosyDawn
        case "맑은 오후":     return .clearDay
        case "눈부신 햇살":   return .sunshine
        case "따뜻한 노을":   return .sunset
        case "고요한 밤":     return .night
        case "깊은 쪽빛":     return .deepBlue
        case "잔잔한 구름":   return .clouds
        case "흐린 오후":     return .overcast
        case "싱그러운 풀빛": return .greenery
        case "청량한 물빛":   return .aqua
        default:
            let base = Color(hex: hex)
            return .custom([base.lighter(0.28), base, base.darker(0.22)])
        }
    }

    /// 위(하늘 높이)에서 아래(지평선)로 흐르는 색 정지점.
    var stops: [Color] {
        switch self {
        case .dawn:     return [Color(hex:"#3A2E6E"), Color(hex:"#7A6FB0"), Color(hex:"#E9B7C8")]
        case .rosyDawn: return [Color(hex:"#F7A8B8"), Color(hex:"#FBC7D4"), Color(hex:"#FCD9A8")]
        case .clearDay: return [Color(hex:"#5794E4"), Color(hex:"#8FBEF0"), Color(hex:"#CFE5FB")]
        case .sunshine: return [Color(hex:"#7EC8F2"), Color(hex:"#BFE3F5"), Color(hex:"#FCEFB0")]
        case .sunset:   return [Color(hex:"#5B3A82"), Color(hex:"#E8746B"), Color(hex:"#FBC18B")]
        case .night:    return [Color(hex:"#070B1E"), Color(hex:"#1B2350"), Color(hex:"#3A4A86")]
        case .deepBlue: return [Color(hex:"#16306B"), Color(hex:"#2456A6"), Color(hex:"#5E8FD6")]
        case .clouds:   return [Color(hex:"#DCE7F2"), Color(hex:"#EAF1F8"), Color(hex:"#F8FBFE")]
        case .overcast: return [Color(hex:"#8A95A3"), Color(hex:"#AEB7C2"), Color(hex:"#D2D8DF")]
        case .greenery: return [Color(hex:"#2E7D5B"), Color(hex:"#6FB58C"), Color(hex:"#CFE9D6")]
        case .aqua:     return [Color(hex:"#1C8C9E"), Color(hex:"#5FBFCB"), Color(hex:"#C7ECEF")]
        case .custom(let c): return c
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }
    /// 텍스트/포인트에 쓸 중간 대표색.
    var accent: Color { stops[stops.count / 2] }
    /// 밤/노을처럼 어두운 무드일 때 별이 더 잘 보이도록.
    var prefersBrightStars: Bool {
        switch self { case .night, .deepBlue, .dawn, .sunset: return true; default: return false }
    }
}
