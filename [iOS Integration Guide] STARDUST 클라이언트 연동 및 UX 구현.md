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

> `MapPinPicker` 는 `MapReader { reader in Map { … }.onTapGesture { reader.convert(...) } }`
> (iOS 17) 또는 중앙 고정 핀 + 카메라 중심 좌표로 간단히 구현하면 된다.

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

### 4.2 별빛 Glow 아바타 뷰

```swift
struct StarGlowAvatar: View {
    let colorHex: String
    var size: CGFloat = 88
    @State private var pulse = false

    private var color: Color { Color(hex: colorHex) }

    var body: some View {
        ZStack {
            // 바깥쪽 부드러운 발광(숨쉬는 듯한 펄스)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .blur(radius: pulse ? 26 : 18)
                .opacity(pulse ? 0.85 : 0.55)
            // 본체
            Circle()
                .fill(color.gradient)
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                .shadow(color: color.opacity(0.8), radius: 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// 사용 예: 업로드 완료 직후 아바타가 새 하늘색으로 번진다
struct ProfileHeader: View {
    @StateObject private var profile = UserProfileStore.shared
    var body: some View {
        VStack(spacing: 8) {
            StarGlowAvatar(colorHex: profile.avatarColorHex)
            if let emotion = profile.latestEmotion {
                Text(emotion).font(.callout.weight(.medium))
                    .foregroundStyle(Color(hex: profile.avatarColorHex))
            }
        }
        .animation(.easeInOut, value: profile.avatarColorHex)
    }
}
```

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
struct AutoplayVideoCell: View {
    let video: SkyVideo
    @EnvironmentObject private var stage: FeedStageCoordinator
    @StateObject private var vm: VideoCellViewModel

    // 무대 중앙 ±활성 허용 범위(절반 높이). 이 안이면 활성 후보.
    private let activeBand: CGFloat = 0.5

    init(video: SkyVideo) {
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
struct TrendingFeedView: View {
    @StateObject private var stage = FeedStageCoordinator()
    @State private var videos: [SkyVideo] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(videos) { video in
                    AutoplayVideoCell(video: video)
                        .environmentObject(stage)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color.black.ignoresSafeArea())
        .task { await loadTrending() }
    }

    private func loadTrending() async {
        // GET /community/trending 호출 후 videos 에 매핑 (응답 구조는 SkyVideo 와 유사)
        // let env = try await StardustAPI.shared.fetchTrending()
        // videos = env.data.items
    }
}
```

> **메모리 안전 포인트**
> - `LazyVStack` + `onDisappear → teardown()` 으로 화면 밖 셀의 `AVPlayer` 를 확실히 해제.
> - 동시에 재생되는 플레이어는 **항상 1개**(무대 중앙)뿐 → CPU/디코더/네트워크 절약.
> - `AVQueuePlayer + AVPlayerLooper` 로 끊김 없는 반복, `isMuted = true` 로 setlog 무음 자동재생.
> - 오디오 세션이 필요하면 앱 시작 시 `AVAudioSession` 을 `.ambient` 로 설정해 배경음/벨소리를 방해하지 않게 한다.

---

## 6. 권장 앱 부트스트랩 순서

```swift
@main
struct StardustApp: App {
    @StateObject private var session = SessionStore()   // 토큰 보관(Keychain 권장)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    // 1) 저장된 토큰 주입 (없으면 로그인 플로우)
                    await StardustAPI.shared.setToken(session.accessToken)
                    // 2) 최초 1회 Safe Zone 온보딩
                    if !SafeZoneManager.shared.hasCompletedSetup {
                        session.showSafeZoneSetup = true
                    }
                }
        }
    }
}
```

### 체크리스트 (Info.plist 권한 문구)
- `NSCameraUsageDescription` — "하늘을 담기 위해 카메라를 사용해요."
- `NSMicrophoneUsageDescription` — (영상 촬영 시) "영상 촬영에 마이크가 필요해요."
- `NSLocationWhenInUseUsageDescription` — "당신이 머문 자리에 별을 띄우기 위해 위치를 사용해요."
- `NSPhotoLibraryUsageDescription` — (앨범 영상 선택 시) 필요.

> 🔐 보안: `access_token` 은 `UserDefaults` 가 아니라 **Keychain** 에 저장한다.
> `SUPABASE_SERVICE_ROLE_KEY` 같은 서버 전용 키는 **iOS 앱에 절대 포함하지 않는다.**
> 실시간 구독이 필요하면 Supabase **ANON KEY** 로만 채널(`room:<sky_video_id>`)을 subscribe 한다.

---

## 7. 요약 — 이 가이드가 지킨 '귀차니즘 제로' 원칙

| 유저가 안 하는 것 | 대신 일어나는 일 |
|---|---|
| 제목/감정/위치명 입력 | 서버가 좌표→명소 매핑 + K-Means 색/감정 자동 생성 |
| 색상 고르기 | 올려다본 하늘색이 아바타 별빛으로 자동 번짐 |
| 매번 위치 가리기 | 최초 1회 Safe Zone 지정 → 이후 200m 내 자동 난독화 |
| 재생 버튼 누르기 | 무대 중앙 셀이 자동 무음 재생, 벗어나면 자동 해제 |

**유저는 그저 하늘을 향해 셔터를 누른다. 나머지는 STARDUST 가 알아서 별로 만든다.** ✨
