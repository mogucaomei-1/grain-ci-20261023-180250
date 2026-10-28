import CoreImage
import SwiftUI
import UIKit

/// 全局外观模式（跟随系统、白天浅色、黑夜深色）
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "白天模式"
        case .dark: "黑夜模式"
        }
    }

    var shortTitle: String {
        switch self {
        case .system: "系统"
        case .light: "白天"
        case .dark: "黑夜"
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolvedColorScheme(systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system: systemScheme
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 相机与录像页面的独立外观模式（默认黑夜深色，可设为白天浅色或跟随系统，独立于主 App 外观）
enum CameraAppearanceMode: String, CaseIterable, Identifiable {
    case dark = "dark"
    case light = "light"
    case system = "system"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "黑夜模式"
        case .light: "白天模式"
        case .system: "跟随系统"
        }
    }

    var shortTitle: String {
        switch self {
        case .dark: "黑夜"
        case .light: "白天"
        case .system: "系统"
        }
    }

    var iconName: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    func resolvedColorScheme(systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: systemScheme
        }
    }
}

enum GrainTheme {
    static let black = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x07 / 255.0, green: 0x07 / 255.0, blue: 0x06 / 255.0, alpha: 1.0)
            : UIColor(red: 0xF6 / 255.0, green: 0xF5 / 255.0, blue: 0xF2 / 255.0, alpha: 1.0)
    })

    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x13 / 255.0, green: 0x13 / 255.0, blue: 0x11 / 255.0, alpha: 1.0)
            : UIColor(red: 0xFF / 255.0, green: 0xFF / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
    })

    static let raised = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x1D / 255.0, green: 0x1D / 255.0, blue: 0x1A / 255.0, alpha: 1.0)
            : UIColor(red: 0xEA / 255.0, green: 0xE8 / 255.0, blue: 0xE3 / 255.0, alpha: 1.0)
    })

    static let paper = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xF4 / 255.0, green: 0xED / 255.0, blue: 0xE1 / 255.0, alpha: 1.0)
            : UIColor(red: 0x18 / 255.0, green: 0x17 / 255.0, blue: 0x15 / 255.0, alpha: 1.0)
    })

    static let muted = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x8E / 255.0, green: 0x8B / 255.0, blue: 0x84 / 255.0, alpha: 1.0)
            : UIColor(red: 0x78 / 255.0, green: 0x76 / 255.0, blue: 0x70 / 255.0, alpha: 1.0)
    })

    static let line = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.09)
            : UIColor.black.withAlphaComponent(0.08)
    })

    static let track = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor.black.withAlphaComponent(0.09)
    })

    static let knob = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xF4 / 255.0, green: 0xED / 255.0, blue: 0xE1 / 255.0, alpha: 1.0)
            : UIColor.white
    })

    static let accent = Color(hex: 0xD9774E)

    static let danger = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xE0 / 255.0, green: 0x68 / 255.0, blue: 0x5C / 255.0, alpha: 1.0)
            : UIColor(red: 0xD9 / 255.0, green: 0x4A / 255.0, blue: 0x3D / 255.0, alpha: 1.0)
    })
}

