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
                    .onChange(of: draft.fontSize) { _, _ in
                        GrainHaptics.selection()
                    }
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

/// iOS 27 Liquid Glass AI 智能调色与 API 调节配置卡片
struct AiApiSettingsCard: View {
    @AppStorage("aiApiEnabled") private var aiApiEnabled = true
    @AppStorage("aiApiBaseURL") private var aiApiBaseURL = "https://api.deepseek.com"
    @AppStorage("aiApiKey") private var aiApiKey = ""
    @AppStorage("aiApiModel") private var aiApiModel = "deepseek-chat"
    @AppStorage("aiApiTemperature") private var aiApiTemperature = 0.7
    @AppStorage("aiApiStylePrompt") private var aiApiStylePrompt = "胶片质感, 高动态范围, 柔和高光, 细致颗粒"

    @State private var showApiKey = false
    @State private var isTesting = false
    @State private var testResultText: String?
    @State private var testIsSuccess: Bool = false

    enum ProviderPreset: String, CaseIterable, Identifiable {
        case deepseek = "DeepSeek"
        case openai = "OpenAI"
        case openrouter = "OpenRouter"
        case custom = "自定义"

        var id: String { rawValue }

        var baseURL: String {
            switch self {
            case .deepseek: "https://api.deepseek.com"
            case .openai: "https://api.openai.com/v1"
            case .openrouter: "https://openrouter.ai/api/v1"
            case .custom: ""
            }
        }

        var defaultModel: String {
            switch self {
            case .deepseek: "deepseek-chat"
            case .openai: "gpt-4o"
            case .openrouter: "deepseek/deepseek-chat"
            case .custom: ""
            }
        }
    }

    private func applyPreset(_ preset: ProviderPreset) {
        if preset != .custom {
            aiApiBaseURL = preset.baseURL
            aiApiModel = preset.defaultModel
        }
        GrainHaptics.selection(enabled: true)
    }

    private func testConnection() {
        let cleanURLString = aiApiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanURLString) else {
            testIsSuccess = false
            testResultText = "URL 格式不合法"
            GrainHaptics.error(enabled: true)
            return
        }

        isTesting = true
        testResultText = nil

