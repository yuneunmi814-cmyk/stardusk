# [iOS Integration Guide] STARDUST 클라이언트 연동 및 UX 구현

> **철학: "유저는 했던 입력을 또 요구받으면 앱을 지운다."**
> STARDUST iOS 앱의 모든 흐름은 **'귀차니즘 제로(Zero-Friction)'** 를 향한다.
> 제목·감정·위치명 같은 텍스트 입력은 **절대 요구하지 않는다.** 유저는 그저 하늘을 찍고,
> 나머지(명소 매핑·감정 색상·라벨)는 **백엔드가 알아서** 채워서 돌려준다.

대상 독자: iOS 개발 팀원 · 복사 → 붙여넣기 즉시 동작을 목표로 한 보일러플레이트.
최소 타깃: **iOS 16.0+** (SwiftUI / async-await / AVKit).

---

## 0. 백엔드 계약 요약 (이 문서가 가정하는 서버 스펙)

| 항목 | 값 |
|---|---|
| Base URL | `https://<your-api-host>/api/v1` |
| 인증 | `Authorization: Bearer <access_token>` (모든 보호 라우트) |
| 토큰 발급 | `POST /auth/login` → `data.access_token`, `data.expires_in` |
| 영상 업로드 | `POST /community/videos` (multipart/form-data) |
| 트렌딩 피드 | `GET /community/trending?limit=&offset=` |
| 실시간 방 | `POST /community/rooms/{id}/join · heartbeat · leave` |
| **성공 응답** | `{ "status": "success", "message": "...", "data": { ... } }` |
| **에러 응답** | `{ "detail": { "status": "error", "code": "...", "message": "..." } }` |

> ⚠️ **에러는 `detail` 로 한 번 감싸여 온다.** (`INVALID_LOCATION`, `OUT_OF_SERVICE_AREA`,
> `UNSUPPORTED_VIDEO_FORMAT`, `VIDEO_TOO_LARGE`, `INTERNAL_ERROR` 등) 디코딩 시 이 구조를 그대로 받는다.

### `POST /community/videos` 멀티파트 필드

| 필드 | 타입 | 필수 | 비고 |
|---|---|---|---|
| `video` | file | ✅ | MP4/MOV — 서버가 매직 넘버로 진위 검증 |
| `latitude` | float (form) | ✅ | 기기 GPS (대한민국 영토 범위만 허용) |
| `longitude` | float (form) | ✅ | 〃 |
| `trip_id` | int (form) | ❌ | 진행 중 여정이 있으면 자동 첨부 |
| `tour_id` | string (form) | ❌ | **보내지 않는다** — 서버가 좌표로 명소 매핑 |

### 업로드 성공 응답 `data` (snake_case)

```jsonc
{
  "sky_video_id": "e2fcc71a-…",
  "trip_id": null,
  "tour_id": null,
  "latitude": 37.7725,
  "longitude": 128.9478,
  "video_url": "https://…/videos/2026/05/star_….mp4",
  "thumbnail_url": "https://…/video_thumb/2026/05/star_….jpg",
  "sky_color_hex": "#5794E4",      // ← 아바타 별빛(Glow) 색
  "emotion_label": "맑은 오후",      // ← 자동 생성된 감정 라벨
  "palette": [ { "hex": "#5794E4", "ratio": 0.958 }, … ],
  "brightness": 0.605,
  "sky_score": 1.0,
  "created_at": "2026-05-31T17:04:53Z"
}
```

---

## 1. 네트워킹 코어 (의존성 0, URLSession 기반)

> Alamofire 없이 `URLSession` 만으로 충분하다. 멀티파트도 직접 만든다(아래 §1.3).
> 외부 라이브러리 의존을 줄여 심사/리뷰 환경에서 빌드 리스크를 없앤다.

### 1.1 응답/에러 모델

```swift
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
```

### 1.2 도메인 모델

```swift
struct PaletteColor: Decodable, Hashable {
    let hex: String
    let ratio: Double
}

/// POST /community/videos 응답의 data
struct SkyVideo: Decodable, Identifiable {
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
```

> `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` 를 쓰면 `sky_video_id → skyVideoId`,
> `sky_color_hex → skyColorHex` 로 자동 매핑된다. URL 키만 `videoUrl/thumbnailUrl` 로 들어오므로
> CodingKeys 에서 보정한다.

### 1.3 멀티파트 빌더 + API 클라이언트

```swift
import Foundation

actor StardustAPI {
    static let shared = StardustAPI(baseURL: URL(string: "https://<your-api-host>/api/v1")!)

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
```

---

## 2. 텍스트 입력 ZERO 업로드 파이프라인 (`POST /community/videos`)

핵심 흐름:

```
[촬영된 영상 URL]  +  [기기 GPS 좌표]
        │
        ▼ (Safe Zone 자동 난독화 — §3)
[멀티파트 전송]  ──►  서버가 명소 매핑 + K-Means 색/감정 추출
        │
        ▼
[응답 sky_color_hex / emotion_label]  ──►  내 아바타 별빛(Glow) 자동 갱신 (§4)
```

### 2.1 업로드 API (제목·감정·위치명 입력 없음)

```swift
extension StardustAPI {
    /// 영상 + 좌표만으로 '별'을 만든다. 텍스트 입력 0.
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
}
```

### 2.2 ViewModel — 촬영 직후 한 번에 처리

