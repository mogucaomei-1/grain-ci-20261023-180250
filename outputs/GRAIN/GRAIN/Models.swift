import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FilmProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case neutral
    case portra
    case film135t
    case portra160
    case portra800
    case pro400h
    case gold
    case ektar100
    case classicChrome
    case velvia50
    case provia100f
    case superia400
    case cinestill
    case vision250d
    case classicNegative
    case nostalgicNeg
    case realaAce
    case eterna
    case colorPlus200
    case ultramax400
    case c200
    case ektachrome100
    case vision500t
    case dazzFxnR
    case dazzCCDR
    case dazzDClassic
    case dazzGRDR
    case dazzDFunS
    case dazzClassicU

    var id: String { rawValue }

    static let dazzPriority: [FilmProfile] = [
        .dazzFxnR,
        .dazzCCDR,
        .dazzDClassic,
        .dazzGRDR,
        .dazzDFunS,
        .dazzClassicU
    ]

    static var defaultDisplayOrder: [FilmProfile] {
        var result: [FilmProfile] = [.neutral]
        result.append(contentsOf: dazzPriority)
        result.append(contentsOf: allCases.filter { !result.contains($0) })
        return result
    }

    static func resolvedDisplayOrder(from storedValue: String) -> [FilmProfile] {
        let parsed = storedValue
            .split(separator: ",")
            .compactMap { FilmProfile(rawValue: String($0)) }
        var seen = Set<String>()
        let stored = parsed.filter { seen.insert($0.rawValue).inserted }
        let hasCompleteDazzOrder = dazzPriority.allSatisfy {
            seen.contains($0.rawValue)
        }

        if stored.isEmpty || !hasCompleteDazzOrder {
            var result: [FilmProfile] = [.neutral]
            result.append(contentsOf: dazzPriority)
            result.append(contentsOf: stored.filter {
                $0 != .neutral && !dazzPriority.contains($0)
            })
            result.append(contentsOf: defaultDisplayOrder.filter {
                !result.contains($0)
            })
            return result
        }

        return stored + defaultDisplayOrder.filter { !seen.contains($0.rawValue) }
    }

    var name: String {
        switch self {
        case .neutral: "原图"
        case .portra: "柯达 波特拉 400"
        case .film135t: "135T 街拍"
        case .portra160: "柯达 波特拉 160"
        case .portra800: "柯达 波特拉 800"
        case .pro400h: "富士 专业 400H"
        case .gold: "柯达 金 200"
        case .ektar100: "柯达 艾克塔 100"
        case .classicChrome: "富士 经典正片"
        case .velvia50: "富士 维尔维亚 50"
        case .provia100f: "富士 普罗维亚 100F"
        case .superia400: "富士 超级 400"
        case .cinestill: "电影 夜光 800T"
        case .vision250d: "电影 Vision3 250D"
        case .classicNegative: "富士 经典负片"
        case .nostalgicNeg: "富士 怀旧负片"
        case .realaAce: "富士 REALA ACE"
        case .eterna: "富士 ETERNA 电影"
        case .colorPlus200: "柯达 ColorPlus 200"
        case .ultramax400: "柯达 Ultramax 400"
        case .c200: "富士 C200"
        case .ektachrome100: "柯达 反转片 E100"
        case .vision500t: "电影 Vision3 500T"
        case .dazzFxnR: "FXN R · 富士全能"
        case .dazzCCDR: "CCD R · 人像柔光"
        case .dazzDClassic: "D Classic · 街拍故事"
        case .dazzGRDR: "GRD R · 蓝绿静谧"
        case .dazzDFunS: "D FunS · 晴天高彩"
        case .dazzClassicU: "Classic U · 复古负片"
        }
    }

    var shortName: String {
        switch self {
        case .neutral: "原图"
        case .portra: "波特拉"
        case .film135t: "135T"
        case .portra160: "P160"
        case .portra800: "P800"
        case .pro400h: "400H"
        case .gold: "金200"
        case .ektar100: "艾克塔"
        case .classicChrome: "经典"
        case .velvia50: "维尔维亚"
        case .provia100f: "普罗维亚"
        case .superia400: "超级"
        case .cinestill: "夜光"
        case .vision250d: "250D"
        case .classicNegative: "经典负片"
        case .nostalgicNeg: "怀旧"
        case .realaAce: "REALA"
        case .eterna: "ETERNA"
        case .colorPlus200: "CP200"
        case .ultramax400: "U400"
        case .c200: "C200"
        case .ektachrome100: "E100"
        case .vision500t: "500T"
        case .dazzFxnR: "FXN R"
        case .dazzCCDR: "CCD R"
        case .dazzDClassic: "D Classic"
        case .dazzGRDR: "GRD R"
        case .dazzDFunS: "D FunS"
        case .dazzClassicU: "Classic U"
        }
    }

    var descriptor: String {
        switch self {
        case .neutral: "不套用胶片色彩，保留 RAW 基础显影"
        case .portra: "奶油高光 · 柔和肤色"
        case .film135t: "深蓝天空 · 冷青阴影 · 高密度黑位"
        case .portra160: "低饱和肤色 · 细腻层次"
        case .portra800: "暖钨丝光 · 柔和高光"
        case .pro400h: "薄荷青绿 · 空气感"
        case .gold: "金色午后 · 饱满暖调"
        case .ektar100: "锐利细节 · 浓郁红蓝"
        case .classicChrome: "低饱和 · 深青阴影"
        case .velvia50: "高饱和 · 通透风光"
        case .provia100f: "自然浓郁 · 中性肤色"
        case .superia400: "青绿阴影 · 日常街拍"
        case .cinestill: "钨丝蓝 · 夜景红晕"
        case .vision250d: "柔和日光 · 电影宽容度"
        case .classicNegative: "深青绿 · 浓郁红橙 · 日常街拍"
        case .nostalgicNeg: "琥珀暖调 · 柔和金色高光"
        case .realaAce: "清晰自然 · 中性肤色 · 通透层次"
        case .eterna: "低饱和电影色 · 青色阴影"
        case .colorPlus200: "暖黄日光 · 轻复古彩色负片"
        case .ultramax400: "鲜艳暖调 · 高宽容度日常记录"
        case .c200: "清透青绿 · 柔和低对比"
        case .ektachrome100: "通透红蓝 · 干净高光"
        case .vision500t: "暖钨丝光 · 深青夜景"
        case .dazzFxnR: "清透富士色 · 全场景稳定出片"
        case .dazzCCDR: "柔化皮肤 · 旧数码颗粒感"
        case .dazzDClassic: "低调街拍 · 复古故事感"
        case .dazzGRDR: "理光式蓝绿 · 安静城市色调"
        case .dazzDFunS: "阳光高饱和 · 明快彩色负片"
        case .dazzClassicU: "金黄褪色 · 老胶片日常感"
        }
    }

    var palette: [UInt32] {
        switch self {
        case .neutral: [0x8B8D8A, 0xB7B3A9, 0xDFD8CB]
        case .portra: [0xB86F58, 0xD6AA86, 0xEADCC7]
        case .film135t: [0x254B66, 0x4F8A86, 0xD8C0A2]
        case .portra160: [0xB77A66, 0xD9B08F, 0xEEE0CC]
        case .portra800: [0xAA614D, 0xD1A27C, 0xE8C8A9]
        case .pro400h: [0x5F7F79, 0xAABDB0, 0xDDDAC7]
        case .gold: [0xA84A31, 0xD79D54, 0xE9D3A2]
        case .ektar100: [0x8F3E34, 0xC47D56, 0x86A9A2]
        case .classicChrome: [0x344A49, 0x7F8B82, 0xB9B5A7]
        case .velvia50: [0x1F6654, 0xC95346, 0xE5B95E]
        case .provia100f: [0x315E63, 0x91A79A, 0xD4B78C]
        case .superia400: [0x3D765D, 0x8DB78A, 0xD4C8A6]
        case .cinestill: [0x2D5568, 0xB44E42, 0xD8B4A1]
        case .vision250d: [0x536F6B, 0xBE8B62, 0xD7C3A1]
        case .classicNegative: [0x214F52, 0xA94C3C, 0xD9B477]
        case .nostalgicNeg: [0x5D4231, 0xB56F44, 0xE6C88D]
        case .realaAce: [0x37686A, 0x9AAE8B, 0xE4C9A5]
        case .eterna: [0x28494E, 0x6A827A, 0xB7B09A]
        case .colorPlus200: [0x99513A, 0xD6964C, 0xE8CD9A]
        case .ultramax400: [0x9A3D35, 0xD46B3D, 0xE0BE77]
        case .c200: [0x3E7168, 0x7DA88A, 0xD7C7A5]
        case .ektachrome100: [0x285E69, 0xA93D39, 0xE0B765]
        case .vision500t: [0x203B4D, 0x9A5437, 0xD2A46E]
        case .dazzFxnR: [0x356A6C, 0x90AC8B, 0xDFC59D]
        case .dazzCCDR: [0x8D5E58, 0xD3A998, 0xE8D9C9]
        case .dazzDClassic: [0x3C4E47, 0xA16B4A, 0xD2B487]
        case .dazzGRDR: [0x244E58, 0x587E77, 0xB9AE91]
        case .dazzDFunS: [0xB84A34, 0xE38D3C, 0xF0D26E]
        case .dazzClassicU: [0x7D4B35, 0xC68A54, 0xE2C89D]
        }
    }

    var factorySettings: FilmSettings {
        switch self {
        case .neutral:
            .init(exposure: 0, temperature: 6500, tint: 0,
                  highlights: 0, shadows: 0, whites: 0, blacks: 0,
                  contrast: 0, vibrance: 0, saturation: 0, clarity: 0,
                  fade: 0, grain: 0, vignette: 0, sharpness: 0)
        case .portra:
            .init(exposure: 0.12, temperature: 6900, tint: 5,
                  highlights: -8, shadows: 8, whites: -3, blacks: 5,
                  contrast: -8, vibrance: 5, saturation: -10, clarity: -4,
                  fade: 10, grain: 18, vignette: 10, sharpness: 5)
        case .film135t:
            .init(exposure: -0.03, temperature: 6100, tint: -5,
                  highlights: -12, shadows: -12, whites: 2, blacks: -8,
                  contrast: 16, vibrance: 3, saturation: -5, clarity: 4,
                  fade: 3, grain: 22, vignette: 18, sharpness: 11)
        case .portra160:
            .init(exposure: 0.08, temperature: 6800, tint: 3,
                  highlights: -6, shadows: 8, whites: -3, blacks: 4,
                  contrast: -4, vibrance: 4, saturation: -6, clarity: -2,
                  fade: 7, grain: 12, vignette: 8, sharpness: 4)
        case .portra800:
            .init(exposure: 0.16, temperature: 7000, tint: 5,
                  highlights: -10, shadows: 12, whites: -4, blacks: 7,
                  contrast: -10, vibrance: 7, saturation: -6, clarity: -4,
                  fade: 12, grain: 30, vignette: 14, sharpness: 3)
        case .pro400h:
            .init(exposure: 0.22, temperature: 7100, tint: -8,
                  highlights: -10, shadows: 12, whites: -4, blacks: 8,
                  contrast: -12, vibrance: 4, saturation: -16, clarity: -7,
                  fade: 14, grain: 14, vignette: 6, sharpness: 4)
        case .gold:
            .init(exposure: 0.02, temperature: 7600, tint: 8,
                  highlights: -4, shadows: 6, whites: 4, blacks: 3,
                  contrast: 6, vibrance: 10, saturation: 10, clarity: 2,
                  fade: 8, grain: 22, vignette: 16, sharpness: 7)
        case .ektar100:
            .init(exposure: 0.02, temperature: 6600, tint: 2,
                  highlights: -6, shadows: 4, whites: 4, blacks: 3,
                  contrast: 10, vibrance: 12, saturation: 8, clarity: 5,
                  fade: 3, grain: 10, vignette: 10, sharpness: 10)
        case .classicChrome:
            .init(exposure: -0.04, temperature: 6200, tint: 1,
                  highlights: -8, shadows: 4, whites: 4, blacks: 6,
                  contrast: 12, vibrance: -8, saturation: -28, clarity: 4,
                  fade: 5, grain: 14, vignette: 18, sharpness: 9)
        case .velvia50:
            .init(exposure: -0.06, temperature: 6100, tint: -2,
                  highlights: -3, shadows: -4, whites: 6, blacks: -2,
                  contrast: 20, vibrance: 18, saturation: 22, clarity: 10,
                  fade: 0, grain: 6, vignette: 22, sharpness: 16)
        case .provia100f:
            .init(exposure: 0, temperature: 6300, tint: 0,
                  highlights: -5, shadows: 2, whites: 3, blacks: 2,
                  contrast: 10, vibrance: 8, saturation: 4, clarity: 5,
                  fade: 2, grain: 5, vignette: 12, sharpness: 12)
        case .superia400:
            .init(exposure: 0.08, temperature: 7200, tint: 3,
                  highlights: -8, shadows: 6, whites: -2, blacks: 4,
                  contrast: 5, vibrance: 8, saturation: 5, clarity: 0,
                  fade: 8, grain: 24, vignette: 14, sharpness: 6)
        case .cinestill:
            .init(exposure: 0.10, temperature: 4750, tint: -8,
                  highlights: -5, shadows: 10, whites: -2, blacks: 4,
                  contrast: -4, vibrance: 8, saturation: 4, clarity: -2,
                  fade: 12, grain: 26, vignette: 22, sharpness: 2)
        case .vision250d:
            .init(exposure: 0.06, temperature: 6900, tint: 2,
                  highlights: -6, shadows: 8, whites: -2, blacks: 4,
                  contrast: 0, vibrance: 5, saturation: -2, clarity: 0,
                  fade: 8, grain: 16, vignette: 12, sharpness: 5)
        case .classicNegative:
            .init(exposure: 0.06, temperature: 5900, tint: -4,
                  highlights: -10, shadows: 4, whites: 2, blacks: 7,
                  contrast: 10, vibrance: 2, saturation: -8, clarity: 1,
                  fade: 6, grain: 18, vignette: 18, sharpness: 8)
        case .nostalgicNeg:
            .init(exposure: 0.10, temperature: 7400, tint: 5,
                  highlights: -12, shadows: 10, whites: -4, blacks: 8,
                  contrast: -6, vibrance: 8, saturation: 2, clarity: 0,
                  fade: 14, grain: 24, vignette: 18, sharpness: 4)
        case .realaAce:
            .init(exposure: 0, temperature: 6300, tint: -2,
                  highlights: -7, shadows: 4, whites: 4, blacks: 3,
                  contrast: 8, vibrance: 8, saturation: -2, clarity: 3,
                  fade: 3, grain: 12, vignette: 10, sharpness: 11)
        case .eterna:
            .init(exposure: 0.04, temperature: 6000, tint: -4,
                  highlights: -10, shadows: 8, whites: -3, blacks: 6,
                  contrast: -5, vibrance: 0, saturation: -18, clarity: -2,
                  fade: 9, grain: 16, vignette: 14, sharpness: 3)
        case .colorPlus200:
            .init(exposure: 0.04, temperature: 7500, tint: 6,
                  highlights: -5, shadows: 6, whites: 2, blacks: 3,
                  contrast: 4, vibrance: 8, saturation: 6, clarity: 1,
                  fade: 10, grain: 24, vignette: 16, sharpness: 5)
        case .ultramax400:
            .init(exposure: 0.08, temperature: 7200, tint: 3,
                  highlights: -7, shadows: 5, whites: 1, blacks: 2,
                  contrast: 6, vibrance: 10, saturation: 9, clarity: 2,
                  fade: 7, grain: 26, vignette: 14, sharpness: 6)
        case .c200:
            .init(exposure: 0.10, temperature: 7100, tint: -3,
                  highlights: -9, shadows: 7, whites: -2, blacks: 4,
                  contrast: -4, vibrance: 5, saturation: -4, clarity: -2,
                  fade: 12, grain: 20, vignette: 10, sharpness: 4)
        case .ektachrome100:
            .init(exposure: -0.02, temperature: 6400, tint: 1,
                  highlights: -5, shadows: 3, whites: 5, blacks: 4,
                  contrast: 14, vibrance: 8, saturation: 8, clarity: 7,
                  fade: 2, grain: 9, vignette: 10, sharpness: 13)
        case .vision500t:
            .init(exposure: 0.08, temperature: 4700, tint: -6,
                  highlights: -7, shadows: 10, whites: -3, blacks: 5,
                  contrast: -2, vibrance: 6, saturation: -4, clarity: -3,
                  fade: 10, grain: 28, vignette: 24, sharpness: 2)
        case .dazzFxnR:
            .init(exposure: 0.03, temperature: 6300, tint: -2,
                  highlights: -8, shadows: 6, whites: 2, blacks: 3,
                  contrast: 8, vibrance: 8, saturation: 0, clarity: 2,
                  fade: 5, grain: 16, vignette: 12, sharpness: 8)
        case .dazzCCDR:
            .init(exposure: 0.12, temperature: 6900, tint: 6,
                  highlights: -10, shadows: 10, whites: -2, blacks: 5,
                  contrast: -5, vibrance: 4, saturation: -3, clarity: -4,
                  fade: 12, grain: 8, vignette: 14, sharpness: 2)
        case .dazzDClassic:
            .init(exposure: -0.02, temperature: 6200, tint: -1,
                  highlights: -9, shadows: 5, whites: 2, blacks: 7,
                  contrast: 10, vibrance: 3, saturation: -6, clarity: 3,
                  fade: 8, grain: 22, vignette: 20, sharpness: 8)
        case .dazzGRDR:
            .init(exposure: -0.03, temperature: 6100, tint: -4,
                  highlights: -7, shadows: 3, whites: 3, blacks: 5,
                  contrast: 13, vibrance: 5, saturation: -10, clarity: 5,
                  fade: 3, grain: 16, vignette: 17, sharpness: 10)
        case .dazzDFunS:
            .init(exposure: 0.06, temperature: 7400, tint: 5,
                  highlights: -5, shadows: 4, whites: 4, blacks: 2,
                  contrast: 12, vibrance: 15, saturation: 15, clarity: 5,
                  fade: 4, grain: 18, vignette: 12, sharpness: 8)
        case .dazzClassicU:
            .init(exposure: 0.08, temperature: 7100, tint: 4,
                  highlights: -11, shadows: 9, whites: -4, blacks: 7,
                  contrast: 0, vibrance: 5, saturation: -2, clarity: -2,
                  fade: 15, grain: 26, vignette: 18, sharpness: 3)
        }
    }
}

