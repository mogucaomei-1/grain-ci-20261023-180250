import SwiftUI

// MARK: - 主容器视图 (相册目录与文件目录瞬切，无私密冗余，极速流畅)

public struct RootView: View {
    @StateObject private var playerViewModel = PlayerViewModel()
    @State private var selectedTab: Int = 0 // 0: 相册目录 (含已隐藏相册), 1: 文件目录
    @State private var playingVideo: VideoItem? = nil
    @State private var infoVideo: VideoItem? = nil
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        ZStack {
            GrainBackground()

            VStack(spacing: 0) {
                // 顶部品牌栏与设置入口
                topNavigationBar

                // 两大主目录分段切换条 (相册目录 / 文件目录)
                tabSegmentBar

                // 主内容区 (利用 ZStack 预热并瞬时切换，杜绝 TabView 销毁重建卡顿)
                ZStack {
                    PhotoLibraryView(
                        onSelectVideo: { video in startPlayback(video) },
                        onShowInfo: { video in infoVideo = video }
                    )
                    .opacity(selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 0)

                    FileDirectoryView(
                        onSelectVideo: { video in startPlayback(video) },
                        onShowInfo: { video in infoVideo = video }
                    )
                    .opacity(selectedTab == 1 ? 1 : 0)
                    .allowsHitTesting(selectedTab == 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 全屏播放器模态层
            if let video = playingVideo {
                fullscreenPlayerView(for: video)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        // 视频详细参数 Sheet
        .sheet(item: $infoVideo) { video in
            VideoInfoSheet(item: video, metadata: video.metadata)
        }
        // 设置面板 Sheet
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - 顶栏

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            // GRAIN PLAYER 品牌标识
            HStack(spacing: 6) {
                Text("GRAIN")
                    .font(.system(size: 19, weight: .black, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(GrainTheme.paper)

                Circle()
                    .fill(GrainTheme.accent)
                    .frame(width: 6, height: 6)

                Text("PLAYER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(GrainTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(GrainTheme.accent.opacity(0.15))
                    .cornerRadius(4)
            }

            Spacer()

            // 设置按钮
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(GrainTheme.paper)
                    .frame(width: 36, height: 36)
                    .background(GrainTheme.surface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - 两大主目录切换条

    private var tabSegmentBar: some View {
        HStack(spacing: 10) {
            segmentTabButton(title: "相册目录", icon: "photo.on.rectangle.angled", tag: 0)
            segmentTabButton(title: "文件目录", icon: "folder.fill", tag: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func segmentTabButton(title: String, icon: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button(action: {
            selectedTab = tag
            GrainHaptics.selection()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? GrainTheme.black : GrainTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(isSelected ? GrainTheme.accent : GrainTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.clear : GrainTheme.line, lineWidth: 1)
            )
        }
    }

    // MARK: - 全屏播放器层 (性能解耦)

    private func fullscreenPlayerView(for video: VideoItem) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CustomVideoPlayerView(
                player: playerViewModel.player,
                scaleMode: playerViewModel.scaleMode,
                pipDelegate: playerViewModel,
                onPiPReady: { pip in
                    playerViewModel.pipController = pip
                }
            )
            .ignoresSafeArea()

            PlayerOverlayView(
                viewModel: playerViewModel,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        playerViewModel.cleanup()
                        playingVideo = nil
                    }
                },
                onShowInfo: {
                    infoVideo = video
                }
            )
        }
        .statusBarHidden(!playerViewModel.showControls)
    }

    private func startPlayback(_ video: VideoItem) {
        playingVideo = video
        Task {
            await playerViewModel.loadVideo(item: video)
        }
    }
}