```swift
import SwiftUI
import CoreLocation

@MainActor
final class SkyUploadViewModel: ObservableObject {
    enum Phase: Equatable { case idle, uploading, done(SkyVideo), failed(String) }
    @Published private(set) var phase: Phase = .idle

    private let api = StardustAPI.shared
    private let safeZone = SafeZoneManager.shared   // §3

    /// 사용자에게 아무것도 묻지 않는다: 영상 + 현재 좌표만 받으면 끝.
    func publish(videoFileURL: URL,
                 rawCoordinate: CLLocationCoordinate2D,
                 activeTripID: Int?) async {
        phase = .uploading

        // ① Safe Zone 자동 난독화 (유저는 신경 쓸 필요 없음)
        let safe = safeZone.obfuscateIfNeeded(rawCoordinate)

        do {
            let video = try await api.uploadSkyVideo(
                videoFileURL: videoFileURL,
                coordinate: (safe.latitude, safe.longitude),
                tripID: activeTripID
            )
            // ② 내 아바타 별빛 즉시 갱신 (§4)
            UserProfileStore.shared.applyLatestStar(
                colorHex: video.skyColorHex, emotion: video.emotionLabel
            )
            phase = .done(video)
        } catch let e as StardustError {
            // 서버 코드별 친절 메시지
            let msg: String
            switch e.code {
            case "OUT_OF_SERVICE_AREA": msg = "국내(강원) 여행 중에만 별을 남길 수 있어요."
            case "UNSUPPORTED_VIDEO_FORMAT": msg = "표준 동영상(MP4/MOV)만 올릴 수 있어요."
            case "VIDEO_TOO_LARGE": msg = "영상이 너무 길어요. 짧게 잘라볼까요?"
            default: msg = e.errorDescription ?? "잠시 후 다시 시도해 주세요."
            }
            phase = .failed(msg)
        } catch {
            phase = .failed("잠시 후 다시 시도해 주세요.")
        }
    }
}
```

---

## 3. 최초 1회 설정으로 평생 편한 'Safe Zone' (클라이언트 자동 난독화)

> 유저는 **앱 최초 구동 시 집/회사 좌표를 한 번만** 지정한다. 이후 그 반경 200m 안에서
> 별을 남기면, **서버로 쏘기 전에 클라이언트가 알아서** 좌표를 흐리게(grid-snap) 만든다.
> 매번 "위치를 가릴까요?" 같은 보안 체크를 띄우지 않는다.

> 🔒 서버(`app/services/obfuscate.py`)와 **동일한 알고리즘**을 미러링한다:
> **반경 200m / 격자 80m 스냅.** 클라이언트가 먼저 가리고, 서버는 2차 방어선으로 동작한다.

### 3.1 SafeZoneManager

```swift
import CoreLocation

final class SafeZoneManager {
    static let shared = SafeZoneManager()

    // 서버와 동일 상수
    private let safeRadiusM = 200.0
    private let gridM = 80.0
    private let metersPerDegLat = 111_320.0

    private let store = UserDefaults.standard
    private let key = "stardust.safezones.v1"

    struct Zone: Codable { let name: String; let lat: Double; let lng: Double }

    // MARK: 최초 1회 저장 (집/회사)
    func saveZones(_ zones: [Zone]) {
        if let data = try? JSONEncoder().encode(zones) { store.set(data, forKey: key) }
    }
    var zones: [Zone] {
        guard let data = store.data(forKey: key),
              let z = try? JSONDecoder().decode([Zone].self, from: data) else { return [] }
        return z
    }
    var hasCompletedSetup: Bool { store.bool(forKey: "stardust.safezone.setupDone") }
    func markSetupComplete() { store.set(true, forKey: "stardust.safezone.setupDone") }

    // MARK: 현재 좌표가 어떤 Safe Zone 200m 이내인지
    private func nearestZone(to c: CLLocationCoordinate2D) -> Zone? {
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return zones.first { z in
            here.distance(from: CLLocation(latitude: z.lat, longitude: z.lng)) <= safeRadiusM
        }
    }

    /// Safe Zone 안이면 격자 스냅으로 흐리게, 아니면 원본 그대로.
    func obfuscateIfNeeded(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard nearestZone(to: c) != nil else { return c }   // 밖이면 그대로
        let gridLat = gridM / metersPerDegLat
        let gridLng = gridM / (metersPerDegLat * max(cos(c.latitude * .pi / 180), 1e-6))
        return CLLocationCoordinate2D(
            latitude:  (c.latitude  / gridLat).rounded() * gridLat,
            longitude: (c.longitude / gridLng).rounded() * gridLng
        )
    }
}
```

### 3.2 최초 구동 온보딩 (한 번만 묻기)

```swift
import SwiftUI
import MapKit

struct SafeZoneSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var homeCoord: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 20) {
            Text("머무는 곳을 한 번만 알려주세요")
                .font(.title2.bold())
            Text("집·회사 근처에서 남긴 별은 자동으로 위치를 흐리게 가려드려요.\n다신 묻지 않을게요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // (지도에서 한 지점 선택 → homeCoord 에 바인딩하는 MapReader 등으로 구현)
            MapPinPicker(coordinate: $homeCoord)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Button("이 위치를 내 안전지대로 저장") {
                guard let c = homeCoord else { return }
                SafeZoneManager.shared.saveZones([.init(name: "집", lat: c.latitude, lng: c.longitude)])
                SafeZoneManager.shared.markSetupComplete()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(homeCoord == nil)

            Button("나중에 할게요") { SafeZoneManager.shared.markSetupComplete(); dismiss() }
                .font(.footnote)
        }
        .padding()
    }
}
```

