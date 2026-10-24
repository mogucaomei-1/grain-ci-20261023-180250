import AVKit
import SwiftUI

// MARK: - 播放器全套手势与 HUD 控制层 (无冲突手势、常规控制、悬浮锁屏)

public struct PlayerOverlayView: View {
    @ObservedObject var viewModel: PlayerViewModel
    public var onDismiss: () -> Void
    public var onShowInfo: () -> Void

    @State private var isDraggingVertically = false
    @State private var isDraggingHorizontally = false
    @State private var isLeftHalfDrag = false
    @State private var showSubtitlePicker = false

    public init(viewModel: PlayerViewModel, onDismiss: @escaping () -> Void, onShowInfo: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onShowInfo = onShowInfo
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 1. 全屏手势交互捕获层 (避开底部控制条区域，杜绝进度条冲突)
                gestureLayer(in: proxy.size)

                // 2. 字幕浮层
                if let subtitleText = viewModel.currentSubtitleText, !subtitleText.isEmpty {
                    VStack {
                        Spacer()
                        Text(subtitleText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                            .padding(.bottom, viewModel.showControls ? 130 : 36)
                    }
                    .transition(.opacity)
                }

                // 3. 屏幕中心状态 HUD 浮层 (亮度、音量、快进、双击快退/快进、截帧提示)
                centerStatusHUDs

                // 4. 屏幕左侧垂直居中独立悬浮锁定按钮 (绝对不被顶部与底部控制栏遮挡)
                floatingLockToggle

                // 4.1 屏幕右侧垂直居中独立悬浮倍速调节按钮
                if viewModel.showControls && !viewModel.isControlsLocked {
                    floatingSpeedToggle
                }

                // 5. HUD 顶栏与底栏
                if viewModel.showControls && !viewModel.isControlsLocked {
                    VStack(spacing: 0) {
                        topBar(in: proxy.size)
                        Spacer()
                        bottomBar
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .sheet(isPresented: $showSubtitlePicker) {
                SubtitlePickerSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - 手势捕获层

    private func gestureLayer(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            // 单击：切换 HUD 显示
            .onTapGesture(count: 1) {
                viewModel.toggleControlsVisibility()
            }
            // 双击：左半屏 -10s，右半屏 +10s，中间区域播放/暂停
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { event in
                        guard !viewModel.isControlsLocked else { return }
                        let x = event.location.x
                        let width = size.width
                        if x < width * 0.35 {
                            viewModel.doubleTapSeek(forward: false)
                        } else if x > width * 0.65 {
                            viewModel.doubleTapSeek(forward: true)
                        } else {
                            viewModel.togglePlayPause()
                        }
                    }
            )
            // 长按：2.0x 瞬时极速快进
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        guard !viewModel.isControlsLocked else { return }
                        viewModel.startFastForward()
                    }
            )
            // 拖动手势：左侧亮度、右侧音量、水平微调 (限制在非底部栏区域，杜绝进度条冲突)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !viewModel.isControlsLocked else { return }
                        // 如果从底部 110pt 以内开始拖动，说明是点滑进度条，绝对不触发屏幕大滑块
                        guard value.startLocation.y < (size.height - 110) else { return }
                        handleDragChanged(value: value, in: size)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
    }

    private func handleDragChanged(value: DragGesture.Value, in size: CGSize) {
        let translationX = value.translation.width
        let translationY = value.translation.height

        if !isDraggingVertically && !isDraggingHorizontally {
            if abs(translationX) > abs(translationY) {
                isDraggingHorizontally = true
                viewModel.startScrubbing()
            } else {
                isDraggingVertically = true
                isLeftHalfDrag = value.startLocation.x < (size.width / 2)
            }
        }

        if isDraggingHorizontally {
            viewModel.updateScrubbing(fraction: translationX / size.width, translationX: translationX)
        } else if isDraggingVertically {
            let delta = translationY / 300.0
            if isLeftHalfDrag {
                viewModel.adjustBrightness(delta: delta)
            } else {
                viewModel.adjustVolume(delta: Float(delta))
            }
        }
    }

    private func handleDragEnded() {
        if isDraggingHorizontally {
            viewModel.finishScrubbing()
        }
        if viewModel.isFastForwarding {
            viewModel.endFastForward()
        }
        isDraggingVertically = false
        isDraggingHorizontally = false
    }

    // MARK: - 顶栏 (专业电影级极简参数胶囊)

    private func topBar(in size: CGSize) -> some View {
        HStack(spacing: 12) {
            // 返回按钮
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(GrainTheme.paper)
                    .frame(width: 40, height: 40)
                    .background(GrainTheme.badgeBackground)
                    .clipShape(Circle())
            }

            // 视频标题与极简 Pro Cinema 规格胶囊
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentItem?.title ?? "视频播放")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GrainTheme.paper)
                    .lineLimit(1)

                if !viewModel.specsSummaryText.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(viewModel.currentMetadata.isHDR ? Color.yellow : GrainTheme.accent)
                            .frame(width: 5, height: 5)
                        Text(viewModel.specsSummaryText)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(GrainTheme.paper.opacity(0.85))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                }
            }

            Spacer()

            // AirPlay 投屏
            AirPlayRouteButton()
                .frame(width: 36, height: 36)

            // 画中画按钮
            if viewModel.isPiPAvailable {
                Button(action: { viewModel.togglePictureInPicture() }) {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(GrainTheme.paper)
                        .frame(width: 38, height: 38)
                        .background(GrainTheme.badgeBackground)
                        .clipShape(Circle())
                }
            }

            // 字幕选择按钮
            Button(action: { showSubtitlePicker = true }) {
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(viewModel.selectedSubtitleTrack != nil ? GrainTheme.accent : GrainTheme.paper)
                    .frame(width: 38, height: 38)
                    .background(GrainTheme.badgeBackground)
                    .clipShape(Circle())
            }

            // 详细参数信息面板
            Button(action: onShowInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(GrainTheme.paper)
                    .frame(width: 38, height: 38)
                    .background(GrainTheme.badgeBackground)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.75), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - 底栏 (包含常规快退、播放、快进、静音等全套专业控制)

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // 时间轴进度条与时间显示
            HStack(spacing: 12) {
                Text(FormatUtils.formatDuration(viewModel.currentTime))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(GrainTheme.paper)

                CustomScrubber(
                    currentTime: $viewModel.currentTime,
                    duration: viewModel.duration,
                    bufferedProgress: viewModel.bufferedProgress,
                    onScrubStart: { viewModel.startScrubbing() },
                    onScrubChange: { target in viewModel.scrubTargetTime = target },
                    onScrubEnd: { target in viewModel.seek(to: target) }
                )

                Text(FormatUtils.formatDuration(viewModel.duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(GrainTheme.muted)
            }
            .padding(.horizontal, 16)

            // 底部控制按钮行 (后退/暂停/前进 严格居中，左侧静音比例，右侧循环截图)
            HStack(alignment: .center, spacing: 0) {
                // 左侧次要控制区 (靠左对齐)
                HStack(spacing: 12) {
                    // 静音开关
                    Button(action: { viewModel.toggleMute() }) {
                        Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(viewModel.isMuted ? GrainTheme.danger : GrainTheme.paper)
                            .frame(width: 38, height: 38)
                            .background(GrainTheme.card)
                            .clipShape(Circle())
                    }

                    // 画面比例切换
                    Button(action: { viewModel.cycleScaleMode() }) {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.scaleMode.icon)
                            Text(viewModel.scaleMode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(GrainTheme.paper)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(GrainTheme.card)
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 核心控制区：【后退 10 秒】 【播放 / 暂停】 【快进 10 秒】 严格绝对居中
                HStack(spacing: 20) {
                    // 常规后退 10 秒按钮
                    Button(action: { viewModel.seekRelative(-10) }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(GrainTheme.paper)
                            .frame(width: 42, height: 42)
                            .background(GrainTheme.card)
                            .clipShape(Circle())
                    }

                    // 播放 / 暂停大圆钮
                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(GrainTheme.black)
                            .frame(width: 50, height: 50)
                            .background(GrainTheme.accent)
                            .clipShape(Circle())
                            .shadow(color: GrainTheme.accent.opacity(0.35), radius: 8, x: 0, y: 3)
                    }

                    // 常规前进 10 秒按钮
                    Button(action: { viewModel.seekRelative(10) }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(GrainTheme.paper)
                            .frame(width: 42, height: 42)
                            .background(GrainTheme.card)
                            .clipShape(Circle())
                    }
                }

                // 右侧次要控制区 (靠右对齐)
                HStack(spacing: 12) {
                    // 单曲循环开关
                    Button(action: { viewModel.toggleLoop() }) {
                        Image(systemName: viewModel.isLooping ? "repeat.1" : "repeat")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(viewModel.isLooping ? GrainTheme.accent : GrainTheme.muted)
                            .frame(width: 38, height: 38)
                            .background(GrainTheme.card)
                            .clipShape(Circle())
                    }

                    // 截取原画帧按钮
                    Button(action: {
                        Task {
                            await viewModel.captureSnapshot()
                        }
                    }) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(GrainTheme.paper)
                            .frame(width: 38, height: 38)
                            .background(GrainTheme.card)
                            .clipShape(Circle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - 屏幕左侧垂直居中悬浮锁定按钮

    private var floatingLockToggle: some View {
        VStack {
            Spacer()
            HStack {
                Button(action: { viewModel.toggleLockControls() }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isControlsLocked ? GrainTheme.accent : GrainTheme.hudBackground)
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                        Image(systemName: viewModel.isControlsLocked ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(viewModel.isControlsLocked ? GrainTheme.black : GrainTheme.paper)
                    }
                }
                .padding(.leading, 18)
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - 屏幕右侧垂直居中悬浮倍速调节按钮

    private var floatingSpeedToggle: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Menu {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Button(action: {
                            viewModel.setSpeed(speed)
                            GrainHaptics.selection()
                        }) {
                            HStack {
                                Text(speed.title)
                                if viewModel.playbackSpeed == speed {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(GrainTheme.hudBackground)
                            .frame(width: 48, height: 46)
                            .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                        VStack(spacing: 2) {
                            Text(viewModel.playbackSpeed == .normal ? "1.0×" : viewModel.playbackSpeed.title)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(viewModel.playbackSpeed == .normal ? GrainTheme.paper : GrainTheme.accent)
                            Text("倍速")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(GrainTheme.muted)
                        }
                    }
                }
                .padding(.trailing, 18)
            }
            Spacer()
        }
    }

    // MARK: - 中心状态 HUD 浮层

    private var centerStatusHUDs: some View {
        ZStack {
            // 双击快进 / 快退动画
            if let seek = viewModel.seekRipple {
                VStack(spacing: 8) {
                    Image(systemName: seek.isForward ? "goforward.10" : "gobackward.10")
                        .font(.system(size: 38, weight: .bold))
                    Text(seek.text)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                }
                .foregroundColor(GrainTheme.paper)
                .padding(20)
                .background(GrainTheme.hudBackground)
                .grainGlass(cornerRadius: 16)
                .transition(.scale.combined(with: .opacity))
            }

            // 长按 2.0x 快进提示
            if viewModel.isFastForwarding {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                        Text("2.0× 快进中")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(GrainTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(GrainTheme.hudBackground)
                    .grainGlass(cornerRadius: 20)
                    .padding(.top, 70)
                    Spacer()
                }
                .transition(.opacity)
            }

            // 亮度调节 HUD
            if viewModel.showBrightnessHUD {
                VerticalPillHUD(
                    icon: "sun.max.fill",
                    title: "亮度",
                    value: Double(viewModel.currentBrightness)
                )
            }

            // 音量调节 HUD
            if viewModel.showVolumeHUD {
                VerticalPillHUD(
                    icon: viewModel.currentVolume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill",
                    title: "音量",
                    value: Double(viewModel.currentVolume)
                )
            }

            // 时间轴水平微调气泡
            if viewModel.isScrubbing {
                VStack(spacing: 6) {
                    Text(FormatUtils.formatDuration(viewModel.scrubTargetTime))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(GrainTheme.paper)

                    Text(viewModel.scrubDeltaSeconds >= 0 ? "+\(viewModel.scrubDeltaSeconds)s" : "\(viewModel.scrubDeltaSeconds)s")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(GrainTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(GrainTheme.hudBackground)
                .grainGlass(cornerRadius: 16)
            }

            // 截帧成功提示 Toast
            if let toast = viewModel.snapshotToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(GrainTheme.accent)
                        Text(toast)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(GrainTheme.paper)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(GrainTheme.hudBackground)
                    .grainGlass(cornerRadius: 20)
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: - 垂直滑条 HUD (亮度/音量)

struct VerticalPillHUD: View {
    let icon: String
    let title: String
    let value: Double

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(GrainTheme.paper)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 6, height: 100)

                Capsule()
                    .fill(GrainTheme.accent)
                    .frame(width: 6, height: max(0, min(100, 100 * CGFloat(value))))
            }

            Text("\(Int(value * 100))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(GrainTheme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(GrainTheme.hudBackground)
        .grainGlass(cornerRadius: 16)
    }
}

// MARK: - 自定义精准进度滑杆 (独立无干扰事件处理)

struct CustomScrubber: View {
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedProgress: Double
    var onScrubStart: () -> Void
    var onScrubChange: (TimeInterval) -> Void
    var onScrubEnd: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = isDragging ? dragProgress : (duration > 0 ? currentTime / duration : 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: max(0, min(width, width * CGFloat(bufferedProgress))), height: 4)

                Capsule()
                    .fill(GrainTheme.accent)
                    .frame(width: max(0, min(width, width * CGFloat(progress))), height: 4)

                Circle()
                    .fill(GrainTheme.paper)
                    .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(width - (isDragging ? 16 : 10), width * CGFloat(progress) - (isDragging ? 8 : 5))))
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { event in
                        if !isDragging {
                            isDragging = true
                            onScrubStart()
                        }
                        let p = max(0, min(1.0, Double(event.location.x / width)))
                        dragProgress = p
                        onScrubChange(p * duration)
                    }
                    .onEnded { event in
                        let p = max(0, min(1.0, Double(event.location.x / width)))
                        isDragging = false
                        onScrubEnd(p * duration)
                    }
            )
        }
        .frame(height: 28)
    }
}

// MARK: - AirPlay 投屏原生按钮

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.tintColor = UIColor(GrainTheme.paper)
        routePicker.activeTintColor = UIColor(GrainTheme.accent)
        routePicker.prioritizesVideoDevices = true
        return routePicker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - 字幕选择浮层

struct SubtitlePickerSheet: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDocumentPicker = false

    var body: some View {
        NavigationView {
            ZStack {
                GrainTheme.black.ignoresSafeArea()

                List {
                    Section(header: Text("已加载字幕").foregroundColor(GrainTheme.muted)) {
                        Button(action: {
                            viewModel.selectSubtitleTrack(nil)
                            dismiss()
                        }) {
                            HStack {
                                Text("关闭字幕")
                                    .foregroundColor(GrainTheme.paper)
                                Spacer()
                                if viewModel.selectedSubtitleTrack == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(GrainTheme.accent)
                                }
                            }
                        }
                        .listRowBackground(GrainTheme.surface)

                        ForEach(viewModel.subtitleTracks) { track in
                            Button(action: {
                                viewModel.selectSubtitleTrack(track)
                                dismiss()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .foregroundColor(GrainTheme.paper)
                                        Text(track.isExternal ? "外挂字幕 (SRT/VTT)" : "内嵌字幕")
                                            .font(.caption)
                                            .foregroundColor(GrainTheme.muted)
                                    }
                                    Spacer()
                                    if viewModel.selectedSubtitleTrack?.id == track.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(GrainTheme.accent)
                                    }
                                }
                            }
                            .listRowBackground(GrainTheme.surface)
                        }
                    }

                    Section {
                        Button(action: { showDocumentPicker = true }) {
                            Label("导入外挂字幕 (.srt / .vtt)", systemImage: "plus.circle")
                                .foregroundColor(GrainTheme.accent)
                        }
                        .listRowBackground(GrainTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("字幕选择")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(GrainTheme.accent)
                }
            }
            .fileImporter(
                isPresented: $showDocumentPicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    viewModel.loadExternalSubtitle(url: url)
                }
            }
        }
    }
}
