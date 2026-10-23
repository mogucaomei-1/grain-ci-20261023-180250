import Combine
import Foundation
import Photos

/// 批量导出：逐张读取原图、套用同一份配方导出，再写回系统相册。
/// 顺序执行 + autoreleasepool，避免多张高像素照片同时常驻内存。
@MainActor
final class BatchExportViewModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var currentName = ""
    @Published private(set) var summary: String?
    @Published private(set) var errorMessage: String?

    private var worker: Task<Void, Never>?

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    func start(
        assets: [PHAsset],
        recipe: PhotoRecipe,
        options: ExportOptions
    ) {
        guard !isRunning, !assets.isEmpty else { return }
        isRunning = true
        completed = 0
        total = assets.count
        summary = nil
        errorMessage = nil
        currentName = ""

        worker = Task { [weak self] in
            guard let self else { return }
            var failures: [String] = []
            for (index, asset) in assets.enumerated() {
                if Task.isCancelled { break }
                self.currentName = Self.displayName(for: asset)
                do {
                    try await self.exportOne(asset: asset, recipe: recipe, options: options)
                } catch is CancellationError {
                    break
                } catch {
                    failures.append(self.currentName)
                }
                self.completed = index + 1
            }

            self.isRunning = false
            self.currentName = ""
            if failures.isEmpty {
                self.summary = "已导出 \(self.completed) 张照片"
            } else {
                self.summary = "完成 \(self.completed - failures.count) 张，失败 \(failures.count) 张"
            }
        }
    }

    func cancel() {
        worker?.cancel()
        worker = nil
        isRunning = false
        currentName = ""
    }

    func clearSummary() {
        summary = nil
        completed = 0
        total = 0
    }

    private func exportOne(
        asset: PHAsset,
        recipe: PhotoRecipe,
        options: ExportOptions
    ) async throws {
        let originalURL = try await PhotoLibraryAssetLoader.loadOriginal(asset: asset)
        defer { try? FileManager.default.removeItem(at: originalURL) }
        try Task.checkCancellation()

        let stem = "GRAIN-batch-\(UUID().uuidString.prefix(8))"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(stem)
            .appendingPathExtension(options.format.fileExtension)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let profile = recipe.profile
        let settings = recipe.settings
        let intensity = recipe.intensity
        let crop = recipe.crop
        let mosaics = recipe.mosaics
        let overlays = recipe.overlays

        try await Task.detached(priority: .userInitiated) {
            _ = try RawImageProcessor.export(
                from: originalURL,
                profile: profile,
                settings: settings,
                intensity: intensity,
                options: options,
                crop: crop,
                mosaicStrokes: mosaics,
                textOverlays: overlays,
                to: outputURL
            )
        }.value
        try Task.checkCancellation()

        let savedURL = FileManager.default.fileExists(atPath: outputURL.path)
            ? outputURL
            : outputURL.deletingPathExtension().appendingPathExtension("jpg")
        try await addToPhotoLibrary(savedURL)
    }

    private func addToPhotoLibrary(_ fileURL: URL) async throws {
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
                    continuation.resume(
                        throwing: error ?? NSError(
                            domain: "GRAIN.BatchExport",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "写回相册失败"]
                        )
                    )
                }
            }
        }
    }

    private static func displayName(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        if let name = resources.first?.originalFilename, !name.isEmpty {
            return name
        }
        if let date = asset.creationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            return formatter.string(from: date)
        }
        return "照片"
    }
}
