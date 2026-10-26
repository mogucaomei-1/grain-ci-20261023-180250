import SwiftUI
import WidgetKit

// MARK: - 官方 WidgetKit 规范与数据模型 (Apple HIG Specifications)

/// 小组件数据时间线实体
struct GRAINWidgetEntry: TimelineEntry {
    let date: Date
    let filmName: String
    let filmSubtitle: String
    let formatBadge: String
    let isVideoCapable: Bool

    static let preview = GRAINWidgetEntry(
        date: Date(),
        filmName: "PORTRA 400",
        filmSubtitle: "自然温润 · 经典人像",
        formatBadge: "RAW · 48MP",
        isVideoCapable: true
    )
}

/// 时间线提供者
struct GRAINWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> GRAINWidgetEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (GRAINWidgetEntry) -> Void) {
        completion(.preview)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GRAINWidgetEntry>) -> Void) {
        let entry = GRAINWidgetEntry(
            date: Date(),
            filmName: "PORTRA 400",
            filmSubtitle: "自然温润 · 经典人像",
            formatBadge: "RAW · 48MP",
            isVideoCapable: true
        )
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800)))
        completion(timeline)
    }
}

// MARK: - 1. 桌面小组件 Small（官方规格 158 × 158 pt）

struct GRAINSmallWidgetView: View {
    let entry: GRAINWidgetEntry

    var body: some View {
        ZStack {
            // 复古黑金底板
            Color(red: 0.08, green: 0.08, blue: 0.09)

            VStack(alignment: .leading, spacing: 0) {
                // 顶部品牌与快拍标识
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.98, green: 0.42, blue: 0.18))
                            .frame(width: 6, height: 6)
                        Text("GRAIN")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(Color.white)
                            .tracking(0.6)
                    }

                    Spacer()

                    Text("RAW")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.18))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }

                Spacer(minLength: 0)

                // 核心视觉：模拟复古微单镜头光圈与快门核心
                HStack {
                    Spacer()
                    ZStack {
                        // 外层快门纹理环
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 3)
                            .frame(width: 58, height: 58)

                        // 刻度环
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.42, blue: 0.18).opacity(0.8),
                                        Color.white.opacity(0.3),
                                        Color(red: 0.98, green: 0.42, blue: 0.18).opacity(0.8)
                                    ],
                                    center: .center
                                ),
                                lineWidth: 1.5
                            )
                            .frame(width: 50, height: 50)

                        // 内层快门核心按钮
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.42, blue: 0.18),
                                        Color(red: 0.88, green: 0.30, blue: 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .shadow(color: Color(red: 0.98, green: 0.42, blue: 0.18).opacity(0.35), radius: 6, y: 2)

                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                    Spacer()
                }

                Spacer(minLength: 0)

                // 底部胶片信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.filmName)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("点按即开机拍摄")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .padding(14)
        }
        .widgetURL(URL(string: "grain://camera?mode=photo"))
    }
}

// MARK: - 2. 桌面小组件 Medium（官方规格 338 × 158 pt）

struct GRAINMediumWidgetView: View {
    let entry: GRAINWidgetEntry

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.09)

            HStack(spacing: 12) {
                // 左半区：胶卷参数卡片 (约占 40%)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 0.98, green: 0.42, blue: 0.18))
                            .frame(width: 6, height: 6)
                        Text("GRAIN STUDIO")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(Color.white)
                            .tracking(0.5)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.filmName)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)

                        Text(entry.filmSubtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.60))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Text(entry.formatBadge)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.18))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                        Text("ISO AUTO")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.50))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)

                // 分隔虚线
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // 右半区：3 个快捷功能直达按键 (官方 Link 交互)
                VStack(spacing: 8) {
                    // 1. 拍照模式
                    Link(destination: URL(string: "grain://camera?mode=photo")!) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.98, green: 0.42, blue: 0.18))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                            Text("拍照")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.30))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // 2. 录像模式
                    Link(destination: URL(string: "grain://camera?mode=video")!) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.90))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "video.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                            Text("录像")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                            Spacer()
                            Text("4K60")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.40))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.30))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // 3. 暗房图库
                    Link(destination: URL(string: "grain://library")!) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "film.stack")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                            Text("暗房图库")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.30))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .frame(width: 140)
            }
            .padding(14)
        }
    }
}