### 3.3 MapPinPicker (iOS 17 `MapReader` 기반, 완성 코드)

탭한 지점이든 지도 중심이든 한 번에 안전지대 좌표를 잡을 수 있게 만든 픽커.

```swift
import SwiftUI
import MapKit
import CoreLocation

@available(iOS 17.0, *)
struct MapPinPicker: View {
    @Binding var coordinate: CLLocationCoordinate2D?

    // 기본 카메라: 강원 강릉(서비스 주무대) 근방
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7519, longitude: 128.8761),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    )
    @State private var centerCoordinate = CLLocationCoordinate2D(latitude: 37.7519, longitude: 128.8761)

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $camera) {
                    if let coordinate {
                        Annotation("내 안전지대", coordinate: coordinate) {
                            Image(systemName: "house.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white, Color(hex: "#7FA8E0"))
                                .shadow(radius: 4)
                        }
                    }
                    UserAnnotation()   // 현재 위치 점
                }
                .mapControls { MapUserLocationButton(); MapCompass() }
                // ① 지도를 탭하면 그 지점을 좌표로 변환해 선택
                .onTapGesture { screenPoint in
                    if let c = proxy.convert(screenPoint, from: .local) {
                        withAnimation(.spring) { coordinate = c }
                    }
                }
                // ② 카메라가 멈출 때마다 중심 좌표를 기억(중앙 핀 방식 지원)
                .onMapCameraChange(frequency: .onEnd) { ctx in
                    centerCoordinate = ctx.region.center
                }
            }

            // 중앙 고정 조준 핀: 탭하지 않아도 '지도 중심'을 지정할 수 있게 한다.
            if coordinate == nil {
                Image(systemName: "scope")
                    .font(.title)
                    .foregroundStyle(Color(hex: "#7FA8E0"))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            Button {
                withAnimation(.spring) { coordinate = centerCoordinate }
            } label: {
                Label("이 지도 중심으로 지정", systemImage: "mappin.and.ellipse")
                    .font(.caption.bold())
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 12)
        }
    }
}
```

> 지도에서 현재 위치 점(`UserAnnotation`)을 쓰려면 `CLLocationManager` 권한
> (`NSLocationWhenInUseUsageDescription`)이 이미 허용돼 있어야 한다(§6 체크리스트).

---

## 4. 응답 색상 → 아바타 별빛(Glow) 자동 매핑

서버가 돌려준 `sky_color_hex` 를 **유저 프로필 아바타의 발광색**으로 그대로 쓴다.
유저는 색을 고르지 않는다 — 자신이 올려다본 하늘이 곧 자기 색이 된다.

### 4.1 Hex → Color + 프로필 스토어

```swift
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
}

@MainActor
final class UserProfileStore: ObservableObject {
    static let shared = UserProfileStore()
    @Published var avatarColorHex: String = "#5794E4"
    @Published var latestEmotion: String? = nil

    func applyLatestStar(colorHex: String, emotion: String?) {
        withAnimation(.easeInOut(duration: 0.8)) {   // 색이 부드럽게 번지듯 전환
            avatarColorHex = colorHex
            latestEmotion = emotion
        }
        UserDefaults.standard.set(colorHex, forKey: "stardust.avatarColor")
    }
}
```

### 4.2 프로필 헤더 (업로드 직후 별빛이 새 하늘색으로 번진다)

```swift
// 아바타 본체(StarGlowAvatar)와 하늘빛 팔레트(SkyMood)는 §4.3~4.4 에서 정의한다.
struct ProfileHeader: View {
    @StateObject private var profile = UserProfileStore.shared

    var body: some View {
        VStack(spacing: 10) {
            StarGlowAvatar(colorHex: profile.avatarColorHex,
                           emotion: profile.latestEmotion)
            if let emotion = profile.latestEmotion {
                Text(emotion)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SkyMood.resolve(emotion: emotion,
                                                      hex: profile.avatarColorHex).accent)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.8), value: profile.avatarColorHex)
    }
}
```

---

### 4.3 하루의 하늘빛 그러데이션 시스템 (`SkyMood`)

> 앱 아이콘(파스텔 새벽·노을 오브)의 결을 그대로 코드로 옮긴 팔레트.
> 서버가 준 **감정 라벨**을 1순위로, 없으면 **대표색 Hue** 로 추정해 그러데이션을 만든다.
> `color_extract.py` 의 11개 감정 라벨과 1:1로 대응한다.

```swift
import SwiftUI

// MARK: - 색 보정 헬퍼 (대표색에서 위·아래 톤을 만들어 자연스러운 하늘 결 생성)
extension Color {
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
```

---

### 4.4 살아있는 하늘 배경 + 별빛 펄스 아바타

#### (a) `SkyGradientBackground` — 숨 쉬듯 일렁이는 하늘 + 반짝이는 별

```swift
import SwiftUI

/// 그러데이션 위로 빛무리가 천천히 흐르고, 별이 깜빡이는 '살아있는' 하늘 배경.
struct SkyGradientBackground: View {
    let mood: SkyMood

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                mood.gradient.ignoresSafeArea()

                // 천천히 떠다니는 빛무리(하늘이 숨 쉬는 느낌)
                RadialGradient(
                    colors: [mood.stops.first!.opacity(0.0),
                             mood.accent.opacity(0.30)],
                    center: UnitPoint(x: 0.5 + 0.22 * sin(t * 0.12),
                                      y: 0.34 + 0.14 * cos(t * 0.09)),
                    startRadius: 8, endRadius: 460
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

/// Canvas 로 그린 가벼운 별 입자(60개) — 각자 다른 위상으로 반짝인다.
struct StarfieldOverlay: View {
    let date: Date
    var bright: Bool = true

    private struct Star { let x, y, r: CGFloat; let phase: Double }
    private let stars: [Star] = (0..<60).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...1),
             r: .random(in: 0.6...1.9), phase: .random(in: 0...(2 * .pi)))
    }

    var body: some View {
        Canvas { ctx, size in
            let t = date.timeIntervalSinceReferenceDate
            let baseAlpha = bright ? 0.9 : 0.35
            for s in stars {
                let twinkle = 0.25 + 0.75 * (0.5 + 0.5 * sin(t * 1.5 + s.phase))
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
```