        let testEndpoint = url.appendingPathComponent("models")
        var request = URLRequest(url: testEndpoint, timeoutInterval: 8.0)
        request.httpMethod = "GET"
        let cleanKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanKey.isEmpty {
            request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        URLSession.shared.dataTask(with: request) { _, response, error in
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            DispatchQueue.main.async {
                self.isTesting = false
                if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        self.testIsSuccess = true
                        self.testResultText = "连接成功 (HTTP \(httpResponse.statusCode)) · \(elapsed)ms"
                        GrainHaptics.success(enabled: true)
                    } else if httpResponse.statusCode == 401 {
                        self.testIsSuccess = false
                        self.testResultText = "服务器已响应但 API Key 无效 (401)"
                        GrainHaptics.warning(enabled: true)
                    } else {
                        self.testIsSuccess = true
                        self.testResultText = "连通正常 (HTTP \(httpResponse.statusCode)) · \(elapsed)ms"
                        GrainHaptics.selection(enabled: true)
                    }
                } else if let error = error {
                    self.testIsSuccess = false
                    self.testResultText = "连接失败: \(error.localizedDescription)"
                    GrainHaptics.error(enabled: true)
                } else {
                    self.testIsSuccess = false
                    self.testResultText = "未知连接状态"
                }
            }
        }.resume()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(GrainTheme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("AI 智能调色与 API 调节")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                        Text("API 2.0")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(GrainTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(GrainTheme.accent.opacity(0.18), in: Capsule())
                    }
                    Text("自定义大模型色彩科学接口、参数与提示词")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                }
                Spacer()
                Toggle("", isOn: $aiApiEnabled)
                    .labelsHidden()
                    .tint(GrainTheme.accent)
            }

            if aiApiEnabled {
                Divider()
                    .overlay(Color.white.opacity(0.08))

                // Provider Presets Chips
                VStack(alignment: .leading, spacing: 7) {
                    Text("服务商预设")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)

                    HStack(spacing: 6) {
                        ForEach(ProviderPreset.allCases) { preset in
                            let isSelected = (preset != .custom && aiApiBaseURL == preset.baseURL)
                            Button {
                                applyPreset(preset)
                            } label: {
                                Text(preset.rawValue)
                                    .font(.system(size: 9.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? GrainTheme.black : GrainTheme.paper)
                                    .padding(.horizontal, 10)
                                    .frame(height: 25)
                                    .background(isSelected ? GrainTheme.accent : GrainTheme.raised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // API Base URL Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("接口地址 (Base URL)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                            .foregroundStyle(GrainTheme.muted)
                            .frame(width: 14)
                        TextField("https://api.openai.com/v1", text: $aiApiBaseURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(GrainTheme.paper)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(GrainTheme.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    }
                }

                // API Key Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key (密钥)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GrainTheme.muted)
                            .frame(width: 14)
                        if showApiKey {
                            TextField("sk-...", text: $aiApiKey)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(GrainTheme.paper)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("sk-...", text: $aiApiKey)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(GrainTheme.paper)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showApiKey.toggle()
                            GrainHaptics.selection(enabled: true)
                        } label: {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                                .font(.system(size: 11))
                                .foregroundStyle(GrainTheme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(GrainTheme.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    }
                }

                // Model Name Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型名称 (Model)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11))
                            .foregroundStyle(GrainTheme.muted)
                            .frame(width: 14)
                        TextField("gpt-4o / deepseek-chat", text: $aiApiModel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(GrainTheme.paper)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(GrainTheme.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    }
                }

                // Temperature Slider
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("采样温度 (Temperature)")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                        Spacer()
                        Text(String(format: "%.2f", aiApiTemperature))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(GrainTheme.accent)
                    }
                    Slider(value: $aiApiTemperature, in: 0.0...1.5, step: 0.05)
                        .tint(GrainTheme.accent)
                }

                // Style Prompt Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("风格提示词偏好 (Style Prompt)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                    HStack(spacing: 8) {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 11))
                            .foregroundStyle(GrainTheme.muted)
                            .frame(width: 14)
                        TextField("胶片感、高宽容度、柔和高光", text: $aiApiStylePrompt)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(GrainTheme.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    }
                }

                // Test Connection Button & Status
                HStack(spacing: 10) {
                    Button {
                        testConnection()
                    } label: {
                        HStack(spacing: 5) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(GrainTheme.black)
                            } else {
                                Image(systemName: "bolt.horizontal.fill")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            Text(isTesting ? "测试中..." : "测试连接")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(GrainTheme.black)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(GrainTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isTesting)

                    if let result = testResultText {
                        HStack(spacing: 4) {
                            Image(systemName: testIsSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(testIsSuccess ? Color.green : Color.orange)
                            Text(result)
                                .font(.system(size: 9.5, design: .rounded))
                                .foregroundStyle(testIsSuccess ? Color.green : Color.orange)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 18)
    }
}

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private func launchChip(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? GrainTheme.black : GrainTheme.muted)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    selected ? GrainTheme.accent : GrainTheme.raised,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("cameraAppearanceMode") private var cameraAppearanceMode = CameraAppearanceMode.dark
    @AppStorage("showHistogram") private var showHistogram = true
    @AppStorage("showCameraButton") private var showCameraButton = true
    @AppStorage("showFileImportButton") private var showFileImportButton = false
    @AppStorage("showCollageButton") private var showCollageButton = true
    @AppStorage("captureLocationEnabled") private var captureLocationEnabled = true
    @AppStorage("captureDeviceInfoEnabled") private var captureDeviceInfoEnabled = true
    @AppStorage("shutterSoundEnabled") private var shutterSoundEnabled = true
    @AppStorage("focusPeakingColor") private var focusPeakingColor = "red"
    /// 启动时直接进相机（关则停在图库主页）
    @AppStorage("launchWithCamera") private var launchWithCamera = false
    /// 拍摄锐度：-50 柔化 … 0 相机原样 … +50 锐化
    @AppStorage("cameraSharpening") private var cameraSharpening = 0
    /// 人脸追焦：关掉后只保留连续自动对焦，不做人脸检测
    @AppStorage("faceTrackingEnabled") private var faceTrackingEnabled = true
    @State private var showWidgetShowcase = false

    private var sharpeningLabel: String {
        if cameraSharpening <= -5 {
            return "柔和 \(cameraSharpening)"
        }
        if cameraSharpening >= 5 {
            return "锐利 +\(cameraSharpening)"
        }
        return "标准"
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
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
                            .frame(width: 32, height: 32)
                            .liquidGlassCircle(size: 32)
                    }
                    .buttonStyle(LiquidGlassButtonStyle())
                }

                // AI 智能调色与 API 调节（全新功能）
                AiApiSettingsCard()

                // 外观模式（主页与编辑页面，不控制相机）
                HStack(spacing: 12) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("外观模式")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                        Text("主页与编辑页面外观（不影响相机）")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Button {
                                appearanceMode = mode
                                GrainHaptics.selection()
                            } label: {
                                Text(mode.shortTitle)
                                    .font(.system(size: 10, weight: appearanceMode == mode ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(appearanceMode == mode ? GrainTheme.black : GrainTheme.muted)
                                    .padding(.horizontal, 9)
                                    .frame(height: 26)
                                    .background(appearanceMode == mode ? GrainTheme.paper : GrainTheme.raised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)

                // 相机外观（独立控制拍照与视频录制页面的白天/黑夜）
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("相机外观")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                        Text("拍照与视频录制页面的白天/黑夜模式")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(CameraAppearanceMode.allCases) { mode in
                            Button {
                                cameraAppearanceMode = mode
                                GrainHaptics.selection()
                            } label: {
                                Text(mode.shortTitle)
                                    .font(.system(size: 10, weight: cameraAppearanceMode == mode ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(cameraAppearanceMode == mode ? GrainTheme.black : GrainTheme.muted)
                                    .padding(.horizontal, 9)
                                    .frame(height: 26)
                                    .background(cameraAppearanceMode == mode ? GrainTheme.paper : GrainTheme.raised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)

                HStack(spacing: 12) {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("启动时打开")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("打开软件后先进图库还是直接进相机")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        launchChip(title: "图库", selected: !launchWithCamera) {
                            launchWithCamera = false
                        }
                        launchChip(title: "相机", selected: launchWithCamera) {
                            launchWithCamera = true
                        }
                    }
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)

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
                .liquidGlass(cornerRadius: 18)

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
                .liquidGlass(cornerRadius: 18)

                // 桌面与锁屏小组件（官方 HIG 规范第 1 版）
                Button {
                    showWidgetShowcase = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.dashed.inset.filled")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(GrainTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("桌面与锁屏小组件")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(GrainTheme.paper)
                                Text("官方规范")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(GrainTheme.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(GrainTheme.accent.opacity(0.18), in: Capsule())
                            }
                            Text("Small 158pt · Medium 338pt · Lock Screen 锁屏圆标/长条预览")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(GrainTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 18)
                }
                .buttonStyle(.plain)

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
                .liquidGlass(cornerRadius: 18)

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
                .liquidGlass(cornerRadius: 18)

                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("主页编辑工作台入口")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("控制主页右上角的多功能编辑工作台入口")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $showCollageButton)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)

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
                .liquidGlass(cornerRadius: 18)

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
                .liquidGlass(cornerRadius: 18)

                // 快门声音
                HStack(spacing: 12) {
                    Image(systemName: "camera.shutter.button")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("快门声音")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("机械快门声，手动对焦时也有提示音")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $shutterSoundEnabled)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)

                HStack(spacing: 12) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("人脸追焦")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("关闭后只做连续自动对焦，不再检测人脸")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $faceTrackingEnabled)
                        .labelsHidden()
                        .tint(GrainTheme.accent)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)

                // 拍摄锐度
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(GrainTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("拍摄锐度")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("向左柔化可抵消系统相机的锐化感，向右更锐利")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(GrainTheme.muted)
                        }
                        Spacer()
                        Text(sharpeningLabel)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(
                                cameraSharpening == 0 ? GrainTheme.muted : GrainTheme.accent
                            )
                    }

                    HStack(spacing: 9) {
                        Text("柔和")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                        ResetValueSlider(
                            value: Binding(
                                get: { Double(cameraSharpening) },
                                set: { cameraSharpening = Int(($0 / 5).rounded()) * 5 }
                            ),
                            range: -50...50,
                            onEditStart: {
                                GrainHaptics.prepare()
                            },
                            onReset: {
                                cameraSharpening = 0
                                GrainHaptics.selection(enabled: hapticsEnabled)
                            }
                        )
                        Text("锐利")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)

                // 峰值对焦颜色
                HStack(spacing: 12) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("峰值对焦颜色")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("相机与编辑页的合焦描边共用")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(FocusPeakingColor.allCases) { option in
                            Button {
                                focusPeakingColor = option.rawValue
                                GrainHaptics.selection(enabled: hapticsEnabled)
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle().stroke(
                                            focusPeakingColor == option.rawValue
                                                ? GrainTheme.paper
                                                : Color.white.opacity(0.16),
                                            lineWidth: focusPeakingColor == option.rawValue ? 1.8 : 0.8
                                        )
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                        }
                    }
                }
                .padding(16)
                .liquidGlass(cornerRadius: 18)
            }
            .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showWidgetShowcase) {
            WidgetShowcaseView()
        }
    }
}
