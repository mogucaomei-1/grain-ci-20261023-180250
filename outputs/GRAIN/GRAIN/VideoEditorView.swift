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
    case adjust = "调节"
    case filter = "滤镜"
    case crop = "构图"
    case trim = "裁剪"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .adjust: "slider.horizontal.3"
        case .filter: "camera.filters"
        case .crop: "crop.rotate"
        case .trim: "film"
        }
    }
}

public enum VideoExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mov = "MOV"

    public var id: String { rawValue }

    var title: String { rawValue }
    var subtitle: String {
        switch self {
        case .mp4: "兼容性强 · 普遍适用社交平台"
        case .mov: "苹果生态 · 原画质 QuickTime"
        }
    }

    var fileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }
}

public enum VideoExportQuality: String, CaseIterable, Identifiable {
    case original = "原分辨率"
    case hd1080p = "1080P 高清"
    case sd720p = "720P 轻便"

    public var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .original: "原始尺寸与最高码率 · 无损画质"
        case .hd1080p: "平衡画质与文件体积 · 社交推荐"
        case .sd720p: "小体积传输 · 极速分享"
        }
    }

    func preset(for naturalSize: CGSize) -> String {
        switch self {
        case .original:
            return AVAssetExportPresetHighestQuality
        case .hd1080p:
            return AVAssetExportPreset1920x1080
        case .sd720p:
            return AVAssetExportPreset1280x720
        }
    }
}

// MARK: - 实时调色引用容器（消除重建 AVVideoComposition 导致的卡顿与抽搐）

final class VideoRecipeHolder {
    var recipe: VideoEditRecipe
    var isComparing: Bool = false
    var isCroppingTab: Bool = false

    init(recipe: VideoEditRecipe) {
        self.recipe = recipe
    }
}

// MARK: - 视频调节视图主界面

public struct VideoEditorView: View {
    let asset: PHAsset
    let onClose: () -> Void
    var onSwitchVideo: ((Int) -> Void)? = nil

    @State private var avAsset: AVAsset?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var duration: Double = 0
    @State private var currentTime: Double = 0

    @State private var recipe = VideoEditRecipe()
    // 默认进入“调节”模式，播放视频并附带视频拖动条
    @State private var activeTab: VideoEditorTab = .adjust
    @State private var activeParam: VideoAdjustParam = .exposure

    @State private var thumbnails: [UIImage] = []
    @State private var isComparing = false
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var errorMessage: String?
    @State private var naturalVideoSize: CGSize = CGSize(width: 1080, height: 1920)

    // 视频参数与格式元数据
    @State private var videoContainerFormat: String = "MP4"
    @State private var videoCodecName: String = "HEVC"
    @State private var videoFPS: Double = 30
    @State private var videoBitrateMbps: Double = 0
    @State private var videoFileSize: Int64 = 0

    // 直方图数据
    @State private var currentHistogram: RGBHistogram?

    // 推荐数值状态
    @State private var isRecommendedApplied = false
    @State private var recommendationBaseline: VideoEditRecipe?

    // 模态弹窗状态
    @State private var showInfoSheet = false
    @State private var showExportSheet = false
    @State private var selectedExportFormat: VideoExportFormat = .mp4
    @State private var selectedExportQuality: VideoExportQuality = .original

    @State private var timeObserverToken: Any?
    @State private var didSwipeBack = false
    @State private var showDeleteConfirmation = false
    @State private var shareURL: URL?
    @State private var isSharing = false
    @State private var lastParamHapticStep: Int = 0
    @State private var lastTrimHapticStep: Int = 0

    // 裁剪条手柄拖动防跳变缓存
    @State private var dragInitialTrimStart: Double? = nil
    @State private var dragInitialTrimEnd: Double? = nil

    private let recipeHolder: VideoRecipeHolder

    public init(
        asset: PHAsset,
        onClose: @escaping () -> Void,
        onSwitchVideo: ((Int) -> Void)? = nil
    ) {
        self.asset = asset
        self.onClose = onClose
        self.onSwitchVideo = onSwitchVideo
        self.recipeHolder = VideoRecipeHolder(recipe: VideoEditRecipe())
    }

    public var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. 顶栏：删除放左边第一个、取消、查看信息、分享放在完成左边、完成
                topBar
                    .padding(.horizontal, 16)
                    .frame(height: 48)

                // 2. 视频主预览画布（右上角直方图、左上角格式标签、右下对比按钮、左右滑切片手势）
                videoPreviewCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 3. 对比开关放置在播放条的右上方
                comparisonActionBar
                    .padding(.top, 4)
                    .padding(.bottom, 2)

                // 4. 视频拖动进度条（带静音开关、时间回显与流畅拖动）
                videoScrubberBar
                    .padding(.bottom, 4)