/// 峰值对焦的描边颜色（相机与编辑页共用）
enum FocusPeakingColor: String, CaseIterable, Identifiable {
    case red
    case yellow
    case blue
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: "红色"
        case .yellow: "黄色"
        case .blue: "蓝色"
        case .white: "白色"
        }
    }

    var color: Color {
        switch self {
        case .red: Color(hex: 0xFF5A3C)
        case .yellow: Color(hex: 0xFFD84A)
        case .blue: Color(hex: 0x4AA8FF)
        case .white: Color(hex: 0xFFFFFF)
        }
    }

    /// 相机峰值直接用 Core Image 上色，省掉 SwiftUI 的一层混合
    var ciColor: CIColor {
        switch self {
        case .red: CIColor(red: 1.0, green: 0.35, blue: 0.24)
        case .yellow: CIColor(red: 1.0, green: 0.85, blue: 0.29)
        case .blue: CIColor(red: 0.29, green: 0.66, blue: 1.0)
        case .white: CIColor(red: 1.0, green: 1.0, blue: 1.0)
        }
    }

    static func resolved(_ rawValue: String) -> FocusPeakingColor {
        FocusPeakingColor(rawValue: rawValue) ?? .red
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension FilmProfile {
    var uiPalette: [Color] {
        palette.map { Color(hex: $0) }
    }
}

// MARK: - iOS 27 液态玻璃设计系统 (Liquid Glass Design System)

struct LiquidGlassBackground: View {
    var body: some View {
        ZStack {
            // 底层：深邃黑曜水晶基底
            GrainTheme.black

            // 液体光斑 1：暖琥珀色深层折射流光（Amber Caustic Glow）
            RadialGradient(
                colors: [GrainTheme.accent.opacity(0.15), .clear],
                center: UnitPoint(x: 0.88, y: 0.02),
                startRadius: 10,
                endRadius: 440
            )

            // 液体光斑 2：冷萃青蓝棱镜光斑（Prismatic Cyan Light）
            RadialGradient(
                colors: [Color(hex: 0x4AE5FF).opacity(0.08), .clear],
                center: UnitPoint(x: 0.10, y: 0.72),
                startRadius: 20,
                endRadius: 480
            )

            // 液体光斑 3：极光紫粉微透光晕（Aurora Violet Dispersion）
            RadialGradient(
                colors: [Color(hex: 0xA855F7).opacity(0.05), .clear],
                center: UnitPoint(x: 0.80, y: 0.85),
                startRadius: 10,
                endRadius: 360
            )

            // 液体光斑 4：顶部流体天际微光带（Top Liquid Horizon Sheen）
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

typealias GrainBackground = LiquidGlassBackground

// MARK: - 液态玻璃微透修饰器 (Liquid Glass Modifiers)

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var opacity: CGFloat = 0.52
    var specularIntensity: CGFloat = 0.45

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // 1. 系统级动态微透磨砂材质 (Ultra-thin Frosted Optical Glass)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // 2. 液体透光基色 (Subsurface Scattering Tint)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(GrainTheme.surface.opacity(opacity))

                    // 3. 顶部液态高光反光层 (Specular Top Reflection)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(specularIntensity * 0.48),
                                    Color.white.opacity(0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                // 4. 多色彩虹棱镜折射镜面边框 (Iridescent Prismatic Specular Border)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(specularIntensity), location: 0.0),
                                .init(color: Color(hex: 0x8BE8FF).opacity(0.38), location: 0.16),
                                .init(color: Color(hex: 0xFFB37C).opacity(0.30), location: 0.32),
                                .init(color: Color.white.opacity(0.10), location: 0.55),
                                .init(color: Color.black.opacity(0.28), location: 0.85),
                                .init(color: Color.white.opacity(0.24), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            }
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 5)
    }
}

struct LiquidGlassCapsuleModifier: ViewModifier {
    var isAccent: Bool = false
    var specularIntensity: CGFloat = 0.42

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)

                    Capsule(style: .continuous)
                        .fill(
                            isAccent
                                ? GrainTheme.accent.opacity(0.22)
                                : GrainTheme.surface.opacity(0.48)
                        )

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    (isAccent ? GrainTheme.accent : Color.white).opacity(0.26),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .clipShape(Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: (isAccent ? GrainTheme.accent : Color.white).opacity(specularIntensity), location: 0.0),
                                .init(color: (isAccent ? Color(hex: 0xFFB37C) : Color(hex: 0x8BE8FF)).opacity(0.35), location: 0.20),
                                .init(color: Color.white.opacity(0.12), location: 0.45),
                                .init(color: Color.black.opacity(0.24), location: 0.78),
                                .init(color: (isAccent ? GrainTheme.accent : Color.white).opacity(0.25), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            }
            .shadow(color: (isAccent ? GrainTheme.accent.opacity(0.20) : Color.black.opacity(0.14)), radius: 9, x: 0, y: 3.5)
    }
}

struct LiquidGlassCircleModifier: ViewModifier {
    var size: CGFloat = 38
    var isAccent: Bool = false

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)

                    Circle()
                        .fill(
                            isAccent
                                ? GrainTheme.accent.opacity(0.24)
                                : GrainTheme.surface.opacity(0.48)
                        )

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    (isAccent ? GrainTheme.accent : Color.white).opacity(0.42),
                                    (isAccent ? Color(hex: 0xFFB37C) : Color(hex: 0x8BE8FF)).opacity(0.15),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: size * 0.8
                            )
                        )
                }
            }
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: (isAccent ? GrainTheme.accent : Color.white).opacity(0.50), location: 0.0),
                                .init(color: (isAccent ? Color(hex: 0xFFB37C) : Color(hex: 0x8BE8FF)).opacity(0.35), location: 0.22),
                                .init(color: Color.white.opacity(0.12), location: 0.50),
                                .init(color: Color.black.opacity(0.28), location: 0.82),
                                .init(color: Color.white.opacity(0.24), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
            }
            .shadow(color: (isAccent ? GrainTheme.accent.opacity(0.18) : Color.black.opacity(0.16)), radius: 7, x: 0, y: 3.5)
    }
}