#### (b) `StarGlowAvatar` — 회전 오로라 링 + 숨쉬는 펄스 (최종 버전)

```swift
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
```

> **무드 ↔ 화면 연동 팁**
> - 프로필/상세 화면 배경에 `SkyGradientBackground(mood: SkyMood.resolve(emotion:hex:))` 를 깔면
>   업로드 결과의 감정이 화면 전체 분위기로 확장된다.
> - 업로드 완료 시 `UserProfileStore.applyLatestStar(...)` 가 `avatarColorHex` 를 바꾸고,
>   `StarGlowAvatar`/`SkyGradientBackground` 가 SwiftUI `animation` 으로 부드럽게 크로스페이드된다.
> - 밤/노을 무드는 `prefersBrightStars == true` 라 별이 더 또렷하게 반짝인다.

---

## 5. setlog 스타일 뷰포트 자동재생 비디오 셀 (메모리 안전)

요구사항:
- 화면 **중앙(무대)** 에 안착한 셀의 `AVPlayer` 가 **자동 무음 재생**
- 화면을 **완전히 벗어나면 즉시 인스턴스 해제** → 메모리 누수 방지
- 재생 버튼 탭 불필요 (스크롤만으로 동작)

### 5.1 효율적 표시 레이어 (`AVPlayerLayer` 래핑)

```swift
import AVFoundation
import SwiftUI

/// AVPlayerLayer 를 직접 쓰는 가벼운 표시 뷰. (SwiftUI VideoPlayer 보다 제어/성능 우수)
final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspectFill }
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView(); v.player = player; return v
    }
    func updateUIView(_ v: PlayerContainerView, context: Context) { v.player = player }
}
```

### 5.2 셀 ViewModel — 지연 생성 / 즉시 해제 / 무한 루프

```swift
import AVFoundation

@MainActor
final class VideoCellViewModel: ObservableObject {
    private let url: URL
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?      // 끊김 없는 무한 반복
    @Published private(set) var activePlayer: AVPlayer?

    init(url: URL) { self.url = url }

    /// 무대 진입 → 플레이어를 '이때' 만든다(메모리 절약).
    func activate() {
        guard player == nil else { player?.play(); return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true                 // setlog: 항상 무음 자동재생
        queue.automaticallyWaitsToMinimizeStalling = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        activePlayer = queue
        queue.play()
    }

    /// 무대 이탈(부분) → 일시정지(아직 화면엔 보일 수 있음).
    func pause() { player?.pause() }

    /// 화면 완전 이탈 → 인스턴스 해제 (누수 차단의 핵심).
    func teardown() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        activePlayer = nil
    }

    deinit { looper?.disableLooping() }
}
```

### 5.3 '무대 중앙' 판정 코디네이터

```swift
import SwiftUI

/// 피드 전체에서 '지금 무대 중앙에 가장 가까운 셀'의 id 하나만 활성으로 둔다.
@MainActor
final class FeedStageCoordinator: ObservableObject {
    @Published var activeID: String?

    private var candidates: [String: CGFloat] = [:]   // id → 화면중앙과의 거리
    private var pending = false

    func report(id: String, distanceToCenter: CGFloat?) {
        if let d = distanceToCenter { candidates[id] = d } else { candidates[id] = nil; candidates.removeValue(forKey: id) }
        scheduleResolve()
    }

    private func scheduleResolve() {
        guard !pending else { return }
        pending = true
        // 스크롤 중 과도한 갱신 방지(다음 런루프에 1회만 계산)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending = false
            let best = self.candidates.min { $0.value < $1.value }?.key
            if best != self.activeID { self.activeID = best }
        }
    }
}
```

### 5.4 자동재생 셀 (GeometryReader 가시성 감지)

```swift
struct AutoplayVideoCell<Item: PlayableSky>: View where Item.ID == String {
    let video: Item
    @EnvironmentObject private var stage: FeedStageCoordinator
    @StateObject private var vm: VideoCellViewModel

    init(video: Item) {
        self.video = video
        _vm = StateObject(wrappedValue: VideoCellViewModel(url: video.videoURL))
    }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let screenMidY = UIScreen.main.bounds.midY
            let distance = abs(frame.midY - screenMidY)
            let isOnScreen = frame.maxY > 0 && frame.minY < UIScreen.main.bounds.height

            ZStack {
                // 썸네일을 먼저 깔아 두면 로딩 중에도 색감이 유지된다(스켈레톤 대체)
                AsyncImage(url: video.thumbnailURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color(hex: video.skyColorHex).opacity(0.4)
                }

                if let player = vm.activePlayer {
                    PlayerLayerView(player: player)
                        .transition(.opacity)
                }

                // 감정 라벨 오버레이 (서버 자동 생성값)
                VStack { Spacer()
                    HStack {
                        if let emotion = video.emotionLabel {
                            Text(emotion)
                                .font(.caption.bold())
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Spacer()
                    }.padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            // 가시성/거리 보고 → 코디네이터가 무대 중앙 셀 선정
            .onChange(of: frame.midY) { _ in
                stage.report(id: video.id, distanceToCenter: isOnScreen ? distance : nil)
            }
            .onAppear {
                stage.report(id: video.id, distanceToCenter: isOnScreen ? distance : nil)
            }
            // 화면 완전 이탈 → 즉시 해제(누수 차단)
            .onDisappear {
                stage.report(id: video.id, distanceToCenter: nil)
                vm.teardown()
            }
            // 내가 '무대 주인공'이 되면 재생, 아니면 일시정지
            .onChange(of: stage.activeID) { active in
                if active == video.id { vm.activate() } else { vm.pause() }
            }
        }
        .aspectRatio(9/16, contentMode: .fit)   // 세로 하늘 영상 기준
    }
}
```

