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
