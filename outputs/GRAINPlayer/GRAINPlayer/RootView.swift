import SwiftUI

// MARK: - 主容器视图 (承载顶栏、三大目录分类与全屏播放器)

public struct RootView: View {
    @StateObject private var playerViewModel = PlayerViewModel()
    @State private var selectedTab: Int = 0 // 0: 相册, 1: 文件, 2: 私密
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

                // 三大主目录分段切换条
                tabSegmentBar

                // 主内容区
                TabView(selection: $selectedTab) {
                    PhotoLibraryView(
                        onSelectVideo: { video in startPlayback(video) },
                        onShowInfo: { video in infoVideo = video }
                    )
                    .tag(0)

                    FileDirectoryView(
                        onSelectVideo: { video in startPlayback(video) },
                        onShowInfo: { video in infoVideo = video }
                    )
                    .tag(1)

                    HiddenVaultView(
                        onSelectVideo: { video in startPlayback(video) },
                        onShowInfo: { video in infoVideo = video }
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
            // GRAIN 品牌标识
            HStack(spacing: 5) {
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
                    .padding(.horizontal, 5)
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
        .padding(.bottom, 8)
    }

    // MARK: - 三大目录切换条

    private var tabSegmentBar: some View {
        HStack(spacing: 8) {
            segmentTabButton(title: "相册目录", icon: "photo.on.rectangle.angled", tag: 0)
            segmentTabButton(title: "文件目录", icon: "folder.fill", tag: 1)
            segmentTabButton(title: "私密空间", icon: "lock.shield.fill", tag: 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func segmentTabButton(title: String, icon: String, tag: Int) -> some View {
        let isSelected = selectedTab == tag
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedTab = tag
            }
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

    // MARK: - 全屏播放器层

    private func fullscreenPlayerView(for video: VideoItem) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CustomVideoPlayerView(viewModel: playerViewModel)
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
