import SwiftUI

// MARK: - 私密空间与相册隐藏相册视频浏览视图 (含 Face ID / Touch ID 生物识别加密保护)

public struct HiddenVaultView: View {
    @ObservedObject var biometricService = BiometricLockService.shared
    @ObservedObject var photoService = PhotoLibraryService.shared
    @ObservedObject var fileService = FileManagerService.shared

    public var onSelectVideo: (VideoItem) -> Void
    public var onShowInfo: (VideoItem) -> Void

    @State private var selectedTab: Int = 0 // 0: 相册隐藏视频, 1: 文件私密保险箱
    @State private var showDocumentPicker = false

    public init(onSelectVideo: @escaping (VideoItem) -> Void, onShowInfo: @escaping (VideoItem) -> Void) {
        self.onSelectVideo = onSelectVideo
        self.onShowInfo = onShowInfo
    }

    public var body: some View {
        ZStack {
            if !biometricService.isUnlocked && biometricService.isBiometricRequired {
                // 生物识别解锁锁定页面
                lockedPromptView
            } else {
                // 已解锁的私密内容
                unlockedContentView
            }
        }
        .task {
            if biometricService.isUnlocked || !biometricService.isBiometricRequired {
                await photoService.loadHiddenAlbumVideos()
                await fileService.reloadAll()
            }
        }
    }

    // MARK: - 锁定状态展示页

    private var lockedPromptView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(GrainTheme.accent.opacity(0.12))
                    .frame(width: 110, height: 110)

                Image(systemName: biometricService.biometricIcon)
                    .font(.system(size: 50))
                    .foregroundColor(GrainTheme.accent)
            }

            VStack(spacing: 8) {
                Text("私密空间已锁定")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(GrainTheme.paper)

                Text("相册「已隐藏」视频与本地私密保险箱已受加密保护，请验证身份以继续访问。")
                    .font(.system(size: 14))
                    .foregroundColor(GrainTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if let error = biometricService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(GrainTheme.danger)
                    .padding(.horizontal, 32)
            }

            Button(action: {
                Task {
                    let success = await biometricService.unlock()
                    if success {
                        await photoService.loadHiddenAlbumVideos()
                        await fileService.reloadAll()
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: biometricService.biometricIcon)
                    Text("使用 \(biometricService.biometricName) 解锁")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(GrainTheme.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(GrainTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 48)
            }

            Spacer()
        }
    }

    // MARK: - 已解锁内容视图

    private var unlockedContentView: some View {
        VStack(spacing: 0) {
            // 顶部锁与切换工具条
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(GrainTheme.accent)
                    Text("私密空间")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(GrainTheme.paper)
                }

                Spacer()

                // 立即重新上锁
                Button(action: {
                    biometricService.lock()
                    GrainHaptics.medium()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("立即上锁")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GrainTheme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(GrainTheme.danger.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // 分段选择器：相册已隐藏 / 文件保险箱
            Picker("私密分类", selection: $selectedTab) {
                Text("相册隐藏视频 (\(photoService.hiddenAlbumVideos.count))").tag(0)
                Text("文件私密保险箱 (\(fileService.vaultVideos.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // 内容列表
            ScrollView {
                VStack(spacing: 16) {
                    if selectedTab == 0 {
                        hiddenAlbumSection
                    } else {
                        vaultFilesSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .refreshable {
                if selectedTab == 0 {
                    await photoService.loadHiddenAlbumVideos()
                } else {
                    await fileService.reloadAll()
                }
            }
        }
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    for url in urls {
                        try? await fileService.importExternalFile(from: url, moveToVault: true)
                    }
                }
            }
        }
    }

    // MARK: - 相册隐藏相册视频列表

    private var hiddenAlbumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("系统相册 · 已隐藏相册")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(GrainTheme.paper)
                    Text("直接读取并播放相册隐藏目录下的所有视频，无需恢复隐藏状态。")
                        .font(.system(size: 11))
                        .foregroundColor(GrainTheme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            if photoService.hiddenAlbumVideos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 42))
                        .foregroundColor(GrainTheme.muted.opacity(0.4))
                    Text("相册中没有隐藏视频")
                        .font(.system(size: 14))
                        .foregroundColor(GrainTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(photoService.hiddenAlbumVideos) { video in
                        PhotoVideoCard(
                            video: video,
                            onTap: { onSelectVideo(video) },
                            onInfo: { onShowInfo(video) },
                            onDelete: {
                                Task {
                                    try? await photoService.deleteVideo(item: video)
                                    await photoService.loadHiddenAlbumVideos()
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 本地私密保险箱文件列表

    private var vaultFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本地私密保险箱")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(GrainTheme.paper)
                    Text("独立存储在 App 加密沙盒目录下，不出现在常规文件与相册中。")
                        .font(.system(size: 11))
                        .foregroundColor(GrainTheme.muted)
                }
                Spacer()

                Button(action: { showDocumentPicker = true }) {
                    Label("导入到保险箱", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GrainTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(GrainTheme.surface)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 4)

            if fileService.vaultVideos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 42))
                        .foregroundColor(GrainTheme.muted.opacity(0.4))
                    Text("保险箱内暂无视频")
                        .font(.system(size: 14))
                        .foregroundColor(GrainTheme.muted)
                    Text("点上方「导入到保险箱」或在常规文件列表中长按视频选择「移入私密保险箱」")
                        .font(.system(size: 12))
                        .foregroundColor(GrainTheme.muted.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            } else {
                ForEach(fileService.vaultVideos) { video in
                    FileVideoRow(
                        video: video,
                        onTap: { onSelectVideo(video) },
                        onInfo: { onShowInfo(video) },
                        onRename: {
                            // 保险箱内重命名
                        },
                        onMove: {},
                        onMoveToVault: {},
                        onDelete: {
                            Task {
                                try? await fileService.deleteVideo(item: video)
                            }
                        }
                    )
                    .contextMenu {
                        Button(action: { onSelectVideo(video) }) { Label("立即播放", systemImage: "play.fill") }
                        Button(action: { onShowInfo(video) }) { Label("详细参数", systemImage: "info.circle") }
                        Button(action: {
                            Task {
                                try? await fileService.moveOutOfVault(item: video)
                            }
                        }) {
                            Label("移出到常规文件目录", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        }
                        Button(role: .destructive, action: {
                            Task { try? await fileService.deleteVideo(item: video) }
                        }) {
                            Label("彻底删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}