                // 5. 底部功能控制面板
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
        // 边缘滑动返回：增加保护，裁剪页面或在底控栏操作时不误触发，彻底解决拖动闪退
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
        .sheet(isPresented: $showInfoSheet) {
            VideoInfoSheetView(
                containerFormat: videoContainerFormat,
                codecName: videoCodecName,
                dimensions: naturalVideoSize,
                fps: videoFPS,
                bitrateMbps: videoBitrateMbps,
                duration: duration,
                fileSize: videoFileSize,
                onClose: { showInfoSheet = false }
            )
            .presentationDetents([.height(460)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExportSheet) {
            VideoExportSheetView(
                originalSize: naturalVideoSize,
                duration: duration,
                fps: videoFPS,
                containerFormat: videoContainerFormat,
                fileSize: videoFileSize,
                selectedFormat: $selectedExportFormat,
                selectedQuality: $selectedExportQuality,
                onSaveToPhotos: {
                    showExportSheet = false
                    executeExport(format: selectedExportFormat, quality: selectedExportQuality, saveToPhotos: true)
                },
                onShare: {
                    showExportSheet = false
                    executeExport(format: selectedExportFormat, quality: selectedExportQuality, saveToPhotos: false)
                },
                onDismiss: { showExportSheet = false }
            )
            .presentationDetents([.height(580)])
            .presentationDragIndicator(.visible)
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
        .onChange(of: asset.localIdentifier) { _, _ in
            cleanupPlayer()
            recipe = VideoEditRecipe()
            recipeHolder.recipe = recipe
            isRecommendedApplied = false
            recommendationBaseline = nil
            Task {
                await loadVideoAsset()
            }
        }
        .onChange(of: activeTab) { _, newTab in
            recipeHolder.isCroppingTab = (newTab == .crop)
            // 切换离开构图页面时，重新合成一次带裁切的画面
            applyRecipeToPlayer(recipe, forceRecompose: true)
        }
        .onChange(of: recipe.cropRect) { _, _ in
            if activeTab != .crop {
                applyRecipeToPlayer(recipe, forceRecompose: true)
            }
        }
    }

    // MARK: - 顶栏：删除放在左边第一个，分享放在完成的左边

    private var topBar: some View {
        HStack(spacing: 12) {
            // 1. 删除：按用户要求放在左边第一个
            Button {
                showDeleteConfirmation = true
                GrainHaptics.selection()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

            // 2. 取消
            Button("取消") {
                cleanupPlayer()
                onClose()
            }
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .foregroundStyle(GrainTheme.paper)
            .buttonStyle(.plain)

            Spacer()

            // 3. 查看视频参数信息按钮
            Button {
                showInfoSheet = true
                GrainHaptics.selection()
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

            // 4. 分享：按用户要求放在完成的左边
            Button {
                showExportSheet = true
                GrainHaptics.selection()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isExporting)

            // 5. 完成
            Button {
                showExportSheet = true
                GrainHaptics.selection()
            } label: {
                Text("完成")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(GrainTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
    }

    private var videoFormatBadge: String {
        let container = videoContainerFormat.uppercased()
        let maxSide = max(naturalVideoSize.width, naturalVideoSize.height)
        let res = maxSide >= 2160 ? "4K" : (maxSide >= 1080 ? "1080P" : "720P")
        let fps = Int(videoFPS.rounded())
        return "\(container) · \(res) \(fps)FPS"
    }

    // MARK: - 播放画布与手势（左上角视频规格、右上角直方图、左右滑动切换视频）

    private var videoPreviewCanvas: some View {
        GeometryReader { proxy in
            // 在构图 Tab 下显示未裁切的完整原始画幅，让用户在完整画面上推动选取框，彻底消除视频抽搐
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

                    // 暂停状态中心大悬浮播放标
                    if !isPlaying && activeTab != .crop {
                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 56, height: 56)
                                .background(Color.black.opacity(0.48), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // 左上角视频规格胶囊与参数入口
                    VStack {
                        HStack {
                            Button {
                                showInfoSheet = true
                                GrainHaptics.selection()
                            } label: {
                                HStack(spacing: 3) {
                                    Text(videoFormatBadge)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(GrainTheme.accent)
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(GrainTheme.paper.opacity(0.8))
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Color.black.opacity(0.58), in: Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // 右上角实时直方图
                            if let currentHistogram {
                                HistogramView(data: currentHistogram)
                                    .frame(width: 76, height: 42)
                                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.18), lineWidth: 0.6))
                            }
                        }
                        .padding(10)

                        Spacer()
                    }
                    .frame(width: frame.width, height: frame.height)
                } else {
                    ProgressView()
                        .tint(GrainTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // 左右滑动切换图库相邻视频，滑动顺序逻辑与图片完全一致
            .simultaneousGesture(switchVideoGesture)
        }
    }

    // MARK: - 调整前后预览开关（放置在播放条的右上方）

    private var comparisonActionBar: some View {
        HStack {
            Spacer()

            // 调整前后对比开关（按住查看原视频）
            Button {
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isComparing ? "eye.fill" : "eye")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isComparing ? "原片" : "对比")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isComparing ? GrainTheme.black : GrainTheme.paper)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(isComparing ? GrainTheme.accent : Color.black.opacity(0.55), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        isComparing = true
                        recipeHolder.isComparing = true
                        if !isPlaying { seek(to: currentTime) }
                    }
                    .onEnded { _ in
                        isComparing = false
                        recipeHolder.isComparing = false
                        if !isPlaying { seek(to: currentTime) }
                    }
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
    }

    // MARK: - 视频进度拖动条（Scrubber Bar，加入静音开关）

    private var videoScrubberBar: some View {
        HStack(spacing: 10) {
            // 1. 播放/暂停
            Button {
                togglePlayPause()
                GrainHaptics.selection()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)

            // 2. 静音开关
            Button {
                isMuted.toggle()
                player?.isMuted = isMuted
                GrainHaptics.selection()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isMuted ? GrainTheme.accent : GrainTheme.paper)
                    .frame(width: 26, height: 26)
                    .background(isMuted ? GrainTheme.accent.opacity(0.2) : Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)

            Text(formatTime(currentTime))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(GrainTheme.paper)
                .frame(width: 34, alignment: .leading)

            GeometryReader { proxy in
                let w = max(proxy.size.width, 1)
                let usableW = max(w - 16, 1)
                let totalDur = max(duration, 0.1)
                let progress = min(max(currentTime / totalDur, 0), 1)
                let knobX = 8 + usableW * CGFloat(progress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(GrainTheme.accent)
                        .frame(width: knobX, height: 4)

                    Circle()
                        .fill(GrainTheme.paper)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: knobX - 8)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            pause()
                            let x = min(max(val.location.x - 8, 0), usableW)
                            let newProg = Double(x / usableW)
                            let newSec = newProg * totalDur
                            currentTime = newSec
                            seek(to: newSec)
                            let step = Int(newProg * 60)
                            if step != lastTrimHapticStep {
                                lastTrimHapticStep = step
                                GrainHaptics.selection()
                            }
                        }
                )
            }
            .frame(height: 22)

            Text(formatTime(recipe.trimEnd - recipe.trimStart > 0 ? (recipe.trimEnd - recipe.trimStart) : duration))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(GrainTheme.muted)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
    }

    // MARK: - 底部控制区（集中紧凑，贴近底部小白条）

    private var bottomControlDeck: some View {
        VStack(spacing: 8) {
            // 当前子功能的操作面板
            Group {
                switch activeTab {
                case .adjust:
                    adjustParamDeck
                case .filter:
                    filterSelectionDeck
                case .crop:
                    cropAspectDeck
                case .trim:
                    timelineTrimDeck
                }
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)

            // 底部 4 个主模式切换胶囊
            HStack(spacing: 20) {
                ForEach(VideoEditorTab.allCases) { tab in
                    Button {
                        activeTab = tab
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: activeTab == tab ? .bold : .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: activeTab == tab ? .bold : .medium))
                        }
                        .foregroundStyle(activeTab == tab ? GrainTheme.accent : GrainTheme.muted)
                        .frame(minWidth: 46)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .background(GrainTheme.surface.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - 1. 曝光与各项画面调节（增加推荐数值按钮，去掉恢复默认数值）

    private var adjustParamDeck: some View {
        VStack(spacing: 4) {
            // 参数项水平切换 + 推荐数值按钮
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 推荐数值按钮（按要求增加，一键应用电影级胶片影调优化）
                    Button {
                        applyRecommendedValues()
                        GrainHaptics.mediumImpact()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 9.5, weight: .bold))
                            Text(isRecommendedApplied ? "已推荐" : "推荐数值")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(isRecommendedApplied ? GrainTheme.black : GrainTheme.accent)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(
                            isRecommendedApplied ? GrainTheme.accent : Color.white.opacity(0.12),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(VideoAdjustParam.allCases) { param in
                        let val = param.value(in: recipe)
                        let isChanged = abs(val) > 0.001

                        Button {
                            activeParam = param
                            GrainHaptics.selection(enabled: true)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: param.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(param.rawValue)
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                if isChanged {
                                    Circle()
                                        .fill(GrainTheme.accent)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .foregroundStyle(activeParam == param ? GrainTheme.black : GrainTheme.paper)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
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

            // 当前参数滑杆（小白点支持双击恢复默认值，去掉右侧的恢复默认数值按钮）
            HStack(spacing: 12) {
                Text(String(format: "%+.0f", activeParam.value(in: recipe)))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(GrainTheme.accent)
                    .frame(width: 38)

                GeometryReader { proxy in
                    let w = max(proxy.size.width, 1)
                    let usableW = max(w - 20, 1)
                    let currentVal = activeParam.value(in: recipe)
                    let span = max(activeParam.range.upperBound - activeParam.range.lowerBound, 0.001)
                    let progress = min(max((currentVal - activeParam.range.lowerBound) / span, 0), 1)
                    let knobX = 10 + usableW * CGFloat(progress)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .frame(height: 4)

                        Capsule()
                            .fill(GrainTheme.accent)
                            .frame(width: knobX, height: 4)

                        // 小白点（旋钮）：支持拖动调节与双击恢复默认值
                        Circle()
                            .fill(GrainTheme.paper)
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                            .offset(x: knobX - 9)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let x = min(max(val.location.x - 10, 0), usableW)
                                let newProg = Double(x / usableW)
                                let newVal = activeParam.range.lowerBound + newProg * span
                                activeParam.applying(newVal, to: &recipe)
                                recipeHolder.recipe = recipe
                                let step = Int(newProg * 50)
                                if step != lastParamHapticStep {
                                    lastParamHapticStep = step
                                    if abs(newVal) < (span / 80) {
                                        GrainHaptics.mediumImpact()
                                    } else {
                                        GrainHaptics.selection()
                                    }
                                }
                                if !isPlaying {
                                    seek(to: currentTime)
                                }
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { _ in
                                resetActiveParamToDefault()
                            }
                    )
                }
                .frame(height: 26)
            }
            .padding(.horizontal, 18)
        }
    }

    private func applyRecommendedValues() {
        if isRecommendedApplied {
            if let base = recommendationBaseline {
                recipe = base
                recipeHolder.recipe = recipe
            }
            isRecommendedApplied = false
            recommendationBaseline = nil
        } else {
            recommendationBaseline = recipe
            var updated = recipe
            updated.exposure = 0.15 * 100 / 1.5 // +0.15 EV 提升通透感
            updated.contrast = 12.0
            updated.highlights = -16.0
            updated.shadows = 14.0
            updated.saturation = 8.0
            updated.warmth = 6.0
            updated.vignette = 10.0
            recipe = updated
            recipeHolder.recipe = recipe
            isRecommendedApplied = true
        }
        if !isPlaying { seek(to: currentTime) }
    }

    private func resetActiveParamToDefault() {
        activeParam.applying(0, to: &recipe)
        recipeHolder.recipe = recipe
        GrainHaptics.mediumImpact()
        if !isPlaying { seek(to: currentTime) }
    }

    // MARK: - 2. 滤镜胶片风格选择（支持浓度滑块小白点双击恢复 100%）

    private var filterProfiles: [FilmProfile] {
        FilmProfile.defaultDisplayOrder
    }

    private var filterSelectionDeck: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filterProfiles) { profile in
                        let isSelected = recipe.filmProfile == profile
                        Button {
                            recipe.filmProfile = profile
                            recipeHolder.recipe = recipe
                            GrainHaptics.selection(enabled: true)
                            if !isPlaying { seek(to: currentTime) }
                        } label: {
                            Text(profile.name)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? GrainTheme.black : GrainTheme.paper)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
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
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)

                    GeometryReader { proxy in
                        let w = max(proxy.size.width, 1)
                        let usableW = max(w - 20, 1)
                        let progress = min(max(recipe.filmIntensity / 1.5, 0), 1)
                        let knobX = 10 + usableW * CGFloat(progress)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.14))
                            .frame(height: 4)

                            Capsule()
                                .fill(GrainTheme.accent)
                                .frame(width: knobX, height: 4)

                            Circle()
                                .fill(GrainTheme.paper)
                                .frame(width: 18, height: 18)
                                .shadow(color: .black.opacity(0.35), radius: 2)
                                .offset(x: knobX - 9)
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { val in
                                    let x = min(max(val.location.x - 10, 0), usableW)
                                    let newProg = Double(x / usableW)
                                    let newIntensity = newProg * 1.5
                                    recipe.filmIntensity = newIntensity
                                    recipeHolder.recipe = recipe
                                    let step = Int(newProg * 30)
                                    if step != lastParamHapticStep {
                                        lastParamHapticStep = step
                                        GrainHaptics.selection()
                                    }
                                    if !isPlaying { seek(to: currentTime) }
                                }
                        )
                        .simultaneousGesture(
                            SpatialTapGesture(count: 2)
                                .onEnded { _ in
                                    recipe.filmIntensity = 1.0
                                    recipeHolder.recipe = recipe
                                    GrainHaptics.mediumImpact()
                                    if !isPlaying { seek(to: currentTime) }
                                }
                        )
                    }
                    .frame(height: 26)

                    Text("\(Int(recipe.filmIntensity * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(width: 38)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - 3. 构图与画幅比例选择（顶满全宽，彻底消除两侧黑边）

    private var cropAspectDeck: some View {
        HStack(spacing: 8) {
            // 旋转 90 度
            Button {
                recipe.rotationDegrees = (recipe.rotationDegrees + 90) % 360
                recipeHolder.recipe = recipe
                GrainHaptics.selection()
                if !isPlaying { seek(to: currentTime) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rotate.right.fill")
                    Text("旋转")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.paper)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)

            // 水平镜像
            Button {
                recipe.isMirrored.toggle()
                recipeHolder.recipe = recipe
                GrainHaptics.selection()
                if !isPlaying { seek(to: currentTime) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    Text("镜像")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(recipe.isMirrored ? GrainTheme.black : GrainTheme.paper)
                .padding(.horizontal, 9)
                .frame(height: 30)
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
                .frame(height: 30)
                .background(GrainTheme.raised, in: Capsule())
            }

            // 重置裁切
            Button {
                recipe.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                recipe.aspect = .original
                recipe.rotationDegrees = 0
                recipe.isMirrored = false
                recipeHolder.recipe = recipe
                GrainHaptics.mediumImpact()
                if !isPlaying { seek(to: currentTime) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("重置")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    private func applyCropAspect(_ aspect: VideoCropAspect) {
        recipe.aspect = aspect
        if aspect == .original || aspect == .freeform {
            recipe.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            recipeHolder.recipe = recipe
            return
        }
        guard let targetRatio = aspect.fixedRatio else { return }
        let currentRatio = naturalVideoSize.width / max(naturalVideoSize.height, 1)
        if currentRatio > targetRatio {
            let normalizedW = targetRatio / currentRatio
            recipe.cropRect = CGRect(
                x: (1.0 - normalizedW) / 2.0,
                y: 0,
                width: normalizedW,
                height: 1.0
            )
        } else {
            let normalizedH = currentRatio / targetRatio
            recipe.cropRect = CGRect(
                x: 0,
                y: (1.0 - normalizedH) / 2.0,
                width: 1.0,
                height: normalizedH
            )
        }
        recipeHolder.recipe = recipe
    }

    // MARK: - 4. 裁剪时间条（彻底修复手柄跳动与闪退 Bug）

    private var timelineTrimDeck: some View {
        GeometryReader { proxy in
            let totalW = max(proxy.size.width - 32, 1)
            let totalDuration = max(duration, 0.1)
            let startRatio = CGFloat(recipe.trimStart / totalDuration)
            let endRatio = CGFloat(recipe.trimEnd / totalDuration)
            let leftX = totalW * startRatio
            let rightX = totalW * endRatio

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
                                .frame(width: totalW / CGFloat(thumbnails.count), height: 42)
                                .clipped()
                        }
                    }
                }
                .frame(width: totalW, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // 左侧未选中的暗层
                Color.black.opacity(0.68)
                    .frame(width: max(leftX, 0), height: 42)

                // 右侧未选中的暗层
                Color.black.opacity(0.68)
                    .frame(width: max(totalW - rightX, 0), height: 42)
                    .offset(x: rightX)

                // 黄色高亮裁剪选框
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(GrainTheme.accent, lineWidth: 2.5)
                    .frame(width: max(rightX - leftX, 16), height: 46)
                    .offset(x: leftX)

                // 左手柄（基于 translation 稳定拖拽，绝不跳零）
                HStack(spacing: 0) {
                    Image(systemName: "chevron.compact.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GrainTheme.black)
                }
                .frame(width: 16, height: 46)
                .background(GrainTheme.accent, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6))
                .offset(x: leftX)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { val in
                            pause()
                            if dragInitialTrimStart == nil {
                                dragInitialTrimStart = recipe.trimStart
                            }
                            let start = dragInitialTrimStart ?? recipe.trimStart
                            let deltaSec = Double(val.translation.width / totalW) * totalDuration
                            let newStart = min(max(start + deltaSec, 0), max(recipe.trimEnd - 0.5, 0))
                            recipe.trimStart = newStart
                            recipeHolder.recipe = recipe
                            seek(to: newStart)
                            let step = Int(newStart * 5)
                            if step != lastTrimHapticStep {
                                lastTrimHapticStep = step
                                GrainHaptics.selection()
                            }
                        }
                        .onEnded { _ in
                            dragInitialTrimStart = nil
                        }
                )

                // 右手柄（基于 translation 稳定拖拽，绝不跳零）
                HStack(spacing: 0) {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GrainTheme.black)
                }
                .frame(width: 16, height: 46)
                .background(GrainTheme.accent, in: UnevenRoundedRectangle(bottomTrailingRadius: 6, topTrailingRadius: 6))
                .offset(x: rightX - 16)
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { val in
                            pause()
                            if dragInitialTrimEnd == nil {
                                dragInitialTrimEnd = recipe.trimEnd
                            }
                            let end = dragInitialTrimEnd ?? recipe.trimEnd
                            let deltaSec = Double(val.translation.width / totalW) * totalDuration
                            let newEnd = min(max(end + deltaSec, recipe.trimStart + 0.5), totalDuration)
                            recipe.trimEnd = newEnd
                            recipeHolder.recipe = recipe
                            seek(to: newEnd)
                            let step = Int(newEnd * 5)
                            if step != lastTrimHapticStep {
                                lastTrimHapticStep = step
                                GrainHaptics.selection()
                            }
                        }
                        .onEnded { _ in
                            dragInitialTrimEnd = nil
                        }
                )
            }
            .frame(width: totalW, height: 46)
            .padding(.horizontal, 16)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
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
                    self.recipeHolder.recipe = self.recipe

                    if let track = loadedAsset.tracks(withMediaType: .video).first {
                        let transformed = track.naturalSize.applying(track.preferredTransform)
                        self.naturalVideoSize = CGSize(
                            width: max(abs(transformed.width), 1),
                            height: max(abs(transformed.height), 1)
                        )
                        self.videoFPS = Double(track.nominalFrameRate > 0 ? track.nominalFrameRate : 30)
                        self.videoBitrateMbps = Double(track.estimatedDataRate) / 1_000_000.0

                        for desc in track.formatDescriptions {
                            let sub = CMFormatDescriptionGetMediaSubType(desc as! CMFormatDescription)
                            if sub == kCMVideoCodecType_HEVC {
                                self.videoCodecName = "HEVC (H.265)"
                            } else if sub == kCMVideoCodecType_H264 {
                                self.videoCodecName = "AVC (H.264)"
                            } else if sub == kCMVideoCodecType_AppleProRes422 || sub == kCMVideoCodecType_AppleProRes422HQ {
                                self.videoCodecName = "Apple ProRes"
                            }
                        }
                    }

                    if let urlAsset = loadedAsset as? AVURLAsset {
                        let ext = urlAsset.url.pathExtension.uppercased()
                        self.videoContainerFormat = ext.isEmpty ? "MOV" : ext
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path),
                           let size = attrs[.size] as? Int64 {
                            self.videoFileSize = size
                        }
                    }

                    self.setupPlayer(with: loadedAsset)
                    self.generateThumbnails(for: loadedAsset)

                    // 默认开启播放
                    self.player?.play()
                    self.isPlaying = true

                    continuation.resume()
                }
            }
        }
    }

    private func setupPlayer(with asset: AVAsset) {
        let item = AVPlayerItem(asset: asset)
        item.videoComposition = createVideoComposition(for: asset, recipe: recipe, compare: false)
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
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

    private func applyRecipeToPlayer(_ newRecipe: VideoEditRecipe, forceRecompose: Bool = false) {
        recipeHolder.recipe = newRecipe
        guard forceRecompose, let avAsset, let item = player?.currentItem else { return }
        item.videoComposition = createVideoComposition(for: avAsset, recipe: newRecipe, compare: isComparing)
    }

    private func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= recipe.trimEnd {
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
        guard let player, seconds.isFinite, seconds >= 0 else { return }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        guard target.isValid else { return }
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func cleanupPlayer() {
        if let token = timeObserverToken {
            timeObserverToken = nil
            player?.removeTimeObserver(token)
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
    }

    private func generateThumbnails(for asset: AVAsset) {
        Task {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 140, height: 90)

            let count = 10
            let step = duration / Double(count)
            var times: [NSValue] = []
            for i in 0..<count {
                let cm = CMTime(seconds: Double(i) * step, preferredTimescale: 600)
                times.append(NSValue(time: cm))
            }

            var loaded: [UIImage] = []
            var firstCG: CGImage?
            for val in times {
                let cm = val.timeValue
                if let cg = try? gen.copyCGImage(at: cm, actualTime: nil) {
                    if firstCG == nil { firstCG = cg }
                    loaded.append(UIImage(cgImage: cg))
                }
            }
            let finished = loaded
            let hist = firstCG.map { Self.histogram(from: $0) }
            await MainActor.run {
                self.thumbnails = finished
                if let hist {
                    self.currentHistogram = hist
                }
            }
        }
    }

    private static func histogram(from image: CGImage) -> RGBHistogram {
        let width = image.width
        let height = image.height
        let binCount = 36
        var redBins = [Double](repeating: 0, count: binCount)
        var greenBins = [Double](repeating: 0, count: binCount)
        var blueBins = [Double](repeating: 0, count: binCount)
        var lumaBins = [Double](repeating: 0, count: binCount)

        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return RGBHistogram(red: [], green: [], blue: [], luminance: [])
        }
        let bytesPerPixel = max(image.bitsPerPixel / 8, 4)
        let bytesPerRow = image.bytesPerRow
        let stepX = max(width / 48, 1)
        let stepY = max(height / 36, 1)

        for y in stride(from: 0, to: height, by: stepY) {
            let rowPtr = ptr + y * bytesPerRow
            for x in stride(from: 0, to: width, by: stepX) {
                let pixel = rowPtr + x * bytesPerPixel
                let r = Double(pixel[0]) / 255.0
                let g = Double(pixel[1]) / 255.0
                let b = Double(pixel[2]) / 255.0
                let l = 0.299 * r + 0.587 * g + 0.114 * b

                let rIdx = min(Int(r * Double(binCount - 1)), binCount - 1)
                let gIdx = min(Int(g * Double(binCount - 1)), binCount - 1)
                let bIdx = min(Int(b * Double(binCount - 1)), binCount - 1)
                let lIdx = min(Int(l * Double(binCount - 1)), binCount - 1)

                redBins[rIdx] += 1
                greenBins[gIdx] += 1
                blueBins[bIdx] += 1
                lumaBins[lIdx] += 1
            }
        }
        func normalize(_ values: [Double]) -> [Double] {
            let mx = max(values.max() ?? 1, 1)
            return values.map { $0 / mx }
        }
        return RGBHistogram(
            red: normalize(redBins),
            green: normalize(greenBins),
            blue: normalize(blueBins),
            luminance: normalize(lumaBins)
        )
    }

    // MARK: - 实时 CIFilter 滤镜管线合成器

    private func createVideoComposition(for asset: AVAsset, recipe: VideoEditRecipe, compare: Bool) -> AVVideoComposition {
        let holder = self.recipeHolder

        let composition = AVMutableVideoComposition(asset: asset) { request in
            let active = holder.recipe
            let comparing = holder.isComparing

            guard !comparing else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            var image = request.sourceImage
            let extent = image.extent

            // 构图裁切：构图交互模式下保持全图预览，离开构图页面或导出时精准裁切
            let shouldCrop = !holder.isCroppingTab && (active.cropRect != CGRect(x: 0, y: 0, width: 1, height: 1))
            if shouldCrop {
                let cropX = active.cropRect.origin.x * extent.width
                let cropY = (1.0 - active.cropRect.origin.y - active.cropRect.height) * extent.height
                let cropW = active.cropRect.width * extent.width
                let cropH = active.cropRect.height * extent.height
                let cropBounds = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
                image = image.cropped(to: cropBounds)
                image = image.transformed(by: CGAffineTransform(translationX: -cropBounds.origin.x, y: -cropBounds.origin.y))
            }

            if active.isMirrored {
                image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -image.extent.width, y: 0))
            }

            // 1. 曝光调整 (-100...100 -> -1.5...1.5 EV)
            if active.exposure != 0 {
                let ev = (active.exposure / 100.0) * 1.5
                image = image.applyingFilter("CIExposureAdjust", parameters: [
                    kCIInputEVKey: ev
                ])
            }

            // 2. 基础色彩调整：对比度、亮度、饱和度
            let contrastVal = 1.0 + (active.contrast / 100.0) * 0.5
            let brightnessVal = (active.brightness / 100.0) * 0.35
            let saturationVal = 1.0 + (active.saturation / 100.0) * 0.8
            if active.contrast != 0 || active.brightness != 0 || active.saturation != 0 {
                image = image.applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: contrastVal,
                    kCIInputBrightnessKey: brightnessVal,
                    kCIInputSaturationKey: saturationVal
                ])
            }

            // 3. 高光与阴影
            if active.highlights != 0 || active.shadows != 0 {
                let hi = max(0, 1.0 - (active.highlights / 100.0) * 0.7)
                let sh = max(0, (active.shadows / 100.0) * 0.7)
                image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": hi,
                    "inputShadowAmount": sh
                ])
            }

            // 4. 色温
            if active.warmth != 0 {
                let targetTemp = 6500.0 + (active.warmth / 100.0) * 2200.0
                image = image.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: targetTemp, y: 0)
                ])
            }

            // 5. 胶片滤镜
            if active.filmProfile != .neutral {
                image = Self.applyFilmLook(to: image, profile: active.filmProfile, intensity: active.filmIntensity)
            }

            // 6. 暗角
            if active.vignette > 0 {
                let vig = (active.vignette / 100.0) * 1.6
                image = image.applyingFilter("CIVignette", parameters: [
                    kCIInputIntensityKey: vig,
                    kCIInputRadiusKey: 1.2
                ])
            }

            request.finish(with: image, context: nil)
        }

        if !holder.isCroppingTab && recipe.cropRect != CGRect(x: 0, y: 0, width: 1, height: 1) {
            let targetW = round(recipe.cropRect.width * naturalVideoSize.width / 2) * 2
            let targetH = round(recipe.cropRect.height * naturalVideoSize.height / 2) * 2
            composition.renderSize = CGSize(width: max(targetW, 16), height: max(targetH, 16))
        }

        return composition
    }

    // MARK: - 胶片风格滤镜模拟算法

    private static func applyFilmLook(to image: CIImage, profile: FilmProfile, intensity: Double) -> CIImage {
        var graded = image
        switch profile {
        case .classicChrome, .classicNegative:
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
            graded = graded
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.85,
                    "inputShadowAmount": 0.28
                ])
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6800, y: 14)
                ])
        case .velvia50:
            graded = graded
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.45,
                    kCIInputContrastKey: 1.22
                ])
        case .provia100f:
            graded = graded
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6300, y: -4)
                ])
        case .cinestill, .film135t:
            graded = graded
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 5200, y: -16)
                ])
        case .gold, .colorPlus200:
            graded = graded
                .applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 7800, y: 22)
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.1
                ])
        case .eterna, .nostalgicNeg, .realaAce:
            graded = graded
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputContrastKey: 0.92,
                    kCIInputSaturationKey: 0.88
                ])
        default:
            break
        }

        if intensity >= 0.999 {
            return graded
        }
        return graded.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: image,
            kCIInputTimeKey: max(0, 1.0 - intensity)
        ])
    }

    // MARK: - 视频导出与写入系统相册

    private func executeExport(format: VideoExportFormat, quality: VideoExportQuality, saveToPhotos: Bool) {
        guard let avAsset else { return }
        pause()
        isExporting = true

        let composition = createVideoComposition(for: avAsset, recipe: recipe, compare: false)
        let preset = quality.preset(for: naturalVideoSize)
        guard let exportSession = AVAssetExportSession(
            asset: avAsset,
            presetName: preset
        ) else {
            isExporting = false
            errorMessage = "无法初始化视频导出器"
            return
        }

        let ext = format == .mp4 ? "mp4" : "mov"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GRAIN-EXPORT-\(Int(Date().timeIntervalSince1970)).\(ext)")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = format.fileType
        exportSession.videoComposition = composition

        let startCM = CMTime(seconds: recipe.trimStart, preferredTimescale: 600)
        let durationCM = CMTime(seconds: recipe.trimEnd - recipe.trimStart, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startCM, duration: durationCM)

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                self.isExporting = false
                if exportSession.status == .completed {
                    if saveToPhotos {
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
                        self.shareURL = outputURL
                        self.isSharing = true
                        GrainHaptics.mediumImpact()
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

    // MARK: - 左右滑动切换图库相邻视频手势（顺序与图片完全一致）

    private var switchVideoGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                // 构图裁切模式下优先操作选框，不触发切视频
                guard activeTab != .crop else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 56,
                      abs(horizontal) > abs(vertical) * 1.35
                else { return }
                // 屏幕左侧边缘右滑留给返回手势
                if horizontal > 0, value.startLocation.x <= 40 { return }
                GrainHaptics.selection()
                // 与图片左右滑逻辑顺序完全一致：右滑上一个视频 (-1)，左滑下一个视频 (+1)
                onSwitchVideo?(horizontal > 0 ? -1 : 1)
            }
    }

    // 屏幕左边缘右滑返回手势（增加区域与模式隔离，解决裁剪拖动闪退）
    private var edgeSwipeBackGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                // 裁剪模式下或触摸发生在底部功能控制区时绝对不触发返回，防止手柄拖拽闪退
                guard !didSwipeBack,
                      activeTab != .trim,
                      value.startLocation.x <= 28,
                      value.startLocation.y < UIScreen.main.bounds.height - 180,
                      value.translation.width > 68,
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

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(GrainTheme.accent)
                    .scaleEffect(1.2)
                Text("正在导出视频…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
            }
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
}

