import Foundation

// MARK: - 공통 응답 봉투
struct APIEnvelope<T: Decodable>: Decodable {
    let status: String
    let message: String?
    let data: T
}

// MARK: - 서버 에러 ({"detail": {...}})
struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let status: String
        let code: String
        let message: String
    }
    let detail: Detail
}

enum StardustError: LocalizedError {
    case server(code: String, message: String, http: Int)
    case transport(Error)
    case decoding(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .server(_, let message, _): return message
        case .transport(let e): return e.localizedDescription
        case .decoding: return "응답을 해석하지 못했어요."
        case .unauthorized: return "다시 로그인해 주세요."
        }
    }
    /// 서버 에러 코드(분기용). 예: "OUT_OF_SERVICE_AREA"
    var code: String? { if case .server(let c, _, _) = self { return c }; return nil }
}

/// data 필드가 없는 단순 성공 응답(신고/차단 등). {status, message}
struct SimpleOK: Decodable {
    let status: String
    let message: String?
}

/// GET /tour/{id}/detail 의 data — 도슨트(설명 듣기)용 상세설명.
struct SpotDetail: Decodable {
    let contentId: String
    let overview: String?
}

// MARK: - 하이브리드 탐색(관광지)
/// 지도 마커 · 리스트 행 · 장소 카드가 공유하는 단일 관광지 모델.
struct TourSpot: Decodable, Identifiable, Hashable {
    let tourId: String
    let spotName: String
    let region: String?
    let address: String?
    let imageUrl: String?       // KTO firstimage (빈 문자열일 수 있어 String 으로 받는다)
    let latitude: Double
    let longitude: Double
    let distanceMeters: Int?    // 기준 좌표가 없으면 nil
    // §3.6 성향 라벨링 — 서버 배치가 계산. nil 이면 미라벨(중립).
    let label: String?              // "hotplace" | "secret"
    let popularityScore: Double?    // 시군구 내 readcount 백분위(0~1)

    var id: String { tourId }

    var imageURL: URL? {
        guard let s = imageUrl, !s.isEmpty else { return nil }
        // KTO 대표사진은 http:// 로 내려오는데 iOS ATS 가 평문 HTTP 로드를 차단한다.
        // visitkorea 호스트는 https 를 지원하므로 스킴을 승격해 차단을 피한다.
        let secure = s.hasPrefix("http://") ? "https://" + s.dropFirst("http://".count) : s
        return URL(string: secure)
    }
    /// "320m" / "1.2km" 표기. 거리 정보가 없으면 nil.
    var distanceText: String? {
        guard let m = distanceMeters else { return nil }
        return m >= 1000 ? String(format: "%.1fkm", Double(m) / 1000) : "\(m)m"
    }
    /// 카드 배지용 — 핫플 / 숨은 명소 / 미라벨(nil).
    var tasteBadge: (text: String, symbol: String)? {
        switch label {
        case "hotplace": return ("인기 핫플", "flame.fill")
        case "secret":   return ("숨은 명소", "leaf.fill")
        default:         return nil
        }
    }
}

/// POST /tour/swipe 응답의 data — 갱신된 취향 스코어.
struct SwipeResult: Decodable {
    let tasteScore: Double          // 0(숨은 명소 선호) ~ 1(핫플 선호)
    let learned: Bool               // Refresh 는 false
    let spotLabel: String?
}

/// GET /tour/search 의 data ({ total, items })
struct TourSearchData: Decodable {
    let total: Int
    let items: [TourSpot]
}

/// GET /tour/regions 의 요소 (시/도 → 시/군/구)
struct RegionGroup: Decodable, Identifiable, Hashable {
    let province: String
    let cities: [String]
    var id: String { province }
}
