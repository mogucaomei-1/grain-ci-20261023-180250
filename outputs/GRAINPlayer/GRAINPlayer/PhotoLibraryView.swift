import Photos
import SwiftUI

// MARK: - 相册目录视频浏览视图 (含已隐藏相册、长按多选、无畸变缩略图)

public struct PhotoLibraryView: View {
    @ObservedObject var libraryService = PhotoLibraryService.shared
    public var onSelectVideo: (VideoItem) -> Void
    public var onShowInfo: (VideoItem) -> Void

    @State private var sortOption: SortOption = .dateDesc
    @State private var isMultiSelecting = false
    @State private var selectedIdentifiers = Set<String>()
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareURLs: [URL] = []

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init(onSelectVideo: @escaping (VideoItem) -> Void, onShowInfo: @escaping (VideoItem) -> Void) {
        self.onSelectVideo = onSelectVideo
        self.onShowInfo = onShowInfo
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 权限未授权引导
            if libraryService.authorizationStatus != .authorized && libraryService.authorizationStatus != .limited {
                permissionPromptView
            } else {
                // 相册横滑分类选择栏 (包含已隐藏相册)
                albumCategoryBar

                // 视频网格与内容
                ScrollView {
                    VStack(spacing: 14) {
                        // 筛选与多选模式操作条
                        filterAndActionBar

                        if currentAssetsList.isEmpty {
                            emptyStateView
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(currentAssetsList, id: \.localIdentifier) { asset in
                                    let isSelected = selectedIdentifiers.contains(asset.localIdentifier)
                                    PhotoVideoCard(
                                        asset: asset,
                                        isMultiSelecting: isMultiSelecting,
                                        isSelected: isSelected,
                                        onTap: {
                                            if isMultiSelecting {
                                                toggleSelection(for: asset.localIdentifier)
                                            } else {
                                                let item = libraryService.makeVideoItem(
                                                    from: asset,
                                                    isHidden: libraryService.selectedAlbumId == "smart_album_hidden"
                                                )
                                                onSelectVideo(item)
                                            }
                                        },
                                        onLongPress: {
                                            if !isMultiSelecting {
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                                    isMultiSelecting = true
                                                    selectedIdentifiers.insert(asset.localIdentifier)
                                                }
                                                GrainHaptics.medium()
                                            }
                                        },
                                        onInfo: {
                                            let item = libraryService.makeVideoItem(from: asset)
                                            onShowInfo(item)
                                        },
                                        onDelete: {
                                            Task {
                                                try? await libraryService.deleteAsset(asset)
                                                await libraryService.reloadAlbumsAndVideos()
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, isMultiSelecting ? 90 : 30)
                        }
                    }
                    .padding(.top, 8)
                }
                .refreshable {
                    await libraryService.reloadAlbumsAndVideos()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isMultiSelecting {
                multiSelectBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            if libraryService.authorizationStatus == .authorized || libraryService.authorizationStatus == .limited {
                if libraryService.currentAssets.isEmpty {
                    await libraryService.reloadAlbumsAndVideos()
                }
            }
        }
        .confirmationDialog(
            "确定要删除所选的 \(selectedIdentifiers.count) 个视频吗？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除视频", role: .destructive) {
                deleteSelectedVideos()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            GrainShareSheet(items: shareURLs)
        }
    }

    // MARK: - 相册分类横滑条 (已隐藏相册位于前列)

    private var albumCategoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(libraryService.albums) { album in
                    let isSelected = libraryService.selectedAlbumId == album.id
                    Button(action: {
                        Task {
                            await libraryService.selectAlbum(id: album.id)
                        }
                        GrainHaptics.selection()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: album.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(album.isHiddenAlbum ? (isSelected ? GrainTheme.paper : GrainTheme.accent) : (isSelected ? GrainTheme.paper : GrainTheme.muted))
                            Text(album.title)
                                .font(.system(size: 13, weight: .medium))
                            Text("\(album.count)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isSelected ? GrainTheme.accent : GrainTheme.muted)
                        }
                        .foregroundColor(isSelected ? GrainTheme.paper : GrainTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? GrainTheme.raised : GrainTheme.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(album.isHiddenAlbum ? GrainTheme.accent.opacity(0.8) : (isSelected ? GrainTheme.accent.opacity(0.7) : GrainTheme.line), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(GrainTheme.surface.opacity(0.4))
    }

    // MARK: - 筛选与多选操作条

    private var filterAndActionBar: some View {
        HStack {
            Text(libraryService.selectedAlbumId == "smart_album_hidden" ? "已隐藏相册 (\(currentAssetsList.count))" : "共 \(currentAssetsList.count) 个视频")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(libraryService.selectedAlbumId == "smart_album_hidden" ? GrainTheme.accent : GrainTheme.muted)

            Spacer()

            // 多选开关按钮
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isMultiSelecting.toggle()
                    if !isMultiSelecting {
                        selectedIdentifiers.removeAll()
                    }
                }
                GrainHaptics.selection()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isMultiSelecting ? "checkmark.circle.fill" : "checklist")
                    Text(isMultiSelecting ? "完成" : "多选")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isMultiSelecting ? GrainTheme.black : GrainTheme.paper)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isMultiSelecting ? GrainTheme.accent : GrainTheme.surface)
                .clipShape(Capsule())
            }

            // 排序菜单
            Menu {
                ForEach(SortOption.allCases) { opt in
                    Button(action: {
                        sortOption = opt
                        GrainHaptics.selection()
                    }) {
                        HStack {
                            Text(opt.rawValue)
                            if sortOption == opt {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GrainTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(GrainTheme.surface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
    }

    private var currentAssetsList: [PHAsset] {
        let assets = (libraryService.selectedAlbumId == "smart_album_hidden") ? libraryService.hiddenAssets : libraryService.currentAssets
        switch sortOption {
        case .dateDesc:
            return assets
        case .dateAsc:
            return assets.reversed()
        case .sizeDesc:
            return assets.sorted(by: { ($0.pixelWidth * $0.pixelHeight) > ($1.pixelWidth * $1.pixelHeight) })
        case .durationDesc:
            return assets.sorted(by: { $0.duration > $1.duration })
        case .nameAsc:
            return assets
        }
    }

    private func toggleSelection(for id: String) {
        if selectedIdentifiers.contains(id) {
            selectedIdentifiers.remove(id)
        } else {
            selectedIdentifiers.insert(id)
        }
        GrainHaptics.selection()
    }

    // MARK: - 多选悬浮底栏

    private var multiSelectBottomBar: some View {
        HStack(spacing: 20) {
            // 全选 / 取消全选
            Button(action: {
                if selectedIdentifiers.count == currentAssetsList.count {
                    selectedIdentifiers.removeAll()
                } else {
                    selectedIdentifiers = Set(currentAssetsList.map(\.localIdentifier))
                }
                GrainHaptics.selection()
            }) {
                Text(selectedIdentifiers.count == currentAssetsList.count ? "取消全选" : "全选")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(GrainTheme.paper)
            }

            Spacer()

            Text("已选 \(selectedIdentifiers.count) 个")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(GrainTheme.accent)

            Spacer()

            // 批量分享
            Button(action: shareSelectedVideos) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selectedIdentifiers.isEmpty ? GrainTheme.muted : GrainTheme.paper)
            }
            .disabled(selectedIdentifiers.isEmpty)

            // 批量删除
            Button(action: { showDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selectedIdentifiers.isEmpty ? GrainTheme.muted : GrainTheme.danger)
            }
            .disabled(selectedIdentifiers.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(GrainTheme.hudBackground)
        .grainGlass(cornerRadius: 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func shareSelectedVideos() {
        let selected = currentAssetsList.filter { selectedIdentifiers.contains($0.localIdentifier) }
        guard !selected.isEmpty else { return }

        Task {
            var urls: [URL] = []
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            for asset in selected {
                if let url = try? await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<URL?, Error>) in
                    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                        if let urlAsset = avAsset as? AVURLAsset {
                            continuation.resume(returning: urlAsset.url)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }), let url {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                self.shareURLs = urls
                self.showShareSheet = true
            }
        }
    }

    private func deleteSelectedVideos() {
        let assetsToDelete = currentAssetsList.filter { selectedIdentifiers.contains($0.localIdentifier) }
        guard !assetsToDelete.isEmpty else { return }

        Task {
            try? await withCheckedThrowingContinuation { continuation in
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
                } completionHandler: { success, error in
                    continuation.resume(returning: ())
                }
            }
            selectedIdentifiers.removeAll()
            isMultiSelecting = false
            await libraryService.reloadAlbumsAndVideos()
            GrainHaptics.success()
        }
    }

    // MARK: - 空状态与权限引导

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: libraryService.selectedAlbumId == "smart_album_hidden" ? "eye.slash" : "video.slash")
                .font(.system(size: 42))
                .foregroundColor(GrainTheme.muted.opacity(0.6))
            Text(libraryService.selectedAlbumId == "smart_album_hidden" ? "相册「已隐藏」相册中暂无视频" : "当前相册暂无视频")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(GrainTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var permissionPromptView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 50))
                .foregroundColor(GrainTheme.accent)

            Text("需要访问您的照片图库")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(GrainTheme.paper)

            Text("GRAIN Player 需要相册读取权限以浏览并播放所有相册视频，包括隐藏相册。")
                .font(.system(size: 14))
                .foregroundColor(GrainTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                Task {
                    _ = await libraryService.requestAuthorization()
                }
            }) {
                Text("授权访问照片")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GrainTheme.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(GrainTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 48)
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - 无畸变 16:9 高速视频卡片 (支持多选指示与长按)

struct PhotoVideoCard: View {
    let asset: PHAsset
    let isMultiSelecting: Bool
    let isSelected: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onInfo: () -> Void
    var onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil
    @State private var requestID: PHImageRequestID? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // 16:9 固定画幅缩略图 (采用 scaledToFill + clipped，彻底解决拉伸变形)
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(
                            ZStack {
                                GrainTheme.surface
                                if let thumbnail {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .clipped()
                                } else {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(GrainTheme.muted.opacity(0.35))
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // 底部时长与分辨率微标
                    HStack(spacing: 4) {
                        Text(FormatUtils.formatDuration(asset.duration))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(4)

                        let maxSide = max(asset.pixelWidth, asset.pixelHeight)
                        if maxSide >= 3800 {
                            Text("4K")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(GrainTheme.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(3)
                        } else if maxSide >= 1900 {
                            Text("1080P")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(GrainTheme.paper)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(3)
                        }

                        Spacer()
                    }
                    .padding(6)

                    // 多选状态圆圈
                    if isMultiSelecting {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(isSelected ? GrainTheme.accent : Color.white.opacity(0.85))
                                    .background(Circle().fill(Color.black.opacity(0.4)))
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                }

                // 拍摄时间简述
                Text(FormatUtils.formatDate(asset.creationDate ?? Date()))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(GrainTheme.muted)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
            .grainCard(cornerRadius: 12, strokeColor: isSelected ? GrainTheme.accent : GrainTheme.line)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    onLongPress()
                }
        )
        .contextMenu {
            if !isMultiSelecting {
                Button(action: onTap) { Label("立即播放", systemImage: "play.fill") }
                Button(action: onInfo) { Label("详细参数", systemImage: "info.circle") }
                Button(action: onLongPress) { Label("选择多个视频", systemImage: "checklist") }
                Button(role: .destructive, action: onDelete) { Label("从相册删除", systemImage: "trash") }
            }
        }
        .onAppear {
            requestThumbnail()
        }
        .onDisappear {
            if let id = requestID {
                PhotoLibraryService.shared.cancelThumbnailRequest(id)
                requestID = nil
            }
        }
    }

    private func requestThumbnail() {
        guard thumbnail == nil else { return }
        requestID = PhotoLibraryService.shared.requestThumbnail(for: asset) { img in
            self.thumbnail = img
        }
    }
}

// MARK: - 系统原生分享控制器

struct GrainShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