// MARK: - 视频参数信息弹窗（VideoInfoSheetView）

private struct VideoInfoSheetView: View {
    let containerFormat: String
    let codecName: String
    let dimensions: CGSize
    let fps: Double
    let bitrateMbps: Double
    let duration: Double
    let fileSize: Int64
    let onClose: () -> Void

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("视频参数")
                            .font(.system(size: 21, weight: .bold, design: .serif))
                            .foregroundStyle(GrainTheme.paper)
                        Text("硬件媒体描述与轨道规格")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(GrainTheme.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GrainTheme.paper)
                }

                // 核心指标网格
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    paramCard(title: "容器格式", value: containerFormat.uppercased())
                    paramCard(title: "视频编码", value: codecName)
                    paramCard(title: "分辨率", value: "\(Int(dimensions.width)) × \(Int(dimensions.height))")
                    paramCard(title: "录制帧率", value: String(format: "%.1f FPS", fps))
                    paramCard(title: "视频码率", value: bitrateMbps > 0 ? String(format: "%.1f Mbps", bitrateMbps) : "自动")
                    paramCard(title: "视频时长", value: formatDuration(duration))
                    paramCard(title: "文件大小", value: fileSize > 0 ? String(format: "%.1f MB", Double(fileSize) / 1_048_576.0) : "—")
                    paramCard(title: "动态范围", value: "SDR / Rec.709")
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }

    private func paramCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(GrainTheme.paper)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = max(0, Int(sec))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 视频导出与分享设置浮层（VideoExportSheetView，类似照片导出）

