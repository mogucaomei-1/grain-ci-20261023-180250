import AVFoundation
import Foundation
import SwiftUI
import UIKit

// MARK: - 本地文件目录与私密保险箱管理服务

@MainActor
public final class FileManagerService: ObservableObject {
    public static let shared = FileManagerService()

    @Published public private(set) var rootVideos: [VideoItem] = []
    @Published public private(set) var folders: [VideoFolder] = []
    @Published public private(set) var vaultVideos: [VideoItem] = []
    @Published public private(set) var currentFolderVideos: [VideoItem] = []
    @Published public private(set) var currentFolder: VideoFolder? = nil
    @Published public private(set) var isLoading: Bool = false

    /// 支持的视频扩展名集合
    public static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "ts", "wmv", "3gp"
    ]

    private let fileManager = FileManager.default

    public var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public var videosDirectory: URL {
        documentsDirectory.appendingPathComponent("Videos", isDirectory: true)
    }

    public var vaultDirectory: URL {
        documentsDirectory.appendingPathComponent(".vault", isDirectory: true)
    }

    public init() {
        createDefaultDirectoriesIfNeeded()
    }

    private func createDefaultDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
    }

    /// 重新扫描本地文件、文件夹及私密保险箱
    public func reloadAll() async {
        isLoading = true
        defer { isLoading = false }

        createDefaultDirectoriesIfNeeded()

        // 1. 加载文件夹
        var fetchedFolders: [VideoFolder] = []
        if let folderUrls = try? fileManager.contentsOfDirectory(at: videosDirectory, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey], options: [.skipsHiddenFiles]) {
            for url in folderUrls {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    let items = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    let videoCount = items.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }.count
                    let createdDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

                    fetchedFolders.append(VideoFolder(
                        name: url.lastPathComponent,
                        url: url,
                        itemCount: videoCount,
                        createdDate: createdDate
                    ))
                }
            }
        }
        self.folders = fetchedFolders.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })

        // 2. 加载 Videos 根目录下的视频
        self.rootVideos = await loadVideos(in: videosDirectory, isVault: false)

        // 3. 加载当前文件夹下的视频（若有选中）
        if let currentFolder {
            self.currentFolderVideos = await loadVideos(in: currentFolder.url, isVault: false)
        } else {
            self.currentFolderVideos = self.rootVideos
        }

        // 4. 加载私密保险箱视频
        self.vaultVideos = await loadVideos(in: vaultDirectory, isVault: true)
    }

    /// 扫描指定目录下的视频
    private func loadVideos(in directory: URL, isVault: Bool) async -> [VideoItem] {
        guard let fileUrls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: isVault ? [] : [.skipsHiddenFiles]
        ) else { return [] }

        var items: [VideoItem] = []
        for url in fileUrls {
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }

            let asset = AVURLAsset(url: url)
            let meta = await VideoMetadataExtractor.extract(from: asset, fileURL: url)

            let title = url.deletingPathExtension().lastPathComponent
            let item = VideoItem(
                id: url.path,
                title: title,
                source: .fileDirectory(url: url, isVault: isVault),
                metadata: meta
            )
            items.append(item)
        }

        return items.sorted(by: { $0.metadata.creationDate > $1.metadata.creationDate })
    }

    /// 切换当前文件夹
    public func enterFolder(_ folder: VideoFolder?) async {
        currentFolder = folder
        if let folder {
            currentFolderVideos = await loadVideos(in: folder.url, isVault: false)
        } else {
            currentFolderVideos = rootVideos
        }
    }

    /// 创建新文件夹
    public func createFolder(named name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let folderURL = videosDirectory.appendingPathComponent(trimmed, isDirectory: true)
        guard !fileManager.fileExists(atPath: folderURL.path) else {
            throw NSError(domain: "GRAINPlayer", code: 409, userInfo: [NSLocalizedDescriptionKey: "同名文件夹已存在"])
        }

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        GrainHaptics.success()
    }

    /// 删除文件夹
    public func deleteFolder(_ folder: VideoFolder) throws {
        try fileManager.removeItem(at: folder.url)
        GrainHaptics.medium()
    }

    /// 重命名文件夹
    public func renameFolder(_ folder: VideoFolder, newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != folder.name else { return }

        let targetURL = folder.url.deletingLastPathComponent().appendingPathComponent(trimmed, isDirectory: true)
        try fileManager.moveItem(at: folder.url, to: targetURL)
        GrainHaptics.success()
    }

    /// 导入外部文件（来自系统文件选择器，处理安全访问书签）
    public func importExternalFile(from sourceURL: URL, toFolder: VideoFolder? = nil, moveToVault: Bool = false) async throws {
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let targetDir = moveToVault ? vaultDirectory : (toFolder?.url ?? videosDirectory)
        var fileName = sourceURL.lastPathComponent
        var destinationURL = targetDir.appendingPathComponent(fileName)

        // 避免文件名冲突
        var counter = 1
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        while fileManager.fileExists(atPath: destinationURL.path) {
            fileName = "\(baseName)_\(counter).\(ext)"
            destinationURL = targetDir.appendingPathComponent(fileName)
            counter += 1
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        GrainHaptics.success()
        await reloadAll()
    }

    /// 移入私密保险箱
    public func moveToVault(item: VideoItem) async throws {
        guard case .fileDirectory(let url, let isVault) = item.source, !isVault else { return }

        let destinationURL = vaultDirectory.appendingPathComponent(url.lastPathComponent)
        try fileManager.moveItem(at: url, to: destinationURL)
        GrainHaptics.success()
        await reloadAll()
    }

    /// 从私密保险箱移出到常规文件目录
    public func moveOutOfVault(item: VideoItem, toFolder: VideoFolder? = nil) async throws {
        guard case .fileDirectory(let url, let isVault) = item.source, isVault else { return }

        let targetDir = toFolder?.url ?? videosDirectory
        let destinationURL = targetDir.appendingPathComponent(url.lastPathComponent)
        try fileManager.moveItem(at: url, to: destinationURL)
        GrainHaptics.success()
        await reloadAll()
    }

    /// 删除文件
    public func deleteVideo(item: VideoItem) async throws {
        guard case .fileDirectory(let url, _) = item.source else { return }
        try fileManager.removeItem(at: url)
        GrainHaptics.medium()
        await reloadAll()
    }

    /// 重命名文件
    public func renameVideo(item: VideoItem, newTitle: String) async throws {
        guard case .fileDirectory(let url, _) = item.source else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ext = url.pathExtension
        let newFileName = ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
        let targetURL = url.deletingLastPathComponent().appendingPathComponent(newFileName)

        try fileManager.moveItem(at: url, to: targetURL)
        GrainHaptics.success()
        await reloadAll()
    }

    /// 生成视频缩略图
    public func generateThumbnail(for url: URL, time: CMTime = .zero) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)

        return try? await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, error in
                if let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