struct LiquidGlassButtonStyle: ButtonStyle {
    var scaleAmount: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.70), value: configuration.isPressed)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, opacity: CGFloat = 0.52) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }

    func liquidGlassCapsule(isAccent: Bool = false) -> some View {
        modifier(LiquidGlassCapsuleModifier(isAccent: isAccent))
    }

    func liquidGlassCircle(size: CGFloat = 38, isAccent: Bool = false) -> some View {
        modifier(LiquidGlassCircleModifier(size: size, isAccent: isAccent))
    }
}

struct FilmPresetChip: View {
    let profile: FilmProfile
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(hex: 0x2B2925),
                        Color(hex: 0x121210)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [
                        profile.uiPalette[1].opacity(0.34),
                        profile.uiPalette[0].opacity(0.10),
                        .clear
                    ],
                    center: UnitPoint(x: 0.68, y: 0.42),
                    startRadius: 1,
                    endRadius: 52
                )
                FilmCameraGlyph(profile: profile, animated: selected)
                    .frame(width: 76, height: 40)
            }
            .frame(width: 82, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(selected ? 0.16 : 0.07), lineWidth: 0.8)
            }

            Text(profile.name)
                .font(.system(size: 8.2, weight: selected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(selected ? GrainTheme.paper : GrainTheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(width: 86, height: 22, alignment: .top)
        }
        .padding(4)
        .background(
            selected ? GrainTheme.raised : Color.clear,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? GrainTheme.accent.opacity(0.86) : .clear, lineWidth: 1)
        }
    }
}