private struct VideoExportSheetView: View {
    let originalSize: CGSize
    let duration: Double
    let fps: Double
    let containerFormat: String
    let fileSize: Int64

    @Binding var selectedFormat: VideoExportFormat
    @Binding var selectedQuality: VideoExportQuality

    let onSaveToPhotos: () -> Void
    let onShare: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                // 顶栏标题
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("导出视频")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(GrainTheme.paper)
                        Text("选择导出格式、压缩比与目标")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(GrainTheme.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GrainTheme.paper)
                }

                // 核心事实参数条
                HStack(spacing: 0) {
                    exportFact(value: "\(Int(originalSize.width))×\(Int(originalSize.height))", label: "分辨率")
                    Divider().overlay(GrainTheme.line).frame(height: 24)
                    exportFact(value: String(format: "%.0f FPS", fps), label: "帧率")
                    Divider().overlay(GrainTheme.line).frame(height: 24)
                    exportFact(value: formatDuration(duration), label: "时长")
                    Divider().overlay(GrainTheme.line).frame(height: 24)
                    exportFact(value: estimatedSizeText, label: "预估体积")
                }
                .padding(.vertical, 10)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                // 格式选择
                VStack(alignment: .leading, spacing: 6) {
                    Text("导出格式")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)

                    HStack(spacing: 8) {
                        ForEach(VideoExportFormat.allCases) { format in
                            Button {
                                selectedFormat = format
                                GrainHaptics.selection()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(format.title)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    Text(format.subtitle)
                                        .font(.system(size: 8.5, design: .rounded))
                                        .foregroundStyle(GrainTheme.muted)
                                }
                                .foregroundStyle(GrainTheme.paper)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selectedFormat == format ? GrainTheme.accent : GrainTheme.line,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 画质与压缩比选择
                VStack(alignment: .leading, spacing: 6) {
                    Text("画质与压缩比")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)

                    VStack(spacing: 6) {
                        ForEach(VideoExportQuality.allCases) { quality in
                            Button {
                                selectedQuality = quality
                                GrainHaptics.selection()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(quality.rawValue)
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                        Text(quality.subtitle)
                                            .font(.system(size: 9, design: .rounded))
                                            .foregroundStyle(GrainTheme.muted)
                                    }
                                    Spacer()
                                    if selectedQuality == quality {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(GrainTheme.accent)
                                    }
                                }
                                .foregroundStyle(GrainTheme.paper)
                                .padding(10)
                                .frame(maxWidth: .infinity)
                                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            selectedQuality == quality ? GrainTheme.accent : GrainTheme.line,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // 操作按钮：存入相册 & 系统分享
                HStack(spacing: 12) {
                    Button {
                        onSaveToPhotos()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle")
                            Text("存入系统相册")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(GrainTheme.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(GrainTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onShare()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享给朋友")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(GrainTheme.line, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
    }

    private func exportFact(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(GrainTheme.paper)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var estimatedSizeText: String {
        let dur = max(duration, 1.0)
        let mbps: Double
        switch selectedQuality {
        case .original:
            mbps = 45.0
        case .hd1080p:
            mbps = 16.0
        case .sd720p:
            mbps = 6.0
        }
        let totalMB = (mbps * dur) / 8.0
        return String(format: "约 %.1f MB", totalMB)
    }

    private func formatDuration(_ sec: Double) -> String {
        let total = max(0, Int(sec))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
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
