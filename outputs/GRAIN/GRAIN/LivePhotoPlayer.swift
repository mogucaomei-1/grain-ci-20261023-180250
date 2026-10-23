import Photos
import PhotosUI
import SwiftUI

/// 实况照片播放器：编辑页点开后可全屏播放拍摄瞬间的动态与声音
struct LivePhotoViewer: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss
    @State private var livePhoto: PHLivePhoto?
    @State private var isLoading = true
    @State private var playbackToken = 0
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let livePhoto {
                LivePhotoContainer(livePhoto: livePhoto, playbackToken: playbackToken)
                    .ignoresSafeArea()
            } else if isLoading {
                VStack(spacing: 10) {
                    ProgressView().tint(GrainTheme.paper)
                    Text("正在载入实况照片")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "livephoto.slash")
                        .font(.system(size: 26, weight: .light))
                    Text(errorMessage ?? "这张照片没有可播放的实况内容")
                        .font(.system(size: 10.5, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(GrainTheme.paper)
                .padding(.horizontal, 36)
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GrainTheme.paper)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if livePhoto != nil {
                    Button {
                        playbackToken += 1
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("重播实况")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(GrainTheme.black)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(GrainTheme.paper, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard asset.mediaSubtypes.contains(.photoLive) else {
            isLoading = false
            errorMessage = "这张照片不是实况照片"
            return
        }

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let loaded: PHLivePhoto? = await withCheckedContinuation { continuation in
            let guardBox = ResumeGuard()
            _ = PHImageManager.default().requestLivePhoto(
                for: asset,
                targetSize: CGSize(width: 2000, height: 2000),
                contentMode: .aspectFit,
                options: options
            ) { photo, _ in
                guard guardBox.consume() else { return }
                continuation.resume(returning: photo)
            }
        }

        if let loaded {
            livePhoto = loaded
        } else {
            errorMessage = "无法读取这段实况内容，可能只在 iCloud 中"
        }
        isLoading = false
    }
}

/// PHLivePhoto 的回调可能多次触发，保证 continuation 只恢复一次
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if finished { return false }
        finished = true
        return true
    }
}

private struct LivePhotoContainer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let playbackToken: Int

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.livePhoto = livePhoto
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        if uiView.livePhoto !== livePhoto {
            uiView.livePhoto = livePhoto
        }
        guard context.coordinator.lastToken != playbackToken else { return }
        context.coordinator.lastToken = playbackToken
        let view = uiView
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            view.startPlayback(with: .full)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastToken = -1
    }
}