struct FilmCameraGlyph: View {
    let profile: FilmProfile
    var animated = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animated)) { timeline in
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let style = profile.cameraIconStyle
                let phase = animated
                    ? timeline.date.timeIntervalSinceReferenceDate
                    : 0
                let bodyWidth = width * style.bodyWidth
                let bodyHeight = height * style.bodyHeight
                let bodyY = height * style.bodyY
                let corner = height * style.corner
                let lensDiameter = height * style.lensDiameter

                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.black.opacity(0.50))
                        .frame(width: bodyWidth, height: bodyHeight)
                        .offset(y: bodyY + height * 0.10)

                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: profile.cameraBodyColors(style: style),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: bodyWidth, height: bodyHeight)
                        .overlay {
                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                .stroke(Color.white.opacity(0.30), lineWidth: 0.7)
                        }
                        .offset(y: bodyY)

                    RoundedRectangle(cornerRadius: corner * 0.38, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.78),
                                    Color(hex: 0x292720)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: bodyWidth * 0.54, height: bodyHeight * 0.43)
                        .overlay {
                            VStack(spacing: max(1, bodyHeight * 0.055)) {
                                ForEach(0..<4, id: \.self) { _ in
                                    Capsule()
                                        .fill(Color.white.opacity(0.05))
                                        .frame(width: bodyWidth * 0.44, height: 0.45)
                                }
                            }
                        }
                        .offset(x: bodyWidth * 0.13, y: bodyY + bodyHeight * 0.22)

                    if style == .slr {
                        Path { path in
                            let topY = bodyY - bodyHeight * 0.49
                            let peakY = topY - height * 0.12
                            path.move(to: CGPoint(x: -bodyWidth * 0.19, y: topY))
                            path.addLine(to: CGPoint(x: -bodyWidth * 0.10, y: peakY))
                            path.addLine(to: CGPoint(x: bodyWidth * 0.10, y: peakY))
                            path.addLine(to: CGPoint(x: bodyWidth * 0.19, y: topY))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [
                                    GrainTheme.paper.opacity(0.90),
                                    profile.uiPalette[1].opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            Path { path in
                                let topY = bodyY - bodyHeight * 0.49
                                let peakY = topY - height * 0.12
                                path.move(to: CGPoint(x: -bodyWidth * 0.19, y: topY))
                                path.addLine(to: CGPoint(x: -bodyWidth * 0.10, y: peakY))
                                path.addLine(to: CGPoint(x: bodyWidth * 0.10, y: peakY))
                                path.addLine(to: CGPoint(x: bodyWidth * 0.19, y: topY))
                                path.closeSubpath()
                            }
                            .stroke(Color.white.opacity(0.26), lineWidth: 0.7)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: corner * 0.70, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        profile.uiPalette[2].opacity(0.92),
                                        GrainTheme.paper.opacity(0.86),
                                        profile.uiPalette[1].opacity(0.68)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(
                                width: bodyWidth * style.topPlateWidth,
                                height: max(3.2, bodyHeight * style.topPlateHeight)
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: corner * 0.70,
                                    style: .continuous
                                )
                                .stroke(Color.white.opacity(0.28), lineWidth: 0.65)
                            }
                            .offset(
                                x: -bodyWidth * style.topPlateOffset,
                                y: bodyY - bodyHeight * 0.54
                            )
                    }

                    if style == .twinLens {
                        CameraLensAssembly(
                            profile: profile,
                            diameter: lensDiameter * 0.76,
                            phase: phase,
                            animated: animated
                        )
                        .offset(x: -width * 0.04, y: -height * 0.03)

                        CameraLensAssembly(
                            profile: profile,
                            diameter: lensDiameter,
                            phase: phase + 0.4,
                            animated: animated
                        )
                        .offset(x: -width * 0.04, y: height * 0.20)
                    } else {
                        CameraLensAssembly(
                            profile: profile,
                            diameter: lensDiameter,
                            phase: phase,
                            animated: animated
                        )
                        .offset(
                            x: -width * style.lensOffsetX,
                            y: height * style.lensOffsetY
                        )
                    }

                    RoundedRectangle(cornerRadius: max(1, height * 0.045), style: .continuous)
                        .fill(Color(hex: 0x151713))
                        .frame(
                            width: max(5, height * (style == .digital ? 0.24 : 0.20)),
                            height: max(4, height * 0.14)
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: max(0.8, height * 0.032),
                                style: .continuous
                            )
                            .stroke(profile.uiPalette[1].opacity(0.72), lineWidth: 0.65)
                            .padding(1.1)
                        }
                        .offset(
                            x: width * style.viewfinderX,
                            y: height * style.viewfinderY
                        )

                    RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                        .fill(profile.uiPalette[0].opacity(0.96))
                        .frame(width: bodyWidth * 0.18, height: max(2.2, height * 0.065))
                        .overlay {
                            Capsule()
                                .fill(Color.white.opacity(0.24))
                                .frame(width: bodyWidth * 0.11, height: 0.5)
                        }
                        .offset(x: bodyWidth * 0.23, y: bodyY - bodyHeight * 0.34)

                    Capsule()
                        .fill(Color(hex: 0x22211E))
                        .frame(width: max(4, width * 0.11), height: max(2.5, height * 0.065))
                        .overlay {
                            Capsule()
                                .fill(GrainTheme.paper.opacity(0.70))
                                .padding(0.8)
                        }
                        .offset(x: width * 0.35, y: bodyY - bodyHeight * 0.26)

                    if style == .instant {
                        HStack(spacing: 0) {
                            ForEach(Array(profile.uiPalette.enumerated()), id: \.offset) { _, color in
                                Rectangle().fill(color)
                            }
                        }
                        .frame(width: bodyWidth * 0.74, height: max(1.8, height * 0.052))
                        .offset(y: bodyY - bodyHeight * 0.41)
                    }

                    Circle()
                        .fill(Color(hex: 0x83D39B))
                        .frame(width: max(1.7, height * 0.036), height: max(1.7, height * 0.036))
                        .opacity(
                            animated
                                ? 0.72 + sin(
                                    phase.truncatingRemainder(dividingBy: 1.6)
                                        / 1.6 * .pi * 2
                                ) * 0.22
                                : 1
                        )
                        .shadow(
                            color: animated
                                ? profile.uiPalette[1].opacity(0.48)
                                : .clear,
                            radius: animated ? 2.0 : 0
                        )
                        .offset(x: -width * 0.16, y: height * 0.006)
                }
            }
        }
        .shadow(color: .black.opacity(0.50), radius: 2.5, y: 2)
    }
}

private struct CameraLensAssembly: View {
    let profile: FilmProfile
    let diameter: CGFloat
    let phase: Double
    let animated: Bool

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        GrainTheme.paper.opacity(0.96),
                        profile.uiPalette[1].opacity(0.82),
                        Color(hex: 0x4A4843)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .fill(Color.black.opacity(0.92))
                    .padding(diameter * 0.085)
            }
            .overlay {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                profile.uiPalette[0],
                                profile.uiPalette[1],
                                profile.uiPalette[2],
                                profile.uiPalette[0]
                            ],
                            center: .center
                        )
                    )
                    .padding(diameter * 0.17)
            }
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                profile.uiPalette[2].opacity(0.58),
                                Color(hex: 0x101817),
                                Color.black
                            ],
                            center: UnitPoint(x: 0.34, y: 0.28),
                            startRadius: 0,
                            endRadius: diameter * 0.42
                        )
                    )
                    .padding(diameter * 0.24)
            }
            .overlay {
                Circle()
                    .trim(from: 0.02, to: 0.22)
                    .stroke(Color.white.opacity(0.72), lineWidth: max(0.7, diameter * 0.035))
                    .rotationEffect(
                        .degrees(animated ? phase.truncatingRemainder(dividingBy: 6) * 60 : -28)
                    )
                    .padding(diameter * 0.12)
                    .opacity(animated ? 0.85 : 0.34)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: diameter * 0.13, height: diameter * 0.13)
                    .blur(radius: 0.3)
                    .offset(x: diameter * 0.25, y: diameter * 0.18)
            }
    }
}

