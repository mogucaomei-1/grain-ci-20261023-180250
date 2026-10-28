import Photos
import SwiftUI
import UIKit

@MainActor
final class PhotoLibraryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var isLoading = false
    @Published private(set) var accessDenied = false
    @Published private(set) var isDownloadingOriginal = false
    @Published private(set) var formatLabels: [String: String] = [:]
    private var hasLoaded = false
    /// 磁盘缓存的格式标签：localIdentifier → RAW/HEIF/PNG…
    /// 每次启动不必再对所有照片调用 PHAssetResource（几千张时非常慢）。
    private var cachedLabels: [String: String] = [:]
    private var isSavingLabels = false
    private var labelsDirty = false

    override init() {
        super.init()
        cachedLabels = Self.loadLabelCache()
        formatLabels = cachedLabels
        PHPhotoLibrary.shared().register(self)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        accessDenied = false
        defer {
            isLoading = false
            hasLoaded = true
        }

        guard await PhotoLibraryAccess.request() else {
            accessDenied = true
            assets = []
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }
        assets = fetchedAssets
        refreshFormatLabels(for: fetchedAssets)
    }

    /// 缩略图格式徽标与「只看某种格式」都依赖资源类型。
    /// 先用本地缓存秒开，再只对缓存里没有的新照片做一次后台扫描。
    private func refreshFormatLabels(for assets: [PHAsset]) {
        let cached = cachedLabels
        var seeded: [String: String] = [:]
        seeded.reserveCapacity(assets.count)
        var missing: [PHAsset] = []
        for asset in assets {
            if let label = cached[asset.localIdentifier], label != "VIDEO" {
                seeded[asset.localIdentifier] = label
            } else {
                missing.append(asset)
            }
        }
        formatLabels = seeded

        let pending = missing
        guard !pending.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            var labels = cached
            for asset in pending {
                labels[asset.localIdentifier] = Self.formatLabel(for: asset)
            }
            let snapshot = labels
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.cachedLabels = snapshot
                self.formatLabels = snapshot
                self.persistLabelCache()
            }
        }
    }

    // MARK: - 格式标签缓存

    nonisolated private static var labelCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GRAIN", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("library-format-labels.json")
    }

    nonisolated private static func loadLabelCache() -> [String: String] {
        guard let data = try? Data(contentsOf: labelCacheURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    private func persistLabelCache() {
        guard !isSavingLabels else {
            labelsDirty = true
            return
        }
        isSavingLabels = true
        labelsDirty = false
        let snapshot = cachedLabels
        Task.detached(priority: .utility) { [weak self] in
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.labelCacheURL, options: .atomic)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSavingLabels = false
                if self.labelsDirty {
                    self.persistLabelCache()
                }
            }
        }
    }

    nonisolated static func formatLabel(for asset: PHAsset) -> String {
        if asset.mediaType == .video {
            return videoFormatLabel(for: asset)
        }
        let resources = PHAssetResource.assetResources(for: asset)
        let candidate = resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
            ?? resources.first
        guard let resource = candidate else { return "IMAGE" }
        let identifier = resource.uniformTypeIdentifier.lowercased()
        let filename = resource.originalFilename.lowercased()
        if identifier.contains("raw") || ["arw", "dng", "srf", "sr2"]
            .contains(where: { filename.hasSuffix(".\($0)") }) {
            return "RAW"
        }
        if identifier.contains("heic") || identifier.contains("heif") {
            return "HEIF"
        }
        if identifier.contains("png") { return "PNG" }
        if identifier.contains("jpeg") || identifier.contains("jpg") { return "JPEG" }
        if identifier.contains("tiff") || identifier.contains("tif") { return "TIFF" }
        return "IMAGE"
    }

    nonisolated static func videoQuickResolutionLabel(for asset: PHAsset) -> String {
        let maxDim = max(asset.pixelWidth, asset.pixelHeight)
        let minDim = min(asset.pixelWidth, asset.pixelHeight)
        if maxDim >= 3800 || minDim >= 2100 {
            return "4K"
        } else if maxDim >= 1900 || minDim >= 1050 {
            return "1080P"
        } else if maxDim >= 1200 || minDim >= 700 {
            return "720P"
        } else if minDim > 0 {
            return "\(minDim)P"
        } else {
            return "VIDEO"
        }
    }

    /// 提取视频的规格与帧率（如 4K 60fps, 1080P 30fps 等），避免只单一显示一个 VIDEO 单词
    nonisolated static func videoFormatLabel(for asset: PHAsset) -> String {
        let res = videoQuickResolutionLabel(for: asset)

        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = false

        let semaphore = DispatchSemaphore(value: 0)
        var resolvedFPS: Int? = nil

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            if let avAsset {
                if let track = avAsset.tracks(withMediaType: .video).first {
                    let rate = track.nominalFrameRate
                    if rate > 0 {
                        resolvedFPS = Int(rate.rounded())
                    } else if track.minFrameDuration.timescale > 0 {
                        let fpsFromDur = Double(track.minFrameDuration.timescale) / Double(max(track.minFrameDuration.value, 1))
                        resolvedFPS = Int(fpsFromDur.rounded())
                    }
                }
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 0.15)

        if let fps = resolvedFPS, fps > 0 {
            return "\(res) \(fps)fps"
        } else {
            return res
        }
    }

    func originalFileURL(for asset: PHAsset) async throws -> URL {
        originalRequestGeneration += 1
        let generation = originalRequestGeneration
        isDownloadingOriginal = true
        defer {
            if generation == originalRequestGeneration {
                isDownloadingOriginal = false
            }
        }

        let url = try await PhotoLibraryAssetLoader.loadOriginal(asset: asset)
        try Task.checkCancellation()
        guard generation == originalRequestGeneration else {
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        return url
    }

    func deleteAssets(identifiers: Set<String>) async throws {
        guard !identifiers.isEmpty else { return }
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: Array(identifiers),
            options: nil
        )
        guard assets.count > 0 else { return }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? NSError(
                            domain: "GRAIN.PhotoLibrary",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "无法删除所选照片，请稍后重试。"
                            ]
                        )
                    )
                }
            }
        }
        await refresh()
    }

    private var originalRequestGeneration = 0
}

