import SwiftUI
import UIKit

// MARK: - GRAIN 视觉主题系统 (延续 GRAIN 暗调胶片美学)

public enum GrainTheme {
    /// 纯粹深黑底色
    public static let black = Color(hex: 0x070706)
    /// 表面次层深灰
    public static let surface = Color(hex: 0x131311)
    /// 卡片抬升层
    public static let raised = Color(hex: 0x1D1D1A)
    /// 浮层与交互卡片
    public static let card = Color(hex: 0x242420)
    /// 柔和纸白文字
    public static let paper = Color(hex: 0xF4EDE1)
    /// 弱化灰度
    public static let muted = Color(hex: 0x8E8B84)
    /// 极细分隔线
    public static let line = Color.white.opacity(0.09)
    /// 温暖胶片琥珀橙强调色
    public static let accent = Color(hex: 0xD9774E)
    /// 强调色半透光晕
    public static let accentGlow = Color(hex: 0xD9774E).opacity(0.18)
    /// 警示与删除红
    public static let danger = Color(hex: 0xE0685C)
    /// 徽标半透黑底
    public static let badgeBackground = Color.black.opacity(0.72)
    /// HUD 磨砂黑
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
}

// MARK: - 胶片光晕背景

public struct GrainBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            GrainTheme.black
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
