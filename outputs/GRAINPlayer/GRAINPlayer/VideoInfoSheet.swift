import SwiftUI

// MARK: - 视频详细技术参数信息面板

public struct VideoInfoSheet: View {
    public let item: VideoItem
    public let metadata: VideoMetadata
    @Environment(\.dismiss) private var dismiss

    public init(item: VideoItem, metadata: VideoMetadata) {
        self.item = item
        self.metadata = metadata
    }

    public var body: some View {
        NavigationView {
            ZStack {
                GrainTheme.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 顶部视频卡片概要
                        headerCard

                        // 视频技术规格网格
                        VStack(spacing: 12) {
                            sectionHeader(title: "视频规格参数", icon: "film")
                            specsGrid
                        }

                        // 音频与元数据规格
                        VStack(spacing: 12) {
                            sectionHeader(title: "音频与存储信息", icon: "waveform")
                            audioAndStorageGrid
                        }

                        // 来源与路径
                        VStack(spacing: 12) {
                            sectionHeader(title: "文件来源与创建时间", icon: "folder")
                            sourceInfoCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("视频参数信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(GrainTheme.accent)
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 38))
                .foregroundColor(GrainTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GrainTheme.paper)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(item.source.displaySourceLabel)
                        .font(.caption)
                        .foregroundColor(item.isHidden ? GrainTheme.danger : GrainTheme.muted)

                    Text("·")
                        .foregroundColor(GrainTheme.line)

                    Text(FormatUtils.formatDuration(metadata.duration))
                        .font(.caption)
                        .foregroundColor(GrainTheme.paper)
                }
            }
            Spacer()
        }
        .padding(16)
        .grainCard()
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(GrainTheme.accent)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(GrainTheme.muted)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var specsGrid: some View {
        VStack(spacing: 8) {
            infoRow(title: "分辨率", value: metadata.resolutionString, badge: metadata.resolutionPill)
            infoRow(title: "帧率 (FPS)", value: metadata.frameRate > 0 ? String(format: "%.2f fps", metadata.frameRate) : "--", badge: metadata.fpsPill)
            infoRow(title: "编码格式", value: metadata.codecName.isEmpty ? "AVC / H.264" : metadata.codecName)
            infoRow(title: "色彩原色", value: metadata.colorPrimaries.isEmpty ? "Standard (sRGB)" : metadata.colorPrimaries)
            infoRow(title: "动态范围 (HDR)", value: metadata.isHDR ? "HDR 高动态范围" : "SDR 标准动态范围", badge: metadata.isHDR ? "HDR" : nil)
            infoRow(title: "视频码率", value: FormatUtils.formatBitrate(metadata.nominalBitrate))
        }
        .padding(14)
        .grainCard()
    }

    private var audioAndStorageGrid: some View {
        VStack(spacing: 8) {
            infoRow(title: "音频编码", value: metadata.audioFormat.isEmpty ? "AAC" : metadata.audioFormat)
            infoRow(title: "声道配置", value: metadata.audioChannels > 0 ? "\(metadata.audioChannels) 声道" : "立体声")
            infoRow(title: "文件大小", value: FormatUtils.formatFileSize(metadata.fileSize))
            infoRow(title: "视频时长", value: FormatUtils.formatDuration(metadata.duration))
        }
        .padding(14)
        .grainCard()
    }

    private var sourceInfoCard: some View {
        VStack(spacing: 8) {
            infoRow(title: "存储位置", value: item.source.displaySourceLabel)
            infoRow(title: "拍摄/创建时间", value: FormatUtils.formatDate(metadata.creationDate))
            if item.isHidden {
                infoRow(title: "隐私保护", value: "已启用 Face ID / Touch ID 加密保护")
            }
        }
        .padding(14)
        .grainCard()
    }

    private func infoRow(title: String, value: String, badge: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(GrainTheme.muted)
            Spacer()
            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(GrainTheme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(GrainTheme.accent.opacity(0.15))
                    .cornerRadius(3)
            }
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(GrainTheme.paper)
        }
        .padding(.vertical, 3)
    }
}