struct FilmSettings: Equatable, Codable, Sendable {
    var exposure: Double
    var temperature: Double
    var tint: Double
    var highlights: Double
    var shadows: Double
    var whites: Double
    var blacks: Double
    var contrast: Double
    var vibrance: Double
    var saturation: Double
    var clarity: Double
    var fade: Double
    var grain: Double
    var vignette: Double
    var sharpness: Double
}

struct PresetClipboard: Codable, Sendable {
    let version: Int
    let profile: FilmProfile
    let settings: FilmSettings
    let intensity: Double

    init(profile: FilmProfile, settings: FilmSettings, intensity: Double) {
        version = 1
        self.profile = profile
        self.settings = settings
        self.intensity = intensity
    }
}

enum CropAspect: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case free
    case square
    case portrait4x5
    case landscape5x4
    case portrait3x4
    case landscape4x3
    case portrait2x3
    case landscape3x2
    case portrait9x16
    case landscape16x9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原始"
        case .free: "自由"
        case .square: "1:1"
        case .portrait4x5: "4:5"
        case .landscape5x4: "5:4"
        case .portrait3x4: "3:4"
        case .landscape4x3: "4:3"
        case .portrait2x3: "2:3"
        case .landscape3x2: "3:2"
        case .portrait9x16: "9:16"
        case .landscape16x9: "16:9"
        }
    }

    var ratio: Double? {
        switch self {
        case .original, .free: nil
        case .square: 1
        case .portrait4x5: 4.0 / 5
        case .landscape5x4: 5.0 / 4
        case .portrait3x4: 3.0 / 4
        case .landscape4x3: 4.0 / 3
        case .portrait2x3: 2.0 / 3
        case .landscape3x2: 3.0 / 2
        case .portrait9x16: 9.0 / 16
        case .landscape16x9: 16.0 / 9
        }
    }
}

