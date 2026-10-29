import AVFoundation
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
        // 遵循 iOS 17 相册逻辑：按拍摄时间正序加载（从下往上排，最旧在上，最新在下）
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
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
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .noResource:
                "iCloud 中未找到该素材的原始文件。"
            case .downloadFailed:
                "无法从 iCloud 下载原始文件，请检查网络后重试。"
            case .exportFailed:
                "无法导出视频文件，请稍后重试。"
            }
        }
    }

    static func loadOriginal(asset: PHAsset) async throws -> URL {
        if asset.mediaType == .video {
            return try await loadVideo(asset: asset)
        }

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

    private static func loadVideo(asset: PHAsset) async throws -> URL {
        let allResources = PHAssetResource.assetResources(for: asset)
        let matchingResources = allResources.filter {
            $0.assetLocalIdentifier == asset.localIdentifier
        }
        let resources = matchingResources.isEmpty ? allResources : matchingResources
        let videoResource = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video })
            ?? resources.first(where: { $0.type == .pairedVideo })

        if let resource = videoResource {
            let originalExtension = (resource.originalFilename as NSString).pathExtension
            let ext = originalExtension.isEmpty ? "mov" : originalExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            do {
                return try await withCheckedThrowingContinuation { continuation in
                    PHAssetResourceManager.default().writeData(
                        for: resource,
                        toFile: destination,
                        options: options
                    ) { error in
                        if error == nil {
                            continuation.resume(returning: destination)
                        } else {
                            continuation.resume(throwing: error ?? LoadError.downloadFailed)
                        }
                    }
                }
            } catch {
                // 如果直接写资源失败，回退到 requestAVAsset 导出
            }
        }

        // 回退方案：通过 PHImageManager requestAVAsset 读取
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    let ext = urlAsset.url.pathExtension.isEmpty ? "mov" : urlAsset.url.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    do {
                        try? FileManager.default.removeItem(at: dest)
                        try FileManager.default.copyItem(at: urlAsset.url, to: dest)
                        continuation.resume(returning: dest)
                        return
                    } catch {
                        // 复制失败则走后续导出
                    }
                }

                guard let avAsset else {
                    continuation.resume(throwing: LoadError.noResource)
                    return
                }

                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                try? FileManager.default.removeItem(at: dest)

                guard let export = AVAssetExportSession(
                    asset: avAsset,
                    presetName: AVAssetExportPresetPassthrough
                ) else {
                    continuation.resume(throwing: LoadError.exportFailed)
                    return
                }

                export.outputURL = dest
                export.outputFileType = .mov
                export.exportAsynchronously {
                    if export.status == .completed {
                        continuation.resume(returning: dest)
                    } else {
                        continuation.resume(throwing: export.error ?? LoadError.exportFailed)
                    }
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

private struct PhotoTileGlobalFramePreferenceKey: PreferenceKey {
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
    @Binding var externalIsSelecting: Bool
    let onSelect: (PHAsset, [PHAsset], CGRect?, [String: CGRect]) -> Void

    private let usesExternalSelecting: Bool
    @State private var localIsSelecting = false
    private var isSelecting: Bool {
        get { usesExternalSelecting ? externalIsSelecting : localIsSelecting }
        nonmutating set {
            if usesExternalSelecting {
                externalIsSelecting = newValue
            } else {
                localIsSelecting = newValue
            }
        }
    }

    init(
        library: PhotoLibraryViewModel,
        isSelecting: Binding<Bool>? = nil,
        onSelect: @escaping (PHAsset, [PHAsset], CGRect?, [String: CGRect]) -> Void
    ) {
        self.library = library
        if let isSelecting {
            self._externalIsSelecting = isSelecting
            self.usesExternalSelecting = true
        } else {
            self._externalIsSelecting = .constant(false)
            self.usesExternalSelecting = false
        }
        self.onSelect = onSelect
    }

    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.openURL) private var openURL
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
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
    @State private var tileGlobalFrames: [String: CGRect] = [:]
    @State private var lastSelectionDragPoint: CGPoint?
    @State private var mediaTypeFilter: LibraryMediaTypeFilter = .all
    @State private var sortAscending = false
    @StateObject private var batch = BatchExportViewModel()
    @State private var showBatchProgress = false
    @State private var batchNotice: String?
    @State private var batchError: String?
    @State private var didInitialScrollToBottom = false

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
            mediaTypeHeaderBar

            if library.accessDenied {
                permissionView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        gridContent
                            .background(
                                ScrollViewPinchAttachment { scale, state, recognizer in
                                    handlePinch(scale: scale, state: state, recognizer: recognizer)
                                }
                            )
                    }
                    .id(mediaTypeFilter)
                    .defaultScrollAnchor(.bottom)
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await library.refresh()
                        scrollToBottom(proxy: proxy)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: mediaTypeFilter) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: visibleAssets.count) { _, count in
                        if count > 0 && !sortAscending {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: library.isLoading) { _, loading in
                        if !loading && !visibleAssets.isEmpty && !sortAscending {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: library.assets.count) { _, count in
                        if count > 0 && !sortAscending {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: sortAscending) { _, ascending in
                        if !ascending {
                            scrollToBottom(proxy: proxy, animated: true)
                        } else if let firstID = visibleAssets.first?.localIdentifier {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo(firstID, anchor: .top)
                            }
                        }
                    }
                }
            }

            // 黑色间隔条：清晰分隔上方照片区域与最下方功能条
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .frame(height: 1)

            if isSelecting {
                selectionToolbar
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
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .liquidGlassCapsule()
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
                    .id(asset.localIdentifier)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 0)
        .coordinateSpace(name: "photo-library-grid")
        .onPreferenceChange(PhotoTileFramePreferenceKey.self) {
            tileFrames = $0
        }
        .onPreferenceChange(PhotoTileGlobalFramePreferenceKey.self) {
            tileGlobalFrames = $0
        }

        if isSelecting {
            grid.simultaneousGesture(selectionDragGesture)
        } else {
            grid
        }
    }

    private var mediaTypeHeaderBar: some View {
        HStack {
            // 左侧：时间排序与媒体统计（黑字白底）
            HStack(spacing: 8) {
                sortChip
                if !library.assets.isEmpty {
                    Text("\(visibleAssets.count)/\(library.assets.count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                                )
                        }
                        .clipShape(Capsule(style: .continuous))
                }
            }

            Spacer()

            // 右侧最上方：媒体类型分类（照片 / 视频 / 截图 / 全部，选择后去橙色改为黑字白底，绝无阴影裁切瑕疵）
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
                    Text(mediaTypeFilter.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                }
                .foregroundStyle(mediaTypeFilter == .all ? GrainTheme.paper : Color.black)
                .padding(.horizontal, 11)
                .frame(height: 29)
                .background {
                    if mediaTypeFilter != .all {
                        Capsule(style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.6)
                            )
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                    }
                }
                .clipShape(Capsule(style: .continuous))
            }
        }
        .padding(.horizontal, 14)
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
            .foregroundStyle(Color.black)
            .padding(.horizontal, 10)
            .frame(height: 25)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6)
                    )
            }
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(LiquidGlassButtonStyle())
    }

    private var selectionToolbar: some View {
        HStack(spacing: 6) {
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        selectedIdentifiers.isEmpty ? Color.black.opacity(0.35) : Color.black
                    )
                    .frame(width: 38, height: 38)
                    .liquidGlassCircle(size: 38, isWhite: true)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(LiquidGlassButtonStyle())
            .disabled(selectedIdentifiers.isEmpty || isDeleting)
            .accessibilityLabel("删除所选照片")

            Button("取消") {
                endSelection()
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(GrainTheme.paper)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .liquidGlassCapsule()
            .buttonStyle(LiquidGlassButtonStyle())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            Text("已选\(selectedIdentifiers.count)张")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .liquidGlassCapsule(isWhite: true)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            Menu {
                Button("批量套用最近配方", systemImage: "paintbrush.pointed") {
                    batchApplyRecipe()
                }
                Button("批量导出所选照片", systemImage: "square.and.arrow.up.on.square") {
                    batchExportSelected()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.stack.3d.down.right")
                        .font(.system(size: 12, weight: .bold))
                    Text("批量")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(
                    selectedIdentifiers.isEmpty ? Color.black.opacity(0.35) : Color.black
                )
                .padding(.horizontal, 10)
                .frame(height: 38)
                .liquidGlassCapsule(isWhite: true)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(LiquidGlassButtonStyle())
            .disabled(selectedIdentifiers.isEmpty || isDeleting || batch.isRunning)

            Button {
                showCollageEditor = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 12, weight: .bold))
                    Text("编辑")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(
                    !selectedAssets.isEmpty && selectedAssets.count <= 10
                        ? Color.black
                        : Color.black.opacity(0.35)
                )
                .padding(.horizontal, 10)
                .frame(height: 38)
                .liquidGlassCapsule(isWhite: true)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(LiquidGlassButtonStyle())
            .disabled(selectedAssets.isEmpty || selectedAssets.count > 10)
            .accessibilityLabel("在编辑工作台中编辑所选照片")

            Button {
                shareSelectedAssets()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold))
                    Text("分享")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(
                    !selectedIdentifiers.isEmpty
                        ? Color.black
                        : Color.black.opacity(0.35)
                )
                .padding(.horizontal, 10)
                .frame(height: 38)
                .liquidGlassCapsule(isWhite: true)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(LiquidGlassButtonStyle())
            .disabled(selectedIdentifiers.isEmpty || isDeleting || isPreparingShare)
            .accessibilityLabel("分享所选照片")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .padding(.bottom, 22)
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

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: gridColumnCount >= 7 ? 11 : (gridColumnCount >= 5 ? 14 : 20), weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .padding(gridColumnCount >= 7 ? 2 : 4)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: gridColumnCount >= 7 ? 11 : (gridColumnCount >= 5 ? 14 : 20), weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: Color.black.opacity(0.45), radius: 1.5, x: 0, y: 1)
                        .padding(gridColumnCount >= 7 ? 2 : 4)
                }

                RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                    .stroke(
                        selected ? Color.white : Color.clear,
                        lineWidth: gridColumnCount >= 7 ? 1.2 : 2.2
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .gesture(libraryTileGesture(asset))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: PhotoTileFramePreferenceKey.self,
                        value: [
                            asset.localIdentifier: proxy.frame(
                                in: .named("photo-library-grid")
                            )
                        ]
                    )
                    .preference(
                        key: PhotoTileGlobalFramePreferenceKey.self,
                        value: [
                            asset.localIdentifier: proxy.frame(in: .global)
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
                        let sourceRect = tileGlobalFrames[asset.localIdentifier]
                        onSelect(asset, visibleAssets, sourceRect, tileGlobalFrames)
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

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = false) {
        guard !sortAscending, let lastID = visibleAssets.last?.localIdentifier else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
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

struct AssetThumbnail: View {
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

// MARK: - 照片浏览 (Photo Detail Browser / iOS 17 风格相册浏览 - 极速高性能 120 FPS 版)

struct FilmstripThumbnailView: View {
    let asset: PHAsset
    let isSelected: Bool
    @State private var image: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            GrainTheme.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: isSelected ? 32 : 24, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(Color.white, lineWidth: 2)
            }
        }
        .onAppear(perform: loadMiniThumbnail)
    }

    private func loadMiniThumbnail() {
        let key = asset.localIdentifier as NSString
        if let cached = Self.cache.object(forKey: key) {
            self.image = cached
            return
        }

        let targetSize = CGSize(width: 72, height: 108)
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result {
                Self.cache.setObject(result, forKey: key)
                self.image = result
            }
        }
    }
}

