import SwiftUI
import CoreLocation

@MainActor
final class SkyUploadViewModel: ObservableObject {
    enum Phase: Equatable { case idle, uploading, done(SkyVideo), failed(String) }
    @Published private(set) var phase: Phase = .idle

    private let api = StardustAPI.shared

    /// 업로드 흐름 밖에서 실패를 표시(예: 위치 권한 거부).
    func markFailed(_ message: String) { phase = .failed(message) }

    /// 새 촬영을 위해 상태 초기화.
    func reset() { phase = .idle }

    /// 사용자에게 아무것도 묻지 않는다: 영상 + 현재 좌표만 받으면 끝.
    func publish(videoFileURL: URL,
                 rawCoordinate: CLLocationCoordinate2D,
                 activeTripID: Int?) async {
        phase = .uploading

        do {
            let video = try await api.uploadSkyVideo(
                videoFileURL: videoFileURL,
                coordinate: (rawCoordinate.latitude, rawCoordinate.longitude),
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