### 5.5 피드 화면 조립

```swift
import SwiftUI

@MainActor
final class TrendingFeedViewModel: ObservableObject {
    @Published private(set) var items: [TrendingItem] = []
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private let api = StardustAPI.shared
    private let pageSize = 20
    private var canLoadMore = true

    /// 첫 진입/당겨서 새로고침.
    func refresh() async {
        canLoadMore = true
        await load(reset: true)
    }

    /// 마지막 셀이 보이면 다음 페이지.
    func loadMoreIfNeeded(current item: TrendingItem) async {
        guard let last = items.last, last.id == item.id, canLoadMore, !isLoading else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let offset = reset ? 0 : items.count
            let page = try await api.fetchTrending(limit: pageSize, offset: offset)
            if reset { items = page } else { items.append(contentsOf: page) }
            if page.count < pageSize { canLoadMore = false }
            errorText = nil
        } catch let e as StardustError {
            errorText = e.errorDescription
        } catch {
            errorText = "피드를 불러오지 못했어요."
        }
    }
}

struct TrendingFeedView: View {
    @StateObject private var stage = FeedStageCoordinator()
    @StateObject private var vm = TrendingFeedViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(vm.items) { item in
                    AutoplayVideoCell(video: item)
                        .environmentObject(stage)
                        .overlay(alignment: .topLeading) { metaBadge(item) }
                        .padding(.horizontal, 16)
                        .task { await vm.loadMoreIfNeeded(current: item) }
                }
                if vm.isLoading {
                    ProgressView().tint(.white).padding(.vertical, 24)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .refreshable { await vm.refresh() }     // 당겨서 새로고침
        .overlay { if let err = vm.errorText, vm.items.isEmpty { errorState(err) } }
        .task { if vm.items.isEmpty { await vm.refresh() } }
    }

    // 명소명/지역 + 동시 접속자 배지 (서버가 좌표로 매핑해 준 값)
    @ViewBuilder
    private func metaBadge(_ item: TrendingItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let spot = item.spotName ?? item.region {
                Label(spot, systemImage: item.isGangwon ? "mountain.2.fill" : "mappin")
                    .font(.caption2.bold())
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            if item.liveUsersCount > 0 {
                Label("\(item.liveUsersCount)명이 같은 하늘 아래", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(26)
    }

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.rain").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
            Text(message).foregroundStyle(.white.opacity(0.8))
            Button("다시 시도") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
```

> **메모리 안전 포인트**
> - `LazyVStack` + `onDisappear → teardown()` 으로 화면 밖 셀의 `AVPlayer` 를 확실히 해제.
> - 동시에 재생되는 플레이어는 **항상 1개**(무대 중앙)뿐 → CPU/디코더/네트워크 절약.
> - `AVQueuePlayer + AVPlayerLooper` 로 끊김 없는 반복, `isMuted = true` 로 setlog 무음 자동재생.
> - 오디오 세션이 필요하면 앱 시작 시 `AVAudioSession` 을 `.ambient` 로 설정해 배경음/벨소리를 방해하지 않게 한다.

---

## 6. 세션/토큰 보관 + 앱 부트스트랩

`access_token` 은 탈취 위험이 큰 `UserDefaults` 가 아니라 **Keychain** 에 저장한다.
아래는 그대로 복사해 쓸 수 있는 ① Keychain 래퍼, ② 세션 상태 머신, ③ 앱 진입점 3종 세트다.

### 6.1 KeychainStore — Security 프레임워크 얇은 래퍼

```swift
import Foundation
import Security

/// 토큰 같은 민감 문자열을 Keychain(kSecClassGenericPassword)에 저장/조회/삭제한다.
/// - UserDefaults 와 달리 기기 잠금/탈옥 보호를 받고, 앱 삭제 시까지 안전하게 남는다.
/// - 접근성: `.afterFirstUnlock` → 부팅 후 한 번 잠금 해제하면 백그라운드에서도 읽힘
///   (백그라운드 업로드/리프레시에 필요). iCloud 동기화는 막아 기기 로컬에만 둔다.
enum KeychainStore {
    /// 같은 앱/디바이스 내 키 충돌 방지용 서비스 네임스페이스
    private static let service = "app.stardust.session"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // upsert: 기존 항목을 지우고 새로 넣어 중복(errSecDuplicateItem)을 피한다.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)

        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    static func remove(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

### 6.2 SessionStore — 로그인/로그아웃 상태 머신

```swift
import Foundation

/// 앱 전역 인증 상태. View 는 이걸 @EnvironmentObject 로 구독한다.
/// 토큰은 Keychain 에만 저장하고, 메모리 캐시는 휘발성으로만 들고 있는다.
@MainActor
final class SessionStore: ObservableObject {

