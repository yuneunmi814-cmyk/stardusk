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

// MARK: - 도메인 모델
struct PaletteColor: Decodable, Hashable {
    let hex: String
    let ratio: Double
}

/// POST /community/videos 응답의 data
struct SkyVideo: Decodable, Identifiable, Equatable {
    let skyVideoId: String
    let tripId: Int?
    let tourId: String?
    let latitude: Double
    let longitude: Double
    let videoURL: URL
    let thumbnailURL: URL?
    let skyColorHex: String          // "#5794E4"
    let emotionLabel: String?        // "맑은 오후"
    let palette: [PaletteColor]
    let brightness: Double?
    let skyScore: Double?
    let createdAt: Date

    var id: String { skyVideoId }

    enum CodingKeys: String, CodingKey {
        case skyVideoId, tripId, tourId, latitude, longitude
        case videoURL = "videoUrl"
        case thumbnailURL = "thumbnailUrl"
        case skyColorHex, emotionLabel, palette, brightness, skyScore, createdAt
    }
}

/// 자동재생 피드 셀이 요구하는 최소 정보(업로드 결과·트렌딩 아이템이 공유).
protocol PlayableSky: Identifiable {
    var id: String { get }
    var videoURL: URL { get }
    var thumbnailURL: URL? { get }
    var skyColorHex: String { get }
    var emotionLabel: String? { get }
}

extension SkyVideo: PlayableSky {}

/// GET /community/trending 의 items 요소
struct TrendingItem: Decodable, PlayableSky {
    let skyVideoId: String
    let userId: String
    let tourId: String?
    let region: String?       // 서버가 좌표로 매핑한 지역명
    let spotName: String?     // 명소명
    let videoURL: URL
    let thumbnailURL: URL?
    let skyColorHex: String
    let emotionLabel: String?
    let latitude: Double
    let longitude: Double
    let liveUsersCount: Int    // 실시간 동시 접속자 수
    let isGangwon: Bool        // 강원도 가중치 대상 여부
    let createdAt: Date

    var id: String { skyVideoId }

    enum CodingKeys: String, CodingKey {
        case skyVideoId, userId, tourId, region, spotName
        case videoURL = "videoUrl"
        case thumbnailURL = "thumbnailUrl"
        case skyColorHex, emotionLabel, latitude, longitude, liveUsersCount, isGangwon, createdAt
    }
}

/// 트렌딩 응답의 data ({ total, items })
struct TrendingPage: Decodable {
    let total: Int
    let items: [TrendingItem]
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
        return URL(string: s)
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
