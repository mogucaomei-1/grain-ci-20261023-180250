import CoreGraphics
import Foundation
import Photos
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 导出落点：系统相册 / 文件
enum ExportDestination: Equatable {
    case photos
    case files
}

enum ExportError: LocalizedError {
    case photoLibraryDenied
    case photoLibraryWriteFailed

    var errorDescription: String? {
        switch self {
        case .photoLibraryDenied:
            "没有相册写入权限，请在系统设置中允许 GRAIN 添加照片。"
        case .photoLibraryWriteFailed:
            "写入相册失败，请检查存储空间后重试。"
        }
    }
}

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var photo: PhotoAsset?
    @Published private(set) var originalPreview: CGImage?
    @Published private(set) var fullGradedPreview: CGImage?
    @Published private(set) var editedPreview: CGImage?
    /// 放大查看时按需解码的全尺寸原图（带当前胶片/裁剪/马赛克），
    /// 平时为 nil，避免长期占用几十到上百 MB 内存
    @Published private(set) var zoomPreview: CGImage?
    @Published private(set) var histogram: RGBHistogram?
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecommending = false
    @Published private(set) var isRecommendationApplied = false
    @Published private(set) var isAdjustmentRecommendationApplied = false
    @Published private(set) var canUndo = false
    @Published private(set) var isExporting = false
    @Published var selectedProfile: FilmProfile = .portra
    @Published var settings: FilmSettings = FilmProfile.portra.factorySettings
    @Published var intensity = 0.82
    @Published var exportOptions = ExportOptions()
    @Published var crop = CropTransform.identity
    @Published var textOverlays: [PhotoTextOverlay] = []
    @Published var mosaicStrokes: [MosaicStroke] = []
    @Published var errorMessage: String?
    @Published var exportResult: ExportResult?
    /// 导出目标的执行状态：相册 / 文件
    @Published private(set) var exportDestination: ExportDestination = .photos
    /// 结果页用来区分「已保存到相册」与「已生成文件」
    @Published private(set) var exportSavedToAlbum = false
    /// 需要弹出系统分享（存储到文件）时使用
    @Published var exportShareURL: URL?
    @Published var noticeMessage: String?
    /// 当前照片对应的系统相册标识；从文件导入时为 nil
    @Published var sourceAssetIdentifier: String?
    /// 当前照片的相册资源，用于实况播放等能力判断
    @Published private(set) var libraryAsset: PHAsset?

    private var previewTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    /// 文件导出完成后暂存，等分享面板关闭再展示结果页
    private var pendingFileExport: ExportResult?
    private var recipeSaveTask: Task<Void, Never>?
    private var recipeIdentity: String?
    private var noticeTask: Task<Void, Never>?
    private var sourcePreview: CGImage?
    private var zoomPreviewTask: Task<Void, Never>?
    private var previewNeedsUpdate = false
    private var previewGeneration = 0
    private var undoStack: [EditorSnapshot] = []
    private var recommendationBaseline: EditorSnapshot?
    private var adjustmentRecommendationBaseline: AdjustmentRecommendationBaseline?

    var canExport: Bool {
        photo != nil && !isPreparing && !isExporting
    }

    /// 系统相册照片的稳定标识：接入后按它恢复上次编辑
    func attachLibraryAssetIdentifier(_ identifier: String) {
        sourceAssetIdentifier = identifier
        libraryAsset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject
        let identity = RecipeIdentity.library(identifier)
        guard identity != recipeIdentity else { return }
        recipeIdentity = identity
        restoreRecipe(identity: identity)
        schedulePreview()
    }

    /// 当前照片对应的相册资源（文件导入时为 nil）
    var currentPHAsset: PHAsset? {
        libraryAsset
    }

    var hasLivePhoto: Bool {
        libraryAsset?.mediaSubtypes.contains(.photoLive) == true
    }

    /// 当前编辑结果，供批量套用与批量导出使用
    var currentRecipe: PhotoRecipe? {
        guard photo != nil else { return nil }
        return PhotoRecipe(
            profile: selectedProfile,
            settings: settings,
            intensity: intensity,
            crop: crop,
            overlays: textOverlays,
            mosaics: mosaicStrokes,
            updatedAt: Date()
        )
    }

    /// 用当前画面取样，把该点校成中性灰
    func pickWhiteBalance(atNormalizedPoint point: CGPoint) {
        guard let image = originalPreview ?? sourcePreview else { return }
        guard let sample = AdvancedGrade.sampleColor(
            from: image,
            normalizedX: point.x,
            normalizedY: point.y
        ) else {
            showNotice("取样区域太暗，换一个位置再试")
            return
        }
        recordUndoSnapshot()
        let gains = AdvancedGrade.whiteBalanceGains(forSample: sample)
        settings.whiteBalanceRed = gains.red
        settings.whiteBalanceGreen = gains.green
        settings.whiteBalanceBlue = gains.blue
        markManualAdjustment()
        schedulePreview()
        showNotice("已按取样点校正白平衡")
    }

    func resetAdvancedGrade() {
        guard settings.hasAdvancedGrade else { return }
        recordUndoSnapshot()
        settings.curve = FilmSettings.identityCurve
        settings.hueShift = FilmSettings.neutralHSL
        settings.saturationShift = FilmSettings.neutralHSL
        settings.luminanceShift = FilmSettings.neutralHSL
        settings.whiteBalanceRed = 1
        settings.whiteBalanceGreen = 1
        settings.whiteBalanceBlue = 1
        markManualAdjustment()
        schedulePreview()
        showNotice("已重置曲线、HSL 与取样白平衡")
    }

    func selectProfile(_ profile: FilmProfile) {
        recordUndoSnapshot()
        recommendationBaseline = nil
        adjustmentRecommendationBaseline = nil
        withAnimation(.snappy(duration: 0.25)) {
            selectedProfile = profile
            settings = profile.factorySettings
            intensity = profile == .neutral ? 1 : 0.82
            isRecommendationApplied = false
            isAdjustmentRecommendationApplied = false
        }
        schedulePreview()
    }

    func returnHome(discardingRecipe: Bool = false) {
        if discardingRecipe {
            if let recipeIdentity {
                RecipeStore.shared.remove(identity: recipeIdentity)
            }
        } else {
            saveRecipeImmediately()
        }
        recipeSaveTask?.cancel()
        recipeSaveTask = nil
        recipeIdentity = nil
        previewTask?.cancel()
        importTask?.cancel()
        previewTask = nil
        previewNeedsUpdate = false
        previewGeneration += 1
        photo = nil
        sourcePreview = nil
        originalPreview = nil
        fullGradedPreview = nil
        editedPreview = nil
        zoomPreview = nil
        zoomPreviewTask?.cancel()
        zoomPreviewTask = nil
        histogram = nil
        crop = .identity
        textOverlays = []
        mosaicStrokes = []
        exportResult = nil
        errorMessage = nil
        isPreparing = false
        isExporting = false
        isRecommendationApplied = false
        isAdjustmentRecommendationApplied = false
        undoStack.removeAll()
        recommendationBaseline = nil
        adjustmentRecommendationBaseline = nil
        canUndo = false
        sourceAssetIdentifier = nil
        libraryAsset = nil
    }

    func resetSelectedProfile() {
        recordUndoSnapshot()
        recommendationBaseline = nil
        adjustmentRecommendationBaseline = nil
        withAnimation(.snappy(duration: 0.25)) {
            settings = selectedProfile.factorySettings
            intensity = selectedProfile == .neutral ? 1 : 0.82
            isRecommendationApplied = false
            isAdjustmentRecommendationApplied = false
        }
        schedulePreview()
    }

    func resetAllAdjustments() {
        recordUndoSnapshot()
        recommendationBaseline = nil
        adjustmentRecommendationBaseline = nil
        withAnimation(.snappy(duration: 0.25)) {
            selectedProfile = .neutral
            settings = FilmProfile.neutral.factorySettings
            intensity = 1
            isRecommendationApplied = false
            isAdjustmentRecommendationApplied = false
        }
        schedulePreview()
    }

    func recommendLook() {
        if isRecommendationApplied {
            cancelRecommendationLook()
            return
        }
        guard let originalPreview, !isRecommending else { return }
        recommendationBaseline = currentSnapshot
        adjustmentRecommendationBaseline = nil
        recordUndoSnapshot()
        isRecommending = true

        Task {
            let recommendation = await Task.detached(priority: .userInitiated) {
                LocalLookAdvisor.recommend(from: originalPreview)
            }.value

            withAnimation(.snappy(duration: 0.24)) {
                selectedProfile = recommendation.profile
                settings = recommendation.settings
                intensity = recommendation.intensity
                isRecommendationApplied = true
                isAdjustmentRecommendationApplied = false
            }
            schedulePreview()
            isRecommending = false
        }
    }

    func recommendAdjustmentsOnly() {
        if isAdjustmentRecommendationApplied {
            cancelAdjustmentRecommendation()
            return
        }
        guard let originalPreview, !isRecommending else { return }
        let profile = selectedProfile
        let baselineSettings = settings
        let baselineIntensity = intensity
        adjustmentRecommendationBaseline = AdjustmentRecommendationBaseline(
            settings: baselineSettings,
            intensity: baselineIntensity
        )
        recommendationBaseline = nil
        recordUndoSnapshot()
        isRecommending = true

        Task {
            let recommendation = await Task.detached(priority: .userInitiated) {
                LocalLookAdvisor.recommend(from: originalPreview)
            }.value
            guard selectedProfile == profile else {
                isRecommending = false
                return
            }

            var adjusted = profile.factorySettings
            let reference = recommendation.profile.factorySettings
            adjusted.exposure = (adjusted.exposure + recommendation.settings.exposure - reference.exposure)
                .clamped(to: -2...2)
            adjusted.temperature = (adjusted.temperature + recommendation.settings.temperature - reference.temperature)
                .clamped(to: 3500...9000)
            adjusted.tint = (adjusted.tint + recommendation.settings.tint - reference.tint)
                .clamped(to: -100...100)
            adjusted.highlights = (adjusted.highlights + recommendation.settings.highlights - reference.highlights)
                .clamped(to: -100...100)
            adjusted.shadows = (adjusted.shadows + recommendation.settings.shadows - reference.shadows)
                .clamped(to: -100...100)
            adjusted.whites = (adjusted.whites + recommendation.settings.whites - reference.whites)
                .clamped(to: -100...100)
            adjusted.blacks = (adjusted.blacks + recommendation.settings.blacks - reference.blacks)
                .clamped(to: -100...100)
            adjusted.contrast = (adjusted.contrast + recommendation.settings.contrast - reference.contrast)
                .clamped(to: -100...100)
            adjusted.vibrance = (adjusted.vibrance + recommendation.settings.vibrance - reference.vibrance)
                .clamped(to: -100...100)
            adjusted.saturation = (adjusted.saturation + recommendation.settings.saturation - reference.saturation)
                .clamped(to: -100...100)
            adjusted.clarity = (adjusted.clarity + recommendation.settings.clarity - reference.clarity)
                .clamped(to: -100...100)
            adjusted.sharpness = (adjusted.sharpness + recommendation.settings.sharpness - reference.sharpness)
                .clamped(to: 0...100)
            adjusted.fade = (adjusted.fade + recommendation.settings.fade - reference.fade)
                .clamped(to: 0...100)
            adjusted.grain = (adjusted.grain + recommendation.settings.grain - reference.grain)
                .clamped(to: 0...100)
            adjusted.vignette = (adjusted.vignette + recommendation.settings.vignette - reference.vignette)
                .clamped(to: 0...100)

            withAnimation(.snappy(duration: 0.24)) {
                settings = adjusted
                isRecommendationApplied = false
                isAdjustmentRecommendationApplied = true
            }
            schedulePreview()
            isRecommending = false
        }
    }

    func copyPreset() {
        guard photo != nil else { return }
#if canImport(UIKit)
        do {
            let preset = PresetClipboard(
                profile: selectedProfile,
                settings: settings,
                intensity: intensity
            )
            let data = try JSONEncoder().encode(preset)
            UIPasteboard.general.string = "GRAIN-PRESET-V1:\(data.base64EncodedString())"
            showNotice("已复制当前调色预设")
        } catch {
            errorMessage = "复制预设失败：\(error.localizedDescription)"
        }
#endif
    }

    func pastePreset() {
#if canImport(UIKit)
        guard let text = UIPasteboard.general.string,
              text.hasPrefix("GRAIN-PRESET-V1:"),
              let data = Data(base64Encoded: String(text.dropFirst("GRAIN-PRESET-V1:".count))),
              let preset = try? JSONDecoder().decode(PresetClipboard.self, from: data),
              preset.version == 1
        else {
            errorMessage = "剪贴板中没有可用的 GRAIN 调色预设。"
            return
        }

        recordUndoSnapshot()
        recommendationBaseline = nil
        adjustmentRecommendationBaseline = nil
        withAnimation(.snappy(duration: 0.24)) {
            selectedProfile = preset.profile
            settings = preset.settings
            intensity = preset.intensity
            isRecommendationApplied = false
            isAdjustmentRecommendationApplied = false
        }
        schedulePreview()
        showNotice("已粘贴预设 · \(preset.profile.name)")
#endif
    }

    func updateCrop(_ newCrop: CropTransform) {
        recordUndoSnapshot()
        crop = newCrop
        isRecommendationApplied = false
        recommendationBaseline = nil
        isAdjustmentRecommendationApplied = false
        adjustmentRecommendationBaseline = nil
        schedulePreview()
    }

    @discardableResult
    func addTextOverlay() -> UUID {
        recordUndoSnapshot()
        var overlay = PhotoTextOverlay()
        overlay.y = 0.68
        textOverlays.append(overlay)
        return overlay.id
    }

    func updateTextOverlay(_ overlay: PhotoTextOverlay) {
        guard let index = textOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        recordUndoSnapshot()
        textOverlays[index] = overlay
        scheduleRecipeSave()
    }

    func moveTextOverlay(id: UUID, x: Double, y: Double) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        textOverlays[index].x = min(max(x, 0.04), 0.96)
        textOverlays[index].y = min(max(y, 0.04), 0.96)
        scheduleRecipeSave()
    }

    func deleteTextOverlay(id: UUID) {
        recordUndoSnapshot()
        textOverlays.removeAll { $0.id == id }
        scheduleRecipeSave()
    }

    func addMosaicStroke(_ stroke: MosaicStroke) {
        guard !stroke.points.isEmpty else { return }
        recordUndoSnapshot()
        mosaicStrokes.append(stroke)
        isRecommendationApplied = false
        isAdjustmentRecommendationApplied = false
        adjustmentRecommendationBaseline = nil
        schedulePreview()
    }

    func clearMosaicStrokes() {
        guard !mosaicStrokes.isEmpty else { return }
        recordUndoSnapshot()
        mosaicStrokes = []
        schedulePreview()
    }

    func markManualAdjustment() {
        isRecommendationApplied = false
        recommendationBaseline = nil
        isAdjustmentRecommendationApplied = false
        adjustmentRecommendationBaseline = nil
    }

    func recordUndoSnapshot() {
        let snapshot = currentSnapshot
        guard undoStack.last != snapshot else { return }
        undoStack.append(snapshot)
        if undoStack.count > 40 {
            undoStack.removeFirst()
        }
        canUndo = true
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        withAnimation(.snappy(duration: 0.24)) {
            selectedProfile = snapshot.profile
            settings = snapshot.settings
            intensity = snapshot.intensity
            crop = snapshot.crop
            textOverlays = snapshot.overlays
            mosaicStrokes = snapshot.mosaics
            isRecommendationApplied = snapshot.recommendationApplied
        }
        canUndo = !undoStack.isEmpty
        recommendationBaseline = nil
        isAdjustmentRecommendationApplied = false
        adjustmentRecommendationBaseline = nil
        schedulePreview()
    }

    func schedulePreview() {
        scheduleRecipeSave()
        guard sourcePreview != nil else { return }
        previewNeedsUpdate = true
        guard previewTask == nil else { return }

        let generation = previewGeneration
        previewTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.previewGeneration == generation {
                guard self.previewNeedsUpdate, let sourcePreview = self.sourcePreview else { break }
                self.previewNeedsUpdate = false
                let profile = self.selectedProfile
                let settings = self.settings
                let intensity = self.intensity
                let suppressVignette = self.photo?.isLikelyScreenshot ?? false
                let crop = self.crop
                let mosaics = self.mosaicStrokes

                do {
                    let rendered = try await Task.detached(priority: .userInitiated) {
                        let edited = try RawImageProcessor.renderGradedPreview(
                            source: sourcePreview,
                            profile: profile,
                            settings: settings,
                            intensity: intensity,
                            suppressVignette: suppressVignette
                        )
                        let cropped = CropProcessor.apply(crop, to: edited)
                        let mosaicked = MosaicProcessor.apply(mosaics, to: cropped)
                        return (
                            full: edited,
                            edited: mosaicked,
                            histogram: LocalLookAdvisor.histogram(from: mosaicked)
                        )
                    }.value
                    guard !Task.isCancelled, self.previewGeneration == generation else { break }
                    self.fullGradedPreview = rendered.full
                    self.editedPreview = rendered.edited
                    self.histogram = rendered.histogram
                } catch {
                    if !Task.isCancelled {
                        self.errorMessage = error.localizedDescription
                    }
                    break
                }
            }

            if self.previewGeneration == generation {
                self.previewTask = nil
                if self.previewNeedsUpdate {
                    self.schedulePreview()
                }
            }
        }
    }

    func importPhoto(from incomingURL: URL) {
        errorMessage = nil
        isPreparing = true
        exportResult = nil
        previewTask?.cancel()
        previewTask = nil
        previewNeedsUpdate = false
        previewGeneration += 1

        let supportedExtensions = [
            "arw", "srf", "sr2", "dng", "jpg", "jpeg",
            "heic", "heif", "png", "tif", "tiff"
        ]
        guard supportedExtensions.contains(incomingURL.pathExtension.lowercased()) else {
            isPreparing = false
            errorMessage = "请选择 Sony ARW、DNG、HEIC 或 JPEG 图片。"
            return
        }

        let accessed = incomingURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                incomingURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let localURL = try copyIntoLibrary(incomingURL)
            let asset = try RawImageProcessor.metadata(for: localURL)
            let quickPreview = try RawImageProcessor.renderQuickPreview(from: localURL)

            sourcePreview = quickPreview
            originalPreview = quickPreview
            fullGradedPreview = nil
            editedPreview = nil
            histogram = nil
            crop = .identity
            textOverlays = []
            mosaicStrokes = []
            selectedProfile = .neutral
            settings = FilmProfile.neutral.factorySettings
            intensity = 1
            photo = asset
            recipeIdentity = RecipeIdentity.file(asset)
            restoreRecipe(identity: recipeIdentity, notify: false)
            exportOptions.keepLocation = asset.hasLocation
            undoStack.removeAll()
            recommendationBaseline = nil
            adjustmentRecommendationBaseline = nil
            canUndo = false
            isRecommendationApplied = false
            isAdjustmentRecommendationApplied = false
            isPreparing = false
            schedulePreview()

            importTask?.cancel()
            let generation = previewGeneration
            importTask = Task {
                do {
                    let source = try await Task.detached(priority: .userInitiated) {
                        try RawImageProcessor.renderSourcePreview(from: localURL)
                    }.value
                    guard !Task.isCancelled, previewGeneration == generation else { return }

                    sourcePreview = source
                    originalPreview = source
                    schedulePreview()
                } catch {
                    guard !Task.isCancelled else { return }
                    if incomingURL.pathExtension.lowercased().contains("arw") {
                        noticeMessage = "已显示快速预览，但当前 iOS 无法解码该 RAW 的全尺寸图像。"
                    }
                }
            }
        } catch {
            isPreparing = false
            errorMessage = error.localizedDescription
        }
    }

    func export(to destination: ExportDestination = .photos) {
        guard let photo, !isExporting else { return }
        isExporting = true
        errorMessage = nil
        exportDestination = destination
        exportSavedToAlbum = false
        exportShareURL = nil

        let profile = selectedProfile
        let settings = settings
        let intensity = intensity
        let options = exportOptions
        let crop = crop
        let textOverlays = textOverlays
        let mosaicStrokes = mosaicStrokes
        let format = options.format
        let stem = makeExportStem(for: photo, profile: profile)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(stem)
            .appendingPathExtension(format.fileExtension)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try RawImageProcessor.export(
                        from: photo.url,
                        profile: profile,
                        settings: settings,
                        intensity: intensity,
                        options: options,
                        crop: crop,
                        mosaicStrokes: mosaicStrokes,
                        textOverlays: textOverlays,
                        to: outputURL
                    )
                }.value

                switch destination {
                case .photos:
                    try await Self.saveToPhotoLibrary(result.url)
                    exportSavedToAlbum = true
                    exportResult = result
                case .files:
                    pendingFileExport = result
                    exportShareURL = result.url
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    /// 文件导出的系统分享面板关闭后，切到结果页
    func finishFileExportSharing() {
        exportShareURL = nil
        guard let pending = pendingFileExport else { return }
        pendingFileExport = nil
        exportResult = pending
    }

    /// 把导出的成品写入系统相册（只申请「添加照片」权限）
    private static func saveToPhotoLibrary(_ fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoLibraryDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: fileURL, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? ExportError.photoLibraryWriteFailed)
                }
            }
        }
    }

    func renderFullResolutionDisplay() async throws -> CGImage {
        guard let photo else {
            throw ImageProcessorError.cannotOpenFile
        }
        let profile = selectedProfile
        let settings = settings
        let intensity = intensity
        let crop = crop
        let mosaics = mosaicStrokes

        return try await Task.detached(priority: .userInitiated) {
            try RawImageProcessor.renderFullResolutionDisplay(
                from: photo.url,
                profile: profile,
                settings: settings,
                intensity: intensity,
                crop: crop,
                mosaicStrokes: mosaics
            )
        }.value
    }

    /// 编辑页放大查看时调用：按当前编辑参数解码全尺寸原图，
    /// 用原图像素替换 1280px 的预览，放大后不再发糊。
    func prepareZoomPreview() {
        guard photo != nil, zoomPreview == nil else { return }
        zoomPreviewTask?.cancel()
        zoomPreviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await self.renderFullResolutionDisplay()
                guard !Task.isCancelled else { return }
                self.zoomPreview = image
            } catch {
                // 全尺寸解码失败（例如个别 RAW 不支持）时退回预览，不打断操作
            }
        }
    }

    /// 退出放大时释放全尺寸图，避免常驻大内存
    func releaseZoomPreview() {
        zoomPreviewTask?.cancel()
        zoomPreviewTask = nil
        zoomPreview = nil
    }

    // MARK: - 编辑配方持久化

    private func restoreRecipe(identity: String?, notify: Bool = true) {
        guard let identity, let recipe = RecipeStore.shared.load(identity: identity) else { return }
        selectedProfile = recipe.profile
        settings = recipe.settings
        intensity = recipe.intensity
        crop = recipe.crop
        textOverlays = recipe.overlays
        mosaicStrokes = recipe.mosaics
        isRecommendationApplied = false
        isAdjustmentRecommendationApplied = false
        recommendationBaseline = nil
        adjustmentRecommendationBaseline = nil
        if notify, recipe.profile != .neutral || recipe.settings.hasAdvancedGrade {
            showNotice("已恢复上次编辑 · \(recipe.summary)")
        }
    }

    private func scheduleRecipeSave() {
        guard recipeIdentity != nil, photo != nil else { return }
        recipeSaveTask?.cancel()
        recipeSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.saveRecipeImmediately()
        }
    }

    private func saveRecipeImmediately() {
        guard let identity = recipeIdentity, let recipe = currentRecipe else { return }
        RecipeStore.shared.save(recipe, identity: identity)
    }

    private func copyIntoLibrary(_ sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let imports = root.appendingPathComponent("GRAIN/Imports", isDirectory: true)
        try fileManager.createDirectory(at: imports, withIntermediateDirectories: true)

        let originalExtension = sourceURL.pathExtension.isEmpty ? "raw" : sourceURL.pathExtension
        let destination = imports
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(originalExtension)

        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            // The shared photo picker may already return a file-backed provider URL.
            // If a copy races with provider cleanup, retry once after reading the bytes.
            let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
            try data.write(to: destination, options: .atomic)
        }
        return destination
    }

    private func makeExportStem(for photo: PhotoAsset, profile: FilmProfile) -> String {
        let cleanName = photo.displayName
            .replacingOccurrences(of: #"[^A-Za-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let prefix = cleanName.isEmpty ? "GRAIN" : cleanName
        let look = profile.shortName.lowercased()
        return "\(prefix)-\(look)-fullres"
    }

    private func showNotice(_ text: String, duration: Double = 2.8) {
        noticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            noticeMessage = text
        }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                noticeMessage = nil
            }
        }
    }

    private var currentSnapshot: EditorSnapshot {
        EditorSnapshot(
            profile: selectedProfile,
            settings: settings,
            intensity: intensity,
            crop: crop,
            overlays: textOverlays,
            mosaics: mosaicStrokes,
            recommendationApplied: isRecommendationApplied
        )
    }

    private func cancelRecommendationLook() {
        guard let recommendationBaseline else {
            isRecommendationApplied = false
            return
        }
        withAnimation(.snappy(duration: 0.24)) {
            selectedProfile = recommendationBaseline.profile
            settings = recommendationBaseline.settings
            intensity = recommendationBaseline.intensity
            isRecommendationApplied = false
        }
        self.recommendationBaseline = nil
        schedulePreview()
    }

    private func cancelAdjustmentRecommendation() {
        guard let baseline = adjustmentRecommendationBaseline else {
            isAdjustmentRecommendationApplied = false
            return
        }
        withAnimation(.snappy(duration: 0.24)) {
            settings = baseline.settings
            intensity = baseline.intensity
            isAdjustmentRecommendationApplied = false
        }
        adjustmentRecommendationBaseline = nil
        schedulePreview()
    }
}

private struct AdjustmentRecommendationBaseline {
    let settings: FilmSettings
    let intensity: Double
}

private struct EditorSnapshot: Equatable {
    let profile: FilmProfile
    let settings: FilmSettings
    let intensity: Double
    let crop: CropTransform
    let overlays: [PhotoTextOverlay]
    let mosaics: [MosaicStroke]
    let recommendationApplied: Bool
}
