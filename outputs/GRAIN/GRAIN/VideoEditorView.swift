import SwiftUI
import AVFoundation
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 视频调节数据模型

public struct VideoEditRecipe: Equatable {
    // 时间修剪 (秒)
    var trimStart: Double = 0
    var trimEnd: Double = 0

    // 曝光与画面调节 (-100 ... 100)
    var exposure: Double = 0        // 曝光 -100...100 -> -1.5...1.5 EV
    var contrast: Double = 0        // 对比度 -100...100 -> 0.5...1.5
    var brightness: Double = 0      // 亮度 -100...100 -> -0.4...0.4
    var highlights: Double = 0      // 高光 -100...100
    var shadows: Double = 0         // 阴影 -100...100
    var saturation: Double = 0      // 饱和度 -100...100 -> 0.0...2.0
    var warmth: Double = 0          // 色温 -100...100
    var vignette: Double = 0        // 暗角 0...100 -> 0.0...1.5

    // 胶片滤镜
    var filmProfile: FilmProfile = .neutral
    var filmIntensity: Double = 1.0

    // 画面裁切与旋转
    var rotationDegrees: Int = 0    // 0, 90, 180, 270
    var isMirrored: Bool = false
    var aspect: VideoCropAspect = .original
    var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1) // 归一化裁切区域 (0...1)

    var isNeutral: Bool {
        exposure == 0 &&
        contrast == 0 &&
        brightness == 0 &&
        highlights == 0 &&
        shadows == 0 &&
        saturation == 0 &&
        warmth == 0 &&
        vignette == 0 &&
        filmProfile == .neutral &&
        rotationDegrees == 0 &&
        !isMirrored &&
        aspect == .original &&
        cropRect == CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    func cropAspectRatio(for naturalSize: CGSize) -> CGFloat {
        if let fixed = aspect.fixedRatio {
            return fixed
        }
        let w = cropRect.width * naturalSize.width
        let h = cropRect.height * naturalSize.height
        guard h > 0 else { return 9 / 16 }
        return w / h
    }
}

public enum VideoCropAspect: String, CaseIterable, Identifiable {
    case original = "原画"
    case freeform = "自由"
    case portrait9x16 = "9:16"
    case landscape16x9 = "16:9"
    case square1x1 = "1:1"
    case portrait4x5 = "4:5"

    public var id: String { rawValue }

    var fixedRatio: CGFloat? {
        switch self {
        case .original, .freeform:
            return nil
        case .portrait9x16:
            return 9 / 16
        case .landscape16x9:
            return 16 / 9
        case .square1x1:
            return 1 / 1
        case .portrait4x5:
            return 4 / 5
        }
    }

    func ratio(for naturalSize: CGSize) -> CGFloat {
        switch self {
        case .original, .freeform:
            guard naturalSize.height > 0 else { return 9 / 16 }
            return naturalSize.width / naturalSize.height
        case .portrait9x16:
            return 9 / 16
        case .landscape16x9:
            return 16 / 9
        case .square1x1:
            return 1 / 1
        case .portrait4x5:
            return 4 / 5
        }
    }
}

public enum VideoAdjustParam: String, CaseIterable, Identifiable {
    case exposure = "曝光"
    case contrast = "对比度"
    case brightness = "亮度"
    case highlights = "高光"
    case shadows = "阴影"
    case saturation = "饱和度"
    case warmth = "色温"
    case vignette = "暗角"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .contrast: "circle.lefthalf.filled"
        case .brightness: "sun.max"
        case .highlights: "sun.haze"
        case .shadows: "moon"
        case .saturation: "drop"
        case .warmth: "thermometer.sun"
        case .vignette: "circle.circle"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .vignette: return 0...100
        default: return -100...100
        }
    }

    func value(in recipe: VideoEditRecipe) -> Double {
        switch self {
        case .exposure: return recipe.exposure
        case .contrast: return recipe.contrast
        case .brightness: return recipe.brightness
        case .highlights: return recipe.highlights
        case .shadows: return recipe.shadows
        case .saturation: return recipe.saturation
        case .warmth: return recipe.warmth
        case .vignette: return recipe.vignette
        }
    }

    func applying(_ value: Double, to recipe: inout VideoEditRecipe) {
        switch self {
        case .exposure: recipe.exposure = value
        case .contrast: recipe.contrast = value
        case .brightness: recipe.brightness = value
        case .highlights: recipe.highlights = value
        case .shadows: recipe.shadows = value
        case .saturation: recipe.saturation = value
        case .warmth: recipe.warmth = value
        case .vignette: recipe.vignette = max(0, value)
        }
    }
}

