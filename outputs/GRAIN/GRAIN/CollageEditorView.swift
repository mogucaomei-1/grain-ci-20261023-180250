import Photos
import PhotosUI
import SwiftUI
import UIKit

enum CollageDirection: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vertical: "纵向拼图"
        case .horizontal: "横向拼图"
        }
    }

    var symbol: String {
        switch self {
        case .vertical: "rectangle.split.1x2"
        case .horizontal: "rectangle.split.2x1"
        }
    }
}

struct CollageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAssets: [PHAsset]
    @State private var direction: CollageDirection = .vertical
    @State private var previewImages: [String: UIImage] = [:]
    @State private var isLoading = true
    @State private var isRendering = false
    @State private var exportURL: URL?
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickerError: String?
    @State private var notice: String?
    @State private var errorMessage: String?

    init(assets: [PHAsset]) {
        _selectedAssets = State(initialValue: Array(assets.prefix(10)))
        _isLoading = State(initialValue: !assets.isEmpty)
    }

    var body: some View {
        ZStack {
            GrainBackground()

            VStack(spacing: 0) {
                topBar
                collagePreview
                controls
            }
            .padding(.bottom, 8)

            if isLoading || isRendering {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(GrainTheme.paper)
                    Text(isRendering ? "正在生成拼图" : "正在读取照片")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.78), in: Capsule())
            }

            if let notice {
                VStack {
                    Text(notice)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.black)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(GrainTheme.paper, in: Capsule())
                        .padding(.top, 62)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .statusBarHidden()
        .task {
            await loadPreviewImages()
        }
        .onChange(of: pickerItems) { _, items in
            Task { await addPickedAssets(items) }
        }
        .onDisappear {
            if let exportURL {
                try? FileManager.default.removeItem(at: exportURL)
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareURL = nil }) {
            if let shareURL {
                GrainShareSheet(items: [shareURL])
                    .ignoresSafeArea()
            }
        }
        .alert(
            "拼图处理失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "无法添加照片",
            isPresented: Binding(
                get: { pickerError != nil },
                set: { if !$0 { pickerError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(pickerError ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 36, height: 36)
                    .background(GrainTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("拼图")
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(GrainTheme.paper)
                Text("\(selectedAssets.count) 张 · 最多 10 张")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(GrainTheme.muted)
            }

            Spacer()

            if selectedAssets.count < 10 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, 10 - selectedAssets.count),
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(GrainTheme.raised, in: Capsule())
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrainTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(GrainTheme.raised, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var collagePreview: some View {
        GeometryReader { proxy in
            let count = max(selectedAssets.count, 1)
            let gap: CGFloat = 2
            let horizontalWidth = (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            let verticalHeight = (proxy.size.height - gap * CGFloat(count - 1)) / CGFloat(count)
            let horizontalCell = min(horizontalWidth, proxy.size.height)
            let verticalCell = min(verticalHeight, proxy.size.width)

            Group {
                if selectedAssets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(GrainTheme.muted)
                        Text("添加照片开始制作拼图")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                        PhotosPicker(
                            selection: $pickerItems,
                            maxSelectionCount: 10,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text("从照片图库添加")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(GrainTheme.black)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(GrainTheme.paper, in: Capsule())
                        }
                    }
                } else if direction == .horizontal {
                    HStack(spacing: gap) {
                        ForEach(selectedAssets, id: \.localIdentifier) { asset in
                            collageCell(asset)
                                .frame(width: horizontalCell, height: horizontalCell)
                        }
                    }
                } else {
                    VStack(spacing: gap) {
                        ForEach(selectedAssets, id: \.localIdentifier) { asset in
                            collageCell(asset)
                                .frame(width: verticalCell, height: verticalCell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(GrainTheme.line, lineWidth: 0.8)
        }
        .padding(.horizontal, 12)
    }

    private func collageCell(_ asset: PHAsset) -> some View {
        ZStack {
            GrainTheme.surface
            if let image = previewImages[asset.localIdentifier] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(GrainTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(CollageDirection.allCases) { option in
                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            direction = option
                        }
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.symbol)
                            Text(option.title)
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            direction == option ? GrainTheme.black : GrainTheme.muted
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            direction == option ? GrainTheme.paper : GrainTheme.raised,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || isRendering)
                }
            }

            HStack(spacing: 10) {
                Button {
                    saveToLibrary()
                } label: {
                    Label("存到图库", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(GrainTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isLoading || isRendering || selectedAssets.isEmpty)

                Button {
                    prepareShare()
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(GrainTheme.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(GrainTheme.paper, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isLoading || isRendering || selectedAssets.isEmpty)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    @MainActor
    private func loadPreviewImages() async {
        guard !selectedAssets.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        for asset in selectedAssets where previewImages[asset.localIdentifier] == nil {
            let image = await CollageImageLoader.image(
                for: asset,
                targetSize: CGSize(width: 900, height: 900)
            )
            if let image {
                previewImages[asset.localIdentifier] = image
            }
        }
        isLoading = false
    }

    @MainActor
    private func addPickedAssets(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        let identifiers = items.compactMap(\.itemIdentifier)
        let fetched = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )
        var lookup: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in
            lookup[asset.localIdentifier] = asset
        }
        let additions = identifiers.compactMap { lookup[$0] }.filter { asset in
            !selectedAssets.contains {
                $0.localIdentifier == asset.localIdentifier
            }
        }
        guard !additions.isEmpty else {
            pickerError = "没有找到可添加的照片，请重新选择。"
            pickerItems = []
            return
        }
        selectedAssets.append(contentsOf: additions.prefix(10 - selectedAssets.count))
        pickerItems = []
        await loadPreviewImages()
    }

    private func saveToLibrary() {
        guard !isRendering else { return }
        isRendering = true
        errorMessage = nil

        Task {
            do {
                let url = try await renderCollage()
                try await saveCollageToLibrary(url)
                replaceExportURL(with: url)
                showNotice("拼图已保存到照片图库")
            } catch {
                errorMessage = error.localizedDescription
            }
            isRendering = false
        }
    }

    private func prepareShare() {
        guard !isRendering else { return }
        isRendering = true
        errorMessage = nil

        Task {
            do {
                let url = try await renderCollage()
                replaceExportURL(with: url)
                shareURL = url
                showShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isRendering = false
        }
    }

    private func renderCollage() async throws -> URL {
        let assets = selectedAssets
        let selectedDirection = direction
        guard !assets.isEmpty, assets.count <= 10 else {
            throw CollageError.invalidPhotoCount
        }

        let maxLongEdge: CGFloat = 6000
        let gap = max(3, maxLongEdge / CGFloat(assets.count) * 0.008)
        let cellSize = min(
            1800,
            floor((maxLongEdge - gap * CGFloat(assets.count - 1)) / CGFloat(assets.count))
        )
        guard cellSize >= 320 else {
            throw CollageError.renderFailed
        }

        var images: [UIImage] = []
        images.reserveCapacity(assets.count)
        for asset in assets {
            guard let image = await CollageImageLoader.image(
                for: asset,
                targetSize: CGSize(width: cellSize, height: cellSize)
            ) else {
                throw CollageError.imageUnavailable
            }
            images.append(image)
        }

        let totalLength = cellSize * CGFloat(assets.count)
            + gap * CGFloat(assets.count - 1)
        let outputSize = selectedDirection == .horizontal
            ? CGSize(width: totalLength, height: cellSize)
            : CGSize(width: cellSize, height: totalLength)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let collage = renderer.image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: outputSize))

            for (index, image) in images.enumerated() {
                let origin = selectedDirection == .horizontal
                    ? CGPoint(x: CGFloat(index) * (cellSize + gap), y: 0)
                    : CGPoint(x: 0, y: CGFloat(index) * (cellSize + gap))
                let rect = CGRect(
                    origin: origin,
                    size: CGSize(width: cellSize, height: cellSize)
                )
                drawAspectFill(image, in: rect, context: context.cgContext)
            }
        }

        guard let data = collage.jpegData(compressionQuality: 1.0) else {
            throw CollageError.renderFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GRAIN-collage-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func drawAspectFill(
        _ image: UIImage,
        in rect: CGRect,
        context: CGContext
    ) {
        let scale = max(
            rect.width / max(image.size.width, 1),
            rect.height / max(image.size.height, 1)
        )
        let drawSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    private func saveCollageToLibrary(_ url: URL) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) {
                    continuation.resume(returning: $0 == .authorized || $0 == .limited)
                }
            }
            guard granted else { throw CollageError.photoLibraryDenied }
        } else if status != .authorized, status != .limited {
            throw CollageError.photoLibraryDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "GRAIN-collage.jpg"
                options.uniformTypeIdentifier = "public.jpeg"
                request.addResource(with: .photo, fileURL: url, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? CollageError.saveFailed
                    )
                }
            }
        }
    }

    private func showNotice(_ text: String) {
        withAnimation(.easeOut(duration: 0.16)) {
            notice = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeIn(duration: 0.16)) {
                notice = nil
            }
        }
    }

    private func replaceExportURL(with url: URL) {
        if let exportURL, exportURL != url {
            try? FileManager.default.removeItem(at: exportURL)
        }
        exportURL = url
    }
}

private enum CollageImageLoader {
    static func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let gate = CollageImageContinuation(continuation)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.version = .current
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                    return
                }
                gate.finish(image)
            }
        }
    }
}

private final class CollageImageContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: image)
    }
}

private enum CollageError: LocalizedError {
    case invalidPhotoCount
    case imageUnavailable
    case renderFailed
    case photoLibraryDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidPhotoCount:
            "请选择 1 到 10 张照片制作拼图。"
        case .imageUnavailable:
            "部分照片无法从 iCloud 读取，请检查网络后重试。"
        case .renderFailed:
            "无法生成拼图，请减少照片数量后重试。"
        case .photoLibraryDenied:
            "请在系统设置中允许 GRAIN 向照片图库添加照片。"
        case .saveFailed:
            "拼图保存失败，请检查存储空间后重试。"
        }
    }
}

struct GrainShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