enum PhotoLibraryAssetLoader {
    enum LoadError: LocalizedError {
        case noResource
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .noResource:
                "iCloud 中没有找到这张照片的原始资源。"
            case .downloadFailed:
                "无法从 iCloud 下载原始照片，请检查网络后重试。"
            }
        }
    }

    static func loadOriginal(asset: PHAsset) async throws -> URL {
        let rawMarkers = ["arw", "srf", "sr2", "dng", "camera-raw"]
        let allResources = PHAssetResource.assetResources(for: asset)
        let matchingResources = allResources.filter {
            $0.assetLocalIdentifier == asset.localIdentifier
        }
        let resources = matchingResources.isEmpty ? allResources : matchingResources
        let rawResource = resources.first { resource in
            let identifier = resource.uniformTypeIdentifier.lowercased()
            let filename = resource.originalFilename.lowercased()
            return rawMarkers.contains { identifier.contains($0) || filename.hasSuffix(".\($0)") }
        }
        let resource = rawResource
            ?? resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
        guard let resource else {
            throw LoadError.noResource
        }

        let originalExtension = (resource.originalFilename as NSString).pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(originalExtension.isEmpty ? "arw" : originalExtension)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().writeData(
                for: resource,
                toFile: destination,
                options: options
            ) { error in
                if error == nil {
                    continuation.resume(returning: destination)
                } else {
                    continuation.resume(throwing: LoadError.downloadFailed)
                }
            }
        }
    }
}