// MARK: - 3. 锁屏小组件 Circular（官方规格 44 × 44 pt）

struct GRAINLockScreenCircularView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("GRAIN")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
            }
        }
        .widgetURL(URL(string: "grain://camera?mode=photo"))
    }
}

// MARK: - 4. 锁屏小组件 Rectangular（官方规格 144 × 44 pt）

struct GRAINLockScreenRectangularView: View {
    let entry: GRAINWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 11, weight: .bold))
                Text("GRAIN CAMERA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            Text(entry.filmName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text("轻触即拍 · \(entry.formatBadge)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "grain://camera?mode=photo"))
    }
}

// MARK: - 5. 锁屏小组件 Inline（官方单行规格）

struct GRAINLockScreenInlineView: View {
    let entry: GRAINWidgetEntry

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "camera.fill")
            Text("GRAIN · \(entry.filmName)")
        }
    }
}

// MARK: - 统一分发视图 (Widget Entry View)

struct GRAINWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: GRAINWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            GRAINSmallWidgetView(entry: entry)
        case .systemMedium:
            GRAINMediumWidgetView(entry: entry)
        case .accessoryCircular:
            GRAINLockScreenCircularView()
        case .accessoryRectangular:
            GRAINLockScreenRectangularView(entry: entry)
        case .accessoryInline:
            GRAINLockScreenInlineView(entry: entry)
        default:
            GRAINSmallWidgetView(entry: entry)
        }
    }
}

// MARK: - 官方 Widget 定义

struct GRAINWidget: Widget {
    let kind: String = "studio.grain.rawfilm.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GRAINWidgetProvider()) { entry in
            GRAINWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("GRAIN 复古相机")
        .description("一键从桌面或锁屏极速开机拍摄，即刻呈现胶片质感。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - App 内部交互式小组件官方规格预览面板 (In-App Showcase)

struct WidgetShowcaseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                GrainTheme.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // 1. 规范概述横幅
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(GrainTheme.accent)
                                    .frame(width: 8, height: 8)
                                Text("APPLE HIG 官方小组件规范")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(GrainTheme.accent)
                            }

                            Text("桌面与锁屏小组件 (第 1 版)")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(GrainTheme.paper)

