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
        aspect == .original
    }
}

public enum VideoCropAspect: String, CaseIterable, Identifiable {
    case original = "原画"
    case portrait9x16 = "9:16"
    case landscape16x9 = "16:9"
    case square1x1 = "1:1"
    case portrait4x5 = "4:5"

    public var id: String { rawValue }

    func ratio(for naturalSize: CGSize) -> CGFloat {
        switch self {
        case .original:
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

    // MARK: - 顶栏：取消、对比、时间回显、完成导出

    private var topBar: some View {
        HStack(spacing: 12) {
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isComparing ? GrainTheme.accent : GrainTheme.paper)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isComparing = true; updateComposition(compare: true) }
                    .onEnded { _ in isComparing = false; updateComposition(compare: false) }
            )

            Button {
                exportVideo()
            } label: {
                Text("完成")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .padding(.horizontal, 14)
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
            let aspect = recipe.aspect.ratio(for: naturalVideoSize)
            let frame = fittedRect(for: aspect, in: proxy.size)

            ZStack {
                if let player {
                    VideoPlayerUIView(player: player)
                        .rotationEffect(.degrees(Double(recipe.rotationDegrees)))
                        .scaleEffect(x: recipe.isMirrored ? -1 : 1, y: 1)
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

                    // 播放/暂停状态悬浮浮标
                    if !isPlaying {
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

    private var filterSelectionDeck: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    let profiles = FilmProfile.defaultDisplayOrder
                    ForEach(profiles) { profile in
                        let isSelected = recipe.filmProfile == profile
                        Button {
                            recipe.filmProfile = profile
                            GrainHaptics.selection(enabled: true)
                        } label: {
                            Text(profile.displayName)
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
        HStack(spacing: 14) {
            // 旋转 90 度
            Button {
                recipe.rotationDegrees = (recipe.rotationDegrees + 90) % 360
                GrainHaptics.selection(enabled: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rotate.right.fill")
                    Text("旋转")
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.paper)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)

            // 水平镜像
            Button {
                recipe.isMirrored.toggle()
                GrainHaptics.selection(enabled: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    Text("镜像")
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(recipe.isMirrored ? GrainTheme.black : GrainTheme.paper)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(recipe.isMirrored ? GrainTheme.accent : GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)

            // 比例选择菜单
            Menu {
                ForEach(VideoCropAspect.allCases) { aspect in
                    Button(aspect.rawValue) {
                        recipe.aspect = aspect
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "aspectratio")
                    Text(recipe.aspect.rawValue)
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(GrainTheme.raised, in: Capsule())
            }
        }
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
                        self.naturalVideoSize = track.naturalSize
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
            await MainActor.run {
                self.thumbnails = loaded
            }
        }
    }

    // MARK: - 实时 CIFilter 滤镜管线合成器

    private func createVideoComposition(for asset: AVAsset, recipe: VideoEditRecipe, compare: Bool) -> AVVideoComposition {
        return AVVideoComposition(asset: asset) { request in
            guard !compare else {
                request.finish(with: request.sourceImage, context: nil)
                return
            }

            var image = request.sourceImage

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
