import SwiftUI
import AVFoundation

/// 无控制栏的原生循环视频背景。播放器只负责画面，始终静音。
struct BackgroundVideoView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        context.coordinator.play(url: url, in: view)
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.play(url: url, in: view)
    }

    static func dismantleNSView(_ view: PlayerView, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }

    final class Coordinator {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        fileprivate var currentURL: URL?

        func play(url: URL, in view: PlayerView) {
            stop()
            let player = AVQueuePlayer()
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .none
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspectFill
            self.player = player
            currentURL = url
            player.play()
        }

        func stop() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
            currentURL = nil
        }
    }
}

final class PlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = playerLayer
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = playerLayer
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