struct CropTransform: Codable, Equatable, Sendable {
    var aspect: CropAspect = .original
    var normalizedX = 0.0
    var normalizedY = 0.0
    var normalizedWidth = 1.0
    var normalizedHeight = 1.0
    var rotationQuarterTurns = 0
    var flipHorizontal = false
    var flipVertical = false

    static let identity = CropTransform()

    var isIdentity: Bool {
        normalizedX == 0 && normalizedY == 0
            && normalizedWidth == 1 && normalizedHeight == 1
            && rotationQuarterTurns == 0
            && !flipHorizontal && !flipVertical
    }
}

enum PhotoTextFont: String, CaseIterable, Identifiable, Codable, Sendable {
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: "现代"
        case .serif: "衬线"
        case .monospaced: "等宽"
        }
    }
}

struct PhotoTextOverlay: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var text = ""
    var x = 0.5
    var y = 0.5
    var fontSize = 0.07
    var font: PhotoTextFont = .rounded
    var red = 1.0
    var green = 1.0
    var blue = 1.0
    var alpha = 1.0
}

struct MosaicPoint: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
}

struct MosaicStroke: Identifiable, Equatable, Codable, Sendable {
    var id = UUID()
    var points: [MosaicPoint]
    var brushSize: Double
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case heic
    case jpeg

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heic: "HEIC"
        case .jpeg: "JPEG"
        }
    }

    var subtitle: String {
        switch self {
        case .heic: "高画质 · 更小体积"
        case .jpeg: "兼容性最佳"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .heic: UTType.heic.identifier as CFString
        case .jpeg: UTType.jpeg.identifier as CFString
        }
    }

    var fileExtension: String {
        switch self {
        case .heic: "heic"
        case .jpeg: "jpg"
        }
    }
}