private struct PhotoTileFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum LibraryMediaTypeFilter: String, CaseIterable, Identifiable {
    case all
    case photos
    case videos
    case screenshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .photos: "照片"
        case .videos: "视频"
        case .screenshots: "截图"
        }
    }

    func matches(_ asset: PHAsset) -> Bool {
        switch self {
        case .all:
            return true
        case .photos:
            // 照片：标准照片（排除视频与屏幕截图）
            return asset.mediaType == .image && !asset.mediaSubtypes.contains(.photoScreenshot)
        case .videos:
            // 视频：媒体类型必须是视频
            return asset.mediaType == .video
        case .screenshots:
            // 截图：包含屏幕截图子类型
            return asset.mediaSubtypes.contains(.photoScreenshot)
        }
    }
}

struct PhotoLibraryHome: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let onSelect: (PHAsset) -> Void
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.openURL) private var openURL
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var isSelecting = false
    @State private var selectedIdentifiers = Set<String>()
    @State private var selectionOrder: [String] = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isPreparingShare = false
    @State private var shareURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var showCollageEditor = false
    @State private var shareError: String?
    @State private var deleteError: String?
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var lastSelectionDragPoint: CGPoint?
    @State private var mediaTypeFilter: LibraryMediaTypeFilter = .all
    @State private var sortAscending = false
    @StateObject private var batch = BatchExportViewModel()
    @State private var showBatchProgress = false
    @State private var batchNotice: String?
    @State private var batchError: String?

    // 双指缩放网格列数（类似 iOS 官方相册动态伸缩：1~10 列），偏好持久化
    @AppStorage("libraryGridColumnCount") private var gridColumnCount: Int = 3
    @State private var baseColumnCount: Int = 3
    @State private var isPinching: Bool = false

    private var columns: [GridItem] {
        let count = max(1, min(10, gridColumnCount))
        let spacing: CGFloat = count >= 8 ? 1.0 : (count >= 5 ? 1.5 : (count >= 4 ? 2 : 3))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    private var gridSpacing: CGFloat {
        gridColumnCount >= 8 ? 1.0 : (gridColumnCount >= 5 ? 1.5 : (gridColumnCount >= 4 ? 2 : 3))
    }

    private func handlePinch(scale: CGFloat, state: UIGestureRecognizer.State, recognizer: UIPinchGestureRecognizer) {
        switch state {
        case .began:
            baseColumnCount = gridColumnCount
            isPinching = true
        case .changed:
            if scale > 1.25 {
                // 双指放大 -> 列数减少，照片变大
                if gridColumnCount > 1 {
                    let next = gridColumnCount - 1
                    GrainHaptics.mediumImpact(enabled: hapticsEnabled)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        gridColumnCount = next
                    }
                    recognizer.scale = 1.0
                }
            } else if scale < 0.80 {
                // 双指缩小 -> 列数增加，照片变小，同屏展示更多照片（支持最多 10 列）
                if gridColumnCount < 10 {
                    let next = gridColumnCount + 1
                    GrainHaptics.mediumImpact(enabled: hapticsEnabled)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        gridColumnCount = next
                    }
                    recognizer.scale = 1.0
                }
            }
        case .ended, .cancelled, .failed:
            isPinching = false
            baseColumnCount = gridColumnCount
        default:
            break
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSelecting {
                selectionToolbar
            } else {
                mediaTypeHeaderBar
            }

            if library.accessDenied {
                permissionView
            } else {
                ScrollView {
                    gridContent
                        .background(
                            ScrollViewPinchAttachment { scale, state, recognizer in
                                handlePinch(scale: scale, state: state, recognizer: recognizer)
                            }
                        )
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await library.refresh()
                }
            }
        }
        .task {
            await library.loadIfNeeded()
        }
        .onChange(of: library.assets.map(\.localIdentifier)) { _, identifiers in
            selectedIdentifiers.formIntersection(Set(identifiers))
            selectionOrder = selectionOrder.filter(selectedIdentifiers.contains)
            if identifiers.isEmpty {
                isSelecting = false
            }
        }
        .overlay {
            if library.isLoading
                || library.isDownloadingOriginal
                || isDeleting
                || isPreparingShare {
                VStack(spacing: 10) {
                    ProgressView().tint(GrainTheme.paper)
                    Text(statusText)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(GrainTheme.surface.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
            }
        }
        .confirmationDialog(
            "删除所选的 \(selectedIdentifiers.count) 张照片？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除照片", role: .destructive) {
                deleteSelectedAssets()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("照片会从系统图库中删除，此操作无法撤销。")
        }
        .alert(
            "无法删除照片",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert(
            "无法分享照片",
            isPresented: Binding(
                get: { shareError != nil },
                set: { if !$0 { shareError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .sheet(isPresented: $showShareSheet, onDismiss: clearShareFiles) {
            GrainShareSheet(items: shareURLs)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCollageEditor) {
            CollageEditorView(assets: selectedAssets)
        }
        .sheet(isPresented: $showBatchProgress, onDismiss: {
            if batch.isRunning {
                batch.cancel()
            }
            batch.clearSummary()
        }) {
            BatchProgressSheet(batch: batch)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "批量处理未完成",
            isPresented: Binding(
                get: { batchError != nil },
                set: { if !$0 { batchError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(batchError ?? "")
        }
        .alert(
            "已套用配方",
            isPresented: Binding(
                get: { batchNotice != nil },
                set: { if !$0 { batchNotice = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(batchNotice ?? "")
        }
        .onChange(of: batch.isRunning) { _, running in
            guard !running, batch.summary != nil else { return }
            Task { await library.refresh() }
        }
    }

    @ViewBuilder
    private var gridContent: some View {
        let grid = LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(visibleAssets, id: \.localIdentifier) { asset in
                libraryTile(asset)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 24)
        .coordinateSpace(name: "photo-library-grid")
        .onPreferenceChange(PhotoTileFramePreferenceKey.self) {
            tileFrames = $0
        }

        if isSelecting {
            grid.simultaneousGesture(selectionDragGesture)
        } else {
            grid
        }
    }

    private var mediaTypeHeaderBar: some View {
        HStack {
            // 左侧：时间排序与媒体统计
            HStack(spacing: 8) {
                sortChip
                if !library.assets.isEmpty {
                    Text("\(visibleAssets.count)/\(library.assets.count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GrainTheme.muted)
                }
            }

            Spacer()

            // 右侧最上方：媒体类型分类（照片 / 视频 / 截图 / 全部）
            Menu {
                ForEach(LibraryMediaTypeFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            mediaTypeFilter = filter
                        }
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        HStack {
                            Text(filter.title)
                            if mediaTypeFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(mediaTypeFilter == .all ? "媒体类型" : mediaTypeFilter.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                }
                .foregroundStyle(mediaTypeFilter == .all ? GrainTheme.paper : GrainTheme.accent)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(GrainTheme.raised, in: Capsule())
                .overlay(
                    Capsule().stroke(
                        mediaTypeFilter == .all ? GrainTheme.line : GrainTheme.accent.opacity(0.6),
                        lineWidth: 0.6
                    )
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var sortChip: some View {
        Button {
            sortAscending.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text("时间")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(GrainTheme.muted)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(GrainTheme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var selectionToolbar: some View {
        HStack(spacing: 5) {
            Button("取消") {
                endSelection()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(GrainTheme.paper)
            .buttonStyle(.plain)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            Text("已选\(selectedIdentifiers.count)张")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 2)

            Menu {
                Button("批量套用最近配方", systemImage: "paintbrush.pointed") {
                    batchApplyRecipe()
                }
                Button("批量导出所选照片", systemImage: "square.and.arrow.up.on.square") {
                    batchExportSelected()
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "square.stack.3d.down.right")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("批量")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(
                    selectedIdentifiers.isEmpty ? GrainTheme.muted : GrainTheme.accent
                )
                .padding(.horizontal, 7)
                .frame(height: 28)
                .background(GrainTheme.raised, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }
            .disabled(selectedIdentifiers.isEmpty || isDeleting || batch.isRunning)

            Button {
                showCollageEditor = true
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("编辑")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(
                    !selectedAssets.isEmpty && selectedAssets.count <= 10
                        ? GrainTheme.accent
                        : GrainTheme.muted
                )
                .padding(.horizontal, 7)
                .frame(height: 28)
                .background(GrainTheme.raised, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .disabled(selectedAssets.isEmpty || selectedAssets.count > 10)
            .accessibilityLabel("在编辑工作台中编辑所选照片")

            Button {
                shareSelectedAssets()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 9.5, weight: .bold))
                    Text("分享")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(
                    !selectedIdentifiers.isEmpty
                        ? GrainTheme.accent
                        : GrainTheme.muted
                )
                .padding(.horizontal, 7)
                .frame(height: 28)
                .background(GrainTheme.raised, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .disabled(selectedIdentifiers.isEmpty || isDeleting || isPreparingShare)
            .accessibilityLabel("分享所选照片")

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        selectedIdentifiers.isEmpty ? GrainTheme.muted : GrainTheme.accent
                    )
                    .frame(width: 28, height: 28)
                    .background(GrainTheme.raised, in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .disabled(selectedIdentifiers.isEmpty || isDeleting)
            .accessibilityLabel("删除所选照片")
        }
        .padding(.horizontal, 8)
        .padding(.top, 3)
        .padding(.bottom, 5)
    }

    private var visibleAssets: [PHAsset] {
        let filtered = library.assets.filter {
            mediaTypeFilter.matches($0)
        }
        return sortAscending ? Array(filtered.reversed()) : filtered
    }

    private var selectedAssets: [PHAsset] {
        let lookup = Dictionary(
            library.assets.map { ($0.localIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return selectionOrder.compactMap { lookup[$0] }
    }

    private var latestRecipe: PhotoRecipe? {
        editor.currentRecipe ?? RecipeStore.shared.latest()
    }

    private func batchApplyRecipe() {
        guard let recipe = latestRecipe else {
            batchError = "还没有可用的调色配方。先在编辑页调整一张照片，再回来批量套用。"
            return
        }
        let identities = selectedAssets.map {
            RecipeIdentity.library($0.localIdentifier)
        }
        let count = RecipeStore.shared.apply(recipe, to: identities)
        batchNotice = "已把「\(recipe.summary)」套用到 \(count) 张照片"
        endSelection()
    }

    private func batchExportSelected() {
        guard let recipe = latestRecipe else {
            batchError = "还没有可用的调色配方。先在编辑页调整一张照片，再回来批量导出。"
            return
        }
        let assets = selectedAssets
        guard !assets.isEmpty else { return }
        batch.start(assets: assets, recipe: recipe, options: editor.exportOptions)
        showBatchProgress = true
        endSelection()
    }

    private var statusText: String {
        if isPreparingShare { return "正在准备分享" }
        if isDeleting { return "正在删除照片" }
        if library.isDownloadingOriginal { return "正在从 iCloud 下载原图" }
        return "正在载入照片"
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func libraryTile(_ asset: PHAsset) -> some View {
        let selected = selectedIdentifiers.contains(asset.localIdentifier)
        let tileRadius: CGFloat = gridColumnCount >= 7 ? 1.5 : (gridColumnCount >= 5 ? 2.5 : 3)

        return ZStack(alignment: .topTrailing) {
            AssetThumbnail(asset: asset)
                .clipShape(RoundedRectangle(cornerRadius: tileRadius, style: .continuous))
                .id(asset.localIdentifier)

            let badgeLabel: String? = {
                if let lbl = library.formatLabels[asset.localIdentifier], lbl != "VIDEO" {
                    return lbl
                }
                if asset.mediaType == .video {
                    return PhotoLibraryViewModel.videoQuickResolutionLabel(for: asset)
                }
                return library.formatLabels[asset.localIdentifier]
            }()

            if gridColumnCount <= 4 {
                AssetFormatBadge(label: badgeLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(gridColumnCount >= 4 ? 3 : 5)
            }

            if asset.mediaType == .video {
                if gridColumnCount <= 6 {
                    HStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.system(size: gridColumnCount >= 4 ? 6 : 7.5))
                        if gridColumnCount <= 4 {
                            Text(Self.formatDuration(asset.duration))
                                .font(.system(size: gridColumnCount >= 4 ? 7.5 : 9, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, gridColumnCount >= 4 ? 3 : 4.5)
                    .padding(.vertical, gridColumnCount >= 4 ? 1.5 : 2.5)
                    .background(Color.black.opacity(0.68), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(gridColumnCount >= 4 ? 2 : 4)
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: gridColumnCount >= 9 ? 4.5 : 5.5))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.8), radius: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(1.5)
                }
            }

            if isSelecting {
                RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                    .fill(Color.black.opacity(selected ? 0.22 : 0.04))

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: gridColumnCount >= 7 ? 10 : (gridColumnCount >= 5 ? 13 : 19), weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        selected ? GrainTheme.paper : Color.white.opacity(0.86),
                        selected ? GrainTheme.accent : Color.black.opacity(0.34)
                    )
                    .padding(gridColumnCount >= 7 ? 2 : 4)

                RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                    .stroke(
                        selected ? GrainTheme.accent : Color.clear,
                        lineWidth: gridColumnCount >= 7 ? 1 : 2
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .gesture(libraryTileGesture(asset))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PhotoTileFramePreferenceKey.self,
                    value: [
                        asset.localIdentifier: proxy.frame(
                            in: .named("photo-library-grid")
                        )
                    ]
                )
            }
        }
        .accessibilityLabel(
            isSelecting
                ? (selected ? "已选中照片" : "未选中照片")
                : "编辑照片"
        )
    }

    private func libraryTileGesture(_ asset: PHAsset) -> some Gesture {
        TapGesture()
            .exclusively(before: LongPressGesture(minimumDuration: 0.36))
            .onEnded { result in
                guard !library.isDownloadingOriginal, !isDeleting else { return }
                switch result {
                case .first:
                    if isSelecting {
                        toggleSelection(asset)
                    } else {
                        onSelect(asset)
                    }
                case .second:
                    if !isSelecting {
                        withAnimation(.easeOut(duration: 0.16)) {
                            isSelecting = true
                            selectedIdentifiers.insert(asset.localIdentifier)
                            selectionOrder.append(asset.localIdentifier)
                        }
                    } else {
                        addSelection(asset.localIdentifier)
                    }
                    GrainHaptics.mediumImpact(enabled: hapticsEnabled)
                }
            }
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("photo-library-grid"))
            .onChanged { value in
                guard isSelecting,
                      !library.isDownloadingOriginal,
                      !isDeleting
                else { return }

                let start = lastSelectionDragPoint ?? value.location
                selectTiles(along: start, end: value.location)
                lastSelectionDragPoint = value.location
            }
            .onEnded { _ in
                lastSelectionDragPoint = nil
            }
    }

    private func selectTiles(along start: CGPoint, end: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let stepCount = max(1, Int(ceil(distance / 10)))
        var didAddSelection = false

        for step in 0...stepCount {
            let progress = CGFloat(step) / CGFloat(stepCount)
            let point = CGPoint(
                x: start.x + dx * progress,
                y: start.y + dy * progress
            )
            guard let identifier = tileFrames.first(where: {
                $0.value.contains(point)
            })?.key else {
                continue
            }
            if selectedIdentifiers.contains(identifier) {
                continue
            }
            selectedIdentifiers.insert(identifier)
            selectionOrder.append(identifier)
            didAddSelection = true
        }

        if didAddSelection {
            GrainHaptics.selection(enabled: hapticsEnabled)
        }
    }

    private func toggleSelection(_ asset: PHAsset) {
        if selectedIdentifiers.contains(asset.localIdentifier) {
            selectedIdentifiers.remove(asset.localIdentifier)
            selectionOrder.removeAll { $0 == asset.localIdentifier }
        } else {
            addSelection(asset.localIdentifier)
        }
        GrainHaptics.selection(enabled: hapticsEnabled)
    }

    private func endSelection() {
        withAnimation(.easeOut(duration: 0.16)) {
            isSelecting = false
            selectedIdentifiers.removeAll()
            selectionOrder.removeAll()
        }
    }

    private func addSelection(_ identifier: String) {
        guard !selectedIdentifiers.contains(identifier) else { return }
        selectedIdentifiers.insert(identifier)
        selectionOrder.append(identifier)
    }

    private func shareSelectedAssets() {
        let assetLookup = Dictionary(
            uniqueKeysWithValues: library.assets.map {
                ($0.localIdentifier, $0)
            }
        )
        let assets = selectionOrder
            .compactMap { assetLookup[$0] }
            .filter { selectedIdentifiers.contains($0.localIdentifier) }
        guard !assets.isEmpty else { return }
        isPreparingShare = true
        shareError = nil
        clearShareFiles()

        Task { @MainActor in
            var urls: [URL] = []
            do {
                for asset in assets {
                    let url = try await PhotoLibraryAssetLoader.loadOriginal(asset: asset)
                    urls.append(url)
                }
                shareURLs = urls
                showShareSheet = true
            } catch {
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
                shareError = error.localizedDescription
            }
            isPreparingShare = false
        }
    }

    private func clearShareFiles() {
        for url in shareURLs {
            try? FileManager.default.removeItem(at: url)
        }
        shareURLs = []
    }

    private func deleteSelectedAssets() {
        let identifiers = selectedIdentifiers
        guard !identifiers.isEmpty else { return }
        isDeleting = true

        Task {
            do {
                try await library.deleteAssets(identifiers: identifiers)
                withAnimation(.easeOut(duration: 0.18)) {
                    isSelecting = false
                    selectedIdentifiers.removeAll()
                    selectionOrder.removeAll()
                }
            } catch {
                deleteError = error.localizedDescription
            }
            isDeleting = false
        }
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 35, weight: .light))
                .foregroundStyle(GrainTheme.muted)
            Text("需要照片访问权限")
                .font(.system(size: 18, weight: .semibold, design: .serif))
            Text("允许读取照片后，才能显示相册并从 iCloud 获取 RAW 原文件。")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(GrainTheme.black)
            .padding(.horizontal, 20)
            .frame(height: 42)
            .background(GrainTheme.paper, in: Capsule())
            Spacer()
        }
    }
}

private struct BatchProgressSheet: View {
    @ObservedObject var batch: BatchExportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("批量导出")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(GrainTheme.paper)
                        Text(batch.isRunning ? "逐张套用配方并写回相册" : "处理结束")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    if !batch.isRunning {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(GrainTheme.raised, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(GrainTheme.paper)
                    }
                }

                if batch.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: batch.progress)
                            .tint(GrainTheme.accent)
                        HStack {
                            Text(batch.currentName)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(GrainTheme.muted)
                                .lineLimit(1)
                            Spacer()
                            Text("\(batch.completed) / \(batch.total)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(GrainTheme.paper)
                        }
                    }

                    Button {
                        batch.cancel()
                    } label: {
                        Text("取消")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(batch.summary ?? "没有处理任何照片")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)

                    Button { dismiss() } label: {
                        Text("完成")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(GrainTheme.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(GrainTheme.paper, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

private struct AssetFormatBadge: View {
    let label: String?

    var body: some View {
        if let label {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 5)
                .frame(height: 15)
                .background(.black.opacity(0.56), in: Capsule())
        }
    }
}

private enum AssetFormat {
    static func label(for asset: PHAsset) -> String? {
        guard let identifier = PHAssetResource.assetResources(for: asset)
            .first?.uniformTypeIdentifier
        else {
            return nil
        }
        return label(forUniformTypeIdentifier: identifier)
    }

    static func label(forUniformTypeIdentifier identifier: String) -> String? {
        switch identifier {
        case "public.heic", "public.heif", "public.heic.sequence":
            return "HEIF"
        case "public.png":
            return "PNG"
        case "public.jpeg":
            return "JPEG"
        case "public.tiff":
            return "TIFF"
        case "com.adobe.raw-image", "com.adobe.digital-negative":
            return "RAW"
        default:
            let lowercased = identifier.lowercased()
            if lowercased.contains("raw") || lowercased.contains("arw") {
                return "RAW"
            }
            if lowercased.hasSuffix("dng") {
                return "RAW"
            }
            return nil
        }
    }
}

private struct AssetThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var requestedIdentifier: String?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    GrainTheme.surface
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 11, weight: .light))
                            .foregroundStyle(GrainTheme.muted.opacity(0.5))
                    }
                }
                .clipped()
            }
        .clipped()
        .onAppear(perform: requestThumbnail)
        .onDisappear {
            if let requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }

    private func requestThumbnail() {
        guard image == nil, requestedIdentifier != asset.localIdentifier else { return }
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        requestedIdentifier = asset.localIdentifier

        let target = CGSize(width: 360, height: 360)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isNetworkAccessAllowed = true
        let identifier = asset.localIdentifier

        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                return
            }
            if let result {
                DispatchQueue.main.async {
                    guard requestedIdentifier == identifier else { return }
                    image = result
                }
            }
        }
    }
}

// MARK: - 专用双指缩放底层挂载（将 UIPinchGestureRecognizer 直接装在底层 UIScrollView 上，彻底解放单指 100% 顺滑纵向滚动）

struct ScrollViewPinchAttachment: UIViewRepresentable {
    let onPinch: (CGFloat, UIGestureRecognizer.State, UIPinchGestureRecognizer) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPinch = onPinch
        DispatchQueue.main.async {
            guard let scrollView = Self.findParentScrollView(of: uiView) else { return }
            context.coordinator.attach(to: scrollView)
        }
    }

    private static func findParentScrollView(of view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let parent = current?.superview {
            if let scroll = parent as? UIScrollView {
                return scroll
            }
            for sub in parent.subviews {
                if let scroll = findScrollView(in: sub) {
                    return scroll
                }
            }
            current = parent
        }
        return nil
    }

    private static func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) {
                return found
            }
        }
        return nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPinch: onPinch)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPinch: (CGFloat, UIGestureRecognizer.State, UIPinchGestureRecognizer) -> Void
        private weak var attachedScrollView: UIScrollView?
        private var pinchRecognizer: UIPinchGestureRecognizer?

        init(onPinch: @escaping (CGFloat, UIGestureRecognizer.State, UIPinchGestureRecognizer) -> Void) {
            self.onPinch = onPinch
        }

        func attach(to scrollView: UIScrollView) {
            guard attachedScrollView !== scrollView else { return }
            if let old = pinchRecognizer, let oldScroll = attachedScrollView {
                oldScroll.removeGestureRecognizer(old)
            }
            attachedScrollView = scrollView
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            pinch.delaysTouchesBegan = false
            pinch.delaysTouchesEnded = false
            pinch.delegate = self
            scrollView.addGestureRecognizer(pinch)
            self.pinchRecognizer = pinch
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            onPinch(recognizer.scale, recognizer.state, recognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
