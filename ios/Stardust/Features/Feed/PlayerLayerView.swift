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