public enum VideoEditorTab: String, CaseIterable, Identifiable {
    case trim = "裁剪"
    case adjust = "调节"
    case filter = "滤镜"
    case crop = "构图"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .trim: "film"
        case .adjust: "slider.horizontal.3"
        case .filter: "camera.filters"
        case .crop: "crop.rotate"
        }
    }
}

// MARK: - 视频调节视图主界面

public struct VideoEditorView: View {
    let asset: PHAsset
    let onClose: () -> Void

    @State private var avAsset: AVAsset?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0

    @State private var recipe = VideoEditRecipe()
    @State private var activeTab: VideoEditorTab = .trim
    @State private var activeParam: VideoAdjustParam = .exposure

    @State private var thumbnails: [UIImage] = []
    @State private var isComparing = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var errorMessage: String?
    @State private var naturalVideoSize: CGSize = CGSize(width: 1080, height: 1920)

    @State private var timeObserverToken: Any?
    @State private var didSwipeBack = false
    @State private var showDeleteConfirmation = false
    @State private var shareURL: URL?
    @State private var isSharing = false
    @State private var lastParamHapticStep: Int = 0
    @State private var lastTrimHapticStep: Int = 0

    public init(asset: PHAsset, onClose: @escaping () -> Void) {
        self.asset = asset
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .frame(height: 50)

                videoPreviewCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomControlDeck
            }

            if isExporting {
                exportingOverlay
            }

