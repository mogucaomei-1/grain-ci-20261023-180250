import AVFoundation
import Photos
import SwiftUI
import UIKit

// MARK: - 相册目录分类模型

public struct AlbumCategory: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let icon: String
    public let isHiddenAlbum: Bool
    public let collection: PHAssetCollection?
    public var count: Int

    public init(id: String, title: String, icon: String, isHiddenAlbum: Bool = false, collection: PHAssetCollection? = nil, count: Int = 0) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isHiddenAlbum = isHiddenAlbum
        self.collection = collection
        self.count = count
    }
}

// MARK: - 相册服务 (包含智能相册、用户相册及隐藏相册)

@MainActor
public final class PhotoLibraryService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    public static let shared = PhotoLibraryService()

    @Published public private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published public private(set) var albums: [AlbumCategory] = []
    @Published public private(set) var currentAlbumVideos: [VideoItem] = []
    @Published public private(set) var hiddenAlbumVideos: [VideoItem] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var selectedAlbumId: String = "all_videos"

    private let imageManager = PHCachingImageManager()
    private var cachedAssets: [String: PHAsset] = [:]

    public override init() {
        super.init()
        self.authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    public nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            await self?.reloadAlbumsAndVideos()
        }
    }

    /// 请求访问相册权限
    public func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authorizationStatus = status
        if status == .authorized || status == .limited {
            await reloadAlbumsAndVideos()
            return true
        }
        return false
    }

    /// 重新加载所有相册分类及当前选中的视频
    public func reloadAlbumsAndVideos() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 1. 获取所有视频数量
        let allVideosFetch = PHAsset.fetchAssets(with: .video, options: nil)
        var albumList: [AlbumCategory] = [
            AlbumCategory(id: "all_videos", title: "全部视频", icon: "video.fill", count: allVideosFetch.count)
        ]

        // 2. 获取智能相册 (最近、个人收藏、慢动作、延时、电影效果)
        let smartSubtypes: [(PHAssetCollectionSubtype, String, String)] = [
            (.smartAlbumRecentlyAdded, "最近项目", "clock.fill"),
            (.smartAlbumFavorites, "个人收藏", "heart.fill"),
            (.smartAlbumSlomoVideos, "慢动作", "slowmo"),
            (.smartAlbumTimelapses, "延时摄影", "timelapse"),
            (.smartAlbumCinematic, "电影效果", "film.fill")
        ]

        for (subtype, title, icon) in smartSubtypes {
            let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            result.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
                let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
                if count > 0 {
                    albumList.append(AlbumCategory(id: collection.localIdentifier, title: title, icon: icon, collection: collection, count: count))
                }
            }
        }

        // 3. 用户自建相册
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
            if count > 0 {
                albumList.append(AlbumCategory(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "相册",
                    icon: "folder.fill",
                    collection: collection,
                    count: count
                ))
            }
        }

        // 4. 核心：相册已隐藏相册 (smartAlbumAllHidden)
        let hiddenFetch = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
        var hiddenCount = 0
        var hiddenCollection: PHAssetCollection? = nil
        hiddenFetch.enumerateObjects { collection, _, _ in
            hiddenCollection = collection
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            hiddenCount = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
        }

        let hiddenCategory = AlbumCategory(
            id: "smart_album_hidden",
            title: "已隐藏",
            icon: "eye.slash.fill",
            isHiddenAlbum: true,
            collection: hiddenCollection,
            count: hiddenCount
        )
        albumList.append(hiddenCategory)

        self.albums = albumList

        // 加载当前选中相册的视频列表
        await loadVideosForSelectedAlbum()
        // 同时静默加载或更新隐藏相册数据
        await loadHiddenAlbumVideos(collection: hiddenCollection)
    }

    /// 切换选中的相册
    public func selectAlbum(id: String) async {
        selectedAlbumId = id
        await loadVideosForSelectedAlbum()
    }

    /// 加载当前相册的视频列表
    private func loadVideosForSelectedAlbum() async {
        guard let album = albums.first(where: { $0.id == selectedAlbumId }) else { return }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult: PHFetchResult<PHAsset>
        if album.id == "all_videos" {
            fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        } else if let collection = album.collection {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            fetchResult = PHAsset.fetchAssets(with: .video, options: options)
        }

        var items: [VideoItem] = []
        items.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { [weak self] asset, _, _ in
            guard let self else { return }
            self.cachedAssets[asset.localIdentifier] = asset

            let title = asset.value(forKey: "filename") as? String
                ?? "视频 \(FormatUtils.formatDate(asset.creationDate ?? Date()))"

            var meta = VideoMetadata()
            meta.duration = asset.duration
            meta.naturalSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
            meta.creationDate = asset.creationDate ?? Date()

            let item = VideoItem(
                id: asset.localIdentifier,
                title: title,
                source: .photoLibrary(localIdentifier: asset.localIdentifier, isHidden: album.isHiddenAlbum, albumTitle: album.title),
                metadata: meta
            )
            items.append(item)
        }

        self.currentAlbumVideos = items
    }

    /// 加载相册隐藏相册内的视频列表
    public func loadHiddenAlbumVideos(collection: PHAssetCollection? = nil) async {
        let col: PHAssetCollection?
        if let collection {
            col = collection
        } else {
            let hiddenFetch = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
            col = hiddenFetch.firstObject
        }

        guard let targetCollection = col else {
            self.hiddenAlbumVideos = []
            return
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(in: targetCollection, options: options)
        var items: [VideoItem] = []
        items.reserveCapacity(result.count)

        result.enumerateObjects { [weak self] asset, _, _ in
            guard let self else { return }
            self.cachedAssets[asset.localIdentifier] = asset

            let title = asset.value(forKey: "filename") as? String
                ?? "已隐藏视频 \(FormatUtils.formatDate(asset.creationDate ?? Date()))"

            var meta = VideoMetadata()
            meta.duration = asset.duration
            meta.naturalSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
            meta.creationDate = asset.creationDate ?? Date()

            let item = VideoItem(
                id: asset.localIdentifier,
                title: title,
                source: .photoLibrary(localIdentifier: asset.localIdentifier, isHidden: true, albumTitle: "已隐藏"),
                metadata: meta
            )
            items.append(item)
        }

        self.hiddenAlbumVideos = items
    }

    /// 请求加载高清或缩略图
    public func requestThumbnail(for item: VideoItem, targetSize: CGSize = CGSize(width: 400, height: 400), completion: @escaping (UIImage?) -> Void) {
        guard case .photoLibrary(let localIdentifier, _, _) = item.source,
              let asset = cachedAssets[localIdentifier] ?? PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            completion(nil)
            return
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast

        imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            completion(image)
        }
    }

    /// 获取视频用于播放的 AVPlayerItem 与精准技术参数
    public func preparePlayerItem(for item: VideoItem) async throws -> (AVPlayerItem, VideoMetadata) {
        guard case .photoLibrary(let localIdentifier, _, _) = item.source,
              let asset = cachedAssets[localIdentifier] ?? PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            throw NSError(domain: "GRAINPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "无法在相册中找到该视频资产"])
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        return try await withCheckedThrowingContinuation { continuation in
            imageManager.requestPlayerItem(forVideo: asset, options: options) { playerItem, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let playerItem else {
                    continuation.resume(throwing: NSError(domain: "GRAINPlayer", code: 500, userInfo: [NSLocalizedDescriptionKey: "加载相册视频流失败"]))
                    return
                }

                Task {
                    var metadata = item.metadata
                    if let avAsset = playerItem.asset as? AVURLAsset {
                        metadata = await VideoMetadataExtractor.extract(from: avAsset, fallbackDuration: asset.duration)
                    }
                    continuation.resume(returning: (playerItem, metadata))
                }
            }
        }
    }

    /// 从相册中删除视频 (带系统确认提示)
    public func deleteVideo(item: VideoItem) async throws {
        guard case .photoLibrary(let localIdentifier, _, _) = item.source,
              let asset = cachedAssets[localIdentifier] ?? PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "GRAINPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "相册视频删除未完成"]))
                }
            }
        }
    }
}