    // Keychain 키 (account)
    private enum K {
        static let token = "access_token"
        static let userId = "user_id"
        static let nickname = "nickname"
    }

    @Published private(set) var accessToken: String?
    @Published private(set) var userId: String?
    @Published private(set) var nickname: String?

    /// 최초 1회 Safe Zone 온보딩 시트 트리거 (부트스트랩에서 set)
    @Published var showSafeZoneSetup = false

    var isAuthenticated: Bool { accessToken?.isEmpty == false }

    private let api = StardustAPI.shared

    init() {
        // 앱 재실행 시 Keychain 에서 토큰 복원 (자동 로그인)
        self.accessToken = KeychainStore.get(K.token)
        self.userId = KeychainStore.get(K.userId)
        self.nickname = KeychainStore.get(K.nickname)
    }

    /// 부팅 시 1회: 저장된 토큰을 API 액터에 주입한다.
    func bootstrap() async {
        await api.setToken(accessToken)
    }

    /// Sign in with Apple 등으로 얻은 identityToken 으로 서버 로그인 → 토큰 영구 보관.
    func login(provider: String, identityToken: String, nickname: String? = nil) async throws {
        let auth = try await api.login(provider: provider,
                                       identityToken: identityToken,
                                       nickname: nickname)
        persist(token: auth.accessToken, userId: auth.userId, nickname: auth.nickname)
        await api.setToken(auth.accessToken)
    }

    /// 로그아웃: 메모리 + Keychain + API 토큰 모두 비운다.
    func logout() {
        KeychainStore.remove(K.token)
        KeychainStore.remove(K.userId)
        KeychainStore.remove(K.nickname)
        accessToken = nil
        userId = nil
        nickname = nil
        Task { await api.setToken(nil) }
    }

    private func persist(token: String, userId: String, nickname: String) {
        KeychainStore.set(token, for: K.token)
        KeychainStore.set(userId, for: K.userId)
        KeychainStore.set(nickname, for: K.nickname)
        self.accessToken = token
        self.userId = userId
        self.nickname = nickname
    }
}
```

### 6.3 앱 진입점 — 토큰 주입 → Safe Zone 온보딩 순서

```swift
@main
struct StardustApp: App {
    @StateObject private var session = SessionStore()   // 토큰은 Keychain 에 보관

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    // 1) Keychain 에 저장돼 있던 토큰을 API 액터에 주입(자동 로그인)
                    await session.bootstrap()
                    // 2) 최초 1회 Safe Zone 온보딩
                    if session.isAuthenticated, !SafeZoneManager.shared.hasCompletedSetup {
                        session.showSafeZoneSetup = true
                    }
                }
                .sheet(isPresented: $session.showSafeZoneSetup) {
                    SafeZoneSetupView()      // §3.2 — 완료 시 hasCompletedSetup = true
                }
        }
    }
}

/// 인증 상태에 따라 로그인/메인을 가르는 루트.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        if session.isAuthenticated {
            TrendingFeedView()           // §5.5 무대(피드)
        } else {
            LoginView()                  // Sign in with Apple → session.login(...)
        }
    }
}
```

### 체크리스트 (Info.plist 권한 문구 + 필수/선택)
- **(필수)** `NSLocationWhenInUseUsageDescription` — "당신이 머문 자리에 별을 띄우기 위해 위치를 사용해요."
- **(필수, 도착 자동 알림용)** `NSLocationAlwaysAndWhenInUseUsageDescription` — "목적지에 도착하면 알려드리기 위해 위치를 사용해요." (백그라운드 지오펜스 → §7.2)
- **(필수)** `NSCameraUsageDescription` — "하늘을 담기 위해 카메라를 사용해요."
- **(선택)** `NSMicrophoneUsageDescription` — "그날의 하늘과 현장음까지 생생하게 담기 위해 마이크를 사용해요."
- **(선택, 갤러리 자동 저장 토글 ON 시)** `NSPhotoLibraryAddUsageDescription` — "담은 하늘을 사진 보관함에도 저장하기 위해 사용해요."
- **(선택)** 알림 — Info.plist 키 없음. 런타임 `UNUserNotificationCenter.requestAuthorization` 으로 요청(도착 알림용).
- 🚫 **광고 추적(ATT) 미사용** — `NSUserTrackingUsageDescription` 키를 두지 않는다(추적하지 않음).

> 📸 **시작 스냅은 iOS '사진' 앱에 자동 저장되지 않는다.** 앱이 기본 카메라가 아니라 커스텀 `AVCaptureSession` 으로 촬영하므로, 캡처 결과는 앱 내부에만 들어온다.
> 갤러리 자동 저장을 원하는 사용자만 **설정의 '내 사진 보관함에도 저장' 토글**을 켜고, 그때만 `PHPhotoLibrary` 로 저장한다(매번 묻지 않아 3단 스와이프 루프가 끊기지 않는다).

> 🔐 보안: `access_token` 은 `UserDefaults` 가 아니라 **Keychain** 에 저장한다.
> `SUPABASE_SERVICE_ROLE_KEY` 같은 서버 전용 키는 **iOS 앱에 절대 포함하지 않는다.**
> 실시간 구독이 필요하면 Supabase **ANON KEY** 로만 채널(`room:<sky_video_id>`)을 subscribe 한다.

---

## 7. 산책 안내(가벼운 길찾기) + 외부 지도 핸드오프

> 목적지는 차로 가는 관광지가 아니라 **걸어서 3~5분, 100~300m 거리의 하늘 좋은 지점**이다.
> 그래서 거창한 턴바이턴 내비를 흉내 내지 않는다. **앱은 "감각적 최소 산책 안내"만** 하고,
> 정밀 길찾기는 사용자가 신뢰하는 **국산 지도 앱(네이버지도·카카오맵·티맵)으로 한 번 탭에 위임**한다.
> (MapKit `MKRoute.steps` 로 구간 안내문은 실제로 제공되므로, 앱 내 최소 안내도 충분히 가능하다.)

### 7.1 도보 경로 + 다음 한 구간 안내 (`MKDirections`, walking)

```swift
import MapKit

