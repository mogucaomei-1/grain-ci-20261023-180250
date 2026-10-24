import AVFoundation
import Photos
import SwiftUI
import UIKit

// MARK: - 视频来源分类

public enum VideoSourceType: Equatable, Hashable {
    /// 来自相册目录 (包括普通相册、自建相册、已隐藏相册)
    case photoLibrary(localIdentifier: String, isHidden: Bool, albumTitle: String? = nil)
    /// 来自 App 文件目录 (沙盒 Documents/Videos 或 Documents/.vault 私密保险箱)
    case fileDirectory(url: URL, isVault: Bool)
    /// 临时自系统文件选择器打开的外部视频 (in-place)
    case externalPicked(url: URL)

    public var isHiddenOrVault: Bool {
        switch self {
        case .photoLibrary(_, let isHidden, _):
            return isHidden
        case .fileDirectory(_, let isVault):
            return isVault
        case .externalPicked:
            return false
        }
    }

    public var displaySourceLabel: String {
        switch self {
        case .photoLibrary(_, let isHidden, let album):
            if isHidden {
                return "相册 · 已隐藏"
            }
            return album.map { "相册 · \($0)" } ?? "系统相册"
        case .fileDirectory(_, let isVault):
            return isVault ? "私密保险箱" : "本地文件"
        case .externalPicked:
            return "外部文件"
        }
    }
}

// MARK: - 视频元数据

public struct VideoMetadata: Equatable, Hashable {
    public var duration: TimeInterval = 0
    public var fileSize: Int64 = 0
    public var naturalSize: CGSize = .zero
    public var frameRate: Float = 0
    public var nominalBitrate: Float = 0
    public var codecName: String = ""
    public var colorPrimaries: String = ""
    public var isHDR: Bool = false
    public var audioFormat: String = ""
    public var audioChannels: Int = 0
    public var creationDate: Date = Date()

    public init(
        duration: TimeInterval = 0,
        fileSize: Int64 = 0,
        naturalSize: CGSize = .zero,
        frameRate: Float = 0,
        nominalBitrate: Float = 0,
        codecName: String = "",
        colorPrimaries: String = "",
        isHDR: Bool = false,
        audioFormat: String = "",
        audioChannels: Int = 0,
        creationDate: Date = Date()
    ) {
        self.duration = duration
        self.fileSize = fileSize
        self.naturalSize = naturalSize
        self.frameRate = frameRate
        self.nominalBitrate = nominalBitrate
        self.codecName = codecName
        self.colorPrimaries = colorPrimaries
        self.isHDR = isHDR
        self.audioFormat = audioFormat
        self.audioChannels = audioChannels
        self.creationDate = creationDate
    }

    public var resolutionString: String {
        guard naturalSize.width > 0 && naturalSize.height > 0 else { return "--" }
        let w = Int(naturalSize.width.rounded())
        let h = Int(naturalSize.height.rounded())
        return "\(w) × \(h)"
    }

    public var resolutionPill: String {
        let maxSide = max(naturalSize.width, naturalSize.height)
        if maxSide >= 3800 {
            return "4K"
        } else if maxSide >= 2500 {
            return "2K"
        } else if maxSide >= 1900 {
            return "1080P"
        } else if maxSide >= 1200 {
            return "720P"
        } else if maxSide > 0 {
            return "SD"
        }
        return ""
    }

    public var fpsPill: String {
        guard frameRate > 0 else { return "" }
        let rounded = Int(frameRate.rounded())
        if rounded >= 55 && rounded <= 65 {
            return "60FPS"
        } else if rounded >= 115 && rounded <= 125 {
            return "120FPS"
        } else if rounded >= 230 && rounded <= 250 {
            return "240FPS"
        } else if rounded >= 23 && rounded <= 25 {
            return "24FPS"
        } else if rounded >= 29 && rounded <= 31 {
            return "30FPS"
        }
        return "\(rounded)FPS"
    }
}

// MARK: - 视频主数据模型

public struct VideoItem: Identifiable, Equatable, Hashable {
    public let id: String
    public var title: String
    public var source: VideoSourceType
    public var metadata: VideoMetadata
    public var thumbnail: UIImage?

    public init(
        id: String,
        title: String,
        source: VideoSourceType,
        metadata: VideoMetadata = VideoMetadata(),
        thumbnail: UIImage? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.metadata = metadata
        self.thumbnail = thumbnail
    }

    public static func == (lhs: VideoItem, rhs: VideoItem) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.metadata == rhs.metadata
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(source)
    }

    public var durationFormatted: String {
        FormatUtils.formatDuration(metadata.duration)
    }

    public var fileSizeFormatted: String {
        FormatUtils.formatFileSize(metadata.fileSize)
    }

    public var isHidden: Bool {
        source.isHiddenOrVault
    }
}

// MARK: - 文件夹模型

public struct VideoFolder: Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var itemCount: Int
    public var createdDate: Date

    public init(id: UUID = UUID(), name: String, url: URL, itemCount: Int = 0, createdDate: Date = Date()) {
        self.id = id
        self.name = name
        self.url = url
        self.itemCount = itemCount
        self.createdDate = createdDate
    }
}

// MARK: - 播放倍速

public enum PlaybackSpeed: Double, CaseIterable, Identifiable {
    case x0_5 = 0.5
    case x0_75 = 0.75
    case x1_0 = 1.0
    case x1_25 = 1.25
    case x1_5 = 1.5
    case x2_0 = 2.0
    case x3_0 = 3.0

    public var id: Double { rawValue }

    public var title: String {
        switch self {
        case .x0_5: return "0.5×"
        case .x0_75: return "0.75×"
        case .x1_0: return "1.0×"
        case .x1_25: return "1.25×"
        case .x1_5: return "1.5×"
        case .x2_0: return "2.0×"
        case .x3_0: return "3.0×"
        }
    }
}

// MARK: - 画面缩放比例模式

public enum VideoScaleMode: String, CaseIterable, Identifiable {
    case aspectFit = "原画比例"
    case aspectFill = "全屏铺满"
    case ratio16x9 = "16:9"
    case ratio4x3 = "4:3"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .aspectFit: return "aspectratio"
        case .aspectFill: return "arrow.up.left.and.arrow.down.right"
        case .ratio16x9: return "rectangle.ratio.16.to.9"
        case .ratio4x3: return "rectangle.ratio.4.to.3"
        }
    }
}

// MARK: - 排序方式

public enum SortOption: String, CaseIterable, Identifiable {
    case dateDesc = "最新添加"
    case dateAsc = "最早添加"
    case sizeDesc = "文件最大"
    case durationDesc = "时长最长"
    case nameAsc = "名称 A-Z"

    public var id: String { rawValue }
}

// MARK: - 字幕模型

public struct SubtitleItem: Identifiable, Equatable {
    public let id = UUID()
    public var index: Int
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String

    public init(index: Int, startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct SubtitleTrack: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var isExternal: Bool
    public var items: [SubtitleItem]

    public init(id: String, title: String, isExternal: Bool, items: [SubtitleItem] = []) {
        self.id = id
        self.title = title
        self.isExternal = isExternal
        self.items = items
    }
}
