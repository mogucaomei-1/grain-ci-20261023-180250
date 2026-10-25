import AVFoundation
import AVKit
import SwiftUI
import UIKit

// MARK: - 原生 AVPlayerLayer 渲染视图 (极度轻量与高帧率，彻底消除卡顿)

public struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    let scaleMode: VideoScaleMode
    weak var pipDelegate: AVPictureInPictureControllerDelegate?
    var onPiPReady: ((AVPictureInPictureController) -> Void)?

    public init(
        player: AVPlayer?,
        scaleMode: VideoScaleMode,
        pipDelegate: AVPictureInPictureControllerDelegate? = nil,
        onPiPReady: ((AVPictureInPictureController) -> Void)? = nil
    ) {
        self.player = player
        self.scaleMode = scaleMode
        self.pipDelegate = pipDelegate
        self.onPiPReady = onPiPReady
    }

    public func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.configure(player: player, scaleMode: scaleMode, pipDelegate: pipDelegate, onPiPReady: onPiPReady)
        return view
    }

    public func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.configure(player: player, scaleMode: scaleMode, pipDelegate: pipDelegate, onPiPReady: onPiPReady)
    }
}

public final class PlayerUIView: UIView {
    public override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    private var pipController: AVPictureInPictureController?
    private var readyObservation: NSKeyValueObservation?
    private weak var currentPipDelegate: AVPictureInPictureControllerDelegate?
    private var currentOnPiPReady: ((AVPictureInPictureController) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        setupReadyObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        readyObservation?.invalidate()
    }

    private func setupReadyObserver() {
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                self.ensurePictureInPictureController()
            }
        }
    }

    public func configure(
        player: AVPlayer?,
        scaleMode: VideoScaleMode,
        pipDelegate: AVPictureInPictureControllerDelegate?,
        onPiPReady: ((AVPictureInPictureController) -> Void)?
    ) {
        self.currentPipDelegate = pipDelegate
        self.currentOnPiPReady = onPiPReady

        if playerLayer.player !== player {
            playerLayer.player = player
            pipController = nil
            ensurePictureInPictureController()
        }

        let targetGravity: AVLayerVideoGravity
        switch scaleMode {
        case .aspectFit:
            targetGravity = .resizeAspect
        case .aspectFill:
            targetGravity = .resizeAspectFill
        case .ratio16x9, .ratio4x3:
            targetGravity = .resize
        }

        if playerLayer.videoGravity != targetGravity {
            playerLayer.videoGravity = targetGravity
        }
    }

    private func ensurePictureInPictureController() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard playerLayer.player != nil else { return }

        if pipController == nil {
            if let pip = AVPictureInPictureController(playerLayer: playerLayer) {
                pip.delegate = currentPipDelegate
                if #available(iOS 14.2, *) {
                    pip.canStartPictureInPictureAutomaticallyFromInline = true
                }
                self.pipController = pip
                currentOnPiPReady?(pip)
            }
        } else if let pip = pipController {
            if #available(iOS 14.2, *) {
                pip.canStartPictureInPictureAutomaticallyFromInline = true
            }
            currentOnPiPReady?(pip)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
