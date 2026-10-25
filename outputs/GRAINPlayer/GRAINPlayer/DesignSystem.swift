import SwiftUI
import UIKit

// MARK: - GRAIN 视觉主题系统 (支持黑夜深色胶片与白天洁白高级工作室双模式)

public enum GrainTheme {
    /// 全局背景底色 (黑夜: #070706 纯粹深黑, 白天: #F7F6F2 柔润纸白)
    public static let black = Color.dynamic(
        light: Color(hex: 0xF7F6F2),
        dark: Color(hex: 0x070706)
    )
    /// 表面次层 (黑夜: #131311 深灰, 白天: #FFFFFF 纯白)
    public static let surface = Color.dynamic(
        light: Color(hex: 0xFFFFFF),
        dark: Color(hex: 0x131311)
    )
    /// 卡片抬升层 (黑夜: #1D1D1A, 白天: #EFECE6)
    public static let raised = Color.dynamic(
        light: Color(hex: 0xEFECE6),
        dark: Color(hex: 0x1D1D1A)
    )
    /// 浮层与交互卡片 (黑夜: #242420, 白天: Color.white)
    public static let card = Color.dynamic(
        light: Color(hex: 0xFFFFFF),
        dark: Color(hex: 0x242420)
    )
    /// 主要文字与高亮 (黑夜: #F4EDE1 柔纸白, 白天: #181715 深墨黑)
    public static let paper = Color.dynamic(
        light: Color(hex: 0x181715),
        dark: Color(hex: 0xF4EDE1)
    )
    /// 弱化灰度与次要说明 (黑夜: #8E8B84, 白天: #7A766F)
    public static let muted = Color.dynamic(
        light: Color(hex: 0x7A766F),
        dark: Color(hex: 0x8E8B84)
    )
    /// 极细分隔线与微边框 (黑夜: 半透白 0.09, 白天: 半透黑 0.09)
    public static let line = Color.dynamic(
        light: Color.black.opacity(0.08),
        dark: Color.white.opacity(0.09)
    )
    /// 温暖胶片琥珀橙强调色 (双模式统一采用高辨识度经典琥珀橙)
    public static let accent = Color(hex: 0xD9774E)
    /// 强调色半透光晕
    public static let accentGlow = Color(hex: 0xD9774E).opacity(0.18)
    /// 警示与删除红
    public static let danger = Color(hex: 0xE0685C)
    /// 徽标半透底色
    public static let badgeBackground = Color.dynamic(
        light: Color.black.opacity(0.65),
        dark: Color.black.opacity(0.72)
    )
    /// HUD 磨砂黑 (全屏观影沉浸体验始终保持深色)
    public static let hudBackground = Color(hex: 0x0C0C0B).opacity(0.88)
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// 动态自适应白天/黑夜颜色生成器
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .light:
                return UIColor(light)
            default:
                return UIColor(dark)
            }
        })
    }
}

// MARK: - 胶片光晕背景 (自适应明暗光晕)

public struct GrainBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            GrainTheme.black
            if colorScheme == .dark {
                RadialGradient(
                    colors: [GrainTheme.accent.opacity(0.06), .clear],
                    center: UnitPoint(x: 0.82, y: 0.04),
                    startRadius: 0,
                    endRadius: 360
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.02), .clear],
                    center: UnitPoint(x: 0.15, y: 0.90),
                    startRadius: 0,
                    endRadius: 400
                )
            } else {
                RadialGradient(
                    colors: [GrainTheme.accent.opacity(0.05), .clear],
                    center: UnitPoint(x: 0.82, y: 0.04),
                    startRadius: 0,
                    endRadius: 360
                )
                RadialGradient(
                    colors: [Color.black.opacity(0.02), .clear],
                    center: UnitPoint(x: 0.15, y: 0.90),
                    startRadius: 0,
                    endRadius: 400
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 触觉反馈系统

public enum GrainHaptics {
    public static func prepare() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
    }

    public static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    public static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    public static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    public static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    public static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    public static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

// MARK: - 胶囊与卡片修饰器

public struct GrainCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 14
    public var strokeColor: Color = GrainTheme.line

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GrainTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

public struct GrainGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat = 20

    public func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(GrainTheme.hudBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

public extension View {
    func grainCard(cornerRadius: CGFloat = 14, strokeColor: Color = GrainTheme.line) -> some View {
        modifier(GrainCardModifier(cornerRadius: cornerRadius, strokeColor: strokeColor))
    }

    func grainGlass(cornerRadius: CGFloat = 20) -> some View {
        modifier(GrainGlassModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - 常用格式化工具

public enum FormatUtils {
    /// 格式化时长（支持 00:00 或 00:00:00）
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds > 0 else {
            return "00:00"
        }
        let totalSeconds = Int(seconds.rounded(.down))
        let s = totalSeconds % 60
        let m = (totalSeconds / 60) % 60
        let h = totalSeconds / 3600

        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    /// 格式化文件大小
    public static func formatFileSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "--" }
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0

        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.0f KB", kb)
        }
    }

    /// 格式化码率
    public static func formatBitrate(_ bps: Float) -> String {
        guard bps > 0 else { return "--" }
        let mbps = Double(bps) / 1_000_000.0
        if mbps >= 1.0 {
            return String(format: "%.1f Mbps", mbps)
        } else {
            let kbps = Double(bps) / 1000.0
            return String(format: "%.0f kbps", kbps)
        }
    }

    /// 格式化日期
    public static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