            if let errorMessage {
                errorAlert(errorMessage)
            }
        }
        .statusBarHidden()
        .simultaneousGesture(edgeSwipeBackGesture)
        .confirmationDialog(
            "删除此视频？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("从相册删除视频", role: .destructive) {
                deleteVideoAsset()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $isSharing) {
            if let shareURL {
                ActivityShareSheet(activityItems: [shareURL])
            }
        }
        .task {
            await loadVideoAsset()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .onChange(of: recipe) { _, newRecipe in
            applyRecipeToPlayer(newRecipe)
        }
    }

    // MARK: - 顶栏：取消、对比、时间回显、分享、删除、完成导出

    private var topBar: some View {
        HStack(spacing: 10) {
            Button("取消") {
                cleanupPlayer()
                onClose()
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(GrainTheme.paper)
            .buttonStyle(.plain)

            Spacer()

            if duration > 0 {
                Text("\(formatTime(currentTime)) / \(formatTime(recipe.trimEnd - recipe.trimStart))")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(GrainTheme.muted)
            }

            Spacer()

            // 按住对比原视频
            Button {
            } label: {
                Image(systemName: isComparing ? "eye.fill" : "eye")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isComparing ? GrainTheme.accent : GrainTheme.paper)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isComparing = true; updateComposition(compare: true) }
                    .onEnded { _ in isComparing = false; updateComposition(compare: false) }
            )

            // 分享
            Button {
                shareCurrentVideo()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

            // 删除
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

            Button {
                exportVideo()
            } label: {
                Text("完成")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(GrainTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
    }

    // MARK: - 播放画布与手势

    private var videoPreviewCanvas: some View {
        GeometryReader { proxy in
            let aspect = activeTab == .crop
                ? (naturalVideoSize.width / max(naturalVideoSize.height, 1))
                : recipe.cropAspectRatio(for: naturalVideoSize)
            let frame = fittedRect(for: aspect, in: proxy.size)

            ZStack {
                if let player {
                    VideoPlayerUIView(player: player)
                        .rotationEffect(.degrees(Double(recipe.rotationDegrees)))
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            togglePlayPause()
                        }

                    if activeTab == .crop {
                        VideoCropSelectionOverlay(
                            cropRect: $recipe.cropRect,
                            aspect: recipe.aspect,
                            naturalSize: naturalVideoSize,
                            displaySize: frame
                        )
                    }

                    // 播放/暂停状态悬浮浮标
                    if !isPlaying && activeTab != .crop {
                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 60, height: 60)
                                .background(Color.black.opacity(0.48), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                } else {
                    ProgressView()
                        .tint(GrainTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 底部控制区

    private var bottomControlDeck: some View {
        VStack(spacing: 12) {
            // 当前子功能的操作面板
            Group {
                switch activeTab {
                case .trim:
                    timelineTrimDeck
                case .adjust:
                    adjustParamDeck
                case .filter:
                    filterSelectionDeck
                case .crop:
                    cropAspectDeck
                }
            }
            .frame(height: 84)

            // 底部 4 个主模式切换胶囊
            HStack(spacing: 24) {
                ForEach(VideoEditorTab.allCases) { tab in
                    Button {
                        activeTab = tab
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: activeTab == tab ? .bold : .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: activeTab == tab ? .bold : .medium))
                        }
                        .foregroundStyle(activeTab == tab ? GrainTheme.accent : GrainTheme.muted)
                        .frame(minWidth: 48)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(GrainTheme.surface.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - 1. 裁剪时间条（参考 iOS 照片应用）

    private var timelineTrimDeck: some View {
        GeometryReader { proxy in
            let totalW = max(proxy.size.width - 32, 1)
            let totalDuration = max(duration, 0.1)
            let startRatio = CGFloat(recipe.trimStart / totalDuration)
            let endRatio = CGFloat(recipe.trimEnd / totalDuration)
            let leftX = totalW * startRatio
            let rightX = totalW * endRatio
            let currentX = totalW * CGFloat(min(max(currentTime / totalDuration, 0), 1))

            ZStack(alignment: .leading) {
                // 缩略图底条
                HStack(spacing: 0) {
                    if thumbnails.isEmpty {
                        Color.white.opacity(0.08)
                    } else {
                        ForEach(0..<thumbnails.count, id: \.self) { idx in
                            Image(uiImage: thumbnails[idx])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: totalW / CGFloat(thumbnails.count), height: 46)
                                .clipped()
                        }
                    }
                }
                .frame(width: totalW, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // 左侧未选中的阴暗层
                Color.black.opacity(0.68)
                    .frame(width: max(leftX, 0), height: 46)

                // 右侧未选中的阴暗层
                Color.black.opacity(0.68)
                    .frame(width: max(totalW - rightX, 0), height: 46)
                    .offset(x: rightX)

                // 黄色/高亮裁剪边框与左右手柄
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(GrainTheme.accent, lineWidth: 3)
                        .frame(width: max(rightX - leftX, 16), height: 50)
                        .offset(x: leftX)

                    // 左滑块手柄
                    HStack(spacing: 0) {
                        Image(systemName: "chevron.compact.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GrainTheme.black)
                    }
                    .frame(width: 14, height: 50)
                    .background(GrainTheme.accent, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6))
                    .offset(x: leftX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                pause()
                                let newRatio = min(max(val.location.x / totalW, 0), endRatio - 0.05)
                                recipe.trimStart = Double(newRatio) * totalDuration
                                seek(to: recipe.trimStart)
                                let step = Int(recipe.trimStart * 5)
                                if step != lastTrimHapticStep {
                                    lastTrimHapticStep = step
                                    GrainHaptics.selection()
                                }
                            }
                    )

                    // 右滑块手柄
                    HStack(spacing: 0) {
                        Image(systemName: "chevron.compact.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GrainTheme.black)
                    }
                    .frame(width: 14, height: 50)
                    .background(GrainTheme.accent, in: UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6))
                    .offset(x: rightX - 14)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                pause()
                                let newRatio = min(max(val.location.x / totalW, startRatio + 0.05), 1.0)
                                recipe.trimEnd = Double(newRatio) * totalDuration
                                seek(to: recipe.trimEnd)
                                let step = Int(recipe.trimEnd * 5)
                                if step != lastTrimHapticStep {
                                    lastTrimHapticStep = step
                                    GrainHaptics.selection()
                                }
                            }
                    )

                    // 播放针（Playhead）
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3, height: 52)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: currentX - 1.5)
                }
            }
            .frame(width: totalW, height: 50)
            .padding(.horizontal, 16)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let ratio = min(max(val.location.x / totalW, 0), 1)
                        seek(to: Double(ratio) * totalDuration)
                        let step = Int(ratio * 30)
                        if step != lastTrimHapticStep {
                            lastTrimHapticStep = step
                            GrainHaptics.selection()
                        }
                    }
            )
        }
        .frame(height: 52)
    }

    // MARK: - 2. 曝光与各项画面调节（参考 iOS 风格滑杆与项）

    private var adjustParamDeck: some View {
        VStack(spacing: 6) {
            // 参数项水平切换
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(VideoAdjustParam.allCases) { param in
                        let val = param.value(in: recipe)
                        let isChanged = abs(val) > 0.001

                        Button {
                            activeParam = param
                            GrainHaptics.selection(enabled: true)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: param.icon)
                                    .font(.system(size: 11, weight: .bold))
                                Text(param.rawValue)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                if isChanged {
                                    Circle()
                                        .fill(GrainTheme.accent)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .foregroundStyle(activeParam == param ? GrainTheme.black : GrainTheme.paper)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                activeParam == param
                                    ? GrainTheme.accent
                                    : (isChanged ? GrainTheme.raised : Color.white.opacity(0.08)),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            // 当前参数滑杆
            HStack(spacing: 12) {
                Button {
                    var updated = recipe
                    activeParam.applying(0, to: &updated)
                    recipe = updated
                    GrainHaptics.lightImpact(enabled: true)
                } label: {
                    Text(String(format: "%+.0f", activeParam.value(in: recipe)))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(GrainTheme.accent)
                        .frame(width: 44)
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { activeParam.value(in: recipe) },
                        set: { val in
                            var updated = recipe
                            activeParam.applying(val, to: &updated)
                            let span = max(activeParam.range.upperBound - activeParam.range.lowerBound, 0.001)
                            let step = Int(((val - activeParam.range.lowerBound) / span * 40).rounded())
                            if step != lastParamHapticStep {
                                lastParamHapticStep = step
                                if abs(val) < (span / 80) {
                                    GrainHaptics.mediumImpact()
                                } else {
                                    GrainHaptics.selection()
                                }
                            }
                            recipe = updated
                        }
                    ),
                    in: activeParam.range
                )
                .tint(GrainTheme.accent)

                Button {
                    var updated = recipe
                    activeParam.applying(0, to: &updated)
                    recipe = updated
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GrainTheme.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - 3. 滤镜胶片风格选择

    private var filterProfiles: [FilmProfile] {
        FilmProfile.defaultDisplayOrder
    }

    private var filterSelectionDeck: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(filterProfiles) { profile in
                        let isSelected = recipe.filmProfile == profile
                        Button {
                            recipe.filmProfile = profile
                            GrainHaptics.selection(enabled: true)
                        } label: {
                            Text(profile.name)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? GrainTheme.black : GrainTheme.paper)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    isSelected ? GrainTheme.accent : GrainTheme.raised,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            if recipe.filmProfile != .neutral {
                HStack(spacing: 12) {
                    Text("浓度")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)

                    Slider(value: $recipe.filmIntensity, in: 0...1.5)
                        .tint(GrainTheme.accent)
                        .onChange(of: recipe.filmIntensity) { _, val in
                            let step = Int((val * 20).rounded())
                            if step != lastParamHapticStep {
                                lastParamHapticStep = step
                                GrainHaptics.selection()
                            }
                        }

                    Text("\(Int(recipe.filmIntensity * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(width: 40)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - 4. 构图与画幅比例选择

    private var cropAspectDeck: some View {
        HStack(spacing: 10) {
            // 旋转 90 度
            Button {
                recipe.rotationDegrees = (recipe.rotationDegrees + 90) % 360
                GrainHaptics.selection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rotate.right.fill")
                    Text("旋转")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.paper)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)

            // 水平镜像
            Button {
                recipe.isMirrored.toggle()
                GrainHaptics.selection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    Text("镜像")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(recipe.isMirrored ? GrainTheme.black : GrainTheme.paper)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(recipe.isMirrored ? GrainTheme.accent : GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)

            // 比例选择菜单
            Menu {
                ForEach(VideoCropAspect.allCases) { aspect in
                    Button(aspect.rawValue) {
                        applyCropAspect(aspect)
                        GrainHaptics.selection()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "aspectratio")
                    Text(recipe.aspect.rawValue)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.accent)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(GrainTheme.raised, in: Capsule())
            }

            // 重置裁切
            Button {
                recipe.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                recipe.aspect = .original
                recipe.rotationDegrees = 0
                recipe.isMirrored = false
                GrainHaptics.mediumImpact()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("重置")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func applyCropAspect(_ aspect: VideoCropAspect) {
        recipe.aspect = aspect
        if aspect == .original || aspect == .freeform {
            recipe.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        guard let targetRatio = aspect.fixedRatio, naturalVideoSize.height > 0 else { return }
        let naturalRatio = naturalVideoSize.width / naturalVideoSize.height
        var w = 1.0
        var h = naturalRatio / targetRatio
        if h > 1.0 {
            h = 1.0
            w = targetRatio / naturalRatio
        }
        recipe.cropRect = CGRect(
            x: max((1.0 - w) / 2, 0),
            y: max((1.0 - h) / 2, 0),
            width: min(w, 1.0),
            height: min(h, 1.0)
        )
    }

    // MARK: - 导出覆盖浮层

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(GrainTheme.accent)

                Text("正在处理并导出视频...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
            }
            .padding(24)
            .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func errorAlert(_ msg: String) -> some View {
        VStack {
            Text(msg)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(GrainTheme.danger, in: Capsule())
                .shadow(radius: 6)
            Spacer()
        }
        .padding(.top, 56)
    }

    // MARK: - 播放与滤镜管线控制

    private func loadVideoAsset() async {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { loadedAsset, _, _ in
                DispatchQueue.main.async {
                    guard let loadedAsset else {
                        continuation.resume()
                        return
                    }
                    self.avAsset = loadedAsset
                    let dur = loadedAsset.duration.seconds
                    self.duration = dur.isFinite && dur > 0 ? dur : 1.0
                    self.recipe.trimStart = 0
                    self.recipe.trimEnd = self.duration

                    if let track = loadedAsset.tracks(withMediaType: .video).first {
                        let transformed = track.naturalSize.applying(track.preferredTransform)
                        self.naturalVideoSize = CGSize(
                            width: max(abs(transformed.width), 1),
                            height: max(abs(transformed.height), 1)
                        )
                    }

                    self.setupPlayer(with: loadedAsset)
                    self.generateThumbnails(for: loadedAsset)
                    continuation.resume()
                }
            }
        }
    }

    private func setupPlayer(with asset: AVAsset) {
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = createVideoComposition(for: asset, recipe: recipe, compare: false)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // 监听播放进度与时间修剪循环
        let interval = CMTime(value: 1, timescale: 30)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            self.currentTime = seconds

            if seconds >= self.recipe.trimEnd {
                player.seek(to: CMTime(seconds: self.recipe.trimStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            }
        }
    }

    private func applyRecipeToPlayer(_ recipe: VideoEditRecipe) {
        guard let avAsset, let item = player?.currentItem else { return }
        item.videoComposition = createVideoComposition(for: avAsset, recipe: recipe, compare: isComparing)
    }

    private func updateComposition(compare: Bool) {
        guard let avAsset, let item = player?.currentItem else { return }
        item.videoComposition = createVideoComposition(for: avAsset, recipe: recipe, compare: compare)
    }

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= recipe.trimEnd || currentTime < recipe.trimStart {
                seek(to: recipe.trimStart)
            }
            player.play()
            isPlaying = true
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    private func cleanupPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    // MARK: - 视频缩略图抽取（用于时间条）

    private func generateThumbnails(for asset: AVAsset) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)

        let count = 8
        let total = duration
        let step = total / Double(count)
        var times: [NSValue] = []
        for i in 0..<count {
            let t = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
            times.append(NSValue(time: t))
        }

        let captureTimes = times
        Task.detached(priority: .utility) {
            var loaded: [UIImage] = []
            for val in captureTimes {
                let time = val.timeValue
                if let cgImg = try? generator.copyCGImage(at: time, actualTime: nil) {
                    loaded.append(UIImage(cgImage: cgImg))
                }
            }
            let finished = loaded
            await MainActor.run {
                self.thumbnails = finished
            }
        }
    }

    // MARK: - 实时 CIFilter 滤镜管线合成器

    private func createVideoComposition(for asset: AVAsset, recipe: VideoEditRecipe, compare: Bool) -> AVVideoComposition {
        let composition = AVMutableVideoComposition(asset: asset) { request in
            guard !compare else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            var image = request.sourceImage
            let extent = image.extent

            // 0. 构图裁切与镜像
            if recipe.cropRect != CGRect(x: 0, y: 0, width: 1, height: 1) {
                let cropX = recipe.cropRect.origin.x * extent.width
                let cropY = (1.0 - recipe.cropRect.origin.y - recipe.cropRect.height) * extent.height
                let cropW = recipe.cropRect.width * extent.width
                let cropH = recipe.cropRect.height * extent.height
                let cropBounds = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
                image = image.cropped(to: cropBounds)
                image = image.transformed(by: CGAffineTransform(translationX: -cropBounds.origin.x, y: -cropBounds.origin.y))
            }

            if recipe.isMirrored {
                image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -image.extent.width, y: 0))
            }

            // 1. 曝光调整 (-100...100 -> -1.5...1.5 EV)
            if recipe.exposure != 0 {
                let ev = (recipe.exposure / 100.0) * 1.5
                image = image.applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: ev
                ])
            }

            // 2. 基础色彩调整：对比度、亮度、饱和度
            let contrastVal = 1.0 + (recipe.contrast / 100.0) * 0.5
            let brightnessVal = (recipe.brightness / 100.0) * 0.35
            let saturationVal = 1.0 + (recipe.saturation / 100.0) * 0.8
            if recipe.contrast != 0 || recipe.brightness != 0 || recipe.saturation != 0 {
                image = image.applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: contrastVal,
                    kCIInputBrightnessKey: brightnessVal,
                    kCIInputSaturationKey: saturationVal
                ])
            }

            // 3. 高光与阴影
            if recipe.highlights != 0 || recipe.shadows != 0 {
                let hi = max(0, 1.0 - (recipe.highlights / 100.0) * 0.7)
                let sh = max(0, (recipe.shadows / 100.0) * 0.7)
                image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": hi,
                    "inputShadowAmount": sh
                ])
            }

            // 4. 色温
            if recipe.warmth != 0 {
                let targetTemp = 6500.0 + (recipe.warmth / 100.0) * 2200.0
                image = image.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: targetTemp, y: 0)
                ])
            }

            // 5. 胶片滤镜
            if recipe.filmProfile != .neutral {
                image = Self.applyFilmLook(to: image, profile: recipe.filmProfile, intensity: recipe.filmIntensity)
            }

            // 6. 暗角
            if recipe.vignette > 0 {
                let vig = (recipe.vignette / 100.0) * 1.6
                image = image.applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: vig,
                    kCIInputRadiusKey: 1.2
                ])
            }

            request.finish(with: image, context: nil)
        }

        let targetW = round(recipe.cropRect.width * naturalVideoSize.width / 2) * 2
        let targetH = round(recipe.cropRect.height * naturalVideoSize.height / 2) * 2
        composition.renderSize = CGSize(width: max(targetW, 16), height: max(targetH, 16))

        return composition
    }

    // MARK: - 胶片风格滤镜模拟算法

    private static func applyFilmLook(to image: CIImage, profile: FilmProfile, intensity: Double) -> CIImage {
        var graded = image
        switch profile {
        case .classicChrome, .classicNegative:
            // 经典正片：反差略高、轻微降低饱和度、暗部偏暖、高光偏青
            graded = graded
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.15,
                    kCIInputSaturationKey: 0.82
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6900, y: 8)
                ])
        case .portra, .portra160, .portra800:
            // 柔和肤色：阴影提亮，肤色微红润暖调
            graded = graded
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.85,
                    "inputShadowAmount": 0.28
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7100, y: 12)
                ])
        case .cinestill, .film135t, .vision500t:
            // 电影冷调：暗部青蓝、高光暖调
            graded = graded
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 1.18,
                    kCIInputSaturationKey: 0.9
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5800, y: -15)
                ])
        case .gold, .colorPlus200:
            // 暖金黄昏
            graded = graded
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7800, y: 22)
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.1
                ])
        case .eterna, .nostalgicNeg:
            // 柔和电影低对比
            graded = graded
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 0.92,
                    kCIInputSaturationKey: 0.88
                ])
        default:
            break
        }

        // 依浓度线性混合
        if intensity >= 0.999 {
            return graded
        }
        return graded.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: image,
            kCIInputTimeKey: max(0, 1.0 - intensity)
        ])
    }

    // MARK: - 视频导出与写入系统相册

    private func exportVideo() {
        guard let avAsset else { return }
        pause()
        isExporting = true

        let composition = createVideoComposition(for: avAsset, recipe: recipe, compare: false)
        guard let exportSession = AVAssetExportSession(
            asset: avAsset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            isExporting = false
            errorMessage = "无法初始化视频导出器"
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GRAIN-EDIT-\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = composition

        let startCM = CMTime(seconds: recipe.trimStart, preferredTimescale: 600)
        let durationCM = CMTime(seconds: recipe.trimEnd - recipe.trimStart, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startCM, duration: durationCM)

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                self.isExporting = false
                if exportSession.status == .completed {
                    Task {
                        do {
                            try await Self.saveExportedVideoToLibrary(outputURL)
                            GrainHaptics.mediumImpact(enabled: true)
                            self.cleanupPlayer()
                            self.onClose()
                        } catch {
                            self.errorMessage = "保存到相册失败：\(error.localizedDescription)"
                        }
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                } else {
                    let err = exportSession.error?.localizedDescription ?? "未知错误"
                    self.errorMessage = "视频导出失败：\(err)"
                }
            }
        }
    }

    private static func saveExportedVideoToLibrary(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "GRAIN.VideoEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有相册写入权限"])
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "GRAIN.VideoEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "写入相册失败"]))
                }
            }
        }
    }

    // MARK: - 辅助计算

    private func shareCurrentVideo() {
        guard let avAsset else { return }
        pause()
        isExporting = true

        let composition = createVideoComposition(for: avAsset, recipe: recipe, compare: false)
        guard let exportSession = AVAssetExportSession(
            asset: avAsset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            isExporting = false
            errorMessage = "无法初始化分享导出器"
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GRAIN-SHARE-\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = composition

        let startCM = CMTime(seconds: recipe.trimStart, preferredTimescale: 600)
        let durationCM = CMTime(seconds: recipe.trimEnd - recipe.trimStart, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startCM, duration: durationCM)

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                self.isExporting = false
                if exportSession.status == .completed {
                    self.shareURL = outputURL
                    self.isSharing = true
                    GrainHaptics.mediumImpact()
                } else {
                    let err = exportSession.error?.localizedDescription ?? "未知错误"
                    self.errorMessage = "准备分享失败：\(err)"
                }
            }
        }
    }

    private func deleteVideoAsset() {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([self.asset] as NSArray)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    GrainHaptics.mediumImpact()
                    self.cleanupPlayer()
                    self.onClose()
                } else if let error {
                    self.errorMessage = "删除失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var edgeSwipeBackGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !didSwipeBack,
                      value.startLocation.x <= 36,
                      value.translation.width > 70,
                      value.translation.width > abs(value.translation.height) * 1.35
                else { return }
                didSwipeBack = true
                GrainHaptics.mediumImpact()
                cleanupPlayer()
                onClose()
            }
            .onEnded { _ in
                didSwipeBack = false
            }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func fittedRect(for aspect: CGFloat, in size: CGSize) -> CGSize {
        let containerAspect = size.width / max(size.height, 1)
        if aspect > containerAspect {
            return CGSize(width: size.width, height: size.width / aspect)
        } else {
            return CGSize(width: size.height * aspect, height: size.height)
        }
    }
}

