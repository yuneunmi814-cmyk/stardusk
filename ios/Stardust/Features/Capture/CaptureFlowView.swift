import SwiftUI
import AVFoundation
import CoreLocation

/// 입력 Zero 3단 루프: ① 촬영 → ② 미리보기 → ③ 올리기(별이 떴어요).
/// 텍스트/제목/감정 입력 없음. 영상 + 자동 좌표만으로 '별'이 만들어진다.
struct CaptureFlowView: View {
    @StateObject private var camera = CameraService()
    @StateObject private var upload = SkyUploadViewModel()
    @StateObject private var location = LocationProvider()

    private enum Step { case capture, preview, result }
    @State private var step: Step = .capture
    @State private var blockingError: String?

    var body: some View {
        ZStack {
            switch step {
            case .capture:
                SkyCaptureView(camera: camera)
                    .onChange(of: camera.recordedURL) { _, url in
                        if url != nil { step = .preview }
                    }
            case .preview:
                previewScreen
            case .result:
                resultScreen
            }
        }
        .task { location.requestWhenInUse() }
    }

    // MARK: ② 미리보기

    @ViewBuilder
    private var previewScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = camera.recordedURL {
                LocalLoopPlayerView(url: url).ignoresSafeArea()
            }
            VStack {
                Text("이 하늘, 마음에 드세요?")
                    .font(.headline).foregroundStyle(.white).shadow(radius: 6)
                    .padding(.top, 24)
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        camera.reset(); step = .capture
                    } label: {
                        Label("다시 찍기", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(.white.opacity(0.16), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Button {
                        step = .result
                        Task { await publish() }
                    } label: {
                        Label("이 하늘 올리기", systemImage: "sparkles")
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 20).padding(.bottom, 36)
            }
        }
    }

    // MARK: ③ 결과

    @ViewBuilder
    private var resultScreen: some View {
        ZStack {
            SkyGradientBackground(mood: resultMood).ignoresSafeArea()
            VStack(spacing: 20) {
                switch upload.phase {
                case .uploading, .idle:
                    ProgressView().tint(.white).scaleEffect(1.3)
                    Text("이 장소의 하늘을 담는 중…")
                        .font(.callout).foregroundStyle(.white.opacity(0.9))

                case .done(let video):
                    StarGlowAvatar(colorHex: video.skyColorHex, emotion: video.emotionLabel, size: 110)
                    Text("별이 떴어요 ✨").font(.title2.bold()).foregroundStyle(.white)
                    if let emotion = video.emotionLabel {
                        Text(emotion).font(.headline).foregroundStyle(.white.opacity(0.9))
                    }
                    Text("색·감정은 자동으로 태깅됐어요")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    Button("또 담기") { restart() }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        .padding(.top, 8)

                case .failed(let msg):
                    Image(systemName: "cloud.rain")
                        .font(.largeTitle).foregroundStyle(.white.opacity(0.8))
                    Text(blockingError ?? msg)
                        .font(.callout).foregroundStyle(.white)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    HStack {
                        Button("다시 시도") { step = .preview }
                            .buttonStyle(.bordered).tint(.white)
                        Button("새로 찍기") { restart() }
                            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    }
                }
            }
        }
    }

    private var resultMood: SkyMood {
        if case .done(let v) = upload.phase {
            return SkyMood.resolve(emotion: v.emotionLabel, hex: v.skyColorHex)
        }
        return .night
    }

    // MARK: 동작

    private func publish() async {
        guard let url = camera.recordedURL else { return }
        do {
            let coord = try await location.currentCoordinate()
            await upload.publish(videoFileURL: url,
                                 rawCoordinate: coord,
                                 activeTripID: nil)
        } catch LocationProvider.LocationError.denied {
            blockingError = "위치 권한이 필요해요. 설정에서 위치 접근을 허용해 주세요."
            upload.markFailed("위치 권한이 필요해요.")
        } catch {
            blockingError = "현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
            upload.markFailed("현재 위치를 확인하지 못했어요.")
        }
    }

    private func restart() {
        blockingError = nil
        camera.reset()
        upload.reset()
        step = .capture
    }
}

/// 로컬 파일을 끊김 없이 반복 재생하는 미리보기(무음).
private struct LocalLoopPlayerView: View {
    let url: URL
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        PlayerLayerView(player: player)
            .onAppear {
                let item = AVPlayerItem(url: url)
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: item)
                player = queue
                queue.play()
            }
            .onDisappear {
                player?.pause()
                looper?.disableLooping()
                player = nil
                looper = nil
            }
    }
}
