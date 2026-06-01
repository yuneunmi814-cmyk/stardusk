import Foundation

actor StardustAPI {
    static let shared = StardustAPI(baseURL: AppConfig.apiBaseURL)

    private let baseURL: URL
    private let session: URLSession
    private var accessToken: String?      // 로그인 후 주입

    init(baseURL: URL) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120   // 영상 업로드 여유
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    func setToken(_ token: String?) { self.accessToken = token }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: 공통 실행기
    private func run<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        var req = request
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(for: req) }
        catch { throw StardustError.transport(error) }

        guard let http = resp as? HTTPURLResponse else { throw StardustError.decoding(URLError(.badServerResponse)) }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw StardustError.unauthorized }
            // 서버 에러 봉투 파싱
            if let body = try? Self.decoder.decode(APIErrorBody.self, from: data) {
                throw StardustError.server(code: body.detail.code,
                                           message: body.detail.message,
                                           http: http.statusCode)
            }
            throw StardustError.server(code: "HTTP_\(http.statusCode)",
                                       message: "요청에 실패했어요.", http: http.statusCode)
        }
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw StardustError.decoding(error) }
    }

    // MARK: 인증 — 소셜 토큰 → 내부 JWT
    struct AuthData: Decodable {
        let userId: String
        let nickname: String
        let accessToken: String
        let expiresIn: Int
    }

    func login(provider: String, identityToken: String, nickname: String?) async throws -> AuthData {
        var req = URLRequest(url: baseURL.appendingPathComponent("auth/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["provider": provider, "identity_token": identityToken]
        if let nickname { body["nickname"] = nickname }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let env = try await run(req, as: APIEnvelope<AuthData>.self)
        return env.data
    }

    // MARK: 트렌딩 피드 — 동접 + 강원 가중치 순
    func fetchTrending(limit: Int = 20, offset: Int = 0) async throws -> [TrendingItem] {
        var comp = URLComponents(
            url: baseURL.appendingPathComponent("community/trending"),
            resolvingAgainstBaseURL: false
        )!
        comp.queryItems = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        let env = try await run(req, as: APIEnvelope<TrendingPage>.self)
        return env.data.items
    }

    // MARK: UGC 모더레이션 — 신고 / 사용자 차단 (App Store Guideline 1.2)
    func reportVideo(skyVideoId: String, reason: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("community/report"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["sky_video_id": skyVideoId, "reason": reason])
        _ = try await run(req, as: SimpleOK.self)
    }

    func blockUser(userId: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("community/block"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["blocked_user_id": userId])
        _ = try await run(req, as: SimpleOK.self)
    }

    // MARK: 하이브리드 탐색 — 주변 명소 / 통합 검색 / 지역 목록
    func fetchNearbySpots(lat: Double, lng: Double,
                          radius: Int = 3000, limit: Int = 100) async throws -> [TourSpot] {
        var comp = URLComponents(
            url: baseURL.appendingPathComponent("tour/spots"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lng)),
            .init(name: "radius", value: String(radius)),
            .init(name: "limit", value: String(limit)),
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        return try await run(req, as: APIEnvelope<[TourSpot]>.self).data
    }

    // MARK: 개인화 큐레이션 — 취향 학습이 반영된 '내 주변 별 탐색' 덱
    func fetchDeck(lat: Double, lng: Double,
                   radius: Int = 5000, limit: Int = 20) async throws -> [TourSpot] {
        var comp = URLComponents(
            url: baseURL.appendingPathComponent("tour/deck"), resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lng)),
            .init(name: "radius", value: String(radius)),
            .init(name: "limit", value: String(limit)),
        ]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        return try await run(req, as: APIEnvelope<[TourSpot]>.self).data
    }

    /// 카드 스와이프(Like/Pass/Refresh)를 취향 학습에 반영. 갱신된 taste_score 반환.
    @discardableResult
    func postSwipe(tourId: String, action: String) async throws -> SwipeResult {
        var req = URLRequest(url: baseURL.appendingPathComponent("tour/swipe"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["tour_id": tourId, "action": action])
        return try await run(req, as: APIEnvelope<SwipeResult>.self).data
    }

    func searchSpots(keyword: String? = nil,
                     province: String? = nil, city: String? = nil,
                     lat: Double? = nil, lng: Double? = nil,
                     limit: Int = 30, offset: Int = 0) async throws -> TourSearchData {
        var comp = URLComponents(
            url: baseURL.appendingPathComponent("tour/search"), resolvingAgainstBaseURL: false)!
        var q: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
        ]
        if let keyword, !keyword.isEmpty { q.append(.init(name: "keyword", value: keyword)) }
        if let province { q.append(.init(name: "province", value: province)) }
        if let city { q.append(.init(name: "city", value: city)) }
        if let lat, let lng {
            q.append(.init(name: "latitude", value: String(lat)))
            q.append(.init(name: "longitude", value: String(lng)))
        }
        comp.queryItems = q
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        return try await run(req, as: APIEnvelope<TourSearchData>.self).data
    }

    func fetchRegions() async throws -> [RegionGroup] {
        var req = URLRequest(url: baseURL.appendingPathComponent("tour/regions"))
        req.httpMethod = "GET"
        return try await run(req, as: APIEnvelope<[RegionGroup]>.self).data
    }

    // MARK: 영상 업로드 — 영상 + 좌표만으로 '별'을 만든다. 텍스트 입력 0.
    func uploadSkyVideo(
        videoFileURL: URL,
        coordinate: (lat: Double, lng: Double),
        tripID: Int? = nil          // 진행 중 여정이 있으면 자동 첨부, 없으면 nil
    ) async throws -> SkyVideo {

        let videoData = try Data(contentsOf: videoFileURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        // tour_id 는 보내지 않는다 — 서버가 좌표로 명소를 매핑한다.
        var fields: [String: String] = [
            "latitude":  String(coordinate.lat),
            "longitude": String(coordinate.lng),
        ]
        if let tripID { fields["trip_id"] = String(tripID) }

        let mime = videoFileURL.pathExtension.lowercased() == "mov"
            ? "video/quicktime" : "video/mp4"

        var req = URLRequest(url: baseURL.appendingPathComponent("community/videos"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = multipartBody(
            boundary: boundary,
            fileField: "video",
            fileName: videoFileURL.lastPathComponent,
            mimeType: mime,
            fileData: videoData,
            fields: fields
        )

        let env = try await run(req, as: APIEnvelope<SkyVideo>.self)
        return env.data
    }

    // MARK: 멀티파트 바디 빌더
    private func multipartBody(
        boundary: String,
        fileField: String, fileName: String, mimeType: String, fileData: Data,
        fields: [String: String]
    ) -> Data {
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        for (key, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