// MARK: - AVPlayerLayer 原生封装

private struct VideoPlayerUIView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerUIView {
        let view = PlayerContainerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: PlayerContainerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

private final class PlayerContainerUIView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

// MARK: - 视频交互式裁切框覆盖层

private struct VideoCropSelectionOverlay: View {
    @Binding var cropRect: CGRect
    let aspect: VideoCropAspect
    let naturalSize: CGSize
    let displaySize: CGSize

    @State private var dragOrigin: CGRect?
    @State private var lastHapticStep: Int = 0

    var body: some View {
        let rect = CGRect(
            x: cropRect.origin.x * displaySize.width,
            y: cropRect.origin.y * displaySize.height,
            width: cropRect.width * displaySize.width,
            height: cropRect.height * displaySize.height
        )

        ZStack {
            Canvas { context, size in
                var outside = Path(CGRect(origin: .zero, size: size))
                outside.addRect(rect)
                context.fill(outside, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            }

            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            cropGrid(rect: rect)

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(moveGesture(rect: rect))

            ForEach(Corner.allCases, id: \.self) { corner in
                Circle()
                    .fill(GrainTheme.paper)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .position(corner.point(in: rect))
                    .gesture(resizeGesture(corner, rect: rect))
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
    }

    private func cropGrid(rect: CGRect) -> some View {
        Path { path in
            for f in [1.0 / 3, 2.0 / 3] {
                let x = rect.minX + rect.width * f
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * f
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
    }

    private func moveGesture(rect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { val in
                if dragOrigin == nil {
                    dragOrigin = cropRect
                    GrainHaptics.prepare()
                }
                guard let origin = dragOrigin else { return }
                let dx = val.translation.width / displaySize.width
                let dy = val.translation.height / displaySize.height
                let newX = min(max(origin.origin.x + dx, 0), 1 - origin.width)
                let newY = min(max(origin.origin.y + dy, 0), 1 - origin.height)
                let step = Int((newX * 50 + newY * 50).rounded())
                if step != lastHapticStep {
                    lastHapticStep = step
                    GrainHaptics.selection()
                }
                cropRect = CGRect(x: newX, y: newY, width: origin.width, height: origin.height)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func resizeGesture(_ corner: Corner, rect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { val in
                if dragOrigin == nil {
                    dragOrigin = cropRect
                    GrainHaptics.prepare()
                }
                guard let origin = dragOrigin else { return }
                let dx = val.translation.width / displaySize.width
                let dy = val.translation.height / displaySize.height

                var x = origin.origin.x
                var y = origin.origin.y
                var w = origin.width
                var h = origin.height

                if corner.isLeft {
                    x = min(max(origin.origin.x + dx, 0), origin.maxX - 0.1)
                    w = origin.maxX - x
                } else {
                    w = min(max(origin.width + dx, 0.1), 1 - origin.origin.x)
                }

                if corner.isTop {
                    y = min(max(origin.origin.y + dy, 0), origin.maxY - 0.1)
                    h = origin.maxY - y
                } else {
                    h = min(max(origin.height + dy, 0.1), 1 - origin.origin.y)
                }

                if let targetRatio = aspect.fixedRatio, naturalSize.height > 0 {
                    let pixelW = w * naturalSize.width
                    let targetPixelH = pixelW / targetRatio
                    let newH = targetPixelH / naturalSize.height
                    if y + newH <= 1.0 {
                        h = newH
                    } else {
                        h = 1.0 - y
                        let pixelH = h * naturalSize.height
                        let targetPixelW = pixelH * targetRatio
                        w = min(targetPixelW / naturalSize.width, 1.0 - x)
                    }
                }

                let step = Int((w * 50 + h * 50).rounded())
                if step != lastHapticStep {
                    lastHapticStep = step
                    GrainHaptics.selection()
                }

                cropRect = CGRect(x: x, y: y, width: w, height: h)
            }
            .onEnded { _ in dragOrigin = nil }
    }
}

// MARK: - 系统分享浮层

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
