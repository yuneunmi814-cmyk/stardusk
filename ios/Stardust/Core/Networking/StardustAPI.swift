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

    /// 회원 탈퇴 — 서버에서 계정·데이터를 파기한다.
    func deleteAccount() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("auth/me"))
        req.httpMethod = "DELETE"
        _ = try await run(req, as: SimpleOK.self)
    }

    /// 게스트(비로그인) 둘러보기 — 서버에서 익명 토큰을 받는다.
    func guestLogin() async throws -> AuthData {
        var req = URLRequest(url: baseURL.appendingPathComponent("auth/guest"))
        req.httpMethod = "POST"
        let env = try await run(req, as: APIEnvelope<AuthData>.self)
        return env.data
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

    /// 저장(라이크)한 명소 목록.
    func fetchSavedSpots() async throws -> [TourSpot] {
        var req = URLRequest(url: baseURL.appendingPathComponent("tour/saved"))
        req.httpMethod = "GET"
        return try await run(req, as: APIEnvelope<[TourSpot]>.self).data
    }

    /// 저장 해제 → 갱신된 저장 목록 반환.
    @discardableResult
    func unsaveSpot(tourId: String) async throws -> [TourSpot] {
        var req = URLRequest(url: baseURL.appendingPathComponent("tour/saved/\(tourId)"))
        req.httpMethod = "DELETE"
        return try await run(req, as: APIEnvelope<[TourSpot]>.self).data
    }

    /// 도슨트(설명 듣기) — 명소 상세설명(overview)을 가져온다.
    func fetchSpotDetail(tourId: String) async throws -> SpotDetail {
        var req = URLRequest(url: baseURL.appendingPathComponent("tour/\(tourId)/detail"))
        req.httpMethod = "GET"
        return try await run(req, as: APIEnvelope<SpotDetail>.self).data
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

}