@MainActor
final class WalkRouteVM: ObservableObject {
    @Published var route: MKRoute?
    @Published var headlineStep: String = ""      // "북동쪽으로 230m 직진 후 우회전"
    @Published var remainingText: String = ""     // "243m · 도보 3분"

    func computeWalk(from: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) async {
        let req = MKDirections.Request()
        req.source      = MKMapItem(placemark: .init(coordinate: from))
        req.destination = MKMapItem(placemark: .init(coordinate: dest))
        req.transportType = .walking                // ← 도보 모드
        req.requestsAlternateRoutes = false
        do {
            let resp = try await MKDirections(request: req).calculate()
            guard let r = resp.routes.first else { return }
            self.route = r
            // 거리/시간 요약
            let m = Int(r.distance.rounded())
            let min = max(1, Int((r.expectedTravelTime / 60).rounded()))
            self.remainingText = (m >= 1000 ? String(format: "%.1fkm", Double(m)/1000) : "\(m)m") + " · 도보 \(min)분"
            // 다음 의미 있는 한 구간만 노출(첫 step 은 종종 빈 안내라 건너뜀)
            self.headlineStep = r.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "목적지 방향으로 이동하세요"
        } catch {
            self.headlineStep = ""    // 실패해도 앱은 거리/방향만으로 안내 가능 → 외부 맵 버튼이 안전망
        }
    }
}
```

지도에는 `route.polyline` 을 그대로 그린다(SwiftUI `Map { MapPolyline(route.polyline) }` 또는 `MKMapView.addOverlay`). 화면은 **상단 목적지·남은거리 + 다음 한 구간 + 작은 지도**면 충분하다.

### 7.2 GPS 자동 도착 감지 + 알림 공해 제어 (`CLCircularRegion` 지오펜스)

사용자가 "다 왔나?"를 확인할 필요가 없도록, 반경 30~50m 진입을 감지해 **도착 시트를 자동 표출**한다(여기서 §2의 위치 Always + 알림 권한이 쓰인다). 핵심은 **피로감 제어**다 — 도착 팝업은 딱 3개의 버튼만 두고, 사용자가 "오늘은 그만"이라고 하면 **자정까지 침묵**한다.

**도착 팝업 = 단 3개 버튼**

| 버튼 | 동작 |
|---|---|
| `[촬영하기]` | 하늘 카메라 즉시 구동 → 별자리 수집 |
| `[닫기]` | 이번 알림만 닫음(다음 목적지에서는 다시 뜸) |
| `[오늘 하루 그만보기]` | 디바이스에 자정까지 mute 플래그 저장 → **오늘은 도착 팝업을 강제 호출하지 않고 백그라운드 동선만 조용히 기록** |

```swift
import CoreLocation
import UserNotifications

/// '오늘 하루 그만보기' — 자정까지 도착 팝업을 침묵시키는 디바이스 로컬 플래그.
enum ArrivalMute {
    private static let key = "arrival_mute_until"
    /// 오늘 자정(다음 날 00:00)까지 mute.
    static func muteForToday() {
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        UserDefaults.standard.set(midnight, forKey: key)
    }
    static var isMuted: Bool {
        guard let until = UserDefaults.standard.object(forKey: key) as? Date else { return false }
        return Date() < until   // 자정 지나면 자동 해제
    }
}

final class ArrivalGeofence: NSObject, CLLocationManagerDelegate {
    private let lm = CLLocationManager()

    func arm(at dest: CLLocationCoordinate2D, id: String) {
        lm.delegate = self
        lm.allowsBackgroundLocationUpdates = true     // 백그라운드 도착 감지
        let region = CLCircularRegion(center: dest, radius: 40, identifier: id)
        region.notifyOnEntry = true; region.notifyOnExit = false
        lm.startMonitoring(for: region)
    }

    func locationManager(_ m: CLLocationManager, didEnterRegion r: CLRegion) {
        m.stopMonitoring(for: r)                      // 1회성
        // mute 중이면 팝업/알림 없이 동선만 조용히 기록(알림 공해 원천 차단).
        guard !ArrivalMute.isMuted else { return }
        let c = UNMutableNotificationContent()
        c.title = "✨ 도착했어요"; c.body = "이 자리의 하늘을 담아보세요"; c.sound = .default
        c.categoryIdentifier = "ARRIVAL"              // 촬영/닫기/오늘 그만보기 액션 부착
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: r.identifier, content: c, trigger: nil))
    }
}
```

> 포그라운드에서는 동일 3버튼을 `confirmationDialog`로 띄우고, `[오늘 하루 그만보기]` → `ArrivalMute.muteForToday()`.
> 백그라운드는 `UNNotificationCategory(identifier: "ARRIVAL", actions:[촬영/닫기/오늘 그만보기])`로 같은 선택지를 잠금화면에 노출한다.

### 7.3 외부 지도 앱으로 한 번 탭 핸드오프 (도보 모드 딥링크)

길이 헷갈리는 사용자는 늘 쓰던 앱으로 즉시 넘긴다. 설치 안 된 앱 버튼은 숨기고(`canOpenURL`), 폴백으로 Apple 지도(`MKMapItem.openInMaps`, 도보 모드)를 둔다.

```swift
import UIKit
import MapKit

