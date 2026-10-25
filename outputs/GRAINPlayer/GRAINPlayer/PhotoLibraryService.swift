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

    /// 重新加载所有相册分类及当前选中的视频 (三级深度隐藏扫描 + 全后台异步，彻底杜绝主线程卡死)
    public func reloadAlbumsAndVideos() async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // 在分离式后台任务中执行 PhotoKit 枚举与检索
        let (albumList, current, hidden) = await Task.detached(priority: .userInitiated) { () -> ([AlbumCategory], [PHAsset], [PHAsset]) in
            // 1. 全局视频扫描 (显式开启 includeHiddenAssets = true)
            let allOptions = PHFetchOptions()
            allOptions.includeHiddenAssets = true
            allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let allVideosFetch = PHAsset.fetchAssets(with: .video, options: allOptions)

            var normalAssets: [PHAsset] = []
            var hiddenAssets: [PHAsset] = []
            var hiddenIds = Set<String>()

            allVideosFetch.enumerateObjects { asset, _, _ in
                if asset.isHidden {
                    hiddenAssets.append(asset)
                    hiddenIds.insert(asset.localIdentifier)
                } else {
                    normalAssets.append(asset)
                }
            }

            // 2. 检查 smartAlbumAllHidden 智能相册
            let hiddenFetch = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
            var hiddenCollection: PHAssetCollection? = nil

            hiddenFetch.enumerateObjects { collection, _, _ in
                hiddenCollection = collection
                let fetchOptions = PHFetchOptions()
                fetchOptions.includeHiddenAssets = true
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                let res = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                res.enumerateObjects { asset, _, _ in
                    if asset.mediaType == .video && !hiddenIds.contains(asset.localIdentifier) {
                        hiddenAssets.append(asset)
                        hiddenIds.insert(asset.localIdentifier)
                    }
                }
            }

            // 3. 扫描全部智能分类中的隐藏相册 (支持英文系统与各系统版本)
            let allSmart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            allSmart.enumerateObjects { collection, _, _ in
                let sub = collection.assetCollectionSubtype
                if sub == .smartAlbumAllHidden || collection.localizedTitle == "已隐藏" || collection.localizedTitle == "Hidden" {
                    if hiddenCollection == nil {
                        hiddenCollection = collection
                    }
                    let colOptions = PHFetchOptions()
                    colOptions.includeHiddenAssets = true
                    let res = PHAsset.fetchAssets(in: collection, options: colOptions)
                    res.enumerateObjects { asset, _, _ in
                        if asset.mediaType == .video && !hiddenIds.contains(asset.localIdentifier) {
                            hiddenAssets.append(asset)
                            hiddenIds.insert(asset.localIdentifier)
                        }
                    }
                }
            }

            var list: [AlbumCategory] = [
                AlbumCategory(id: "all_videos", title: "全部视频", icon: "video.fill", count: normalAssets.count)
            ]

            let hiddenCategory = AlbumCategory(
                id: "smart_album_hidden",
                title: "已隐藏",
                icon: "eye.slash.fill",
                isHiddenAlbum: true,
                collection: hiddenCollection,
                count: hiddenAssets.count
            )
            list.append(hiddenCategory)

            // 4. 常用智能分类
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

            // 5. 用户自建相册
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

            return (list, normalAssets, hiddenAssets)
        }.value

        self.albums = albumList
        self.currentAssets = current
        self.hiddenAssets = hidden
    }

    /// 切换选中的相册
    public func selectAlbum(id: String) async {
        selectedAlbumId = id
        if id == "smart_album_hidden" {
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

    /// 加载相册隐藏相册内的视频列表 (三级深度过滤，确保隐私视频完整呈现)
    public func loadHiddenAlbumVideos() async {
        let fetched: [PHAsset] = await Task.detached(priority: .userInitiated) {
            var hiddenAssets: [PHAsset] = []
            var hiddenIds = Set<String>()

            // 1. 全局视频扫描带 includeHiddenAssets = true 与 isHidden 过滤
            let allOptions = PHFetchOptions()
            allOptions.includeHiddenAssets = true
            allOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let allVideosFetch = PHAsset.fetchAssets(with: .video, options: allOptions)
            allVideosFetch.enumerateObjects { asset, _, _ in
                if asset.isHidden {
                    hiddenAssets.append(asset)
                    hiddenIds.insert(asset.localIdentifier)
                }
            }

            // 2. smartAlbumAllHidden 集合扫描
            let hiddenFetch = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumAllHidden, options: nil)
            hiddenFetch.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.includeHiddenAssets = true
                let res = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                res.enumerateObjects { asset, _, _ in
                    if asset.mediaType == .video && !hiddenIds.contains(asset.localIdentifier) {
                        hiddenAssets.append(asset)
                        hiddenIds.insert(asset.localIdentifier)
                    }
                }
            }

            // 3. 扫描全部智能分类中的隐藏相册
            let allSmart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
            allSmart.enumerateObjects { collection, _, _ in
                if collection.assetCollectionSubtype == .smartAlbumAllHidden || collection.localizedTitle == "已隐藏" || collection.localizedTitle == "Hidden" {
                    let colOptions = PHFetchOptions()
                    colOptions.includeHiddenAssets = true
                    let res = PHAsset.fetchAssets(in: collection, options: colOptions)
                    res.enumerateObjects { asset, _, _ in
                        if asset.mediaType == .video && !hiddenIds.contains(asset.localIdentifier) {
                            hiddenAssets.append(asset)
                            hiddenIds.insert(asset.localIdentifier)
                        }
                    }
                }
            }

            return hiddenAssets
        }.value

        self.hiddenAssets = fetched
    }

    /// 请求加载缩略图 (完全异步调度，杜绝视图重入死循环)
    @discardableResult
    public func requestThumbnail(for asset: PHAsset, targetSize: CGSize = CGSize(width: 320, height: 180), completion: @escaping (UIImage?) -> Void) -> PHImageRequestID? {
        let key = NSString(string: "\(asset.localIdentifier)_\(Int(targetSize.width))")
        if let cached = thumbnailCache.object(forKey: key) {
            // 命中内存缓存时立即同步交付，彻底根治滑动时的排队掉帧卡顿
            if Thread.isMainThread {
                completion(cached)
            } else {
                DispatchQueue.main.async { completion(cached) }
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
            if Thread.isMainThread {
                completion(image)
            } else {
                DispatchQueue.main.async {
                    completion(image)
                }
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

    /// 获取视频用于播放的 AVPlayerItem 与基础技术参数 (全格式硬件加速支持：H.264、HEVC、ProRes 等)
    public func preparePlayerItem(for item: VideoItem) async throws -> (AVPlayerItem, VideoMetadata) {
        guard case .photoLibrary(let localIdentifier, _, _) = item.source else {
            throw NSError(domain: "GRAINPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "非相册资产"])
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.includeHiddenAssets = true
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: fetchOptions)
        guard let asset = assets.firstObject else {
            throw NSError(domain: "GRAINPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "无法在相册中找到该视频资产"])
        }

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        // 策略 1: 优先使用 requestAVAsset 获取硬件解码原生地图，完美播放 H.264 与 HEVC
        do {
            let (avAsset, audioMix): (AVAsset, AVAudioMix?) = try await withCheckedThrowingContinuation { continuation in
                var hasResumed = false
                let lock = NSLock()

                imageManager.requestAVAsset(forVideo: asset, options: options) { loadedAsset, loadedMix, info in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !hasResumed else { return }

                    if let error = info?[PHImageErrorKey] as? Error {
                        hasResumed = true
                        continuation.resume(throwing: error)
                        return
                    }

                    if let loadedAsset {
                        hasResumed = true
                        continuation.resume(returning: (loadedAsset, loadedMix))
                        return
                    }

                    if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                        hasResumed = true
                        continuation.resume(throwing: NSError(domain: "GRAINPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "加载已取消"]))
                        return
                    }

                    hasResumed = true
                    continuation.resume(throwing: NSError(domain: "GRAINPlayer", code: -2, userInfo: [NSLocalizedDescriptionKey: "未获取到底层视频资产"]))
                }
            }

            let playerItem = AVPlayerItem(asset: avAsset)
            if let audioMix {
                playerItem.audioMix = audioMix
            }

            var meta = item.metadata
            meta.duration = asset.duration
            meta.naturalSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
            meta.creationDate = asset.creationDate ?? Date()

            return (playerItem, meta)
        } catch {
            // 策略 2: 兜底使用 requestPlayerItem
            return try await withCheckedThrowingContinuation { continuation in
                var hasResumed = false
                let lock = NSLock()

                let fallbackOptions = PHVideoRequestOptions()
                fallbackOptions.isNetworkAccessAllowed = true
                fallbackOptions.deliveryMode = .automatic

                imageManager.requestPlayerItem(forVideo: asset, options: fallbackOptions) { playerItem, info in
                    lock.lock()
                    defer { lock.unlock() }
                    guard !hasResumed else { return }

                    if let err = info?[PHImageErrorKey] as? Error {
                        hasResumed = true
                        continuation.resume(throwing: err)
                        return
                    }

                    if let playerItem {
                        hasResumed = true
                        var meta = item.metadata
                        meta.duration = asset.duration
                        meta.naturalSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
                        meta.creationDate = asset.creationDate ?? Date()
                        continuation.resume(returning: (playerItem, meta))
                        return
                    }

                    hasResumed = true
                    continuation.resume(throwing: error)
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