struct FilmstripBarView: View {
    let allAssets: [PHAsset]
    @Binding var currentIndex: Int

    @State private var isScrubbing = false
    @State private var dragStartIndex = 0

    var body: some View {
        ScrollViewReader { stripProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(0..<allAssets.count, id: \.self) { index in
                        let asset = allAssets[index]
                        let isSelected = index == currentIndex
                        FilmstripThumbnailView(asset: asset, isSelected: isSelected)
                            .id(asset.localIdentifier)
                            .onTapGesture {
                                currentIndex = index
                                GrainHaptics.selection(enabled: true)
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    stripProxy.scrollTo(asset.localIdentifier, anchor: .center)
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(filmstripDragGesture(stripProxy: stripProxy))
            .onChange(of: currentIndex) { _, newIndex in
                if !isScrubbing, newIndex >= 0, newIndex < allAssets.count {
                    let id = allAssets[newIndex].localIdentifier
                    withAnimation(.easeOut(duration: 0.2)) {
                        stripProxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onAppear {
                if currentIndex >= 0, currentIndex < allAssets.count {
                    stripProxy.scrollTo(allAssets[currentIndex].localIdentifier, anchor: .center)
                }
            }
        }
    }

    private func filmstripDragGesture(stripProxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isScrubbing {
                    isScrubbing = true
                    dragStartIndex = currentIndex
                }
                let step: CGFloat = 26.0
                let delta = -Int(round(value.translation.width / step))
                let targetIndex = max(0, min(allAssets.count - 1, dragStartIndex + delta))
                if targetIndex != currentIndex {
                    currentIndex = targetIndex
                    GrainHaptics.selection(enabled: true)
                    stripProxy.scrollTo(allAssets[targetIndex].localIdentifier, anchor: .center)
                }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.width - value.translation.width
                let extra = -Int(round(velocity / 80.0))
                let finalIndex = max(0, min(allAssets.count - 1, currentIndex + extra))
                if finalIndex != currentIndex {
                    currentIndex = finalIndex
                    GrainHaptics.selection(enabled: true)
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    stripProxy.scrollTo(allAssets[finalIndex].localIdentifier, anchor: .center)
                }
                isScrubbing = false
            }
    }
}

struct BrowserTopBarView: View {
    let date: Date?
    let formatLabel: String?
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Button {
                GrainHaptics.selection(enabled: true)
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text("相册")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(GrainTheme.paper)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .liquidGlassCapsule()
            }
            .buttonStyle(LiquidGlassButtonStyle())

            Spacer()

            if let date {
                VStack(spacing: 1) {
                    Text(formatDate(date))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                    Text(formatTime(date))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                }
            }

            Spacer()

            if let formatLabel {
                AssetFormatBadge(label: formatLabel)
            } else {
                Color.clear.frame(width: 44, height: 32)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct BrowserBottomBarView: View {
    let onDelete: () -> Void
    let onShare: () -> Void
    let onShowInfo: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Spacer()

            HStack(spacing: 18) {
                // 1. 删除
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GrainTheme.danger)
                        .liquidGlassCircle(size: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("删除照片")

                // 2. 分享
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .liquidGlassCircle(size: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("分享照片")

                // 3. 图片信息
                Button(action: onShowInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .liquidGlassCircle(size: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("查看照片信息")

                // 4. 编辑 (仅保留图标，无文字)
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .liquidGlassCircle(size: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("编辑照片")
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .padding(.bottom, 22)
    }
}

struct PhotoPagingViewControllerRepresentable: UIViewControllerRepresentable {
    let allAssets: [PHAsset]
    @Binding var currentIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [UIPageViewController.OptionsKey.interPageSpacing: 16]
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear

        if currentIndex >= 0 && currentIndex < allAssets.count {
            let initialVC = PhotoSinglePageVC(asset: allAssets[currentIndex], index: currentIndex)
            pvc.setViewControllers([initialVC], direction: .forward, animated: false)
        }
        return pvc
    }

    func updateUIViewController(_ uiViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard let currentVC = uiViewController.viewControllers?.first as? PhotoSinglePageVC else { return }
        if currentVC.index != currentIndex && currentIndex >= 0 && currentIndex < allAssets.count {
            let dir: UIPageViewController.NavigationDirection = currentIndex >= currentVC.index ? .forward : .reverse
            let newVC = PhotoSinglePageVC(asset: allAssets[currentIndex], index: currentIndex)
            uiViewController.setViewControllers([newVC], direction: dir, animated: false)
        }
    }

    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PhotoPagingViewControllerRepresentable

        init(_ parent: PhotoPagingViewControllerRepresentable) {
            self.parent = parent
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? PhotoSinglePageVC, page.index > 0 else { return nil }
            let prevIndex = page.index - 1
            return PhotoSinglePageVC(asset: parent.allAssets[prevIndex], index: prevIndex)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? PhotoSinglePageVC, page.index < parent.allAssets.count - 1 else { return nil }
            let nextIndex = page.index + 1
            return PhotoSinglePageVC(asset: parent.allAssets[nextIndex], index: nextIndex)
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            if completed, let current = pageViewController.viewControllers?.first as? PhotoSinglePageVC {
                if parent.currentIndex != current.index {
                    parent.currentIndex = current.index
                }
            }
        }
    }
}

class PhotoSinglePageVC: UIViewController {
    let asset: PHAsset
    let index: Int
    private let imageView = UIImageView()
    private let playIcon = UIImageView()
    private var requestID: PHImageRequestID?

    init(asset: PHAsset, index: Int) {
        self.asset = asset
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        if asset.mediaType == .video {
            let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .light)
            playIcon.image = UIImage(systemName: "play.circle.fill", withConfiguration: config)
            playIcon.tintColor = UIColor.white.withAlphaComponent(0.85)
            playIcon.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(playIcon)
            NSLayoutConstraint.activate([
                playIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                playIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        loadImage()
    }

    private func loadImage() {
        let scale = UIScreen.main.scale
        let screenBounds = UIScreen.main.bounds
        let targetSize = CGSize(
            width: screenBounds.width * scale,
            height: screenBounds.height * scale
        )

        // 先以快速模式取低清缩略图即时渲染（零延迟上屏）
        let fastOptions = PHImageRequestOptions()
        fastOptions.deliveryMode = .fastFormat
        fastOptions.resizeMode = .fast
        fastOptions.isNetworkAccessAllowed = false
        _ = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 320, height: 320),
            contentMode: .aspectFit,
            options: fastOptions
        ) { [weak self] img, _ in
            if let img, self?.imageView.image == nil {
                self?.imageView.image = img
            }
        }

        // 后台并发请求全高清屏幕适配图
        let fullOptions = PHImageRequestOptions()
        fullOptions.deliveryMode = .opportunistic
        fullOptions.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: fullOptions
        ) { [weak self] img, _ in
            if let img {
                self?.imageView.image = img
            }
        }
    }

    deinit {
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
    }
}

struct PhotoDetailBrowserView: View {
    let initialAsset: PHAsset
    let allAssets: [PHAsset]
    let library: PhotoLibraryViewModel
    let sourceRect: CGRect?
    let tileFrames: [String: CGRect]
    let onDismiss: () -> Void
    let onEdit: (PHAsset) -> Void
    let onShowInfo: (PHAsset) -> Void
    let onShare: (PHAsset) -> Void
    let onDelete: (PHAsset) -> Void

    @State private var currentIndex: Int
    @State private var showDeleteConfirm = false
    @State private var isPresented = false
    @State private var isClosing = false
    @State private var isDraggingDown = false
    @State private var dragTranslation: CGSize = .zero

    init(
        initialAsset: PHAsset,
        allAssets: [PHAsset],
        library: PhotoLibraryViewModel,
        sourceRect: CGRect? = nil,
        tileFrames: [String: CGRect] = [:],
        onDismiss: @escaping () -> Void,
        onEdit: @escaping (PHAsset) -> Void,
        onShowInfo: @escaping (PHAsset) -> Void,
        onShare: @escaping (PHAsset) -> Void,
        onDelete: @escaping (PHAsset) -> Void
    ) {
        self.initialAsset = initialAsset
        let list = allAssets.isEmpty ? [initialAsset] : allAssets
        self.allAssets = list
        self.library = library
        self.sourceRect = sourceRect
        self.tileFrames = tileFrames
        self.onDismiss = onDismiss
        self.onEdit = onEdit
        self.onShowInfo = onShowInfo
        self.onShare = onShare
        self.onDelete = onDelete
        let idx = list.firstIndex(where: { $0.localIdentifier == initialAsset.localIdentifier }) ?? 0
        _currentIndex = State(initialValue: idx)
    }

    private var currentAsset: PHAsset? {
        guard currentIndex >= 0 && currentIndex < allAssets.count else { return allAssets.first }
        return allAssets[currentIndex]
    }

    private struct BrowserGeometry {
        let offset: CGSize
        let scale: CGFloat
        let cornerRadius: CGFloat
        let opacity: Double
    }

    private func computeGeometry(screenSize: CGSize) -> BrowserGeometry {
        let screenCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        let currentTileRect = (currentAsset != nil ? tileFrames[currentAsset!.localIdentifier] : nil) ?? sourceRect

        if isClosing {
            if let rect = currentTileRect, rect.width > 20 && rect.height > 20 {
                let targetX = rect.midX - screenCenter.x
                let targetY = rect.midY - screenCenter.y
                let targetScale = rect.width / screenSize.width
                return BrowserGeometry(
                    offset: CGSize(width: targetX, height: targetY),
                    scale: targetScale,
                    cornerRadius: 3.5,
                    opacity: 0.0
                )
            } else {
                return BrowserGeometry(
                    offset: CGSize(width: 0, height: screenSize.height * 0.35),
                    scale: 0.82,
                    cornerRadius: 24.0,
                    opacity: 0.0
                )
            }
        }

        if !isPresented {
            if let rect = sourceRect, rect.width > 20 && rect.height > 20 {
                let initialX = rect.midX - screenCenter.x
                let initialY = rect.midY - screenCenter.y
                let initialScale = rect.width / screenSize.width
                return BrowserGeometry(
                    offset: CGSize(width: initialX, height: initialY),
                    scale: initialScale,
                    cornerRadius: 3.5,
                    opacity: 1.0
                )
            } else {
                return BrowserGeometry(
                    offset: CGSize(width: 0, height: 40),
                    scale: 0.90,
                    cornerRadius: 20.0,
                    opacity: 0.0
                )
            }
        }

        if isDraggingDown {
            let dy = max(0, dragTranslation.height)
            let dx = dragTranslation.width * 0.35
            let progress = min(1.0, dy / 320.0)
            let scale = max(0.65, 1.0 - progress * 0.35)
            let radius = min(28.0, progress * 28.0)
            let opacity = max(0.35, 1.0 - progress * 0.45)
            return BrowserGeometry(
                offset: CGSize(width: dx, height: dy),
                scale: scale,
                cornerRadius: radius,
                opacity: opacity
            )
        }

        return BrowserGeometry(
            offset: .zero,
            scale: 1.0,
            cornerRadius: 0.0,
            opacity: 1.0
        )
    }

    private var windowSafeAreaTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        let top = window?.safeAreaInsets.top ?? 0
        return top > 0 ? top : 54
    }

    private var windowSafeAreaBottom: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        let bottom = window?.safeAreaInsets.bottom ?? 0
        return bottom > 0 ? bottom : 34
    }

    var body: some View {
        GeometryReader { geo in
            let screenSize = geo.size
            let geom = computeGeometry(screenSize: screenSize)
            let dragProgress = min(1.0, max(0.0, dragTranslation.height / 320.0))
            let bgOpacity: Double = {
                if !isPresented || isClosing { return 0.0 }
                if isDraggingDown { return max(0.0, 1.0 - Double(dragProgress) * 0.95) }
                return 1.0
            }()
            let controlsOpacity: Double = {
                if !isPresented || isClosing { return 0.0 }
                if isDraggingDown { return max(0.0, 1.0 - Double(dragProgress) * 2.8) }
                return 1.0
            }()

            ZStack {
                GrainTheme.black
                    .opacity(bgOpacity)
                    .ignoresSafeArea()

                PhotoPagingViewControllerRepresentable(
                    allAssets: allAssets,
                    currentIndex: $currentIndex
                )
                .offset(geom.offset)
                .scaleEffect(geom.scale)
                .clipShape(RoundedRectangle(cornerRadius: geom.cornerRadius, style: .continuous))
                .opacity(geom.opacity)
                .shadow(
                    color: Color.black.opacity(geom.cornerRadius > 2 ? 0.35 * geom.opacity : 0),
                    radius: 16,
                    y: 8
                )
                .contentShape(Rectangle())
                .simultaneousGesture(downwardDragGesture)

                VStack(spacing: 0) {
                    BrowserTopBarView(
                        date: currentAsset?.creationDate,
                        formatLabel: currentAsset.flatMap { library.formatLabels[$0.localIdentifier] },
                        onDismiss: closeBrowser
                    )
                    .padding(.top, max(geo.safeAreaInsets.top, windowSafeAreaTop) + 4)

                    Spacer(minLength: 0)

                    FilmstripBarView(
                        allAssets: allAssets,
                        currentIndex: $currentIndex
                    )
                    .padding(.bottom, 6)

                    BrowserBottomBarView(
                        onDelete: { showDeleteConfirm = true },
                        onShare: { if let a = currentAsset { onShare(a) } },
                        onShowInfo: { if let a = currentAsset { onShowInfo(a) } },
                        onEdit: { if let a = currentAsset { onEdit(a) } }
                    )
                    .padding(.bottom, max(0, max(geo.safeAreaInsets.bottom, windowSafeAreaBottom) - 22))
                }
                .opacity(controlsOpacity)
                .allowsHitTesting(controlsOpacity > 0.5)
            }
            .ignoresSafeArea()
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        isPresented = true
                    }
                }
            }
        }
        .confirmationDialog(
            "确定要删除这张照片吗？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let asset = currentAsset {
                    performDelete(asset)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该照片将从图库中被移除。")
        }
    }

    private var downwardDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if !isDraggingDown {
                    if value.translation.height > 6 && abs(value.translation.height) > abs(value.translation.width) * 1.25 {
                        isDraggingDown = true
                    }
                }
                if isDraggingDown {
                    dragTranslation = CGSize(
                        width: value.translation.width,
                        height: max(0, value.translation.height)
                    )
                }
            }
            .onEnded { value in
                if isDraggingDown {
                    let velocityY = value.predictedEndTranslation.height - value.translation.height
                    if value.translation.height > 70 || velocityY > 140 {
                        closeBrowser()
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            dragTranslation = .zero
                            isDraggingDown = false
                        }
                    }
                }
            }
    }

    private func closeBrowser() {
        guard !isClosing else { return }
        GrainHaptics.selection(enabled: true)
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            isClosing = true
            isPresented = false
            isDraggingDown = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            onDismiss()
        }
    }

    private func performDelete(_ asset: PHAsset) {
        onDelete(asset)
        let remaining = allAssets.filter { $0.localIdentifier != asset.localIdentifier }
        if remaining.isEmpty {
            closeBrowser()
        } else {
            currentIndex = min(currentIndex, remaining.count - 1)
        }
    }
}