enum ExternalMap {
    /// 도보 길안내를 외부 앱으로 위임. dest=목적지 좌표, name=표시명.
    static func openWalking(to dest: CLLocationCoordinate2D, name: String) -> [(label: String, action: () -> Void)] {
        let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var out: [(String, () -> Void)] = []

        // 네이버지도: 도보 경로
        if let u = URL(string: "nmap://route/walk?dlat=\(dest.latitude)&dlng=\(dest.longitude)&dname=\(enc)&appname=com.stardust.app"),
           UIApplication.shared.canOpenURL(u) {
            out.append(("네이버지도", { UIApplication.shared.open(u) }))
        }
        // 카카오맵: 도보 경로(FOOT)
        if let u = URL(string: "kakaomap://route?ep=\(dest.latitude),\(dest.longitude)&by=FOOT"),
           UIApplication.shared.canOpenURL(u) {
            out.append(("카카오맵", { UIApplication.shared.open(u) }))
        }
        // 티맵: 목적지 안내
        if let u = URL(string: "tmap://route?goalname=\(enc)&goalx=\(dest.longitude)&goaly=\(dest.latitude)"),
           UIApplication.shared.canOpenURL(u) {
            out.append(("티맵", { UIApplication.shared.open(u) }))
        }
        // 폴백: 애플 지도(항상 가능)
        out.append(("지도", {
            let item = MKMapItem(placemark: .init(coordinate: dest))
            item.name = name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        }))
        return out
    }
}
```

> ⚠️ 네이버/카카오/티맵 커스텀 스킴(`nmap`, `kakaomap`, `tmap`)을 `canOpenURL` 로 조회하려면
> **Info.plist `LSApplicationQueriesSchemes`** 에 해당 스킴을 등록해야 한다.

**설계 요약**: 앱 = 가벼운 산책 안내 + GPS 자동 도착 감지. 그 이상 정밀 길찾기는 사용자가 신뢰하는 국산 지도 앱에 위임 → "어설프게 흉내 내다 지는" 대신 **잘하는 건 우리가, 길찾기는 익숙한 앱이**.

### 7.4 명소 카드 `[자세히 보기 🎧]` — 오디오 도슨트 바텀시트

장소 카드 하단의 `[자세히 보기 🎧]`를 누르면, 빽빽한 텍스트 뷰 대신 **하단 시트(Bottom Sheet)로 오디오 가이드 플레이어**가 떠오른다. 한국관광공사 OpenAPI의 상세 설명(`overview`)과 멀티미디어 가이드(상세 이미지·오디오) 데이터를 받아, 사용자가 **폰을 보지 않고 이어폰으로 명소의 유래를 도슨트처럼 들으며 걷게** 한다. 걷는 힐링을 끊지 않는 '듣는 안내'다.

```swift
// 카드 하단 링크
Button { showDocent = true } label: {
    Label("자세히 보기", systemImage: "headphones").font(.callout.weight(.semibold))
}
.sheet(isPresented: $showDocent) {
    DocentSheet(spot: spot)
        .presentationDetents([.height(220), .medium])   // 살짝 떠서 산책 흐름 유지
        .presentationDragIndicator(.visible)
}
```

```swift
/// 오디오 도슨트 — overview 텍스트를 AVSpeechSynthesizer로 낭독(멀티미디어 가이드 있으면 AVPlayer 재생).
@MainActor final class DocentPlayer: ObservableObject {
    @Published var isPlaying = false
    private let tts = AVSpeechSynthesizer()

    func play(text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = 0.46
        try? AVAudioSession.sharedInstance().setCategory(.playback)  // 백그라운드/이어폰 재생
        tts.speak(u); isPlaying = true
    }
    func stop() { tts.stopSpeaking(at: .immediate); isPlaying = false }
}
```

> 데이터 소스: `GET /tour/spots`·`/tour/search` 응답의 명소 메타데이터 + (확장) OpenAPI `detailCommon`(overview)·`detailInfo`(상세 안내). 오디오 파일이 없으면 `overview` 텍스트를 온디바이스 TTS(`AVSpeechSynthesizer`)로 낭독해 **추가 비용 없이** 도슨트 경험을 제공한다.

---

## 8. 요약 — 이 가이드가 지킨 '귀차니즘 제로' 원칙

| 유저가 안 하는 것 | 대신 일어나는 일 |
|---|---|
| 제목/감정/위치명 입력 | 서버가 좌표→명소 매핑 + K-Means 색/감정 자동 생성 |
| 색상 고르기 | 올려다본 하늘색이 아바타 별빛으로 자동 번짐 |
| 도착 알림 피로 | `[오늘 하루 그만보기]` 한 번 → 자정까지 침묵, 동선만 조용히 기록 |
| 상세정보 읽기 | `[자세히 보기 🎧]` → 오디오 도슨트가 걸으며 들려줌 |
| 재생 버튼 누르기 | 무대 중앙 셀이 자동 무음 재생, 벗어나면 자동 해제 |

**유저는 그저 하늘을 향해 셔터를 누른다. 나머지는 STARDUST 가 알아서 별로 만든다.** ✨
