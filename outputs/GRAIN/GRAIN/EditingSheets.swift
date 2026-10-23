import SwiftUI
import UIKit

struct TextOverlayEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    let overlayID: UUID
    @State private var draft = PhotoTextOverlay()
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("添加文字")
                        .font(.system(size: 23, weight: .bold, design: .serif))
                        .foregroundStyle(GrainTheme.paper)
                    Spacer()
                    Button {
                        editor.deleteTextOverlay(id: overlayID)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(GrainTheme.muted)
                    }
                    .buttonStyle(.plain)
                    Button {
                        if draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            editor.deleteTextOverlay(id: overlayID)
                        } else {
                            editor.updateTextOverlay(draft)
                        }
                        dismiss()
                    } label: {
                        Text("完成")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(GrainTheme.black)
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background(GrainTheme.paper, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.text)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                        .scrollContentBackground(.hidden)
                        .padding(10)

                    if draft.text.isEmpty {
                        Text("输入文字")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(GrainTheme.muted.opacity(0.46))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 105)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(GrainTheme.line, lineWidth: 1)
                }

                HStack(spacing: 8) {
                    ForEach(PhotoTextFont.allCases) { font in
                        Button {
                            draft.font = font
                        } label: {
                            Text(font.title)
                                .font(font.swiftUIFont(size: 13))
                                .foregroundStyle(draft.font == font ? GrainTheme.black : GrainTheme.paper)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    draft.font == font ? GrainTheme.paper : GrainTheme.raised,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Text("字号")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                    Slider(
                        value: $draft.fontSize,
                        in: 0.025...0.18
                    )
                    .tint(GrainTheme.accent)
                    Text("\(Int(draft.fontSize * 100))")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(width: 30)
                }

                HStack(spacing: 10) {
                    Text("颜色")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                    ForEach(Array(colorOptions.enumerated()), id: \.offset) { _, color in
                        Button {
                            applyColor(color)
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 23, height: 23)
                                .overlay {
                                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.7)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(red: draft.red, green: draft.green, blue: draft.blue, opacity: draft.alpha) },
                            set: { applyColor($0) }
                        ),
                        supportsOpacity: true
                    )
                    .labelsHidden()
                }

                Text("支持 Emoji。文字可以直接在照片上拖动位置。")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(GrainTheme.muted)
            }
            .padding(20)
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            if let overlay = editor.textOverlays.first(where: { $0.id == overlayID }) {
                draft = overlay
            }
        }
    }

    private var colorOptions: [Color] {
        [
            GrainTheme.paper,
            .black,
            GrainTheme.accent,
            .red,
            .yellow,
            .blue,
            .green
        ]
    }

    private func applyColor(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            draft.red = red
            draft.green = green
            draft.blue = blue
            draft.alpha = alpha
        }
    }
}

extension PhotoTextFont {
    func swiftUIFont(size: CGFloat) -> Font {
        switch self {
        case .rounded: .system(size: size, weight: .semibold, design: .rounded)
        case .serif: .system(size: size, weight: .semibold, design: .serif)
        case .monospaced: .system(size: size, weight: .semibold, design: .monospaced)
        }
    }
}