private enum FilmCameraIconStyle {
    case rangefinder
    case slr
    case compact
    case digital
    case instant
    case twinLens

    var bodyWidth: CGFloat {
        switch self {
        case .rangefinder: 0.88
        case .slr: 0.92
        case .compact: 0.84
        case .digital: 0.91
        case .instant: 0.79
        case .twinLens: 0.72
        }
    }

    var bodyHeight: CGFloat {
        switch self {
        case .rangefinder: 0.58
        case .slr: 0.62
        case .compact: 0.60
        case .digital: 0.54
        case .instant: 0.68
        case .twinLens: 0.72
        }
    }

    var bodyY: CGFloat {
        switch self {
        case .digital: 0.14
        case .instant: 0.10
        case .twinLens: 0.08
        default: 0.11
        }
    }

    var corner: CGFloat {
        switch self {
        case .digital: 0.10
        case .instant: 0.07
        case .twinLens: 0.10
        default: 0.16
        }
    }

    var lensDiameter: CGFloat {
        switch self {
        case .digital: 0.47
        case .instant: 0.57
        case .twinLens: 0.34
        default: 0.54
        }
    }

    var lensOffsetX: CGFloat {
        switch self {
        case .digital: 0.18
        case .compact: 0.11
        default: 0.08
        }
    }

    var lensOffsetY: CGFloat {
        switch self {
        case .slr: 0.13
        case .instant: 0.17
        default: 0.14
        }
    }

    var topPlateWidth: CGFloat {
        self == .rangefinder ? 0.59 : 0.45
    }

    var topPlateHeight: CGFloat {
        self == .instant ? 0.20 : 0.17
    }

    var topPlateOffset: CGFloat {
        self == .rangefinder ? 0.12 : 0.04
    }

    var viewfinderX: CGFloat {
        switch self {
        case .rangefinder: 0.27
        case .digital: 0.32
        case .twinLens: 0.25
        default: 0.30
        }
    }

    var viewfinderY: CGFloat {
        self == .slr ? -0.20 : -0.17
    }
}

private extension FilmProfile {
    var cameraIconStyle: FilmCameraIconStyle {
        switch self {
        case .dazzFxnR, .film135t:
            return .rangefinder
        case .dazzCCDR, .c200:
            return .digital
        case .dazzDClassic, .provia100f, .ektar100, .ektachrome100:
            return .slr
        case .dazzGRDR, .superia400, .classicChrome, .realaAce:
            return .compact
        case .dazzDFunS, .portra, .portra160, .portra800, .gold, .colorPlus200:
            return .instant
        case .dazzClassicU, .nostalgicNeg, .pro400h:
            return .twinLens
        default:
            return .compact
        }
    }

    func cameraBodyColors(style: FilmCameraIconStyle) -> [Color] {
        switch style {
        case .slr:
            return [
                Color(hex: 0x57554F),
                Color(hex: 0x25241F),
                Color(hex: 0x121210)
            ]
        case .digital:
            return [
                GrainTheme.paper.opacity(0.96),
                uiPalette[1].opacity(0.82),
                Color(hex: 0x77736B)
            ]
        case .instant:
            return [
                GrainTheme.paper,
                uiPalette[2].opacity(0.72),
                Color(hex: 0xB5AD9E)
            ]
        case .twinLens:
            return [
                Color(hex: 0xB8B0A2),
                Color(hex: 0x5A554B),
                Color(hex: 0x201F1C)
            ]
        case .compact:
            return [
                Color(hex: 0x8D8980),
                Color(hex: 0x45433D),
                Color(hex: 0x181815)
            ]
        case .rangefinder:
            return [
                GrainTheme.paper.opacity(0.98),
                uiPalette[2].opacity(0.68),
                Color(hex: 0x766F64)
            ]
        }
    }
}
