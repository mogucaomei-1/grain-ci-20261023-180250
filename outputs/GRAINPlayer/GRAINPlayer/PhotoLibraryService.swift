import AVFoundation
import LocalAuthentication
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

// MARK: - 生物识别与隐私认证服务 (Face ID / Touch ID / 设备密码)

@MainActor
public final class BiometricAuthService: ObservableObject {
    public static let shared = BiometricAuthService()

    @Published public private(set) var isUnlocked: Bool = false
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var biometricName: String = "面容 ID"

    public init() {
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch ctx.biometryType {
            case .faceID:
                biometricName = "面容 ID"
            case .touchID:
                biometricName = "触控 ID"
            case .opticID:
                biometricName = "Optic ID"
            default:
                biometricName = "生物识别"
            }
        } else {
            biometricName = "设备密码"
        }
    }

    /// 请求 Face ID / 密码认证解锁隐藏相册
    @discardableResult
    public func authenticate(reason: String = "验证身份以访问相册「已隐藏」视频") async -> Bool {
        if isUnlocked { return true }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var authError: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &authError) else {
            // 若设备未设置任何密码或生物识别，直接允许访问
            self.isUnlocked = true
            return true
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success {
                        self?.isUnlocked = true
                        continuation.resume(returning: true)
                    } else {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    public func lock() {
        isUnlocked = false
    }
}

// MARK: - 高性能相册服务 (全后台异步并发扫描、零主线程阻塞与智能隐藏直读)

@MainActor
public final class PhotoLibraryService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    public static let shared = PhotoLibraryService()

    @Published public private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published public private(set) var albums: [AlbumCategory] = []
    @Published public private(set) var currentAssets: [PHAsset] = []
    @Published public private(set) var hiddenAssets: [PHAsset] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var selectedAlbumId: String = "all_videos"

    private let imageManager = PHCachingImageManager()
    private let thumbnailCache = NSCache<NSString, UIImage>()

    public override init() {
        super.init()
        thumbnailCache.countLimit = 300 // 最多缓存 300 张缩略图
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

    /// 重新加载所有相册分类及当前选中的视频 (全后台异步并发，彻底杜绝主线程卡死)
    public func reloadAlbumsAndVideos() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 在分离式后台任务中执行 PhotoKit 枚举与检索
        let (albumList, current, hidden) = await Task.detached(priority: .userInitiated) { () -> ([AlbumCategory], [PHAsset], [PHAsset]) in
            // 1. 全部视频 (按创建时间倒序)
            let allOptions = PHFetchOptions()
            allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let allVideosFetch = PHAsset.fetchAssets(with: .video, options: allOptions)

            var list: [AlbumCategory] = [
                AlbumCategory(id: "all_videos", title: "全部视频", icon: "video.fill", count: allVideosFetch.count)
            ]

            // 2. 核心：相册已隐藏相册 (smartAlbumAllHidden + 全局 includeHiddenAssets 检索)
            let hiddenFetch = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
            var hiddenCount = 0
            var hiddenCollection: PHAssetCollection? = nil
            var hiddenAssets: [PHAsset] = []

            hiddenFetch.enumerateObjects { collection, _, _ in
                hiddenCollection = collection
                let fetchOptions = PHFetchOptions()
                fetchOptions.includeHiddenAssets = true // 必须启用隐藏资产包含
                fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let res = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                hiddenCount = res.count
                res.enumerateObjects { asset, _, _ in
                    hiddenAssets.append(asset)
                }
            }

            // 兜底策略：如果 smartAlbumAllHidden 集合未被系统直接返回，使用包含隐藏属性的全局检索
            if hiddenAssets.isEmpty {
                let backupOptions = PHFetchOptions()
                backupOptions.includeHiddenAssets = true
                backupOptions.predicate = NSPredicate(format: "mediaType == %d AND isHidden == YES", PHAssetMediaType.video.rawValue)
                backupOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let backupResult = PHAsset.fetchAssets(with: backupOptions)
                hiddenCount = backupResult.count
                backupResult.enumerateObjects { asset, _, _ in
                    hiddenAssets.append(asset)
                }
            }

            let hiddenCategory = AlbumCategory(
                id: "smart_album_hidden",
                title: "已隐藏",
                icon: "eye.slash.fill",
                isHiddenAlbum: true,
                collection: hiddenCollection,
                count: hiddenCount
            )
            list.append(hiddenCategory)

            // 3. 常用智能分类
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
                        list.append(AlbumCategory(id: collection.localIdentifier, title: title, icon: icon, collection: collection, count: count))
                    }
                }
            }

            // 4. 用户自建相册
            let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            userAlbums.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
                let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
                if count > 0 {
                    list.append(AlbumCategory(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "相册",
                        icon: "folder.fill",
                        collection: collection,
                        count: count
                    ))
                }
            }

            // 5. 将“全部视频”游标轻量转换
            var allAssets: [PHAsset] = []
            allAssets.reserveCapacity(allVideosFetch.count)
            allVideosFetch.enumerateObjects { asset, _, _ in
                allAssets.append(asset)
            }

            return (list, allAssets, hiddenAssets)
        }.value

        self.albums = albumList
        self.currentAssets = current
        self.hiddenAssets = hidden
    }

    /// 切换选中的相册
    public func selectAlbum(id: String) async {
        selectedAlbumId = id
        if id == "smart_album_hidden" {
            // 已预取隐藏相册资产，必要时后台重新载入一次
            await loadHiddenAlbumVideos()
            return
        }
        await loadVideosForSelectedAlbum()
    }

    /// 高性能后台加载当前相册的视频列表
    private func loadVideosForSelectedAlbum() async {
        guard let album = albums.first(where: { $0.id == selectedAlbumId }) else { return }

        let fetched: [PHAsset] = await Task.detached(priority: .userInitiated) {
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

            var list: [PHAsset] = []
            list.reserveCapacity(fetchResult.count)
            fetchResult.enumerateObjects { asset, _, _ in
                list.append(asset)
            }
            return list
        }.value

        self.currentAssets = fetched
    }

    /// 加载相册隐藏相册内的视频列表 (带 includeHiddenAssets = true 与双重兜底)
    public func loadHiddenAlbumVideos(collection: PHAssetCollection? = nil) async {
        let fetched: [PHAsset] = await Task.detached(priority: .userInitiated) {
            var fetchedAssets: [PHAsset] = []

            let col: PHAssetCollection?
            if let collection {
                col = collection
            } else {
                let hiddenFetch = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
                col = hiddenFetch.firstObject
            }

            if let col {
                let options = PHFetchOptions()
                options.includeHiddenAssets = true
                options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let result = PHAsset.fetchAssets(in: col, options: options)
                result.enumerateObjects { asset, _, _ in
                    fetchedAssets.append(asset)
                }
            }

            if fetchedAssets.isEmpty {
                let backupOptions = PHFetchOptions()
                backupOptions.includeHiddenAssets = true
                backupOptions.predicate = NSPredicate(format: "mediaType == %d AND isHidden == YES", PHAssetMediaType.video.rawValue)
                backupOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let backupResult = PHAsset.fetchAssets(with: backupOptions)
                backupResult.enumerateObjects { asset, _, _ in
                    fetchedAssets.append(asset)
                }
            }

            return fetchedAssets
        }.value

        self.hiddenAssets = fetched
    }

    /// 请求加载缩略图 (完全异步调度，杜绝视图重入死循环)
    @discardableResult
    public func requestThumbnail(for asset: PHAsset, targetSize: CGSize = CGSize(width: 320, height: 180), completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let key = NSString(string: "\(asset.localIdentifier)_\(Int(targetSize.width))")
        if let cached = thumbnailCache.object(forKey: key) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return nil
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        return imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { [weak self] image, info in
            guard let image else { return }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !isDegraded {
                self?.thumbnailCache.setObject(image, forKey: key)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    public func cancelThumbnailRequest(_ id: PHImageRequestID) {
        imageManager.cancelImageRequest(id)
    }

    /// 构建轻量级 VideoItem 模型 (避免提前解析大图)
    public func makeVideoItem(from asset: PHAsset, isHidden: Bool = false, albumTitle: String? = nil) -> VideoItem {
        let title = "视频 · \(FormatUtils.formatDate(asset.creationDate ?? Date()))"
        var meta = VideoMetadata()
        meta.duration = asset.duration
        meta.naturalSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        meta.creationDate = asset.creationDate ?? Date()

        return VideoItem(
            id: asset.localIdentifier,
            title: title,
            source: .photoLibrary(localIdentifier: asset.localIdentifier, isHidden: isHidden, albumTitle: albumTitle),
            metadata: meta
        )
    }

    /// 获取视频用于播放的 AVPlayerItem 与精准技术参数 (支持已隐藏相册直读)
    public func preparePlayerItem(for item: VideoItem) async throws -> (AVPlayerItem, VideoMetadata) {
        guard case .photoLibrary(let localIdentifier, _, _) = item.source else {
            throw NSError(domain: "GRAINPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "非相册资产"])
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = true // 必须启用隐藏资产包含，否则相册隐藏视频返回空
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: fetchOptions)
        guard let asset = assets.firstObject else {
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

    /// 从相册中删除视频
    public func deleteAsset(_ asset: PHAsset) async throws {
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
