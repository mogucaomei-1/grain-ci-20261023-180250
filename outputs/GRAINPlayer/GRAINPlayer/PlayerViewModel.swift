import AVFoundation
import AVKit
import Combine
import MediaPlayer
import Photos
import SwiftUI
import UIKit

// MARK: - 纯视频播放器核心控制器 (高性能解耦)

@MainActor
public final class PlayerViewModel: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    // MARK: - 播放核心对象
    @Published public private(set) var player: AVPlayer?
    @Published public private(set) var currentItem: VideoItem?
    @Published public private(set) var currentMetadata: VideoMetadata = VideoMetadata()
    @Published public private(set) var isReadyToPlay: Bool = false
    @Published public private(set) var isBuffering: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    // MARK: - 播放进度与状态
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var bufferedProgress: Double = 0
    @Published public var playbackSpeed: PlaybackSpeed = .x1_0
    @Published public var scaleMode: VideoScaleMode = .aspectFit
    @Published public var isLooping: Bool = false
    @Published public var isMuted: Bool = false

    // MARK: - 手势与 HUD 交互状态
    @Published public var showControls: Bool = true
    @Published public var isControlsLocked: Bool = false
    @Published public var isScrubbing: Bool = false
    @Published public var scrubTargetTime: TimeInterval = 0
    @Published public var scrubDeltaSeconds: Int = 0

    // 亮度与音量 HUD
    @Published public var showBrightnessHUD: Bool = false
    @Published public var currentBrightness: CGFloat = 0.5
    @Published public var showVolumeHUD: Bool = false
    @Published public var currentVolume: Float = 0.5

    // 长按 2.0x 瞬时倍速
    @Published public var isFastForwarding: Bool = false

    // 双击快进/快退浮层动画
    @Published public var seekRipple: (isForward: Bool, text: String)? = nil

    // 截帧成功提示
    @Published public var snapshotToast: String? = nil

    // MARK: - 字幕与音轨
    @Published public var subtitleTracks: [SubtitleTrack] = []
    @Published public var selectedSubtitleTrack: SubtitleTrack? = nil
    @Published public var currentSubtitleText: String? = nil

    // MARK: - 画中画 (PiP)
    @Published public var isPiPAvailable: Bool = false
    @Published public var isPiPActive: Bool = false
    public var pipController: AVPictureInPictureController?

    // 内部私有属性
    private var timeObserverToken: Any?
    private var controlsDismissTask: Task<Void, Never>?
    private var brightnessDismissTask: Task<Void, Never>?
    private var volumeDismissTask: Task<Void, Never>?
    private var originalSpeedBeforeFastForward: PlaybackSpeed = .x1_0
    private var playerItemCancellables = Set<AnyCancellable>()
    private var volumeView = MPVolumeView()

    @AppStorage("doubleTapSeekInterval") public var doubleTapSeekInterval: Int = 10
    @AppStorage("autoPictureInPicture") public var autoPiPEnabled: Bool = true
    @AppStorage("enableBackgroundAudio") public var backgroundAudioEnabled: Bool = true

    public override init() {
        super.init()
        setupAudioSession()
        currentBrightness = UIScreen.main.brightness
    }

    // MARK: - 规格简述文字 (优雅极简 Pro Cinema 风格)

    public var specsSummaryText: String {
        var parts: [String] = []
        if !currentMetadata.resolutionPill.isEmpty {
            parts.append(currentMetadata.resolutionPill)
        }
        if !currentMetadata.fpsPill.isEmpty {
            parts.append(currentMetadata.fpsPill)
        }
        if currentMetadata.isHDR {
            parts.append("HDR")
        }
        if !currentMetadata.codecName.isEmpty {
            parts.append(currentMetadata.codecName)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 初始化后台音频与 Session

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .duckOthers])
            try session.setActive(true)
        } catch {
            print("AudioSession 配置失败: \(error)")
        }
    }

    // MARK: - 加载并开始播放视频

    public func loadVideo(item: VideoItem) async {
        cleanup()
        self.currentItem = item
        self.currentMetadata = item.metadata
        self.duration = item.metadata.duration
        self.errorMessage = nil
        self.isReadyToPlay = false
        self.isBuffering = true
        self.showControls = true

        do {
            let (playerItem, initialMeta) = try await resolvePlayerItem(for: item)
            self.currentMetadata = initialMeta
            if initialMeta.duration > 0 {
                self.duration = initialMeta.duration
            }

            let newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.actionAtItemEnd = .none
            self.player = newPlayer

            setupPlayerObservations(player: newPlayer, playerItem: playerItem)
            setupPictureInPicture()
            parseEmbeddedSubtitles(from: playerItem.asset)

            newPlayer.play()
            self.isPlaying = true
            applySpeed(self.playbackSpeed)
            self.isReadyToPlay = true
            self.isBuffering = false

            GrainHaptics.success()
            scheduleControlsDismissal()

            // 异步后台提取高级规格 (码率、色彩空间、HDR 等)，绝不阻塞即刻起播
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let detailed = await VideoMetadataExtractor.extract(
                    from: playerItem.asset,
                    fallbackDuration: initialMeta.duration
                )
                await MainActor.run {
                    self.currentMetadata = detailed
                    if self.duration == 0 && detailed.duration > 0 {
                        self.duration = detailed.duration
                    }
                }
            }
        } catch {
            self.errorMessage = "视频加载失败: \(error.localizedDescription)"
            self.isBuffering = false
            GrainHaptics.error()
        }
    }

    private func resolvePlayerItem(for item: VideoItem) async throws -> (AVPlayerItem, VideoMetadata) {
        switch item.source {
        case .photoLibrary:
            return try await PhotoLibraryService.shared.preparePlayerItem(for: item)
        case .fileDirectory(let url), .externalPicked(let url):
            let playerItem = AVPlayerItem(url: url)
            return (playerItem, item.metadata)
        }
    }

    // MARK: - 监听播放器状态 (平滑低功耗 5Hz 调度，彻底杜绝掉帧)

    private func setupPlayerObservations(player: AVPlayer, playerItem: AVPlayerItem) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let seconds = CMTimeGetSeconds(time)
            guard !seconds.isNaN && !seconds.isInfinite else { return }
            self.currentTime = seconds
            self.updateActiveSubtitle(at: seconds)
        }

        // 监听缓冲范围与状态
        playerItem.publisher(for: \.loadedTimeRanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timeRanges in
                guard let self, let firstRange = timeRanges.first?.timeRangeValue else { return }
                let bufferedSeconds = CMTimeGetSeconds(firstRange.start + firstRange.duration)
                if self.duration > 0 {
                    self.bufferedProgress = min(1.0, max(0.0, bufferedSeconds / self.duration))
                }
            }
            .store(in: &playerItemCancellables)

        // 监听缓冲中状态
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                self?.isBuffering = isEmpty
            }
            .store(in: &playerItemCancellables)

        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] likely in
                if likely { self?.isBuffering = false }
            }
            .store(in: &playerItemCancellables)

        // 播放结束通知
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isLooping {
                    self.seek(to: 0)
                    self.player?.play()
                } else {
                    self.isPlaying = false
                    self.showControls = true
                }
            }
            .store(in: &playerItemCancellables)
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        playerItemCancellables.removeAll()
    }

    // MARK: - 基础播放控制

    public func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            showControls = true
            controlsDismissTask?.cancel()
            GrainHaptics.light()
        } else {
            if currentTime >= duration && duration > 0 {
                seek(to: 0)
            }
            player.play()
            applySpeed(playbackSpeed)
            isPlaying = true
            scheduleControlsDismissal()
            GrainHaptics.light()
        }
    }

    public func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(duration, seconds))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        self.currentTime = clamped
    }

    public func seekRelative(_ deltaSeconds: Double) {
        guard duration > 0 else { return }
        seek(to: currentTime + deltaSeconds)
        let text = deltaSeconds > 0 ? "+\(Int(deltaSeconds))s" : "\(Int(deltaSeconds))s"
        seekRipple = (isForward: deltaSeconds > 0, text: text)
        GrainHaptics.medium()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.seekRipple?.text == text {
                self?.seekRipple = nil
            }
        }
    }

    public func setSpeed(_ speed: PlaybackSpeed) {
        self.playbackSpeed = speed
        if isPlaying && !isFastForwarding {
            applySpeed(speed)
        }
        GrainHaptics.selection()
    }

    private func applySpeed(_ speed: PlaybackSpeed) {
        player?.rate = Float(speed.rawValue)
    }

    public func toggleLoop() {
        isLooping.toggle()
        GrainHaptics.selection()
    }

    public func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        GrainHaptics.selection()
    }

    public func cycleScaleMode() {
        switch scaleMode {
        case .aspectFit:
            scaleMode = .aspectFill
        case .aspectFill:
            scaleMode = .ratio16x9
        case .ratio16x9:
            scaleMode = .ratio4x3
        case .ratio4x3:
            scaleMode = .aspectFit
        }
        GrainHaptics.selection()
    }

    // MARK: - 手势 1: 双击快进 / 快退 ±10s

    public func doubleTapSeek(forward: Bool) {
        let interval = Double(doubleTapSeekInterval)
        seekRelative(forward ? interval : -interval)
    }

    // MARK: - 手势 2: 垂直拖动调节亮度 (左半屏)

    public func adjustBrightness(delta: CGFloat) {
        let current = UIScreen.main.brightness
        let newBrightness = max(0.0, min(1.0, current - delta))
        UIScreen.main.brightness = newBrightness
        self.currentBrightness = newBrightness
        self.showBrightnessHUD = true

        brightnessDismissTask?.cancel()
        brightnessDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.showBrightnessHUD = false
        }
    }

    // MARK: - 手势 3: 垂直拖动调节音量 (右半屏)

    public func adjustVolume(delta: Float) {
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        let current = slider?.value ?? currentVolume
        let newVolume = max(0.0, min(1.0, current - delta))

        slider?.setValue(newVolume, animated: false)
        self.currentVolume = newVolume
        self.showVolumeHUD = true

        volumeDismissTask?.cancel()
        volumeDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self.showVolumeHUD = false
        }
    }

    // MARK: - 手势 4: 水平滑动精准时间轴微调

    public func startScrubbing() {
        isScrubbing = true
        scrubTargetTime = currentTime
        scrubDeltaSeconds = 0
        controlsDismissTask?.cancel()
        GrainHaptics.selection()
    }

    public func updateScrubbing(fraction: CGFloat, translationX: CGFloat) {
        guard duration > 0 else { return }
        let delta = Double(translationX) * 0.15
        let target = max(0, min(duration, currentTime + delta))
        scrubDeltaSeconds = Int((target - currentTime).rounded())
        scrubTargetTime = target
    }

    public func finishScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        seek(to: scrubTargetTime)
        scheduleControlsDismissal()
        GrainHaptics.light()
    }

    // MARK: - 手势 5: 长按 2.0x 瞬时快速快进

    public func startFastForward() {
        guard isPlaying, !isFastForwarding else { return }
        isFastForwarding = true
        originalSpeedBeforeFastForward = playbackSpeed
        player?.rate = 2.0
        GrainHaptics.medium()
    }

    public func endFastForward() {
        guard isFastForwarding else { return }
        isFastForwarding = false
        applySpeed(originalSpeedBeforeFastForward)
        GrainHaptics.light()
    }

    // MARK: - 截取原画高清视频帧

    public func captureSnapshot() async {
        guard let asset = player?.currentItem?.asset else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
        do {
            let cgImage = try await generator.image(at: cmTime).image
            let uiImage = UIImage(cgImage: cgImage)

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }

            snapshotToast = "已截取原画帧并保存到相册"
            GrainHaptics.success()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.snapshotToast = nil
            }
        } catch {
            snapshotToast = "截帧失败: \(error.localizedDescription)"
            GrainHaptics.error()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.snapshotToast = nil
            }
        }
    }

    // MARK: - 画中画 (PiP) 设置

    private func setupPictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPiPAvailable = false
            return
        }
        isPiPAvailable = true
    }

    public func togglePictureInPicture() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
        GrainHaptics.selection()
    }

    public nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = true
        }
    }

    public nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = false
        }
    }

    // MARK: - 字幕控制

    private func parseEmbeddedSubtitles(from asset: AVAsset) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var list: [SubtitleTrack] = []
            if let mediaSelectionGroup = try? await asset.loadMediaSelectionGroup(for: .legible) {
                for option in mediaSelectionGroup.options {
                    let title = option.displayName
                    list.append(SubtitleTrack(id: option.locale?.identifier ?? title, title: title, isExternal: false))
                }
            }
            let result = list
            await MainActor.run {
                self.subtitleTracks = result
            }
        }
    }

    public func loadExternalSubtitle(url: URL) {
        do {
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }

            let text = try String(contentsOf: url, encoding: .utf8)
            let track = SubtitleParser.parse(content: text, trackTitle: url.lastPathComponent)
            self.subtitleTracks.append(track)
            self.selectedSubtitleTrack = track
            GrainHaptics.success()
        } catch {
            print("外挂字幕解析失败: \(error)")
        }
    }

    public func selectSubtitleTrack(_ track: SubtitleTrack?) {
        self.selectedSubtitleTrack = track
        if track == nil {
            self.currentSubtitleText = nil
        }
        GrainHaptics.selection()
    }

    private func updateActiveSubtitle(at time: TimeInterval) {
        guard let track = selectedSubtitleTrack, track.isExternal else {
            currentSubtitleText = nil
            return
        }
        currentSubtitleText = SubtitleParser.currentSubtitle(at: time, in: track.items)
    }

    // MARK: - HUD 显隐调度

    public func toggleControlsVisibility() {
        guard !isControlsLocked else {
            // 锁定状态下点击屏幕晃动锁图标提示
            GrainHaptics.light()
            return
        }
        showControls.toggle()
        if showControls && isPlaying {
            scheduleControlsDismissal()
        } else {
            controlsDismissTask?.cancel()
        }
        GrainHaptics.light()
    }

    public func scheduleControlsDismissal() {
        controlsDismissTask?.cancel()
        controlsDismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.isPlaying && !self.isScrubbing && !self.isControlsLocked {
                self.showControls = false
            }
        }
    }

    public func toggleLockControls() {
        isControlsLocked.toggle()
        if isControlsLocked {
            showControls = false
        }
        GrainHaptics.medium()
    }

    // MARK: - 清理释放

    public func cleanup() {
        removeTimeObserver()
        player?.pause()
        player = nil
        currentItem = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        bufferedProgress = 0
        currentSubtitleText = nil
        isFastForwarding = false
        isControlsLocked = false
        showControls = true
    }
}