struct ExportOptions: Equatable, Sendable {
    var format: ExportFormat = .heic
    var quality: Double = 1.0
    var keepLocation = true
    var keepCameraMetadata = true
}

struct PhotoAsset: Identifiable, Equatable, Sendable {
    let id = UUID()
    let url: URL
    let displayName: String
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64
    let cameraMake: String
    let cameraModel: String
    let lensModel: String
    let capturedAt: Date?
    let hasLocation: Bool
    let latitude: Double?
    let longitude: Double?
    let orientation: UInt32
    let isLikelyScreenshot: Bool

    var dimensionsLabel: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var megapixelsLabel: String {
        let megapixels = Double(pixelWidth * pixelHeight) / 1_000_000
        return String(format: "%.1f MP", megapixels)
    }

    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var cameraLabel: String {
        [cameraMake, cameraModel]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "Sony Sony", with: "Sony")
    }

    var sourceKindLabel: String {
        switch url.pathExtension.lowercased() {
        case "arw", "srf", "sr2", "dng", "raw":
            return "RAW"
        case "heic", "heif":
            return "HEIF"
        case "png":
            return "PNG"
        case "jpg", "jpeg":
            return "JPEG"
        case "tif", "tiff":
            return "TIFF"
        case "":
            return "IMAGE"
        default:
            return url.pathExtension.uppercased()
        }
    }
}

struct ExportResult: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let dimensions: String
    let format: ExportFormat
}