                            Text("依据苹果官方摄影类 App 设计准则构建：提供即刻开拍的快门直达能力、胶片配方状态回显及多功能直达通道。")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(GrainTheme.paper.opacity(0.68))
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                        // 2. 规格一：桌面小组件 (systemSmall 158 × 158 pt)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("1. 桌面单功能快拍（systemSmall）")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(GrainTheme.paper)
                                Spacer()
                                Text("158 × 158 pt")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(GrainTheme.accent)
                            }
                            .padding(.horizontal, 18)

                            HStack {
                                Spacer()
                                GRAINSmallWidgetView(entry: .preview)
                                    .frame(width: 158, height: 158)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .stroke(GrainTheme.line, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
                                Spacer()
                            }

                            Text("• 核心定位：单焦点极致启动。大尺寸微单快门钮设计，点击即刻打开相机并进入拍照模式。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(GrainTheme.paper.opacity(0.60))
                                .padding(.horizontal, 18)
                        }

                        // 3. 规格二：桌面多功能中心 (systemMedium 338 × 158 pt)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("2. 桌面创作中心（systemMedium）")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(GrainTheme.paper)
                                Spacer()
                                Text("338 × 158 pt")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(GrainTheme.accent)
                            }
                            .padding(.horizontal, 18)

                            HStack {
                                Spacer()
                                GRAINMediumWidgetView(entry: .preview)
                                    .frame(width: 338, height: 158)
                                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .stroke(GrainTheme.line, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
                                Spacer()
                            }

                            Text("• 核心定位：左侧呈现当前胶卷模拟配方与规格，右侧提供【拍照】、【录像】、【暗房】3 路官方 Link 深度直达。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(GrainTheme.paper.opacity(0.60))
                                .padding(.horizontal, 18)
                        }

                        // 4. 规格三：锁屏小组件 (accessoryCircular & accessoryRectangular)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("3. 锁屏极速直达（Lock Screen）")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(GrainTheme.paper)
                                Spacer()
                                Text("iOS 16+ 锁屏")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(GrainTheme.accent)
                            }
                            .padding(.horizontal, 18)

                            HStack(spacing: 24) {
                                Spacer()

                                // 锁屏圆标
                                VStack(spacing: 6) {
                                    GRAINLockScreenCircularView()
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
                                    Text("圆形 (44×44)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(GrainTheme.paper.opacity(0.55))
                                }

                                // 锁屏长条
                                VStack(spacing: 6) {
                                    GRAINLockScreenRectangularView(entry: .preview)
                                        .padding(8)
                                        .frame(width: 150, height: 48)
                                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                    Text("矩形 (144×44)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(GrainTheme.paper.opacity(0.55))
                                }

                                Spacer()
                            }
                            .padding(.vertical, 6)

                            Text("• 核心定位：iOS 16/17/18 锁屏快速启动，锁屏状态下单触即可瞬间唤醒相机进入创作。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(GrainTheme.paper.opacity(0.60))
                                .padding(.horizontal, 18)
                        }

                        // 5. URL Scheme 直达测试
                        VStack(alignment: .leading, spacing: 10) {
                            Text("4. 交互直达验证")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(GrainTheme.paper)
                                .padding(.horizontal, 18)

                            VStack(spacing: 8) {
                                Button {
                                    WidgetCenter.shared.reloadAllTimelines()
                                    GrainHaptics.notification(type: .success)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(GrainTheme.accent)
                                        Text("向系统强制刷新与注册小组件")
                                            .font(.system(size: 12.5, weight: .bold))
                                            .foregroundStyle(GrainTheme.paper)
                                        Spacer()
                                        Text("立即触发")
                                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                            .foregroundStyle(GrainTheme.accent)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(GrainTheme.accent.opacity(0.18), in: Capsule())
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 44)
                                    .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(GrainTheme.accent.opacity(0.85), lineWidth: 1.0))
                                }

                                Text("系统使用说明：长按 iPhone 桌面空白处进入编辑模式 -> 点击左上角「+」号 -> 搜索「GRAIN」即可找到官方小组件添加到桌面或锁屏。")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(GrainTheme.paper.opacity(0.55))
                                    .lineSpacing(2.5)
                                    .padding(.vertical, 2)

                                Button {
                                    if let url = URL(string: "grain://camera?mode=photo") {
                                        UIApplication.shared.open(url)
                                        dismiss()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "camera.fill")
                                            .foregroundStyle(GrainTheme.accent)
                                        Text("测试唤醒【拍照模式】(grain://camera?mode=photo)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(GrainTheme.paper)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 11))
                                            .foregroundStyle(GrainTheme.paper.opacity(0.4))
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 42)
                                    .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(GrainTheme.line, lineWidth: 0.8))
                                }

                                Button {
                                    if let url = URL(string: "grain://camera?mode=video") {
                                        UIApplication.shared.open(url)
                                        dismiss()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "video.fill")
                                            .foregroundStyle(Color.red)
                                        Text("测试唤醒【录像模式】(grain://camera?mode=video)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(GrainTheme.paper)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 11))
                                            .foregroundStyle(GrainTheme.paper.opacity(0.4))
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 42)
                                    .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(GrainTheme.line, lineWidth: 0.8))
                                }

                                Button {
                                    if let url = URL(string: "grain://library") {
                                        UIApplication.shared.open(url)
                                        dismiss()
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "film.stack")
                                            .foregroundStyle(GrainTheme.paper)
                                        Text("测试唤醒【暗房图库】(grain://library)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(GrainTheme.paper)
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 11))
                                            .foregroundStyle(GrainTheme.paper.opacity(0.4))
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 42)
                                    .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(GrainTheme.line, lineWidth: 0.8))
                                }
                            }
                            .padding(.horizontal, 18)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("桌面与锁屏小组件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.accent)
                }
            }
        }
    }
}