struct ImageInfoSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    /// 按内容实际高度撑开 sheet，避免信息区下面留出一大片空白
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            GrainTheme.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("图片信息")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(GrainTheme.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                if let photo = editor.photo {
                    VStack(spacing: 0) {
                        infoRow("文件名", photo.displayName)
                        infoRow("图片尺寸", photo.dimensionsLabel)
                        infoRow("像素", photo.megapixelsLabel)
                        infoRow("文件大小", photo.fileSizeLabel)
                        infoRow("机型", photo.cameraLabel.isEmpty ? "未记录" : photo.cameraLabel)
                        infoRow("镜头", photo.lensModel.isEmpty ? "未记录" : photo.lensModel)
                        infoRow("拍摄时间", formattedDate(photo.capturedAt))
                        infoRow("位置", locationText(photo), isLast: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ImageInfoHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        .onPreferenceChange(ImageInfoHeightKey.self) { height in
            guard height > 240, abs(height - contentHeight) > 0.5 else { return }
            contentHeight = height
        }
        .presentationDetents([.height(contentHeight > 0 ? contentHeight + 20 : 470)])
        .presentationDragIndicator(.visible)
    }

    private func infoRow(_ title: String, _ value: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(GrainTheme.paper)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
            if !isLast {
                EmptyView()
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(GrainTheme.line).frame(height: 1)
            }
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "未记录" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return formatter.string(from: date)
    }

    private func locationText(_ photo: PhotoAsset) -> String {
        guard let latitude = photo.latitude, let longitude = photo.longitude else {
            return "未记录"
        }
        return String(format: "%.6f, %.6f", latitude, longitude)
    }
}

private struct ImageInfoHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct FilmOrderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("filmOrder") private var filmOrder = ""
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var profiles = FilmProfile.defaultDisplayOrder
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("胶片排序")
                            .font(.system(size: 25, weight: .bold, design: .serif))
                            .foregroundStyle(GrainTheme.paper)
                        Text("拖动右侧手柄调整顺序，返回后立即同步到胶片栏")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }

                    Spacer()

                    Button {
                        resetOrder()
                    } label: {
                        Text("恢复默认")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                            .padding(.horizontal, 10)
                            .frame(height: 29)
                            .background(GrainTheme.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Text("完成")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(GrainTheme.black)
                            .padding(.horizontal, 13)
                            .frame(height: 31)
                            .background(GrainTheme.paper, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)

                List {
                    ForEach(profiles) { profile in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(hex: 0x171714))
                                RadialGradient(
                                    colors: [
                                        profile.uiPalette[1].opacity(0.24),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: 24
                                )
                                FilmCameraGlyph(profile: profile)
                                    .padding(.horizontal, 1)
                            }
                            .frame(width: 46, height: 31)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(GrainTheme.paper)
                                Text(profile.descriptor)
                                    .font(.system(size: 8.5, design: .rounded))
                                    .foregroundStyle(GrainTheme.muted)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .listRowBackground(GrainTheme.surface)
                        .listRowSeparatorTint(GrainTheme.line)
                    }
                    .onMove(perform: move)
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            profiles = FilmProfile.resolvedDisplayOrder(from: filmOrder)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        persistOrder()
    }

    private func resetOrder() {
        withAnimation(.easeOut(duration: 0.2)) {
            profiles = FilmProfile.defaultDisplayOrder
        }
        persistOrder()
    }

    private func persistOrder() {
        filmOrder = profiles.map(\.rawValue).joined(separator: ",")
        GrainHaptics.lightImpact(enabled: hapticsEnabled)
    }

}

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("showHistogram") private var showHistogram = true
    @AppStorage("showCameraButton") private var showCameraButton = true
    @AppStorage("showFileImportButton") private var showFileImportButton = false
    @AppStorage("showCollageButton") private var showCollageButton = true
    @AppStorage("captureLocationEnabled") private var captureLocationEnabled = true
    @AppStorage("captureDeviceInfoEnabled") private var captureDeviceInfoEnabled = true

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("设置")
                            .font(.system(size: 26, weight: .bold, design: .serif))
                        Text("GRAIN 1.1 · \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 31, height: 31)
                            .background(GrainTheme.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("震动反馈")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("用于参数滑动、文字吸附和返回手势")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $hapticsEnabled)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                        .onChange(of: hapticsEnabled) { _, enabled in
                            if enabled {
                                GrainHaptics.lightImpact(enabled: true)
                            }
                        }
                }
                .padding(16)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }

                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("主页直方图")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("打开照片后显示实时 RGB 直方图")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $showHistogram)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }

                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("主页相机入口")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("立即同步到主页右上角功能区")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $showCameraButton)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }

                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("主页文件导入")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("控制主页右上角的文件导入入口")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $showFileImportButton)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }

                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("主页拼图入口")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("控制主页右上角的拼图创建入口")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $showCollageButton)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }

                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("位置信息")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("在拍摄的照片中写入 GPS 位置")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $captureLocationEnabled)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                        .onChange(of: captureLocationEnabled) { _, enabled in
                            if enabled {
                                // 用户在这里主动打开，才允许弹出系统授权
                                CaptureLocationProvider.shared.requestAuthorization()
                            } else {
                                CaptureLocationProvider.shared.stop()
                            }
                        }
                }
                .padding(16)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }

                HStack(spacing: 12) {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("机型与镜头参数")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("在拍摄的照片中写入相机型号与镜头信息")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $captureDeviceInfoEnabled)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 17))
                .overlay {
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }

                Spacer()
            }
            .padding(20)
        }
    }
}
