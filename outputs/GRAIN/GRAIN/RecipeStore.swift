import Foundation

/// 一张照片的完整编辑配方（胶片、参数、裁剪、文字、马赛克）。
/// 持久化后重新打开同一张照片会自动恢复。
struct PhotoRecipe: Codable, Equatable, Sendable {
    var version = 1
    var profile: FilmProfile
    var settings: FilmSettings
    var intensity: Double
    var crop: CropTransform
    var overlays: [PhotoTextOverlay]
    var mosaics: [MosaicStroke]
    var updatedAt: Date

    var isNeutral: Bool {
        profile == .neutral
            && abs(intensity - 1) < 0.001
            && crop.isIdentity
            && overlays.isEmpty
            && mosaics.isEmpty
            && !settings.hasAdvancedGrade
            && settings == FilmProfile.neutral.factorySettings
    }

    var summary: String {
        let look = profile == .neutral ? "原始" : profile.name
        return "\(look) · 强度 \(Int(intensity * 100))%"
    }
}

enum RecipeIdentity {
    /// 系统相册资源：直接按 localIdentifier 做稳定哈希
    static func library(_ identifier: String) -> String {
        "asset-" + stableHash(identifier)
    }

    /// 文件导入：没有稳定 ID，用尺寸 + 文件大小 + 拍摄时间构建指纹
    static func file(_ asset: PhotoAsset) -> String {
        let stamp = asset.capturedAt?.timeIntervalSince1970 ?? 0
        let seed = [
            String(asset.pixelWidth),
            String(asset.pixelHeight),
            String(asset.fileSize),
            String(format: "%.0f", stamp),
            asset.url.pathExtension.lowercased()
        ].joined(separator: "-")
        return "file-" + stableHash(seed)
    }

    /// FNV-1a 64 位：跨启动稳定，不依赖哈希随机化
    static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}

/// 编辑配方的本地仓库：Application Support/GRAIN/Recipes/<identity>.json
final class RecipeStore: @unchecked Sendable {
    static let shared = RecipeStore()

    private let queue = DispatchQueue(label: "studio.grain.recipe-store", qos: .utility)
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let latestFileName = "latest.json"

    init(directory: URL? = nil) {
        let resolved: URL
        if let directory {
            resolved = directory
        } else {
            let root = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            resolved = root.appendingPathComponent("GRAIN/Recipes", isDirectory: true)
        }
        self.directory = resolved
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try? FileManager.default.createDirectory(
            at: resolved,
            withIntermediateDirectories: true
        )
    }

    func load(identity: String) -> PhotoRecipe? {
        queue.sync {
            guard let data = try? Data(contentsOf: url(for: identity)) else { return nil }
            guard let recipe = try? decoder.decode(PhotoRecipe.self, from: data) else { return nil }
            return recipe.version == 1 ? recipe : nil
        }
    }

    func save(_ recipe: PhotoRecipe, identity: String) {
        var stamped = recipe
        stamped.version = 1
        stamped.updatedAt = Date()
        queue.async { [directory, encoder, latestFileName] in
            guard let data = try? encoder.encode(stamped) else { return }
            let target = directory.appendingPathComponent("\(identity).json")
            try? data.write(to: target, options: .atomic)
            try? data.write(
                to: directory.appendingPathComponent(latestFileName),
                options: .atomic
            )
        }
    }

    func remove(identity: String) {
        queue.async { [url = url(for: identity)] in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 最近一次保存的配方，批量套用与批量导出以它为来源
    func latest() -> PhotoRecipe? {
        queue.sync {
            guard let data = try? Data(
                contentsOf: directory.appendingPathComponent(latestFileName)
            ) else { return nil }
            guard let recipe = try? decoder.decode(PhotoRecipe.self, from: data) else { return nil }
            return recipe.version == 1 ? recipe : nil
        }
    }

    /// 批量套用：把同一份配方写到多张照片，返回成功数量
    @discardableResult
    func apply(_ recipe: PhotoRecipe, to identities: [String]) -> Int {
        guard !identities.isEmpty else { return 0 }
        var count = 0
        for identity in Set(identities) {
            save(recipe, identity: identity)
            count += 1
        }
        return count
    }

    private func url(for identity: String) -> URL {
        directory.appendingPathComponent("\(identity).json")
    }
}
