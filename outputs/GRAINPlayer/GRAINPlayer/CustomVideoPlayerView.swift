import AVFoundation
import AVKit
import SwiftUI
import UIKit

// MARK: - 原生 AVPlayerLayer 渲染视图 (支持自适应缩放与画中画)

public struct CustomVideoPlayerView: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerViewModel

    public init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    public func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.viewModel = viewModel
        view.configure(player: viewModel.player, scaleMode: viewModel.scaleMode)
        return view
    }

    public func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.configure(player: viewModel.player, scaleMode: viewModel.scaleMode)
    }
}

public final class PlayerUIView: UIView {
    public weak var viewModel: PlayerViewModel?

    public override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    private var pipController: AVPictureInPictureController?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(player: AVPlayer?, scaleMode: VideoScaleMode) {
        if playerLayer.player !== player {
            playerLayer.player = player
            setupPiPIfNeeded()
        }

        switch scaleMode {
        case .aspectFit:
            playerLayer.videoGravity = .resizeAspect
        case .aspectFill:
            playerLayer.videoGravity = .resizeAspectFill
        case .ratio16x9, .ratio4x3:
            playerLayer.videoGravity = .resize
        }
    }

    private func setupPiPIfNeeded() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if pipController == nil {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.delegate = viewModel
            viewModel?.pipController = pipController
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
