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
