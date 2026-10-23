import Photos
import SwiftUI
import UIKit

@MainActor
final class PhotoLibraryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var isLoading = false
    @Published private(set) var accessDenied = false
    @Published private(set) var isDownloadingOriginal = false
    private var hasLoaded = false

    override init() {
        super.init()
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
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var fetchedAssets: [PHAsset] = []
        fetchedAssets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            fetchedAssets.append(asset)
        }
        assets = fetchedAssets
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

private enum PhotoLibraryAssetLoader {
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

struct PhotoLibraryHome: View {
    @ObservedObject var library: PhotoLibraryViewModel
    let onSelect: (PHAsset) -> Void
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
    @State private var shareError: String?
    @State private var deleteError: String?
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var lastSelectionDragPoint: CGPoint?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            if isSelecting {
                selectionToolbar
            } else {
                HStack {
                    Spacer()
                    if !library.assets.isEmpty {
                        Text("\(library.assets.count)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(GrainTheme.muted)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }

            if library.accessDenied {
                permissionView
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(library.assets, id: \.localIdentifier) { asset in
                            libraryTile(asset)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 24)
                    .coordinateSpace(name: "photo-library-grid")
                    .onPreferenceChange(PhotoTileFramePreferenceKey.self) {
                        tileFrames = $0
                    }
                    .simultaneousGesture(selectionDragGesture)
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
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(.black.opacity(0.74), in: Capsule())
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
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Button("取消") {
                endSelection()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(GrainTheme.paper)
            .buttonStyle(.plain)

            Text("已选择 \(selectedIdentifiers.count) 张")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.accent)

            Spacer()

            Button {
                shareSelectedAssets()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享")
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(
                    !selectedIdentifiers.isEmpty
                        ? GrainTheme.accent
                        : GrainTheme.muted
                )
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedIdentifiers.isEmpty || isDeleting || isPreparingShare)
            .accessibilityLabel("分享所选照片")

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        selectedIdentifiers.isEmpty ? GrainTheme.muted : GrainTheme.accent
                    )
                    .frame(width: 32, height: 28)
                    .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedIdentifiers.isEmpty || isDeleting)
            .accessibilityLabel("删除所选照片")
        }
        .padding(.horizontal, 12)
        .padding(.top, 3)
        .padding(.bottom, 5)
    }

    private var statusText: String {
        if isPreparingShare { return "正在准备分享" }
        if isDeleting { return "正在删除照片" }
        if library.isDownloadingOriginal { return "正在从 iCloud 下载原图" }
        return "正在载入照片"
    }

    private func libraryTile(_ asset: PHAsset) -> some View {
        let selected = selectedIdentifiers.contains(asset.localIdentifier)

        return ZStack(alignment: .topTrailing) {
            AssetThumbnail(asset: asset)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .id(asset.localIdentifier)

            if isSelecting {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(selected ? 0.22 : 0.04))

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        selected ? GrainTheme.paper : Color.white.opacity(0.86),
                        selected ? GrainTheme.accent : Color.black.opacity(0.34)
                    )
                    .padding(6)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(
                        selected ? GrainTheme.accent : Color.clear,
                        lineWidth: 2
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
                            .font(.system(size: 17, weight: .light))
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
