import AVFoundation
import Combine

/// 하늘 영상 촬영용 캡처 세션 래퍼.
/// - 권한 요청 → 세션 구성(후면 카메라 + 마이크) → 짧은 클립 녹화 → 임시 .mov URL 반환.
/// - 시뮬레이터에는 카메라 하드웨어가 없으므로 `isAvailable == false` 로 떨어진다(앱은 크래시 없이 안내만).
@MainActor
final class CameraService: NSObject, ObservableObject {

    enum State: Equatable {
        case idle           // 준비 전
        case configuring    // 세션 구성 중
        case ready          // 미리보기 가능
        case recording      // 녹화 중
        case denied         // 권한 거부
        case unavailable    // 카메라 없음(시뮬레이터 등)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var recordedURL: URL?      // 녹화 완료 파일
    @Published private(set) var errorText: String?

    /// 최대 녹화 길이(초). 하늘은 짧게 — 서버 용량/심사 부담 최소화.
    let maxDuration: TimeInterval = 8

    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "app.stardust.camera.session")
    private var isConfigured = false

    // MARK: 권한 + 구성

    /// 화면 진입 시 호출. 권한을 확인하고 세션을 구성·시작한다.
    func prepare() {
        #if targetEnvironment(simulator)
        state = .unavailable
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            state = .configuring
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    granted ? self?.configureAndStart() : (self?.state = .denied)
                }
            }
        default:
            state = .denied
        }
        #endif
    }

    private func configureAndStart() {
        state = .configuring
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if self.isConfigured, !self.session.isRunning {
                self.session.startRunning()
            }
            Task { @MainActor in
                self.state = self.isConfigured ? .ready : .unavailable
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // 후면 카메라
        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let videoInput = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(videoInput)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoInput)

        // 마이크(선택 권한) — 거부돼 있어도 영상은 무음으로 진행
        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(movieOutput)
        session.commitConfiguration()
        isConfigured = true
    }

    // MARK: 녹화

    func startRecording() {
        guard state == .ready else { return }
        recordedURL = nil
        errorText = nil
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sky-\(UUID().uuidString).mov")
        movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 600)
        sessionQueue.async { [weak self] in
            self?.movieOutput.startRecording(to: url, recordingDelegate: self!)
        }
        state = .recording
    }

    func stopRecording() {
        guard state == .recording else { return }
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }

    /// 다시 찍기 — 이전 녹화 결과를 버리고 미리보기로 복귀.
    func reset() {
        if let url = recordedURL { try? FileManager.default.removeItem(at: url) }
        recordedURL = nil
        errorText = nil
        if state != .unavailable && state != .denied { state = .ready }
    }

    /// 화면 이탈 시 세션 정지(배터리/발열 절약).
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            // maxRecordedDuration 도달 시 error 가 채워지지만 파일은 유효하다.
            let reachedMax = (error as? NSError)?.code == AVError.maximumDurationReached.rawValue
            if let error, !reachedMax {
                self.errorText = "녹화에 실패했어요. 다시 시도해 주세요."
                self.state = .ready
                return
            }
            self.recordedURL = outputFileURL
            self.state = .ready
        }
    }
}
