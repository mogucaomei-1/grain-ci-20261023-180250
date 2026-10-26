import SwiftUI
import WidgetKit
import AppIntents

// MARK: - iOS 17+ 官方 WidgetConfigurationIntent 小组件配置与启动意图规范
struct OpenGRAINCameraIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "GRAIN 胶片快拍"
    static var description = IntentDescription("一键极速启动 GRAIN 复古微单相机")

    @Parameter(title: "拍摄模式", default: "photo")
    var mode: String

    init() {
        self.mode = "photo"
    }

    init(mode: String) {
        self.mode = mode
    }
}

// MARK: - iOS 17+ AppIntent Timeline Provider
struct GRAINAppIntentProvider: AppIntentTimelineProvider {
    typealias Entry = GRAINWidgetEntry
    typealias Intent = OpenGRAINCameraIntent

    func placeholder(in context: Context) -> GRAINWidgetEntry {
        .preview
    }

    func snapshot(for configuration: OpenGRAINCameraIntent, in context: Context) async -> GRAINWidgetEntry {
        .preview
    }

    func timeline(for configuration: OpenGRAINCameraIntent, in context: Context) async -> Timeline<GRAINWidgetEntry> {
        let entry = GRAINWidgetEntry(
            date: Date(),
            filmName: "PORTRA 400",
            filmSubtitle: "自然温润 · 经典人像",
            formatBadge: "RAW · 48MP",
            isVideoCapable: true
        )
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800)))
    }
}

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
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 3)
                            .frame(width: 58, height: 58)

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
                // 左半区：胶卷参数卡片
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

                // 分隔线
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // 右半区：3 个快捷功能直达按键
                VStack(spacing: 8) {
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

// MARK: - 统一分发视图 (Widget Entry View - iOS 17+ 适配)

struct GRAINWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: GRAINWidgetEntry

    var body: some View {
        Group {
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
        .containerBackground(for: .widget) {
            Color(red: 0.08, green: 0.08, blue: 0.09)
        }
    }
}

// MARK: - 官方 Widget 定义与 Bundle 入口 (支持 StaticConfiguration 与 iOS 17+ AppIntentConfiguration)

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
        .contentMarginsDisabled()
    }
}

@main
struct GRAINWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GRAINWidget()
    }
}
