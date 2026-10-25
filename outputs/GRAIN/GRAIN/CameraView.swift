import AudioToolbox
import AVFoundation
import CoreImage
import CoreLocation
import CoreMotion
import Foundation
import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension AVCaptureConnection {
    /// 安全设置竖屏朝向：优先采用 iOS 17+ 的 videoRotationAngle (90°)，未支持时回退到 videoOrientation，严防双调引发 NSInvalidArgumentException
    func applyPortraitOrientationSafely() {
        if isVideoRotationAngleSupported(90) {
            videoRotationAngle = 90
        } else if isVideoOrientationSupported {
            videoOrientation = .portrait
        }
    }
}

enum CameraCaptureFormat: String, CaseIterable, Identifiable {
    case heif
    case jpeg
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heif: "HEIF"
        case .jpeg: "JPG"
        case .raw: "RAW"
        }
    }
}

enum CameraResolution: String, CaseIterable, Identifiable {
    case standard24
    case high48

    var id: String { rawValue }
    var title: String { self == .standard24 ? "24MP" : "48MP" }
    var targetPixels: Double { self == .standard24 ? 24_000_000 : 48_000_000 }
}

enum CameraAspect: String, CaseIterable, Identifiable {
    case portrait3x4
    case square
    case portrait3x2
    case portrait16x9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait3x4: "3:4"
        case .square: "1:1"
        case .portrait3x2: "3:2"
        case .portrait16x9: "16:9"
        }
    }

    /// App 锁定竖屏，所以比例一律按竖屏理解：
    /// 16:9 表示 9:16 的竖幅裁切（与 iOS 原生相机在竖屏下的取景一致）。
    var ratio: Double {
        switch self {
        case .portrait3x4: 3.0 / 4
        case .square: 1
        case .portrait3x2: 2.0 / 3
        case .portrait16x9: 9.0 / 16
        }
    }
}

enum CameraTimer: String, CaseIterable, Identifiable {
    case off
    case three
    case five
    case ten

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "计时关"
        case .three: "3 秒"
        case .five: "5 秒"
        case .ten: "10 秒"
        }
    }
    var seconds: Int {
        switch self {
        case .off: 0
        case .three: 3
        case .five: 5
        case .ten: 10
        }
    }
}

/// 录像规格：分辨率 + 帧率（数字按数字，4K大写，帧率如 60fps 小写）
enum VideoQuality: String, CaseIterable, Identifiable {
    case uhd4k120
    case uhd4k60
    case uhd4k30
    case uhd4k24
    case uhd4k20
    case hd1080p60
    case hd1080p30

    var id: String { rawValue }

    /// 视频尺寸按横向存储（与 AVCaptureDevice.Format 的 dimensions 一致）
    var shortSide: Int {
        switch self {
        case .hd1080p30, .hd1080p60: 1080
        case .uhd4k20, .uhd4k24, .uhd4k30, .uhd4k60, .uhd4k120: 2160
        }
    }

    var longSide: Int {
        switch self {
        case .hd1080p30, .hd1080p60: 1920
        case .uhd4k20, .uhd4k24, .uhd4k30, .uhd4k60, .uhd4k120: 3840
        }
    }

    var fps: Int {
        switch self {
        case .hd1080p30, .uhd4k30: 30
        case .hd1080p60, .uhd4k60: 60
        case .uhd4k20: 20
        case .uhd4k24: 24
        case .uhd4k120: 120
        }
    }

    var title: String {
        switch self {
        case .uhd4k120: "4K120"
        case .uhd4k60: "4K60"
        case .uhd4k30: "4K30"
        case .uhd4k24: "4K24"
        case .uhd4k20: "4K20"
        case .hd1080p60: "1080P60"
        case .hd1080p30: "1080P30"
        }
    }
}

/// 录像画面比例：4:3, 16:9, 2:1, 2.35:1
enum VideoAspect: String, CaseIterable, Identifiable {
    case sixteenByNine = "16:9"
    case fourByThree = "4:3"
    case twoToOne = "2:1"
    case twoThirtyFive = "2.35:1"

    var id: String { rawValue }
    var title: String { rawValue }

    /// 竖屏取景与录制宽高比 (width / height)
    var portraitRatio: CGFloat {
        switch self {
        case .sixteenByNine: 9.0 / 16.0
        case .fourByThree: 3.0 / 4.0
        case .twoToOne: 1.0 / 2.0
        case .twoThirtyFive: 1.0 / 2.35
        }
    }
}

/// 视频快门速度手动档位
enum ManualShutterOption: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case s24 = "1/24"
    case s30 = "1/30"
    case s48 = "1/48"
    case s50 = "1/50"
    case s60 = "1/60"
    case s120 = "1/120"
    case s240 = "1/240"
    case s500 = "1/500"
    case s1000 = "1/1000"

    var id: String { rawValue }
    var title: String { rawValue }

    var duration: CMTime? {
        switch self {
        case .auto: return nil
        case .s24: return CMTime(value: 1, timescale: 24)
        case .s30: return CMTime(value: 1, timescale: 30)
        case .s48: return CMTime(value: 1, timescale: 48)
        case .s50: return CMTime(value: 1, timescale: 50)
        case .s60: return CMTime(value: 1, timescale: 60)
        case .s120: return CMTime(value: 1, timescale: 120)
        case .s240: return CMTime(value: 1, timescale: 240)
        case .s500: return CMTime(value: 1, timescale: 500)
        case .s1000: return CMTime(value: 1, timescale: 1000)
        }
    }
}

/// 视频 ISO 手动档位
enum ManualISOOption: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case iso50 = "50"
    case iso100 = "100"
    case iso200 = "200"
    case iso400 = "400"
    case iso800 = "800"
    case iso1600 = "1600"
    case iso3200 = "3200"

    var id: String { rawValue }
    var title: String { self == .auto ? "ISO 自动" : "ISO \(rawValue)" }

    var value: Float? {
        switch self {
        case .auto: return nil
        case .iso50: return 50
        case .iso100: return 100
        case .iso200: return 200
        case .iso400: return 400
        case .iso800: return 800
        case .iso1600: return 1600
        case .iso3200: return 3200
        }
    }
}

/// 视频白平衡模式
enum VideoWhiteBalanceMode: String, CaseIterable, Identifiable {
    case auto = "AWB"
    case incandescent = "3200K"
    case fluorescent = "4000K"
    case daylight = "5500K"
    case cloudy = "6500K"
    case shade = "7500K"

    var id: String { rawValue }
    var title: String { rawValue }

    var temperature: Float? {
        switch self {
        case .auto: return nil
        case .incandescent: return 3200
        case .fluorescent: return 4000
        case .daylight: return 5500
        case .cloudy: return 6500
        case .shade: return 7500
        }
    }
}

/// 视频色彩空间：Rec.709, Display P3, Apple Log / HDR
enum VideoColorSpacePreference: String, CaseIterable, Identifiable {
    case rec709 = "Rec.709"
    case p3 = "Display P3"
    case hlgHDR = "Apple Log / HDR"

    var id: String { rawValue }
    var title: String { rawValue }

    var avColorSpace: AVCaptureColorSpace {
        switch self {
        case .rec709: return .sRGB
        case .p3: return .P3_D65
        case .hlgHDR: return .HLG_BT2020
        }
    }
}

/// 视频比例裁切服务：录制完毕后按所选比例 (4:3, 2:1, 2.35:1) 导出保存
enum VideoCropService {
    static func crop(url: URL, to aspect: VideoAspect) async throws -> URL {
        guard aspect != .sixteenByNine else { return url }
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return url
        }
        let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        guard naturalSize.width > 0, naturalSize.height > 0 else { return url }

        // 计算旋转变换后的可视尺寸
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let visualWidth = abs(transformedRect.width)
        let visualHeight = abs(transformedRect.height)
        guard visualWidth > 0, visualHeight > 0 else { return url }

        let targetRatio = aspect.portraitRatio
        let currentRatio = visualWidth / visualHeight

        var targetWidth = visualWidth
        var targetHeight = visualHeight

        if currentRatio > targetRatio {
            targetWidth = round((visualHeight * targetRatio) / 2.0) * 2.0
        } else {
            targetHeight = round((visualWidth / targetRatio) / 2.0) * 2.0
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GRAIN-CROPPED-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).\(url.pathExtension)")
        try? FileManager.default.removeItem(at: outputURL)

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return url }

        let duration = (try? await asset.load(.duration)) ?? .zero
        guard duration.seconds > 0 else { return url }
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        do {
            try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        } catch {
            return url
        }

        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: targetWidth, height: targetHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)

        let xOffset = (targetWidth - visualWidth) / 2.0
        let yOffset = (targetHeight - visualHeight) / 2.0
        let finalTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: xOffset, y: yOffset)
        )

        layerInstruction.setTransform(finalTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { return url }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        if exportSession.status == .completed {
            return outputURL
        }
        return url
    }
}

/// 录像防抖档位：增强、电影级、标准、关
enum VideoStabilization: String, CaseIterable, Identifiable {
    case cinematicExtended
    case cinematic
    case standard
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cinematicExtended: "增强"
        case .cinematic: "电影级"
        case .standard: "标准"
        case .off: "关"
        }
    }

    var mode: AVCaptureVideoStabilizationMode {
        switch self {
        case .cinematicExtended: .cinematicExtended
        case .cinematic: .cinematic
        case .standard: .standard
        case .off: .off
        }
    }
}

/// 录像封装格式：MOV 与 MP4
enum VideoContainerPreference: String, CaseIterable, Identifiable {
    case mov
    case mp4

    var id: String { rawValue }
    var title: String { self == .mov ? "MOV" : "MP4" }
    var fileExtension: String { self == .mov ? "mov" : "mp4" }
    var outputFileType: AVFileType { self == .mov ? .mov : .mp4 }
}

/// 录像编码：只列系统相机也提供的两种，具体可用性按设备过滤
enum VideoCodecPreference: String, CaseIterable, Identifiable {
    case hevc
    case h264

    var id: String { rawValue }

    var title: String { self == .hevc ? "HEVC" : "H.264" }

    var codecType: AVVideoCodecType { self == .hevc ? .hevc : .h264 }
}

/// 相机工作模式：拍照 / 录像
enum CameraMode: String {
    case photo
    case video
}

enum CameraFlashSetting: String, CaseIterable, Identifiable {
    case off
    case auto
    case on

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "闪光关"
        case .auto: "自动闪光"
        case .on: "闪光开"
        }
    }
    var symbol: String {
        switch self {
        case .off: "bolt.slash"
        case .auto: "bolt.badge.automatic"
        case .on: "bolt.fill"
        }
    }
    var captureMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: .off
        case .auto: .auto
        case .on: .on
        }
    }
}

struct CameraCaptureConfiguration {
    let format: CameraCaptureFormat
    let resolution: CameraResolution
    let aspect: CameraAspect
    let timer: CameraTimer
    let flash: CameraFlashSetting
    let livePhoto: Bool
}

final class CameraController: ObservableObject {
    static let shared = CameraController()
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "studio.grain.camera.session")
    private var cameraDevice: AVCaptureDevice?
    /// 长焦相对主摄的光学倍率（iPhone 17 Pro 为 4×）
    private var teleReach: CGFloat = 4
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var photoOutputAttached = false
    private var isSessionConfigured = false
    private var formatSwitchFailure: String?
    private var requestedResolution: CameraResolution = .standard24
    private var supportsRawCapture = false
    private var activeProcessors: [Int64: CameraPhotoCaptureProcessor] = [:]
    private let processorLock = NSLock()
    private var captureGeneration = 0

    // 峰值对焦：按需挂一个视频数据输出，关闭时立刻移除，
    // 默认关闭，保证不开启时相机管线与之前完全一致。
    private let peakingOutput = AVCaptureVideoDataOutput()
    private let peakingQueue = DispatchQueue(
        label: "studio.grain.camera.peaking",
        qos: .userInitiated
    )
    private let peakingProcessor = FocusPeakingProcessor()
    private var peakingAttached = false
    private var hintGeneration = 0
    /// 预览视图直接从这里取峰值帧，绕开 SwiftUI 的状态刷新
    let peakingOverlay = PeakingOverlaySink()

    // 自动追焦：主体检测 + 连续对焦，手动点按时自动让位
    private let metadataOutput = AVCaptureMetadataOutput()
    private let metadataQueue = DispatchQueue(
        label: "studio.grain.camera.metadata",
        qos: .utility
    )
    private let trackingProcessor = FocusTrackingProcessor()
    private var metadataAttached = false
    /// 预览视图从这里取主体框，换算成图层坐标后画追焦框
    let trackingSink = FocusTrackingSink()
    private var lastTrackingPoint = CGPoint(x: 0.5, y: 0.5)
    private var manualFocusActive = false
    private var subjectAreaObserver: NSObjectProtocol?

    @Published private(set) var isReady = false
    @Published private(set) var isCapturing = false
    @Published private(set) var countdown: Int?
    @Published private(set) var errorMessage: String?
    /// 峰值对焦：彩色描边标出合焦区域
    @Published private(set) var isFocusPeakingEnabled = false
    @Published private(set) var peakingHint: String?
    /// 自动追焦：开机会话后默认开启，主体变化自动跟焦
    @Published private(set) var focusTrackingEnabled = true
    /// 用户手动点按/锁定对焦后，追焦暂停，等待手动恢复
    @Published private(set) var isManualFocusActive = false
    /// 曝光手动模式：锁定曝光，滑杆直接决定画面亮度
    @Published private(set) var exposureManual = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingSeconds: Int = 0
    @Published private(set) var recordingError: String?
    /// 录像补光灯（录像用的是手电筒，不是拍照闪光灯）
    @Published private(set) var isTorchOn = false
    /// 设备可用的录像编码，UI 只展示这些
    @Published private(set) var availableVideoCodecs: [AVVideoCodecType] = []
    @Published private(set) var isLivePhotoSupported = false
    @Published private(set) var isLivePhotoArmed = false
    @Published private(set) var isRawSupported = false
    @Published private(set) var maxPhotoDimensions = CMVideoDimensions(width: 0, height: 0)
    @Published private(set) var minimumZoom: CGFloat = 1
    @Published private(set) var maximumZoom: CGFloat = 8
    @Published private(set) var selectedZoom: CGFloat = 1
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var minimumExposureBias: Float = -2
    @Published private(set) var maximumExposureBias: Float = 2
    @Published private(set) var isUsingFrontCamera = false
    @Published private(set) var latestCaptureThumbnail: UIImage?
    /// 最近一张成功写入相册的照片标识，用于从左下角缩略图直接进入编辑
    @Published private(set) var latestCaptureAssetIdentifier: String?
    /// 实时直方图数据
    @Published private(set) var liveHistogram: RGBHistogram?

    /// 录像实时电平与剩余空间监控
    @Published private(set) var liveAudioLevel: Float = 0.0
    @Published private(set) var freeStorageBytes: Int64 = 0
    /// 录像内存防爆安全阈值：至少保证本机剩余 10GB 空间
    static let minimumStorageForRecording: Int64 = 10 * 1024 * 1024 * 1024
    private var audioMeterTimer: Timer?
    private var updateStorageTimer: Timer?
    private var activeRecordingAspect: VideoAspect = .sixteenByNine

    var freeStorageString: String {
        let gb = Double(freeStorageBytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            let mb = Double(freeStorageBytes) / 1_048_576.0
            return String(format: "%.0f MB", mb)
        }
    }

    func remainingTimeString(for quality: VideoQuality) -> String {
        let bytesPerSecond: Int64
        switch quality {
        case .uhd4k120: bytesPerSecond = 18_000_000
        case .uhd4k60: bytesPerSecond = 10_000_000
        case .uhd4k30, .uhd4k24, .uhd4k20: bytesPerSecond = 5_000_000
        case .hd1080p60: bytesPerSecond = 3_200_000
        case .hd1080p30: bytesPerSecond = 2_000_000
        }
        let recordableBytes = max(0, freeStorageBytes - Self.minimumStorageForRecording)
        if recordableBytes == 0 {
            return "不可录(需>10G)"
        }
        let totalSecs = recordableBytes / max(bytesPerSecond, 1)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let seconds = totalSecs % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    func startAudioAndStorageMonitoring() {
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        updateFreeStorage()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioMeterTimer?.invalidate()
            self.audioMeterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let self else { return }
                // 待机与拍摄时均实时监听麦克风电平
                guard self.movieAttached, self.session.isRunning else {
                    if self.liveAudioLevel != 0 {
                        self.liveAudioLevel = 0
                    }
                    return
                }
                if let audioConn = self.movieOutput.connection(with: .audio),
                   let channel = audioConn.audioChannels.first {
                    let power = channel.averagePowerLevel
                    if !power.isNaN && !power.isInfinite {
                        let norm = max(0.0, min(1.0, Float((power + 50.0) / 50.0)))
                        self.liveAudioLevel = norm
                    }
                }
                // 录制中持续监控可用空间；若低于 10GB 安全阈值，立刻自动停止录像防止爆仓
                if self.isRecording && self.freeStorageBytes < Self.minimumStorageForRecording {
                    self.stopRecording()
                    self.recordingError = "设备剩余可用空间已低于 10GB 安全阈值，已自动保存并停止录像，以防止存储耗尽。"
                }
            }
            self.updateStorageTimer?.invalidate()
            self.updateStorageTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.updateFreeStorage()
            }
        }
    }

    func stopAudioAndStorageMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioMeterTimer?.invalidate()
            self.audioMeterTimer = nil
            self.updateStorageTimer?.invalidate()
            self.updateStorageTimer = nil
            self.liveAudioLevel = 0
        }
    }

    private func updateFreeStorage() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            DispatchQueue.main.async {
                self.freeStorageBytes = bytes
            }
        } else if let dict = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                  let freeSize = dict[.systemFreeSize] as? NSNumber {
            DispatchQueue.main.async {
                self.freeStorageBytes = freeSize.int64Value
            }
        }
    }

    func applyManualExposure(shutter: ManualShutterOption, iso: ManualISOOption) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if shutter == .auto && iso == .auto {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                } else {
                    let currentDuration = device.exposureDuration
                    let currentISO = device.iso
                    let format = device.activeFormat
                    let targetDuration: CMTime
                    if let dur = shutter.duration {
                        let clamped = max(min(dur.seconds, format.maxExposureDuration.seconds), format.minExposureDuration.seconds)
                        targetDuration = CMTime(seconds: clamped, preferredTimescale: 1_000_000)
                    } else {
                        targetDuration = currentDuration
                    }
                    let targetISO: Float
                    if let i = iso.value {
                        targetISO = max(min(i, format.maxISO), format.minISO)
                    } else {
                        targetISO = currentISO
                    }
                    device.setExposureModeCustom(duration: targetDuration, iso: targetISO, completionHandler: nil)
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func applyWhiteBalance(_ mode: VideoWhiteBalanceMode) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if let temp = mode.temperature {
                    let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temp, tint: 0)
                    var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                    let maxGain = device.maxWhiteBalanceGain
                    gains.redGain = max(1.0, min(gains.redGain, maxGain))
                    gains.greenGain = max(1.0, min(gains.greenGain, maxGain))
                    gains.blueGain = max(1.0, min(gains.blueGain, maxGain))
                    if device.isWhiteBalanceModeSupported(.locked) {
                        device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                    }
                } else {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func applyColorSpace(_ preference: VideoColorSpacePreference) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                let targetSpace = preference.avColorSpace
                if device.activeFormat.supportedColorSpaces.contains(targetSpace) {
                    device.activeColorSpace = targetSpace
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func start() async {
        let cameraAllowed = await requestMediaAccess(for: .video)
        guard cameraAllowed else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "请在系统设置中允许 GRAIN 使用相机。"
            }
            return
        }
        let wantsLocation = UserDefaults.standard
            .object(forKey: "captureLocationEnabled") as? Bool ?? true
        if wantsLocation {
            await MainActor.run {
                CaptureLocationProvider.shared.start()
            }
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 视图可能重复出现；已配置过就只恢复运行，避免重复 addInput 触发
            // “无法配置相机会话”。
            if self.isSessionConfigured {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    self.isReady = true
                }
                return
            }
            self.configureSession()
        }
    }

    func stop() {
        captureGeneration += 1
        DispatchQueue.main.async {
            CaptureLocationProvider.shared.stop()
        }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - 峰值对焦

    /// 开启时临时挂一个视频数据输出分析边缘；关闭时立即移除，
    /// 保证默认状态下的拍照管线与之前完全一致。
    func setFocusPeaking(_ enabled: Bool) {
        guard enabled != isFocusPeakingEnabled else { return }
        isFocusPeakingEnabled = enabled
        peakingHint = nil
        if !enabled {
            peakingOverlay.submit(nil)
        }
        if enabled && !peakingAttached {
            sessionQueue.async { [weak self] in
                self?.attachPeakingOutput()
            }
        }
    }

    /// 峰值描边颜色（红 / 黄 / 蓝 / 白），切换后下一帧即生效
    func setPeakingColor(_ color: FocusPeakingColor) {
        let resolved = color.ciColor
        peakingQueue.async { [weak self] in
            self?.peakingProcessor.tintColor = resolved
        }
    }

    private func attachPeakingOutput() {
        guard !peakingAttached else { return }
        guard isSessionConfigured else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isFocusPeakingEnabled = false
                self.showPeakingHint("相机还在启动，请稍后再试")
            }
            return
        }
        peakingOutput.alwaysDiscardsLateVideoFrames = true
        peakingOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        peakingOutput.setSampleBufferDelegate(peakingProcessor, queue: peakingQueue)
        peakingProcessor.onMask = { [weak self] image in
            guard let self, self.isFocusPeakingEnabled else { return }
            self.peakingOverlay.submit(image)
        }
        peakingProcessor.onHistogram = { [weak self] hist in
            DispatchQueue.main.async {
                self?.liveHistogram = hist
            }
        }

        session.beginConfiguration()
        guard session.canAddOutput(peakingOutput) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isFocusPeakingEnabled = false
                self.peakingOverlay.submit(nil)
                self.showPeakingHint("当前镜头不支持峰值对焦")
            }
            return
        }
        session.addOutput(peakingOutput)
        peakingAttached = true
        // 视频输出不参与静态拍照，但会话重配后同步一次照片尺寸，避免超出当前格式限制
        if let device = cameraDevice, let dims = maximumPhotoDimensions(for: device),
           device.activeFormat.supportedMaxPhotoDimensions.contains(where: { $0.width == dims.width && $0.height == dims.height }) {
            photoOutput.maxPhotoDimensions = dims
        }
        session.commitConfiguration()
        updatePeakingConnection()
    }

    private func detachPeakingOutput() {
        guard peakingAttached else { return }
        session.beginConfiguration()
        session.removeOutput(peakingOutput)
        session.commitConfiguration()
        peakingAttached = false
        peakingProcessor.onMask = nil
        peakingProcessor.onHistogram = nil
        peakingOverlay.submit(nil)
    }

    var currentStabilization: VideoStabilization = .standard

    /// 分析图的方向与防抖必须和预览层保持严格一致，确保红色描边与实物像素完全对齐
    func updatePeakingConnection(stabilization: VideoStabilization? = nil) {
        guard let connection = peakingOutput.connection(with: .video) else { return }
        connection.applyPortraitOrientationSafely()
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = cameraDevice?.position == .front
                && frontMirrorEnabled
        }
        let stab = stabilization ?? currentStabilization
        if connection.isVideoStabilizationSupported {
            applyStabilization(stab, to: connection)
        }
    }

    private func showPeakingHint(_ text: String) {
        peakingHint = text
        hintGeneration += 1
        let generation = hintGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard let self, self.hintGeneration == generation else { return }
            self.peakingHint = nil
        }
    }

    func setZoom(_ zoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let requested = min(max(zoom, 0.5), self.maximumZoom)
            self.selectLensIfNeeded(for: requested)
            guard let device = self.cameraDevice else { return }
            let factor = self.hardwareZoomFactor(for: requested, device: device)
            do {
                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.selectedZoom = requested
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "无法切换相机倍率。"
                }
            }
        }
    }

    /// 0.5× 走超广角，4×/8× 自动调用长焦物理镜头。
    /// 这样 4×/8× 是真正的长焦光学成像，而不是主摄裁切数码放大。
    /// 只在 sessionQueue 上调用。
    private func selectLensIfNeeded(for zoom: CGFloat) {
        guard cameraDevice?.position == .back else { return }
        let ultraWideDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        )
        let ultraWide = ultraWideDiscovery.devices.first
            ?? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)

        let wideDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        let wide = wideDiscovery.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

        let teleDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTelephotoCamera],
            mediaType: .video,
            position: .back
        )
        let tele = teleDiscovery.devices.first
            ?? AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)

        if let wide, let tele {
            teleReach = opticalReach(tele: tele, wide: wide)
            let current = cameraDevice?.deviceType
            // 用户要求：4 倍与 8 倍自动调用长焦镜头；达到 3.5x 以上即自动切到长焦
            if zoom >= 3.5, current != .builtInTelephotoCamera {
                if replaceVideoInput(with: tele, preserveZoom: true) { return }
            }
            // 回到广角留滞回，避免在临界点来回跳镜头
            if current == .builtInTelephotoCamera, zoom < 2.8 {
                if replaceVideoInput(with: wide, preserveZoom: true) { return }
            }
            if cameraDevice?.deviceType == .builtInTelephotoCamera { return }
        }

        if zoom < 0.65 {
            if let ultraWide, cameraDevice?.deviceType != .builtInUltraWideCamera {
                _ = replaceVideoInput(with: ultraWide, preserveZoom: true)
            }
        } else if cameraDevice?.deviceType == .builtInUltraWideCamera, let wide, zoom >= 0.75 {
            _ = replaceVideoInput(with: wide, preserveZoom: true)
        }
    }

    /// 用户倍率换算成当前镜头上的硬件倍率
    private func hardwareZoomFactor(for zoom: CGFloat, device: AVCaptureDevice) -> CGFloat {
        let requested: CGFloat
        switch device.deviceType {
        case .builtInUltraWideCamera:
            requested = 1
        case .builtInTelephotoCamera:
            let base = max(teleReach, 1)
            requested = zoom / base
        default:
            requested = zoom
        }
        return min(
            max(requested, device.minAvailableVideoZoomFactor),
            device.maxAvailableVideoZoomFactor
        )
    }

    /// 用两台镜头的视场角估算长焦相对主摄的光学倍率，并吸附到常见档位
    private func opticalReach(tele: AVCaptureDevice, wide: AVCaptureDevice) -> CGFloat {
        let wideFOV = wide.activeFormat.videoFieldOfView
        let teleFOV = tele.activeFormat.videoFieldOfView
        guard wideFOV > 1, teleFOV > 1, teleFOV < wideFOV else { return teleReach }
        let ratio = CGFloat(
            tan(Double(wideFOV) * .pi / 360) / tan(Double(teleFOV) * .pi / 360)
        )
        guard ratio > 1.2 else { return teleReach }
        let common: [CGFloat] = [2, 2.5, 3, 3.5, 4, 4.5, 5, 6]
        return common.min {
            abs(log(ratio / $0)) < abs(log(ratio / $1))
        } ?? 4
    }

    private func replaceVideoInput(
        with device: AVCaptureDevice,
        preserveZoom: Bool = false
    ) -> Bool {
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            // ProRAW 与实况照片/其他镜头可能互斥，换镜头前先关闭，
            // 由下一次 RAW 拍摄重新开启。
            if photoOutput.isAppleProRAWEnabled {
                photoOutput.isAppleProRAWEnabled = false
            }
            if let videoInput {
                session.removeInput(videoInput)
            }
            guard session.canAddInput(newInput) else {
                session.commitConfiguration()
                return false
            }
            session.addInput(newInput)
            // 输入加入会话后再切格式，否则手动选择的格式会被会话重置
            let promoted = promoteToHighestPhotoFormat(device)
            let preferred = photoOutput.isLivePhotoCaptureEnabled
                ? standardPhotoDimensions(for: device)
                : (promoted ?? maximumPhotoDimensions(for: device))
            if let preferred,
               device.activeFormat.supportedMaxPhotoDimensions.contains(where: {
                   $0.width == preferred.width && $0.height == preferred.height
               }) {
                // 输出上限必须跟随当前镜头，否则超广角会沿用主摄的 48MP
                photoOutput.maxPhotoDimensions = preferred
            }
            // 换镜头后要同步照片输出的镜像状态，否则前置拍出来和预览左右相反
            applyPhotoMirroring(for: device)
            session.commitConfiguration()
            videoInput = newInput
            cameraDevice = device
            // 换镜头后原来的手动对焦点已失效，回到自动追焦
            manualFocusActive = false
            lastTrackingPoint = CGPoint(x: 0.5, y: 0.5)
            trackingSink.submit(nil)
            DispatchQueue.main.async { [weak self] in
                self?.isManualFocusActive = false
            }
            if focusTrackingEnabled {
                applyContinuousAutoFocus(true)
            }
            // 换镜头后峰值输出的方向/镜像必须跟着更新，否则红色描边会错位
            if peakingAttached {
                updatePeakingConnection()
            }
            supportsRawCapture = device.position == .back
                && (
                    photoOutput.isAppleProRAWSupported
                    || !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
                )
            publishDeviceCapabilities(
                device,
                liveSupported: device.position == .back,
                rawSupported: supportsRawCapture,
                preserveZoom: preserveZoom
            )
            if let preferred {
                DispatchQueue.main.async { [weak self] in
                    self?.maxPhotoDimensions = preferred
                }
            }
            return true
        } catch {
            return false
        }
    }

    func focus(at devicePoint: CGPoint, lock: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let cameraDevice = self.cameraDevice else { return }
            // 手动对焦接管：立刻停掉追焦覆盖，直到用户点“追焦”恢复
            self.manualFocusActive = true
            self.lastTrackingPoint = devicePoint
            self.trackingSink.submit(nil)
            DispatchQueue.main.async { [weak self] in
                self?.isManualFocusActive = true
            }
            do {
                try cameraDevice.lockForConfiguration()
                if cameraDevice.isFocusPointOfInterestSupported {
                    cameraDevice.focusPointOfInterest = devicePoint
                    cameraDevice.focusMode = lock ? .locked : .autoFocus
                }
                if cameraDevice.isExposurePointOfInterestSupported {
                    cameraDevice.exposurePointOfInterest = devicePoint
                    cameraDevice.exposureMode = lock ? .locked : .autoExpose
                }
                cameraDevice.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "无法设置对焦区域。"
                }
            }
        }
    }

    // MARK: - 自动追焦

    /// 开关追焦；已开启状态下再次点击表示“从手动对焦恢复自动追焦”
    func setFocusTracking(_ enabled: Bool) {
        guard enabled != focusTrackingEnabled else {
            if enabled { resumeAutoFocus() }
            return
        }
        focusTrackingEnabled = enabled
        manualFocusActive = false
        isManualFocusActive = false
        trackingSink.submit(nil)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if enabled {
                self.attachMetadataOutput()
                self.applyContinuousAutoFocus(true)
            } else {
                self.detachMetadataOutput()
                self.trackingSink.submit(nil)
            }
        }
    }

    /// 手动对焦之后恢复自动追焦
    func resumeAutoFocus() {
        trackingSink.submit(nil)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.manualFocusActive = false
            self.lastTrackingPoint = CGPoint(x: 0.5, y: 0.5)
            DispatchQueue.main.async { [weak self] in
                self?.isManualFocusActive = false
            }
            self.applyContinuousAutoFocus(true)
        }
    }

    /// 追焦把对焦点移到主体上；位移太小就不打断当前对焦，避免来回拉风箱
    func applyTrackingFocus(_ point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self,
                  self.focusTrackingEnabled,
                  !self.manualFocusActive,
                  let device = self.cameraDevice
            else { return }
            let dx = abs(point.x - self.lastTrackingPoint.x)
            let dy = abs(point.y - self.lastTrackingPoint.y)
            guard dx + dy > 0.035 else { return }
            self.lastTrackingPoint = point
            guard device.isFocusPointOfInterestSupported else { return }
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                // 手动曝光下不跟着主体挪测光点，否则亮度会跟着跑
                if !self.exposureManual, device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                }
                device.unlockForConfiguration()
            } catch {
                // 对焦配置偶发失败不打断拍照流程
            }
        }
    }

    private func applyContinuousAutoFocus(_ on: Bool) {
        guard let device = cameraDevice else { return }
        do {
            try device.lockForConfiguration()
            if on {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                // 手动曝光时不要把曝光交还给自动测光
                if !self.exposureManual,
                   device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                // 画面主体变化时系统会回调，用于重新合焦
                if device.isSubjectAreaChangeMonitoringEnabled != on {
                    device.isSubjectAreaChangeMonitoringEnabled = on
                }
            }
            device.unlockForConfiguration()
        } catch {
            // 忽略
        }
    }

    /// 人脸追焦开关（设置页）：关掉后只保留连续自动对焦，不做人脸检测
    var faceTrackingEnabled: Bool {
        UserDefaults.standard.object(forKey: "faceTrackingEnabled") as? Bool ?? true
    }

    /// 设置页切换「人脸追焦」时同步相机会话
    func setFaceTracking(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "faceTrackingEnabled")
        if !enabled {
            trackingSink.submit(nil)
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if enabled && !self.metadataAttached {
                self.attachMetadataOutput()
            }
        }
    }

    private func attachMetadataOutput() {
        guard !metadataAttached, isSessionConfigured else { return }
        // 关掉人脸追焦时完全不挂检测输出，省掉一路上的人脸分析开销
        guard faceTrackingEnabled else { return }
        metadataOutput.setMetadataObjectsDelegate(trackingProcessor, queue: metadataQueue)
        trackingProcessor.onSubject = { [weak self] rect in
            guard let self else { return }
            guard self.focusTrackingEnabled, self.faceTrackingEnabled, !self.manualFocusActive else {
                self.trackingSink.submit(nil)
                return
            }
            self.trackingSink.submit(rect)
        }

        session.beginConfiguration()
        guard session.canAddOutput(metadataOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(metadataOutput)
        // 只保留会话实际支持的类型；设置为空数组会崩溃
        let wanted: [AVMetadataObject.ObjectType] = [.face]
            .filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
        guard !wanted.isEmpty else {
            session.removeOutput(metadataOutput)
            session.commitConfiguration()
            return
        }
        metadataOutput.metadataObjectTypes = wanted
        metadataAttached = true
        session.commitConfiguration()
    }

    private func detachMetadataOutput() {
        guard metadataAttached else { return }
        session.beginConfiguration()
        session.removeOutput(metadataOutput)
        session.commitConfiguration()
        metadataAttached = false
        trackingProcessor.onSubject = nil
    }

    // MARK: - 录像

    private let movieOutput = AVCaptureMovieFileOutput()
    private var movieAttached = false
    private let recordingDelegate = MovieRecordingDelegate()
    private var recordingTimer: Timer?
    private var recordingURL: URL?

    func startRecording(
        quality: VideoQuality,
        stabilization: VideoStabilization,
        codec: VideoCodecPreference,
        container: VideoContainerPreference = .mov,
        aspect: VideoAspect = .sixteenByNine
    ) {
        guard !isRecording else { return }
        recordingError = nil
        guard freeStorageBytes >= Self.minimumStorageForRecording else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recordingError = "设备剩余可用空间不足 10GB（当前约 \(self.freeStorageString)），为防止内存过爆已禁止录像，请先清理空间。"
            }
            return
        }
        activeRecordingAspect = aspect
        recordingDelegate.onFinish = { [weak self] url, error in
            self?.finishRecording(url: url, error: error)
        }
        Task {
            let micAllowed = await requestMediaAccess(for: .audio)
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if !self.movieAttached {
                    if micAllowed { self.attachAudioInput() }
                    self.attachMovieOutput()
                }
                self.configureVideoFormat(quality, stabilization: stabilization)
                self.configureMovieConnection(stabilization: stabilization, codec: codec)

                let ext = container.fileExtension
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("GRAIN-\(Int(Date().timeIntervalSince1970)).\(ext)")
                try? FileManager.default.removeItem(at: url)
                self.recordingURL = url

                self.movieOutput.startRecording(
                    to: url,
                    recordingDelegate: self.recordingDelegate
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isRecording = true
                    self.recordingSeconds = 0
                    self.startRecordingTimer()
                }
            }
        }
    }

    /// 切换到录像模式时原子配置音视频输出、防抖格式、色彩空间与编码
    func prepareForVideoMode(
        quality: VideoQuality,
        stabilization: VideoStabilization,
        codec: VideoCodecPreference,
        colorSpace: VideoColorSpacePreference = .rec709
    ) {
        Task {
            let micAllowed = await requestMediaAccess(for: .audio)
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.session.beginConfiguration()

                // 1. 设置 sessionPreset 为 .inputPriority（严禁在 .photo preset 下挂载 movieOutput，否则 commitConfiguration 必闪退）
                if self.session.canSetSessionPreset(.inputPriority) {
                    self.session.sessionPreset = .inputPriority
                }

                // 2. 实况照片与录像输出互斥，切到录像模式时先行解除实况照片
                if self.photoOutput.isLivePhotoCaptureEnabled {
                    self.photoOutput.isLivePhotoCaptureEnabled = false
                }
                DispatchQueue.main.async {
                    self.isLivePhotoArmed = false
                }

                // 3. 移除与录像输出冲突的峰值/直方图视频数据输出 (AVCaptureVideoDataOutput)
                if self.peakingAttached {
                    self.session.removeOutput(self.peakingOutput)
                    self.peakingAttached = false
                }

                // 4. 移除与录像可能冲突的人脸元数据输出 (AVCaptureMetadataOutput)
                if self.metadataAttached {
                    self.session.removeOutput(self.metadataOutput)
                    self.metadataAttached = false
                    self.trackingProcessor.onSubject = nil
                }

                // 5. 挂载音频输入
                if micAllowed && self.audioInput == nil {
                    if let mic = AVCaptureDevice.default(for: .audio),
                       let input = try? AVCaptureDeviceInput(device: mic),
                       self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.audioInput = input
                    }
                }

                // 6. 挂载录像输出
                if !self.movieAttached {
                    if self.session.canAddOutput(self.movieOutput) {
                        self.session.addOutput(self.movieOutput)
                        self.movieAttached = true
                    }
                }

                // 7. 配置视频专属 16:9 格式、帧率与防抖
                self.configureVideoFormatInternal(quality, stabilization: stabilization)

                // 8. 应用色彩空间
                if let device = self.cameraDevice {
                    let targetSpace = colorSpace.avColorSpace
                    if device.activeFormat.supportedColorSpaces.contains(targetSpace) {
                        do {
                            try device.lockForConfiguration()
                            device.activeColorSpace = targetSpace
                            device.unlockForConfiguration()
                        } catch {}
                    }
                }

                // 9. 提交配置完成图连接
                self.session.commitConfiguration()

                // 10. 会话提交后安全配置录像连接（防抖、旋转、镜像），避免在 beginConfiguration 中操作未就绪的连接导致闪退
                self.configureMovieConnection(stabilization: stabilization, codec: codec)

                // 11. 提交配置后安全更新可用的录像编码选项
                let codecs = self.movieOutput.availableVideoCodecTypes
                DispatchQueue.main.async {
                    self.availableVideoCodecs = codecs
                }
            }
        }
    }

    /// 切回拍照模式时恢复照片最高可用分辨率档位与快门曝光帧率范围，并恢复实况照片能力
    func restorePhotoFormat(resolution: CameraResolution = .standard24) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            self.session.beginConfiguration()

            // 1. 移除录像输出，使 photoOutput 能够重新激活实况照片能力 (isLivePhotoCaptureSupported 恢复为 true)
            if self.movieAttached {
                self.session.removeOutput(self.movieOutput)
                self.movieAttached = false
            }

            // 2. 重新挂载峰值与直方图输出 (AVCaptureVideoDataOutput)
            if !self.peakingAttached, self.session.canAddOutput(self.peakingOutput) {
                self.session.addOutput(self.peakingOutput)
                self.peakingAttached = true
            }

            // 3. 如果需要，重新挂载人脸追焦 (AVCaptureMetadataOutput)
            if self.faceTrackingEnabled, !self.metadataAttached, self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                let wanted: [AVMetadataObject.ObjectType] = [.face]
                    .filter { self.metadataOutput.availableMetadataObjectTypes.contains($0) }
                if !wanted.isEmpty {
                    self.metadataOutput.metadataObjectTypes = wanted
                    self.metadataAttached = true
                } else {
                    self.session.removeOutput(self.metadataOutput)
                }
            }

            // 4. 如果实况照片未激活，移除音频输入以节约电量
            if !self.photoOutput.isLivePhotoCaptureEnabled, let audioInput = self.audioInput {
                self.session.removeInput(audioInput)
                self.audioInput = nil
            }

            // 5. 重置视频帧率限制
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = .invalid
                device.activeVideoMaxFrameDuration = .invalid
                device.unlockForConfiguration()
            } catch {}

            // 6. 恢复照片最高分辨率格式或实况模式
            if self.photoOutput.isLivePhotoCaptureEnabled {
                if self.session.canSetSessionPreset(.photo) {
                    self.session.sessionPreset = .photo
                }
                if !self.photoOutput.isLivePhotoCaptureSupported {
                    self.selectLivePhotoFormat(for: device)
                }
            } else {
                if self.session.canSetSessionPreset(.inputPriority) {
                    self.session.sessionPreset = .inputPriority
                }
                _ = self.promoteToHighestPhotoFormat(device)
            }
            let promoted = self.photoOutput.isLivePhotoCaptureEnabled
                ? self.standardPhotoDimensions(for: device)
                : self.promoteToHighestPhotoFormat(device)
            let dims = promoted ?? self.maximumPhotoDimensions(for: device)

            // 7. 恢复高质量照片优先级
            self.photoOutput.maxPhotoQualityPrioritization = .quality

            if let dims,
               device.activeFormat.supportedMaxPhotoDimensions.contains(where: {
                   $0.width == dims.width && $0.height == dims.height
               }) {
                self.photoOutput.maxPhotoDimensions = dims
            }
            self.applyPhotoMirroring(for: device)

            self.session.commitConfiguration()

            // 8. 提交会话后安全更新峰值连接
            if self.peakingAttached {
                self.updatePeakingConnection()
            }

            // 9. 重新发布相机能力（此时 isLivePhotoSupported 恢复为 true）
            let liveSupported = self.photoOutput.isLivePhotoCaptureSupported || device.position == .back || device.position == .front
            let rawSupported = self.supportsRawCapture
            self.publishDeviceCapabilities(
                device,
                liveSupported: liveSupported,
                rawSupported: rawSupported,
                preserveZoom: true
            )
        }
    }

    /// 动态切换防抖档位（增强、电影级、标准、关）
    func setVideoStabilization(
        _ stabilization: VideoStabilization,
        quality: VideoQuality
    ) {
        currentStabilization = stabilization
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureVideoFormat(quality, stabilization: stabilization)
            if let connection = self.movieOutput.connection(with: .video) {
                self.applyStabilization(stabilization, to: connection)
            }
            if self.peakingAttached {
                self.updatePeakingConnection(stabilization: stabilization)
            }
        }
    }

    private func applyStabilization(
        _ stabilization: VideoStabilization,
        to connection: AVCaptureConnection
    ) {
        guard connection.isVideoStabilizationSupported else { return }
        let targetMode = stabilization.mode
        guard let device = cameraDevice else {
            connection.preferredVideoStabilizationMode = targetMode
            return
        }
        if device.activeFormat.isVideoStabilizationModeSupported(targetMode) {
            connection.preferredVideoStabilizationMode = targetMode
        } else if targetMode == .cinematicExtended && device.activeFormat.isVideoStabilizationModeSupported(.cinematic) {
            connection.preferredVideoStabilizationMode = .cinematic
        } else if targetMode != .off && device.activeFormat.isVideoStabilizationModeSupported(.standard) {
            connection.preferredVideoStabilizationMode = .standard
        } else {
            connection.preferredVideoStabilizationMode = targetMode == .off ? .off : .auto
        }
    }

    private func configureMovieConnection(
        stabilization: VideoStabilization,
        codec: VideoCodecPreference
    ) {
        guard let connection = self.movieOutput.connection(with: .video) else { return }
        // 竖屏录制：写 90° 旋转元数据，而不是把像素真的转一遍
        connection.applyPortraitOrientationSafely()
        if connection.isVideoStabilizationSupported {
            applyStabilization(stabilization, to: connection)
        }
        // 前置自拍镜像与拍照保持一致
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored =
                self.isUsingFrontCamera && self.frontMirrorEnabled
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }

    /// 录像补光：录像用的是常亮手电筒，不是拍照闪光灯
    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.cameraDevice,
                  device.hasTorch
            else {
                DispatchQueue.main.async { [weak self] in self?.isTorchOn = false }
                return
            }
            do {
                try device.lockForConfiguration()
                if on, device.isTorchModeSupported(.on) {
                    device.torchMode = .on
                } else if !on, device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { [weak self] in self?.isTorchOn = on }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.isTorchOn = false }
            }
        }
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.recordingSeconds += 1
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    /// 录像时把镜头切到对应分辨率 / 帧率与防抖档位的专属 16:9 视频格式
    private func configureVideoFormat(
        _ quality: VideoQuality,
        stabilization: VideoStabilization = .cinematicExtended
    ) {
        session.beginConfiguration()
        configureVideoFormatInternal(quality, stabilization: stabilization)
        session.commitConfiguration()
    }

    private func configureVideoFormatInternal(
        _ quality: VideoQuality,
        stabilization: VideoStabilization = .cinematicExtended
    ) {
        guard let device = cameraDevice else { return }
        let targetShort = quality.shortSide
        let targetLong = quality.longSide
        let targetFPS = Double(quality.fps)
        let desiredMode = stabilization.mode

        // 检查当前格式是否已经是尺寸匹配、支持帧率且支持当前防抖的 16:9 视频格式
        let currentDims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let curShort = Int(min(currentDims.width, currentDims.height))
        let curLong = Int(max(currentDims.width, currentDims.height))
        let is16by9 = abs(Double(curLong) / max(Double(curShort), 1) - (16.0 / 9.0)) < 0.05
        let curSupportsFPS = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.maxFrameRate >= targetFPS - 0.5
        }
        let curSupportsStab = desiredMode == .off || device.activeFormat.isVideoStabilizationModeSupported(desiredMode)

        if curShort == targetShort && curLong == targetLong && is16by9 && curSupportsFPS && curSupportsStab {
            applySafeFrameRate(to: device, targetFPS: targetFPS)
            return
        }

        let formats = device.formats
        var candidates: [AVCaptureDevice.Format] = []
        for format in formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let short = Int(min(dims.width, dims.height))
            let long = Int(max(dims.width, dims.height))
            guard short == targetShort, long == targetLong else { continue }
            let supportsFPS = format.videoSupportedFrameRateRanges.contains {
                $0.maxFrameRate >= targetFPS - 0.5
            }
            guard supportsFPS else { continue }
            candidates.append(format)
        }

        if candidates.isEmpty {
            for format in formats {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let short = Int(min(dims.width, dims.height))
                let long = Int(max(dims.width, dims.height))
                let ratio = Double(long) / max(Double(short), 1)
                guard abs(ratio - (16.0 / 9.0)) < 0.05 else { continue }
                candidates.append(format)
            }
        }

        // 优先挑选支持目标防抖档位的硬件格式
        var best: AVCaptureDevice.Format? = nil
        for format in candidates {
            if desiredMode == .cinematicExtended && format.isVideoStabilizationModeSupported(.cinematicExtended) {
                best = format
                break
            } else if (desiredMode == .cinematicExtended || desiredMode == .cinematic) && format.isVideoStabilizationModeSupported(.cinematic) {
                if best == nil || !best!.isVideoStabilizationModeSupported(.cinematic) {
                    best = format
                }
            } else if desiredMode != .off && format.isVideoStabilizationModeSupported(.standard) {
                if best == nil {
                    best = format
                }
            } else if best == nil {
                best = format
            }
        }

        guard let format = best ?? candidates.first else { return }

        // 1. 先切换设备 activeFormat 到目标格式
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()
        } catch {}

        // 2. 在 activeFormat 生效后，再将 photoOutput 约束到新格式实际支持的尺寸，并降低优先级为 .balanced
        photoOutput.maxPhotoQualityPrioritization = .balanced
        if let maxDim = device.activeFormat.supportedMaxPhotoDimensions.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }),
           device.activeFormat.supportedMaxPhotoDimensions.contains(where: { $0.width == maxDim.width && $0.height == maxDim.height }) {
            photoOutput.maxPhotoDimensions = maxDim
        }

        // 3. 应用安全帧率
        applySafeFrameRate(to: device, targetFPS: targetFPS)
    }

    private func applySafeFrameRate(to device: AVCaptureDevice, targetFPS: Double) {
        do {
            try device.lockForConfiguration()
            let ranges = device.activeFormat.videoSupportedFrameRateRanges
            // 先将 min 与 max 置为 .invalid，避免先后赋值因互相比较越界抛出异常
            device.activeVideoMinFrameDuration = .invalid
            device.activeVideoMaxFrameDuration = .invalid

            if let matchedRange = ranges.first(where: { targetFPS >= $0.minFrameRate - 0.5 && targetFPS <= $0.maxFrameRate + 0.5 }) {
                let duration = CMTime(value: 1, timescale: Int32(targetFPS))
                // AVFoundation 约束：minFrameDuration 必须 <= maxFrameDuration
                let safeMaxDuration = max(matchedRange.maxFrameDuration, duration)
                device.activeVideoMaxFrameDuration = safeMaxDuration
                device.activeVideoMinFrameDuration = duration
            } else if let fallbackRange = ranges.first {
                let clampedFPS = max(fallbackRange.minFrameRate, min(targetFPS, fallbackRange.maxFrameRate))
                let duration = CMTime(value: 1, timescale: Int32(clampedFPS))
                let safeMaxDuration = max(fallbackRange.maxFrameDuration, duration)
                device.activeVideoMaxFrameDuration = safeMaxDuration
                device.activeVideoMinFrameDuration = duration
            }
            device.unlockForConfiguration()
        } catch {}
    }

    private func attachAudioInput() {
        guard audioInput == nil,
              let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic)
        else { return }
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        audioInput = input
        session.commitConfiguration()
    }

    private func attachMovieOutput() {
        guard !movieAttached else { return }
        session.beginConfiguration()
        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(movieOutput)
        movieAttached = true
        // 会话重配后同步一次照片尺寸，避免超出当前格式限制
        if let device = cameraDevice, let dims = maximumPhotoDimensions(for: device),
           device.activeFormat.supportedMaxPhotoDimensions.contains(where: { $0.width == dims.width && $0.height == dims.height }) {
            photoOutput.maxPhotoDimensions = dims
        }
        session.commitConfiguration()
    }

    /// 录制结束后：抽取首帧缩略图并写入相册
    private func finishRecording(url: URL?, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.stopRecordingTimer()
            self?.isRecording = false
            if let error {
                self?.recordingError = error.localizedDescription
            }
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let url else { return }

            Task {
                var finalExportURL = url
                if self.activeRecordingAspect != .sixteenByNine {
                    if let cropped = try? await VideoCropService.crop(url: url, to: self.activeRecordingAspect) {
                        finalExportURL = cropped
                    }
                }

                // 1. 抽取视频首帧作为左下角缩略图实时显示
                let asset = AVAsset(url: finalExportURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 160, height: 160)
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let thumbnail = UIImage(cgImage: cgImage)
                    DispatchQueue.main.async {
                        self.latestCaptureThumbnail = thumbnail
                    }
                }

                do {
                    let assetID = try await Self.saveVideoToLibrary(finalExportURL)
                    DispatchQueue.main.async {
                        self.latestCaptureAssetIdentifier = assetID
                        GrainHaptics.mediumImpact()
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.recordingError = error.localizedDescription
                    }
                }
                try? FileManager.default.removeItem(at: url)
                if finalExportURL != url {
                    try? FileManager.default.removeItem(at: finalExportURL)
                }
            }
        }
    }

    private static func saveVideoToLibrary(_ url: URL) async throws -> String {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoLibraryDenied
        }
        var placeholderID: String?
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
                if let placeholder = request.placeholderForCreatedAsset {
                    placeholderID = placeholder.localIdentifier
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? ExportError.photoLibraryWriteFailed)
                }
            }
        }
        guard let id = placeholderID else {
            throw ExportError.photoLibraryWriteFailed
        }
        return id
    }

    /// 画面主体明显变化时重新合焦（追焦开启且未手动接管时才响应）
    private func observeSubjectAreaChanges() {
        guard subjectAreaObserver == nil else { return }
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceSubjectAreaDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self,
                  self.focusTrackingEnabled,
                  !self.manualFocusActive
            else { return }
            self.sessionQueue.async { [weak self] in
                self?.applyContinuousAutoFocus(true)
            }
        }
    }

    /// A / M 切换：M 锁定曝光，A 交还给系统自动测光并把补偿归零。
    /// 默认停在 A 档；用户一动曝光条就会自动切到 M（见 setExposureBias）。
    func setExposureManual(_ manual: Bool) {
        guard manual != exposureManual else { return }
        exposureManual = manual
        // 回到 A 档＝“交给相机自动判断”，补偿回中间，滑杆也跟着回 0 EV
        if !manual { exposureBias = 0 }
        let bias = exposureBias
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            self.applyExposureMode(to: device, manual: manual, bias: bias, retry: true)
        }
    }

    /// 真正写入曝光模式；相机正忙（拍照中）时会自动重试一次，
    /// 否则会出现“点了 A 档但画面还是锁死的”。
    private func applyExposureMode(
        to device: AVCaptureDevice,
        manual: Bool,
        bias: Float,
        retry: Bool
    ) {
        do {
            try device.lockForConfiguration()
            if manual {
                if device.isExposureModeSupported(.locked) {
                    device.exposureMode = .locked
                }
            } else {
                // 回到自动：手动期间可能改过测光点，先归位再交还自动测光
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.setExposureTargetBias(bias)
            }
            device.unlockForConfiguration()
            return
        } catch {
            // 忽略，走下面的重试
        }

        guard retry else { return }
        let target = manual
        sessionQueue.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  self.exposureManual == target,
                  let device = self.cameraDevice
            else { return }
            self.applyExposureMode(
                to: device,
                manual: target,
                bias: self.exposureBias,
                retry: false
            )
        }
    }

    /// 手动曝光下松手后重新锁定：先按新补偿测光，再锁住，滑杆即亮度
    func relockExposure() {
        guard exposureManual else { return }
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                return
            }
            self.sessionQueue.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                guard let self,
                      self.exposureManual,
                      let device = self.cameraDevice
                else { return }
                do {
                    try device.lockForConfiguration()
                    if device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                    device.unlockForConfiguration()
                } catch {
                    // 忽略
                }
            }
        }
    }

    /// - parameter fromUser: 用户拖动曝光条时传 true：
    ///   默认 A 档，只要动过曝光就自动进入 M 档，右下角开关跟着变成 M。
    func setExposureBias(_ value: Float, fromUser: Bool = false) {
        if fromUser, !exposureManual {
            exposureManual = true
        }
        sessionQueue.async { [weak self] in
            guard let self, let cameraDevice = self.cameraDevice else { return }
            let clamped = min(
                max(value, cameraDevice.minExposureTargetBias),
                cameraDevice.maxExposureTargetBias
            )
            do {
                try cameraDevice.lockForConfiguration()
                // M 档下先把测光交还自动，补偿才能立刻反映到画面；
                // 松手后 relockExposure 会再锁回去，滑杆就等价于亮度。
                if fromUser,
                   cameraDevice.isExposureModeSupported(.continuousAutoExposure) {
                    cameraDevice.exposureMode = .continuousAutoExposure
                }
                cameraDevice.setExposureTargetBias(clamped)
                cameraDevice.unlockForConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.exposureBias = clamped
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "无法调整曝光补偿。"
                }
            }
        }
    }

    func setPhotoResolution(_ resolution: CameraResolution) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 静态照片始终按相机最大分辨率采集，24MP/48MP 在导出阶段降采样，
            // 避免在运行中的会话里反复改 maxPhotoDimensions 触发异常。
            self.requestedResolution = resolution
            let dims = self.cameraDevice.flatMap {
                self.maximumPhotoDimensions(for: $0)
            } ?? CMVideoDimensions(width: 0, height: 0)
            DispatchQueue.main.async {
                self.maxPhotoDimensions = dims
            }
        }
    }

    /// 当前格式支持的最大静态照片尺寸（iPhone 17 Pro 主摄为 8064×6048）
    private func maximumPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions.max {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
    }

    /// 12MP 档位，用于实况照片等不支持满分辨率输出的场景
    private func standardPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions? {
        device.activeFormat.supportedMaxPhotoDimensions
            .filter { Int($0.width) * Int($0.height) <= 13_000_000 }
            .max {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }
    }

    /// 所选分辨率对应的采集尺寸：取不超过目标像素的最大受支持档位，
    /// 没有更小档位时退到最小档，避免请求超过设置值。
    private func requestedPhotoDimensions(
        for resolution: CameraResolution,
        device: AVCaptureDevice
    ) -> CMVideoDimensions? {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        guard !supported.isEmpty else { return nil }
        let target = resolution.targetPixels
        let withinTarget = supported.filter {
            Double($0.width) * Double($0.height) <= target * 1.05
        }
        if let best = withinTarget.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            return best
        }
        return supported.min {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
    }

    /// RAW 的实际可用尺寸：ProRAW 的 48MP 仅主摄 1× 支持，
    /// 超广角、长焦、数码变焦与前置一律按 12MP 采集。
    private func rawPhotoDimensions(
        for resolution: CameraResolution,
        device: AVCaptureDevice
    ) -> CMVideoDimensions? {
        let isMainCameraAt1x = device.position == .back
            && device.deviceType == .builtInWideAngleCamera
            && selectedZoom <= 1.05
        guard isMainCameraAt1x else {
            return standardPhotoDimensions(for: device)
        }
        return requestedPhotoDimensions(for: resolution, device: device)
    }

    /// 选中支持最大照片尺寸的格式，并返回该格式实际支持的最大尺寸。
    /// 逐档尝试并在切换后回读，切换失败时会记录原因用于诊断。
    private func promoteToHighestPhotoFormat(_ device: AVCaptureDevice) -> CMVideoDimensions? {
        let candidates = device.formats
            .map { format -> (format: AVCaptureDevice.Format, area: Int, videoLongEdge: Int) in
                let video = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return (
                    format,
                    maximumPhotoArea(format),
                    max(Int(video.width), Int(video.height))
                )
            }
            // 部分镜头（尤其是前置）存在“照片尺寸很大、视频流却只有 192×144”的格式。
            // 一旦选中它，预览会糊成马赛克，成片也可能只有几百像素，必须先排除。
            .filter { $0.area > 0 && $0.videoLongEdge >= 1280 }
            .sorted { $0.area > $1.area }

        for candidate in candidates where candidate.area > maximumPhotoArea(device.activeFormat) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = candidate.format
                device.unlockForConfiguration()
            } catch {
                formatSwitchFailure = error.localizedDescription
                continue
            }
            formatSwitchFailure = nil
            if maximumPhotoArea(device.activeFormat) >= candidate.area {
                break
            }
        }

        return device.activeFormat.supportedMaxPhotoDimensions.max {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
    }

    /// 相机能力摘要，用于在无法获得 24MP/48MP 时向用户说明真实状态
    private func capabilityReport(
        _ device: AVCaptureDevice,
        dimensions: CMVideoDimensions?
    ) -> String {
        let highResolutionFormats = device.formats.filter {
            maximumPhotoArea($0) >= 20_000_000
        }.count
        let maxDimensions = dimensions
            ?? device.activeFormat.supportedMaxPhotoDimensions.max {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }
        let dims = maxDimensions.map { "\($0.width)×\($0.height)" } ?? "未知"
        var report = "设备 \(device.deviceType.rawValue)｜≥24MP 格式 \(highResolutionFormats) 个｜最高 \(dims)｜ProRAW \(photoOutput.isAppleProRAWSupported ? "支持" : "不支持")｜输出 \(photoOutput.maxPhotoDimensions.width)×\(photoOutput.maxPhotoDimensions.height)"
        if let formatSwitchFailure {
            report += "｜格式切换失败：\(formatSwitchFailure)"
        }
        return report
    }

    private func maximumPhotoArea(_ format: AVCaptureDevice.Format) -> Int {
        format.supportedMaxPhotoDimensions
            .map { Int($0.width) * Int($0.height) }
            .max() ?? 0
    }

    /// 查找并切换到支持实况照片 (Live Photo) 的 12MP 标准格式
    private func selectLivePhotoFormat(for device: AVCaptureDevice) {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxArea = maximumPhotoArea(format)
            let is12MP = maxArea <= 13_000_000 && maxArea >= 8_000_000
            let hasGoodVideo = dims.width >= 1280 && dims.height >= 720
            let supports30fps = format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 29.5 }
            return is12MP && hasGoodVideo && supports30fps
        }
        for candidate in candidates {
            do {
                try device.lockForConfiguration()
                device.activeFormat = candidate
                device.unlockForConfiguration()
                if photoOutput.isLivePhotoCaptureSupported {
                    break
                }
            } catch {}
        }
    }

    func setLivePhotoEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            _ = await requestMediaAccess(for: .audio)
        }

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                self.session.beginConfiguration()
                if enabled {
                    if let microphone = AVCaptureDevice.default(for: .audio),
                       let input = try? AVCaptureDeviceInput(device: microphone),
                       self.audioInput == nil,
                       self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.audioInput = input
                    }
                } else if let audioInput = self.audioInput {
                    self.session.removeInput(audioInput)
                    self.audioInput = nil
                }
                // ProRAW 与实况照片互斥，必须先关掉 ProRAW 再开启实况照片
                if enabled, self.photoOutput.isAppleProRAWEnabled {
                    self.photoOutput.isAppleProRAWEnabled = false
                }
                // 实况照片切换至 12MP 标准格式以激活 isLivePhotoCaptureSupported
                if let device = self.cameraDevice {
                    if enabled {
                        if self.session.canSetSessionPreset(.photo) {
                            self.session.sessionPreset = .photo
                        }
                    } else {
                        if self.session.canSetSessionPreset(.inputPriority) {
                            self.session.sessionPreset = .inputPriority
                        }
                        _ = self.promoteToHighestPhotoFormat(device)
                    }
                    let target = enabled
                        ? self.standardPhotoDimensions(for: device)
                        : self.maximumPhotoDimensions(for: device)
                    if let target,
                       device.activeFormat.supportedMaxPhotoDimensions.contains(where: {
                           $0.width == target.width && $0.height == target.height
                       }) {
                        self.photoOutput.maxPhotoDimensions = target
                    }
                }
                self.session.commitConfiguration()

                // commitConfiguration 提交后，isLivePhotoCaptureSupported 才会由 AVFoundation 更新
                if enabled {
                    // 若 .photo preset 下仍未激活，再尝试格式回退
                    if !self.photoOutput.isLivePhotoCaptureSupported, let device = self.cameraDevice {
                        self.session.beginConfiguration()
                        if self.session.canSetSessionPreset(.inputPriority) {
                            self.session.sessionPreset = .inputPriority
                        }
                        self.selectLivePhotoFormat(for: device)
                        self.session.commitConfiguration()
                    }
                    if self.photoOutput.isLivePhotoCaptureSupported {
                        self.photoOutput.isLivePhotoCaptureEnabled = true
                    }
                } else {
                    self.photoOutput.isLivePhotoCaptureEnabled = false
                }

                let armed = self.photoOutput.isLivePhotoCaptureEnabled
                DispatchQueue.main.async {
                    self.isLivePhotoArmed = armed
                    self.isLivePhotoSupported = self.photoOutput.isLivePhotoCaptureSupported || armed || self.isUsingFrontCamera || self.cameraDevice?.position == .back
                    continuation.resume(returning: armed)
                }
            }
        }
    }

    func toggleCamera() {
        let targetPosition: AVCaptureDevice.Position = isUsingFrontCamera ? .back : .front
        guard let device = discoverCamera(position: targetPosition) else {
            errorMessage = "没有找到可切换的镜头。"
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.replaceVideoInput(with: device) {
                DispatchQueue.main.async {
                    self.isUsingFrontCamera = device.position == .front
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "无法切换相机。"
                }
            }
        }
    }

    func capture(_ configuration: CameraCaptureConfiguration) {
        guard isReady, !isCapturing else { return }
        captureGeneration += 1
        let generation = captureGeneration
        isCapturing = true
        errorMessage = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            if configuration.timer.seconds > 0 {
                for value in stride(from: configuration.timer.seconds, through: 1, by: -1) {
                    guard generation == self.captureGeneration else { return }
                    self.countdown = value
                    GrainHaptics.selection(enabled: true)
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            guard generation == self.captureGeneration else { return }
            self.countdown = nil
            sessionQueue.async { [weak self] in
                self?.performCapture(configuration)
            }
        }
    }

    func cancelCapture() {
        captureGeneration += 1
        countdown = nil
        isCapturing = false
    }

    private func configureSession() {
        guard let device = discoverCamera(position: .back) else {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "当前设备没有可用的后置相机。"
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            var didCommitConfiguration = false
            defer {
                if !didCommitConfiguration {
                    session.commitConfiguration()
                }
            }

            session.sessionPreset = .photo
            guard session.canAddInput(input) else {
                throw CameraError.cannotConfigure
            }
            session.addInput(input)
            videoInput = input

            // sessionPreset 会覆盖手动选择的 activeFormat，因此先切到 inputPriority，
            // 再挑支持 24MP/48MP 的最高分辨率格式，否则永远只有 12MP。
            session.sessionPreset = .inputPriority
            let promotedDimensions = promoteToHighestPhotoFormat(device)

            guard session.canAddOutput(photoOutput) else {
                throw CameraError.cannotConfigure
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            let captureDimensions = promotedDimensions
                ?? maximumPhotoDimensions(for: device)
            if let captureDimensions,
               device.activeFormat.supportedMaxPhotoDimensions.contains(where: {
                   $0.width == captureDimensions.width
                    && $0.height == captureDimensions.height
               }) {
                photoOutput.maxPhotoDimensions = captureDimensions
            }
            // 不在会话建立时无条件开启 ProRAW：它与实况照片互斥，
            // 开启后一旦切到实况照片就会抛异常闪退。改由每次拍摄按格式开启。
            supportsRawCapture = device.position == .back
                && (
                    photoOutput.isAppleProRAWSupported
                    || !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
                )
            // 照片输出常驻会话：反复移除/添加会让 ProRAW 与最大尺寸状态丢失，
            // 也是 RAW 拍摄失效和闪退的来源之一。
            photoOutputAttached = true

            // 2. 音频输入（若权限已就绪）
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let mic = AVCaptureDevice.default(for: .audio),
               let aInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(aInput) {
                session.addInput(aInput)
                audioInput = aInput
            }

            // 录像输出按需挂载，避免在拍照模式下占用会话并导致实况照片（Live Photo）支持失效
            movieAttached = false

            // 4. 元数据输出（人脸追焦）常驻会话
            metadataOutput.setMetadataObjectsDelegate(trackingProcessor, queue: metadataQueue)
            trackingProcessor.onSubject = { [weak self] rect in
                guard let self else { return }
                guard self.focusTrackingEnabled, self.faceTrackingEnabled, !self.manualFocusActive else {
                    self.trackingSink.submit(nil)
                    return
                }
                self.trackingSink.submit(rect)
            }
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                let wanted: [AVMetadataObject.ObjectType] = [.face]
                    .filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
                if !wanted.isEmpty {
                    metadataOutput.metadataObjectTypes = wanted
                    metadataAttached = true
                } else {
                    session.removeOutput(metadataOutput)
                }
            }

            // 5. 视频数据输出（峰值对焦与实时直方图）常驻会话
            peakingOutput.alwaysDiscardsLateVideoFrames = true
            peakingOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
            ]
            peakingOutput.setSampleBufferDelegate(peakingProcessor, queue: peakingQueue)
            peakingProcessor.onMask = { [weak self] image in
                guard let self, self.isFocusPeakingEnabled else { return }
                self.peakingOverlay.submit(image)
            }
            peakingProcessor.onHistogram = { [weak self] hist in
                DispatchQueue.main.async {
                    self?.liveHistogram = hist
                }
            }
            if session.canAddOutput(peakingOutput) {
                session.addOutput(peakingOutput)
                peakingAttached = true
                updatePeakingConnection()
            }

            // 官方摄影接口：低光自动增强
            if device.isLowLightBoostSupported {
                try? device.lockForConfiguration()
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
                device.unlockForConfiguration()
            }

            cameraDevice = device
            let liveSupported = device.position == .back
            let rawSupported = supportsRawCapture
            let maxDims = captureDimensions
                ?? CMVideoDimensions(width: 0, height: 0)

            session.commitConfiguration()
            didCommitConfiguration = true
            session.startRunning()
            isSessionConfigured = true

            // 追焦默认开启：无需重新提交配置，直接应用连续对焦
            if self.focusTrackingEnabled {
                self.applyContinuousAutoFocus(true)
            }
            self.observeSubjectAreaChanges()

            let report = capabilityReport(device, dimensions: captureDimensions)
            let hasHighResolution = (captureDimensions.map {
                Int($0.width) * Int($0.height)
            } ?? 0) >= 20_000_000

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.maxPhotoDimensions = maxDims
                if !hasHighResolution {
                    // 让用户能直接看到相机真实能力，便于继续定位
                    self.errorMessage = "相机未提供 24MP 以上分辨率：\(report)"
                }
                self.isReady = true
                self.publishDeviceCapabilities(
                    device,
                    liveSupported: liveSupported,
                    rawSupported: rawSupported
                )
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    private func discoverCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            // 24MP/48MP 静态照片与 ProRAW 只在主摄这一物理设备上可用；
            // 虚拟三摄会退化到 12MP 且不提供 RAW 格式。
            if let wide = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ), wide.formats.contains(where: { format in
                format.supportedMaxPhotoDimensions.contains {
                    Int($0.width) * Int($0.height) >= 40_000_000
                }
            }) {
                return wide
            }
            return AVCaptureDevice.default(
                .builtInTripleCamera,
                for: .video,
                position: .back
            ) ?? AVCaptureDevice.default(
                .builtInDualWideCamera,
                for: .video,
                position: .back
            ) ?? AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            )
        }
        return AVCaptureDevice.default(
            .builtInTrueDepthCamera,
            for: .video,
            position: .front
        ) ?? AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        )
    }

    private func publishDeviceCapabilities(
        _ device: AVCaptureDevice,
        liveSupported: Bool,
        rawSupported: Bool,
        preserveZoom: Bool = false
    ) {
        let minimumZoom = device.position == .back ? 0.5 : 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 变焦驱动的换镜头不能把用户正在用的倍率重置回 1×
            if !preserveZoom {
                self.minimumZoom = minimumZoom
                self.maximumZoom = 8
                self.selectedZoom = 1
            }
            self.minimumExposureBias = device.minExposureTargetBias
            self.maximumExposureBias = device.maxExposureTargetBias
            self.exposureBias = min(max(0, device.minExposureTargetBias), device.maxExposureTargetBias)
            self.isUsingFrontCamera = device.position == .front
            self.isLivePhotoSupported = liveSupported || self.photoOutput.isLivePhotoCaptureSupported || device.position == .back || device.position == .front
            self.isRawSupported = rawSupported
        }
    }

    private func performCapture(_ configuration: CameraCaptureConfiguration) {
        // 录像中抓拍：会话正在写文件，不再 begin/commitConfiguration，
        // 直接按当前输出状态拍一张，避免打断录制。
        if isRecording {
            captureProcessed(configuration)
            return
        }
        guard configurePhotoOutputForCapture(
            livePhoto: configuration.livePhoto,
            configuration: configuration
        ) else {
            finishCapture(error: CameraError.cannotConfigure)
            return
        }

        let rawFormats = photoOutput.availableRawPhotoPixelFormatTypes
        // 只接受 ProRAW：Bayer RAW 的容器/元数据无法保证被照片图库接受，
        // 之前超广角 RAW 报 PHPhotosError 3302 就是这种情况。
        let rawFormat = rawFormats.first {
            AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
        }

        if configuration.format == .raw {
            guard let rawFormat else {
                finishCapture(error: CameraError.rawUnavailable)
                return
            }
            captureRaw(configuration, rawFormat: rawFormat)
        } else {
            captureProcessed(configuration)
        }
    }

    /// 每张照片开拍前只同步实况照片开关；照片输出自会话建立后常驻，
    /// 避免反复增删输出导致 ProRAW 与最大尺寸配置失效。
    private func configurePhotoOutputForCapture(
        livePhoto: Bool,
        configuration: CameraCaptureConfiguration
    ) -> Bool {
        session.beginConfiguration()
        if !photoOutputAttached, session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutputAttached = true
        }
        requestedResolution = configuration.resolution

        // ProRAW 与实况照片互斥：先按本次格式切换，避免两者同时开启抛异常。
        let wantsRaw = configuration.format == .raw
            && cameraDevice?.position == .back
        if wantsRaw {
            if photoOutput.isLivePhotoCaptureEnabled {
                photoOutput.isLivePhotoCaptureEnabled = false
            }
            if photoOutput.isAppleProRAWSupported,
               !photoOutput.isAppleProRAWEnabled {
                photoOutput.isAppleProRAWEnabled = true
            }
        } else if photoOutput.isAppleProRAWEnabled {
            photoOutput.isAppleProRAWEnabled = false
        }

        // 实况照片按 12MP、普通照片按当前相机满分辨率。
        if let device = cameraDevice {
            if livePhoto {
                if !photoOutput.isLivePhotoCaptureSupported {
                    session.sessionPreset = .photo
                    if !photoOutput.isLivePhotoCaptureSupported {
                        selectLivePhotoFormat(for: device)
                    }
                }
            }
            let target = livePhoto
                ? standardPhotoDimensions(for: device)
                : maximumPhotoDimensions(for: device)
            if let target,
               device.activeFormat.supportedMaxPhotoDimensions.contains(where: {
                   $0.width == target.width && $0.height == target.height
               }),
               photoOutput.maxPhotoDimensions.width != target.width
                || photoOutput.maxPhotoDimensions.height != target.height {
                photoOutput.maxPhotoDimensions = target
            }
        }

        // 尺寸与 ProRAW 状态就绪后再开实况照片
        if !wantsRaw {
            photoOutput.isLivePhotoCaptureEnabled =
                livePhoto && photoOutput.isLivePhotoCaptureSupported
        }
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored =
                cameraDevice?.position == .front && frontMirrorEnabled
        }
        session.commitConfiguration()
        return photoOutputAttached
    }

    /// 前置是否镜像（与相机页开关同源）
    private var frontMirrorEnabled: Bool {
        UserDefaults.standard.object(forKey: "frontCameraMirrorEnabled") as? Bool ?? true
    }

    /// 把镜像设置写到照片输出连接：前置按开关镜像，后置永远不镜像
    private func applyPhotoMirroring(for device: AVCaptureDevice) {
        guard let connection = photoOutput.connection(with: .video),
              connection.isVideoMirroringSupported
        else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = device.position == .front && frontMirrorEnabled
    }

    /// 用户切换镜像开关后，实时更新到运行中的会话
    func applyFrontMirroring() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let device = self.cameraDevice {
                self.applyPhotoMirroring(for: device)
            }
            self.updatePeakingConnection()
            self.session.commitConfiguration()
        }
    }

    private func captureProcessed(_ configuration: CameraCaptureConfiguration) {
        let settings: AVCapturePhotoSettings
        if configuration.livePhoto {
            settings = AVCapturePhotoSettings()
        } else if configuration.format == .jpeg {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
            )
        } else if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.hevc]
            )
        } else {
            settings = AVCapturePhotoSettings(
                format: [AVVideoCodecKey: AVVideoCodecType.jpeg]
            )
        }
        // 满分辨率时与输出保持一致；12MP 档不指定，交给输出默认值。
        let outputDimensions = photoOutput.maxPhotoDimensions
        if configuration.livePhoto == false,
           Int(outputDimensions.width) * Int(outputDimensions.height) >= 20_000_000 {
            settings.maxPhotoDimensions = outputDimensions
        }
        settings.photoQualityPrioritization = .quality
        applyCommonSettings(settings, configuration: configuration)
        settings.livePhotoMovieFileURL = configuration.livePhoto
            && photoOutput.isLivePhotoCaptureEnabled
            ? temporaryLivePhotoURL()
            : nil
        if settings.livePhotoMovieFileURL != nil {
            if photoOutput.availableLivePhotoVideoCodecTypes.contains(.hevc) {
                settings.livePhotoVideoCodecType = .hevc
            } else if let first = photoOutput.availableLivePhotoVideoCodecTypes.first {
                settings.livePhotoVideoCodecType = first
            }
        }
        startProcessor(settings: settings, configuration: configuration)
    }

    private func captureRaw(
        _ configuration: CameraCaptureConfiguration,
        rawFormat: OSType
    ) {
        let settings = AVCapturePhotoSettings(
            rawPixelFormatType: rawFormat,
            processedFormat: nil
        )
        // 不指定尺寸时 ProRAW 一律按 12MP 输出；必须在每张设置上写明，
        // 系统才会按所选 24MP/48MP 采集（不支持时会回落到可用档位）。
        if let device = cameraDevice,
           let dimensions = rawPhotoDimensions(
               for: configuration.resolution,
               device: device
           ) {
            settings.maxPhotoDimensions = dimensions
        }
        // 高分辨率 ProRAW 依赖高质量优先级；用 .speed 会被静默降级到 12MP。
        settings.photoQualityPrioritization = .quality
        applyCommonSettings(settings, configuration: configuration)
        startProcessor(settings: settings, configuration: configuration)
    }

    private func applyCommonSettings(
        _ settings: AVCapturePhotoSettings,
        configuration: CameraCaptureConfiguration
    ) {
        if photoOutput.supportedFlashModes.contains(configuration.flash.captureMode) {
            settings.flashMode = configuration.flash.captureMode
        }
    }

    private func startProcessor(
        settings: AVCapturePhotoSettings,
        configuration: CameraCaptureConfiguration
    ) {
        let id = settings.uniqueID
        let wantsLocation = UserDefaults.standard
            .object(forKey: "captureLocationEnabled") as? Bool ?? true
        let processor = CameraPhotoCaptureProcessor(
            expectLivePhoto: settings.livePhotoMovieFileURL != nil,
            location: wantsLocation ? CaptureLocationProvider.shared.latestLocation : nil
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.processorLock.lock()
                self.activeProcessors.removeValue(forKey: id)
                self.processorLock.unlock()
                switch result {
                case .success(let output):
                    self.processCapturedOutput(output, configuration: configuration)
                case .failure(let error):
                    self.finishCapture(error: error)
                }
            }
        }
        processorLock.lock()
        activeProcessors[id] = processor
        processorLock.unlock()
        photoOutput.capturePhoto(with: settings, delegate: processor)
    }

    private func processCapturedOutput(
        _ output: CameraCapturedOutput,
        configuration: CameraCaptureConfiguration
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let processed = try await Task.detached(priority: .userInitiated) {
                    try CameraImageProcessor.prepare(
                        output: output,
                        configuration: configuration
                    )
                }.value
                if let thumbnail = CameraImageProcessor.thumbnail(from: processed.data) {
                    latestCaptureThumbnail = UIImage(cgImage: thumbnail)
                }
                let assetIdentifier = try await saveToPhotoLibrary(processed)
                latestCaptureAssetIdentifier = assetIdentifier
                GrainHaptics.mediumImpact(enabled: true)
            } catch {
                errorMessage = error.localizedDescription
            }
            if let liveURL = output.livePhotoURL {
                try? FileManager.default.removeItem(at: liveURL)
            }
            isCapturing = false
        }
    }

    private func saveToPhotoLibrary(_ output: CameraPreparedOutput) async throws -> String? {
        guard await requestPhotoLibraryAddAccess() else {
            throw CameraError.photoLibraryDenied
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(
                (output.fileName as NSString).pathExtension.isEmpty
                    ? "heif"
                    : (output.fileName as NSString).pathExtension
            )
        try output.data.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            return try await commitPhotoLibrarySave(
                output,
                fileURL: tempURL,
                attempt: .fileWithMetadata
            )
        } catch {
            // PhotoKit 对 DNG 的写入器匹配很挑：文件 + 显式 UTI 被拒时，
            // 再让系统按扩展名自行判定，最后用内存数据兜底。
            do {
                return try await commitPhotoLibrarySave(
                    output,
                    fileURL: tempURL,
                    attempt: .fileInferredType
                )
            } catch {
                do {
                    return try await commitPhotoLibrarySave(
                        output,
                        fileURL: tempURL,
                        attempt: .dataWithMetadata
                    )
                } catch {
                    throw Self.mappedSaveError(error)
                }
            }
        }
    }

    /// PHPhotosError 3302 表示资源校验失败（格式不被接受），给出中文说明
    private static func mappedSaveError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == "PHPhotosErrorDomain", nsError.code == 3302 {
            return CameraError.photoLibraryRejectedFormat
        }
        return error
    }

    private func commitPhotoLibrarySave(
        _ output: CameraPreparedOutput,
        fileURL: URL,
        attempt: PhotoSaveAttempt
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            var createdIdentifier: String?
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.location = output.location
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = output.fileName
                options.shouldMoveFile = false
                if attempt != .fileInferredType {
                    options.uniformTypeIdentifier = output.uniformTypeIdentifier
                }
                if attempt == .dataWithMetadata {
                    request.addResource(with: .photo, data: output.data, options: options)
                } else {
                    request.addResource(with: .photo, fileURL: fileURL, options: options)
                }
                createdIdentifier = request.placeholderForCreatedAsset?.localIdentifier

                if let livePhotoURL = output.livePhotoURL {
                    let videoOptions = PHAssetResourceCreationOptions()
                    videoOptions.originalFilename = output.fileName
                        .replacingOccurrences(of: ".heic", with: ".mov")
                        .replacingOccurrences(of: ".heif", with: ".mov")
                        .replacingOccurrences(of: ".png", with: ".mov")
                    request.addResource(
                        with: .pairedVideo,
                        fileURL: livePhotoURL,
                        options: videoOptions
                    )
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: createdIdentifier)
                } else {
                    continuation.resume(
                        throwing: error ?? CameraError.saveFailed
                    )
                }
            }
        }
    }

    private func finishCapture(error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
            self?.isCapturing = false
            self?.countdown = nil
        }
    }

    private func temporaryLivePhotoURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
    }

    private func requestMediaAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) {
                    continuation.resume(returning: $0)
                }
            }
        default:
            return false
        }
    }

    private func requestPhotoLibraryAddAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(
                        returning: status == .authorized || status == .limited
                    )
                }
            }
        default:
            return false
        }
    }
}

private struct CameraCapturedOutput: @unchecked Sendable {
    let data: Data
    let metadata: [String: Any]
    let capturedAt: Date
    let location: CLLocation?
    let livePhotoURL: URL?
}

private struct CameraPreparedOutput: @unchecked Sendable {
    let data: Data
    let fileName: String
    let uniformTypeIdentifier: String
    let location: CLLocation?
    let livePhotoURL: URL?
}

/// PhotoKit 写入方式：DNG 在不同系统版本上可接受的组合不同，按顺序尝试
private enum PhotoSaveAttempt {
    case fileWithMetadata
    case fileInferredType
    case dataWithMetadata
}

private final class CameraPhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    typealias Completion = (Result<CameraCapturedOutput, Error>) -> Void

    private let expectLivePhoto: Bool
    private let location: CLLocation?
    private let completion: Completion
    private var photoData: Data?
    private var photoMetadata: [String: Any] = [:]
    private var capturedAt = Date()
    private var livePhotoURL: URL?
    private var captureError: Error?
    private var captureFinished = false
    private var hasCompleted = false

    init(
        expectLivePhoto: Bool,
        location: CLLocation?,
        completion: @escaping Completion
    ) {
        self.expectLivePhoto = expectLivePhoto
        self.location = location
        self.completion = completion
    }

    /// 快门声音开关：在系统播放快门声之前接管
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        GrainShutterSound.playForCapture()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            captureError = error
        } else {
            photoData = photo.fileDataRepresentation()
            photoMetadata = photo.metadata
            capturedAt = Date()
        }
        finishIfReady()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            captureError = error
        } else {
            livePhotoURL = outputFileURL
        }
        finishIfReady()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            captureError = error
        }
        captureFinished = true
        finishIfReady()
    }

    private func finishIfReady() {
        guard captureFinished, !hasCompleted else { return }
        if let captureError {
            hasCompleted = true
            completion(.failure(captureError))
            return
        }
        guard let photoData else {
            hasCompleted = true
            completion(.failure(CameraError.missingPhotoData))
            return
        }
        if expectLivePhoto, livePhotoURL == nil {
            hasCompleted = true
            completion(.failure(CameraError.livePhotoFailed))
            return
        }
        hasCompleted = true
        completion(.success(CameraCapturedOutput(
            data: photoData,
            metadata: photoMetadata,
            capturedAt: capturedAt,
            location: location,
            livePhotoURL: expectLivePhoto ? livePhotoURL : nil
        )))
    }
}

private enum CameraImageProcessor {
    /// DNG 的标准 UTI；UTType.dng 在部分 SDK 里没有暴露，直接用标识符。
    static let dngTypeIdentifier = "com.adobe.raw-image"

    static func prepare(
        output: CameraCapturedOutput,
        configuration: CameraCaptureConfiguration
    ) throws -> CameraPreparedOutput {
        try autoreleasepool {
            if configuration.format == .raw {
                // 只有真正的 DNG 才能按 RAW 写入相册；否则 PhotoKit 会以
                // “resource invalid” 拒绝整张照片。
                guard isDNG(output.data) else {
                    throw CameraError.rawUnavailable
                }
                return CameraPreparedOutput(
                    data: output.data,
                    fileName: "GRAIN-\(timestamp()).dng",
                    // DNG 的 UTI 是 com.adobe.raw-image（UTType.dng）；
                    // 填成 com.adobe.digital-negative 会让 PhotoKit 找不到
                    // 写入器并以 PHPhotosErrorDomain 3302 拒绝整张照片。
                    uniformTypeIdentifier: dngTypeIdentifier,
                    location: output.location,
                    livePhotoURL: nil
                )
            }

            // 实况照片：直接返回 AVFoundation 原始生成的配对 HEIC/JPEG 图像数据，
            // 完整保留 Apple MakerNote 中的 ContentIdentifier 配对元数据，
            // 避免二次解码/重编码导致 PhotoKit 报 3300/3302 错误。
            if output.livePhotoURL != nil {
                let fileExtension = configuration.format == .jpeg ? "jpg" : "heic"
                let uti = configuration.format == .jpeg ? UTType.jpeg.identifier : UTType.heic.identifier
                return CameraPreparedOutput(
                    data: output.data,
                    fileName: "GRAIN-\(timestamp()).\(fileExtension)",
                    uniformTypeIdentifier: uti,
                    location: output.location,
                    livePhotoURL: output.livePhotoURL
                )
            }

            guard let source = CGImageSourceCreateWithData(
                output.data as CFData,
                nil
            ) else {
                throw CameraError.imageDecodeFailed
            }

            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
            else {
                throw CameraError.imageDecodeFailed
            }

            let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
            let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            let targetPixels = configuration.resolution.targetPixels
            let sourceLongEdge = max(sourceWidth, sourceHeight)

            // 尺寸读不出来时按 12MP 处理，避免把缩略图尺寸当成上限
            let effectiveLongEdge = sourceLongEdge > 0 ? sourceLongEdge : 4032
            if sourceLongEdge > 0, sourceLongEdge < 1000 {
                // 正常 iPhone 镜头不可能只有几百像素，说明拿到了预览流而不是照片
                throw CameraError.photoTooSmall
            }

            // 解码时留出裁切余量，避免整张 48MP 位图常驻内存。
            // WithTransform 让 ImageIO 直接按 EXIF 方向生成正向像素，
            // 不再自己拼旋转矩阵（此前手写矩阵把竖拍图转了 180°）。
            let decodeLimit = min(effectiveLongEdge, (targetPixels * 2).squareRoot().rounded())
            let decodeOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(decodeLimit))
            ]
            guard let decoded = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                decodeOptions as CFDictionary
            ) else {
                throw CameraError.imageDecodeFailed
            }
            if Double(max(decoded.width, decoded.height)) < effectiveLongEdge * 0.5 {
                throw CameraError.photoTooSmall
            }

            // decoded 已按 orientation 转正，裁切与缩放都在正向坐标系里进行
            let sharpening = UserDefaults.standard
                .object(forKey: "cameraSharpening") as? Int ?? 0
            let image = applySharpness(
                to: resized(
                    crop(decoded, to: configuration.aspect.ratio),
                    targetPixels: targetPixels
                ),
                level: sharpening
            )
            let type: UTType = configuration.format == .jpeg ? .jpeg : .heic
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                type.identifier as CFString,
                1,
                nil
            ) else {
                throw CameraError.imageEncodeFailed
            }
            CGImageDestinationAddImage(
                destination,
                image,
                destinationProperties(
                    metadata: output.metadata,
                    width: image.width,
                    height: image.height,
                    capturedAt: output.capturedAt,
                    location: output.location
                ) as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else {
                throw CameraError.imageEncodeFailed
            }

            let fileExtension = configuration.format == .jpeg ? "jpg" : "heic"
            return CameraPreparedOutput(
                data: data as Data,
                fileName: "GRAIN-\(timestamp()).\(fileExtension)",
                uniformTypeIdentifier: type.identifier,
                location: output.location,
                livePhotoURL: output.livePhotoURL
            )
        }
    }

    private static let gradeContext = CIContext(options: [.cacheIntermediates: false])

    /// 按设置调整锐度：正值锐化，负值柔化（用来抵消系统相机偏重的锐化）。
    /// level 为 0 时直接返回原图，不产生任何额外开销。
    /// RAW(DNG) 不做处理，保持原始感光数据。
    private static func applySharpness(to image: CGImage, level: Int) -> CGImage {
        guard level != 0 else { return image }
        let input = CIImage(cgImage: image)
        let extent = input.extent
        guard extent.width > 2, extent.height > 2 else { return image }

        let normalized = CGFloat(level) / 50.0
        let output: CIImage
        if level > 0 {
            output = input.applyingFilter(
                "CISharpenLuminance",
                parameters: [kCIInputSharpnessKey: 0.25 + normalized * 0.85]
            )
        } else {
            // 轻微高斯模糊抵消锐化带来的硬边，比直接降对比更自然
            output = input.applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: -normalized * 1.5]
            )
        }
        let cropped = output.cropped(to: extent)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let rendered = gradeContext.createCGImage(
            cropped,
            from: extent,
            format: .RGBA8,
            colorSpace: space
        ) else {
            return image
        }
        return rendered
    }

    /// 把 AVCapturePhoto 的 EXIF/TIFF/GPS 写入重编码后的 HEIF/PNG。
    /// 同时应用设置里的“位置信息”“机型与镜头参数”开关。
    private static func destinationProperties(
        metadata: [String: Any],
        width: Int,
        height: Int,
        capturedAt: Date,
        location: CLLocation?
    ) -> [String: Any] {
        var properties = metadata
        properties[kCGImageDestinationLossyCompressionQuality as String] = 1.0
        var tiff = stringDictionary(properties[kCGImagePropertyTIFFDictionary as String])
        var exif = stringDictionary(properties[kCGImagePropertyExifDictionary as String])

        let deviceInfoEnabled = UserDefaults.standard
            .object(forKey: "captureDeviceInfoEnabled") as? Bool ?? true
        if !deviceInfoEnabled {
            tiff.removeValue(forKey: kCGImagePropertyTIFFMake as String)
            tiff.removeValue(forKey: kCGImagePropertyTIFFModel as String)
            exif.removeValue(forKey: kCGImagePropertyExifLensMake as String)
            exif.removeValue(forKey: kCGImagePropertyExifLensModel as String)
            exif.removeValue(forKey: "LensSerialNumber")
        }

        // 像素已经按 EXIF 转正，标记方向和尺寸都要同步
        properties[kCGImagePropertyOrientation as String] = 1
        tiff[kCGImagePropertyTIFFOrientation as String] = 1

        exif[kCGImagePropertyExifPixelXDimension as String] = width
        exif[kCGImagePropertyExifPixelYDimension as String] = height
        if exif[kCGImagePropertyExifDateTimeOriginal as String] == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            let stamp = formatter.string(from: capturedAt)
            exif[kCGImagePropertyExifDateTimeOriginal as String] = stamp
            exif[kCGImagePropertyExifDateTimeDigitized as String] = stamp
        }

        let locationEnabled = UserDefaults.standard
            .object(forKey: "captureLocationEnabled") as? Bool ?? true
        if locationEnabled {
            if properties[kCGImagePropertyGPSDictionary as String] == nil,
               let location {
                properties[kCGImagePropertyGPSDictionary as String] =
                    gpsProperties(for: location)
            }
        } else {
            properties.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
        }

        properties[kCGImagePropertyTIFFDictionary as String] = tiff
        properties[kCGImagePropertyExifDictionary as String] = exif
        return properties
    }

    private static func stringDictionary(_ value: Any?) -> [String: Any] {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let dictionary = value as? [CFString: Any] {
            return dictionary.reduce(into: [:]) { result, pair in
                result[pair.key as String] = pair.value
            }
        }
        return [:]
    }

    private static func gpsProperties(for location: CLLocation) -> [String: Any] {
        let coordinate = location.coordinate
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitudeRef as String:
                coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLatitude as String: abs(coordinate.latitude),
            kCGImagePropertyGPSLongitudeRef as String:
                coordinate.longitude >= 0 ? "E" : "W",
            kCGImagePropertyGPSLongitude as String: abs(coordinate.longitude)
        ]
        if location.horizontalAccuracy >= 0 {
            gps[kCGImagePropertyGPSHPositioningError as String] =
                location.horizontalAccuracy
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd"
        gps[kCGImagePropertyGPSDateStamp as String] =
            formatter.string(from: location.timestamp)
        formatter.dateFormat = "HH:mm:ss"
        gps[kCGImagePropertyGPSTimeStamp as String] =
            formatter.string(from: location.timestamp)
        return gps
    }

    /// 缩放到位图的精确像素量；源图更小则保持原样，不做插值放大
    private static func resized(_ image: CGImage, targetPixels: Double) -> CGImage {
        let currentPixels = Double(image.width) * Double(image.height)
        guard currentPixels > targetPixels * 1.02 else { return image }
        let ratio = Double(image.width) / Double(max(image.height, 1))
        let height = (targetPixels / ratio).squareRoot()
        let width = height * ratio
        let targetWidth = max(1, Int(width.rounded()))
        let targetHeight = max(1, Int(height.rounded()))
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage() ?? image
    }

    private static func crop(_ image: CGImage, to ratio: Double) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let currentRatio = width / max(height, 1)
        // 竖直方向的照片自动取倒数，让“4:3”在竖拍时表示 3:4 而不是强行裁成横图
        var targetRatio = CGFloat(ratio)
        if currentRatio < 1, targetRatio > 1 {
            targetRatio = 1 / targetRatio
        } else if currentRatio > 1, targetRatio < 1 {
            targetRatio = 1 / targetRatio
        }
        let cropRect: CGRect
        if currentRatio > targetRatio {
            let targetWidth = height * targetRatio
            cropRect = CGRect(
                x: (width - targetWidth) / 2,
                y: 0,
                width: targetWidth,
                height: height
            )
        } else {
            let targetHeight = width / targetRatio
            cropRect = CGRect(
                x: 0,
                y: (height - targetHeight) / 2,
                width: width,
                height: targetHeight
            )
        }
        return image.cropping(to: cropRect.integral) ?? image
    }

    /// DNG 采用 TIFF 容器：II*\0 或 MM\0*
    private static func isDNG(_ data: Data) -> Bool {
        let header = [UInt8](data.prefix(4))
        return header == [0x49, 0x49, 0x2A, 0x00]
            || header == [0x4D, 0x4D, 0x00, 0x2A]
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    /// 读取最终文件的像素尺寸，用于在提示里回显真实保存结果
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else {
            return nil
        }
        return (width, height)
    }

    static func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 360
            ] as CFDictionary
        )
    }
}

private enum CameraError: LocalizedError {
    case cannotConfigure
    case rawUnavailable
    case missingPhotoData
    case livePhotoFailed
    case photoLibraryDenied
    case imageDecodeFailed
    case imageEncodeFailed
    case saveFailed
    case photoLibraryRejectedFormat
    case photoTooSmall

    var errorDescription: String? {
        switch self {
        case .cannotConfigure:
            "无法配置相机会话，请确认没有其他应用正在占用相机。"
        case .rawUnavailable:
            "当前相机镜头不支持 RAW 输出。"
        case .missingPhotoData:
            "相机没有返回照片数据。"
        case .livePhotoFailed:
            "实况照片视频处理失败，请重试。"
        case .photoLibraryDenied:
            "请在系统设置中允许 GRAIN 向照片图库添加照片。"
        case .imageDecodeFailed:
            "无法读取刚拍摄的照片。"
        case .imageEncodeFailed:
            "无法生成所选照片格式。"
        case .saveFailed:
            "照片保存失败，请检查存储空间。"
        case .photoLibraryRejectedFormat:
            "照片图库拒绝了这张照片的文件格式（PHPhotosError 3302）。如果这是 RAW 照片，请把这条提示发给开发者。"
        case .photoTooSmall:
            "相机返回了异常低的分辨率，请切换镜头或重新打开相机后再试。"
        }
    }
}

/// 从视频流抽帧做边缘检测，输出透明底 + 彩色描边的峰值图。
/// 720p 分辨率 + 30fps 实时刷新，边缘清晰锐利且彻底消除拖影。
final class FocusPeakingProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onMask: ((CGImage?) -> Void)?
    var onHistogram: ((RGBHistogram) -> Void)?
    /// 描边颜色；切换颜色只影响下一帧，不需要重建会话
    var tintColor = CIColor(red: 1.0, green: 0.35, blue: 0.24)

    private let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    private let analysisSize: CGFloat = 720
    private var lastTime: CFAbsoluteTime = 0
    private var lastHistogramTime: CFAbsoluteTime = 0

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 1. 实时直方图计算（每秒约 10 次，低消耗）
        if onHistogram != nil && (now - lastHistogramTime >= 0.09) {
            lastHistogramTime = now
            if let hist = Self.generateHistogram(from: pixelBuffer) {
                onHistogram?(hist)
            }
        }

        guard onMask != nil else { return }

        // 2. 峰值描边（约 30fps，即 0.030s）：高帧率消除描边拖影
        guard now - lastTime >= 0.030 else { return }
        lastTime = now

        var source = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = source.extent
        guard extent.width > 2, extent.height > 2 else { return }

        // 如果底层未物理旋转或输出横幅传感器帧（宽大于高），自动旋转 90 度匹配竖屏取景框
        if extent.width > extent.height {
            source = source.oriented(.right)
        }
        let origin = source.extent.origin
        if origin.x != 0 || origin.y != 0 {
            source = source.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }

        let curExtent = source.extent
        let scale = analysisSize / max(curExtent.width, curExtent.height)
        let resized = source.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        // CIEdges 之类的邻域滤镜可能输出无限范围，必须先钉回有限尺寸
        let outputExtent = CGRect(x: 0, y: 0, width: curExtent.width * scale, height: curExtent.height * scale).integral
        guard outputExtent.width > 2, outputExtent.height > 2 else { return }

        let mono = resized.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.5
        ])
        let edges = mono.applyingFilter("CIEdges", parameters: [
            kCIInputIntensityKey: 2.8
        ]).cropped(to: outputExtent)
        let punched = edges.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 3.0,
            kCIInputBrightnessKey: -0.12
        ]).cropped(to: outputExtent)

        let clear = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: outputExtent)
        let tint = CIImage(color: tintColor).cropped(to: outputExtent)
        let masked = tint.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: punched
        ])
        guard let image = context.createCGImage(masked, from: outputExtent) else {
            return
        }
        onMask?(image)
    }

    /// 从 CVPixelBuffer 高性能提取 RGB 与亮度直方图
    static func generateHistogram(from pixelBuffer: CVPixelBuffer) -> RGBHistogram? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        let binCount = 36
        var redBins = [Double](repeating: 0, count: binCount)
        var greenBins = [Double](repeating: 0, count: binCount)
        var blueBins = [Double](repeating: 0, count: binCount)
        var lumaBins = [Double](repeating: 0, count: binCount)

        let stepX = max(width / 64, 1)
        let stepY = max(height / 48, 1)

        let yPtr = yPlane.assumingMemoryBound(to: UInt8.self)
        let uvPtr = uvPlane.assumingMemoryBound(to: UInt8.self)

        for y in stride(from: 0, to: height, by: stepY) {
            let yRow = yPtr + y * yBytesPerRow
            let uvRow = uvPtr + (y / 2) * uvBytesPerRow
            for x in stride(from: 0, to: width, by: stepX) {
                let yVal = Double(yRow[x])
                let uvIndex = (x / 2) * 2
                let cb = Double(uvRow[uvIndex])
                let cr = Double(uvRow[uvIndex + 1])

                let yNorm = max(0, min(1, (yVal - 16.0) / 219.0))
                let cbNorm = (cb - 128.0) / 224.0
                let crNorm = (cr - 128.0) / 224.0

                let r = max(0, min(1, yNorm + 1.5748 * crNorm))
                let g = max(0, min(1, yNorm - 0.1873 * cbNorm - 0.4681 * crNorm))
                let b = max(0, min(1, yNorm + 1.8556 * cbNorm))

                let rIdx = min(Int(r * Double(binCount - 1)), binCount - 1)
                let gIdx = min(Int(g * Double(binCount - 1)), binCount - 1)
                let bIdx = min(Int(b * Double(binCount - 1)), binCount - 1)
                let lIdx = min(Int(yNorm * Double(binCount - 1)), binCount - 1)

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
}

/// 峰值叠加层：直接写 `CALayer.contents`。
/// 之前把每帧的 CGImage 塞进 @Published，SwiftUI 每秒要重建十几次整个相机页面，
/// 主线程被占满后预览掉帧、描边明显滞后，看起来就是一条拖影。
/// 改成图层直写 + 合并未决帧后，主线程几乎没有额外开销。
final class PeakingOverlaySink {
    private weak var layer: CALayer?
    private var latest: CGImage?
    private var applyScheduled = false
    private let lock = NSLock()

    func attach(_ layer: CALayer) {
        lock.lock()
        self.layer = layer
        let image = latest
        lock.unlock()
        Self.apply(image, to: layer)
    }

    func detach(_ layer: CALayer) {
        lock.lock()
        if self.layer === layer {
            self.layer = nil
        }
        lock.unlock()
    }

    func submit(_ image: CGImage?) {
        lock.lock()
        latest = image
        guard !applyScheduled else {
            lock.unlock()
            return
        }
        applyScheduled = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let image = self.latest
            let layer = self.layer
            self.applyScheduled = false
            self.lock.unlock()
            guard let layer else { return }
            Self.apply(image, to: layer)
        }
    }

    private static func apply(_ image: CGImage?, to layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        CATransaction.commit()
    }
}

/// 自动追焦的主体框：把检测到的主体矩形交给预览层换算成图层坐标后画框。
/// 同样绕开 SwiftUI 刷新，避免频繁重建相机页面。
final class FocusTrackingSink {
    var onUpdate: ((CGRect?) -> Void)?

    private var pending: CGRect?
    private var scheduled = false
    private let lock = NSLock()

    func submit(_ rect: CGRect?) {
        lock.lock()
        pending = rect
        guard !scheduled else {
            lock.unlock()
            return
        }
        scheduled = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let rect = self.pending
            self.scheduled = false
            self.lock.unlock()
            self.onUpdate?(rect)
        }
    }
}

/// 录像结束回调：把结果交回控制器做落盘与格式恢复
final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onFinish: ((URL?, Error?) -> Void)?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        onFinish?(error == nil ? outputFileURL : nil, error)
    }
}

/// 人脸 / 主体检测：只取画面中最大的一张脸，节流后交给追焦逻辑。
final class FocusTrackingProcessor: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var onSubject: ((CGRect?) -> Void)?

    private var lastTime: CFAbsoluteTime = 0

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastTime >= 0.18 else { return }
        lastTime = now

        var best: AVMetadataFaceObject?
        var bestArea: CGFloat = 0
        for object in metadataObjects {
            guard let face = object as? AVMetadataFaceObject else { continue }
            let area = face.bounds.width * face.bounds.height
            if area > bestArea {
                bestArea = area
                best = face
            }
        }
        guard let face = best else {
            onSubject?(nil)
            return
        }
        onSubject?(face.bounds)
    }
}

/// 从静态预览图生成峰值图（编辑页使用）
enum FocusPeakingRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func mask(from image: CGImage) -> CGImage? {
        let source = CIImage(cgImage: image)
        let extent = source.extent
        guard extent.width > 4, extent.height > 4 else { return nil }
        let scale = min(1, 1400 / max(extent.width, extent.height))
        let resized = source.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        // 同样先固定输出范围，避免邻域滤镜的无限 extent 让导出失败
        let outputExtent = resized.extent.integral
        guard outputExtent.width > 4, outputExtent.height > 4 else { return nil }

        let mono = resized.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputContrastKey: 1.4
        ])
        let edges = mono.applyingFilter("CIEdges", parameters: [
            kCIInputIntensityKey: 2.2
        ]).cropped(to: outputExtent)
        let punched = edges.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 2.8,
            kCIInputBrightnessKey: -0.08
        ]).cropped(to: outputExtent)

        let clear = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: outputExtent)
        let white = CIImage(
            color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ).cropped(to: outputExtent)
        let masked = white.applyingFilter("CIBlendWithRedMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: punched
        ])
        return context.createCGImage(masked, from: outputExtent)
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    /// 峰值叠加层的数据源；直接写预览视图的子图层，避免 SwiftUI 每帧重建
    var peakingSink: PeakingOverlaySink?
    /// 自动追焦的主体框数据源
    var trackingSink: FocusTrackingSink?
    /// 追焦把主体中心换算成设备坐标后回传给控制器设置对焦点
    var onTrackingFocus: ((CGPoint) -> Void)?
    var isFreezing: Bool = false
    let onFocus: (_ devicePoint: CGPoint, _ lock: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.attachPeakingSink(peakingSink)
        view.attachTrackingSink(trackingSink)
        view.onTrackingFocus = onTrackingFocus
        if let connection = view.previewLayer.connection {
            connection.applyPortraitOrientationSafely()
            // 前置相机按系统相机习惯做镜像预览
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.focusTapped(_:))
        )
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.focusLocked(_:))
        )
        longPress.minimumPressDuration = 0.48
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        return view
    }

    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: Coordinator) {
        uiView.attachPeakingSink(nil)
        uiView.attachTrackingSink(nil)
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        context.coordinator.parent = self
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        if uiView.attachedSink !== peakingSink {
            uiView.attachPeakingSink(peakingSink)
        }
        if uiView.attachedTrackingSink !== trackingSink {
            uiView.attachTrackingSink(trackingSink)
        }
        uiView.onTrackingFocus = onTrackingFocus
        if let connection = uiView.previewLayer.connection {
            connection.applyPortraitOrientationSafely()
            if connection.isVideoMirroringSupported,
               connection.isVideoMirrored != mirrored {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
        if isFreezing {
            uiView.freezeCurrentPreview()
        } else {
            uiView.unfreezePreview(animated: true)
        }
    }

    final class Coordinator: NSObject {
        var parent: CameraPreviewView

        init(parent: CameraPreviewView) {
            self.parent = parent
        }

        @objc func focusTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? CameraPreviewUIView else { return }
            let screenPoint = gesture.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(
                fromLayerPoint: screenPoint
            )
            view.showFocusReticle(at: screenPoint, locked: false)
            GrainFocusSound.playSonyFocusSound()
            parent.onFocus(devicePoint, false)
        }

        @objc func focusLocked(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let view = gesture.view as? CameraPreviewUIView
            else { return }
            let screenPoint = gesture.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(
                fromLayerPoint: screenPoint
            )
            view.showFocusReticle(at: screenPoint, locked: true)
            GrainFocusSound.playSonyFocusSound()
            parent.onFocus(devicePoint, true)
        }
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    private var latestFocusLayer: CALayer?

    /// 冻结图层：切换拍照与录像模式或重配格式时垫住最后一帧画面，消除底层相机重新握手导致的黑屏闪烁
    private let freezeLayer = CALayer()
    private var previewSnapshotView: UIView?

    /// 峰值描边图层：与预览层同 gravity，天然对齐，不会出现错位重影
    private let peakingLayer = CALayer()
    private(set) var attachedSink: PeakingOverlaySink?

    /// 自动追焦的主体框
    private let trackingLayer = CAShapeLayer()
    private(set) var attachedTrackingSink: FocusTrackingSink?
    var onTrackingFocus: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black

        freezeLayer.contentsGravity = .resizeAspectFill
        freezeLayer.masksToBounds = true
        freezeLayer.opacity = 1.0
        freezeLayer.zPosition = 2
        freezeLayer.isHidden = true
        layer.addSublayer(freezeLayer)

        peakingLayer.contentsGravity = .resizeAspectFill
        peakingLayer.masksToBounds = true
        peakingLayer.opacity = 0.95
        peakingLayer.zPosition = 3
        peakingLayer.magnificationFilter = .linear
        peakingLayer.minificationFilter = .linear
        peakingLayer.allowsEdgeAntialiasing = true
        layer.addSublayer(peakingLayer)

        trackingLayer.strokeColor = UIColor(
            red: 0.85, green: 0.47, blue: 0.31, alpha: 0.95
        ).cgColor
        trackingLayer.fillColor = UIColor.clear.cgColor
        trackingLayer.lineWidth = 1.6
        trackingLayer.lineJoin = .round
        trackingLayer.isHidden = true
        trackingLayer.zPosition = 4
        layer.addSublayer(trackingLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        freezeLayer.frame = bounds
        peakingLayer.frame = bounds
        CATransaction.commit()
    }

    func freezeCurrentPreview() {
        guard bounds.width > 2, bounds.height > 2 else { return }
        previewSnapshotView?.removeFromSuperview()
        if let snap = self.snapshotView(afterScreenUpdates: false) {
            snap.frame = bounds
            snap.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(snap)
            previewSnapshotView = snap
        } else {
            let renderer = UIGraphicsImageRenderer(bounds: bounds)
            let img = renderer.image { _ in
                drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            freezeLayer.contents = img.cgImage
            freezeLayer.opacity = 1.0
            freezeLayer.isHidden = false
            CATransaction.commit()
        }
    }

    func unfreezePreview(animated: Bool = true) {
        if let snap = previewSnapshotView {
            previewSnapshotView = nil
            if animated {
                UIView.animate(withDuration: 0.28, delay: 0.05, options: [.curveEaseOut]) {
                    snap.alpha = 0.0
                } completion: { _ in
                    snap.removeFromSuperview()
                }
            } else {
                snap.removeFromSuperview()
            }
        }
        if !freezeLayer.isHidden {
            if animated {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.28)
                CATransaction.setCompletionBlock { [weak self] in
                    self?.freezeLayer.isHidden = true
                    self?.freezeLayer.contents = nil
                }
                freezeLayer.opacity = 0.0
                CATransaction.commit()
            } else {
                freezeLayer.isHidden = true
                freezeLayer.contents = nil
            }
        }
    }

    func attachPeakingSink(_ sink: PeakingOverlaySink?) {
        guard sink !== attachedSink else { return }
        attachedSink?.detach(peakingLayer)
        attachedSink = sink
        sink?.attach(peakingLayer)
    }

    func attachTrackingSink(_ sink: FocusTrackingSink?) {
        guard sink !== attachedTrackingSink else { return }
        attachedTrackingSink?.onUpdate = nil
        attachedTrackingSink = sink
        sink?.onUpdate = { [weak self] rect in
            self?.updateTracking(rect)
        }
        if sink == nil {
            setTrackingHidden(true)
        }
    }

    private var trackingGeneration = 0

    /// 检测框是元数据坐标系的矩形，用预览层换算成图层坐标，
    /// 再把中心换成设备坐标回传，设置真正的对焦点。
    private func updateTracking(_ rect: CGRect?) {
        // 人脸离开画面时系统不会再回调（空结果不触发 delegate），
        // 所以每收到一帧就刷新代号，超时没有新帧就自动收起框。
        trackingGeneration += 1
        let generation = trackingGeneration

        guard let rect, bounds.width > 1, bounds.height > 1 else {
            setTrackingHidden(true)
            return
        }
        var layerRect = previewLayer.layerRectConverted(fromMetadataOutputRect: rect)
        // 前置预览做了镜像，检测框要跟着翻一次，否则会指到反方向
        if previewLayer.connection?.isVideoMirrored == true {
            layerRect = CGRect(
                x: bounds.width - layerRect.maxX,
                y: layerRect.minY,
                width: layerRect.width,
                height: layerRect.height
            )
        }
        guard layerRect.width > 4, layerRect.height > 4 else {
            setTrackingHidden(true)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackingLayer.frame = layerRect
        trackingLayer.path = CGPath(
            roundedRect: CGRect(origin: .zero, size: layerRect.size),
            cornerWidth: 5,
            cornerHeight: 5,
            transform: nil
        )
        trackingLayer.isHidden = false
        CATransaction.commit()

        let center = CGPoint(x: layerRect.midX, y: layerRect.midY)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: center)
        onTrackingFocus?(devicePoint)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.trackingGeneration == generation else { return }
            self.setTrackingHidden(true)
        }
    }

    private func setTrackingHidden(_ hidden: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackingLayer.isHidden = hidden
        CATransaction.commit()
    }

    func showFocusReticle(at point: CGPoint, locked: Bool) {
        latestFocusLayer?.removeFromSuperlayer()

        let reticle = CALayer()
        let size: CGFloat = locked ? 80 : 72
        reticle.frame = CGRect(
            x: point.x - size / 2,
            y: point.y - size / 2,
            width: size,
            height: size
        )
        reticle.backgroundColor = UIColor.black.withAlphaComponent(0.08).cgColor
        reticle.cornerRadius = 5

        let bracketPath = CGMutablePath()
        let inset: CGFloat = 5
        let arm: CGFloat = 17
        bracketPath.move(to: CGPoint(x: inset, y: inset + arm))
        bracketPath.addLine(to: CGPoint(x: inset, y: inset))
        bracketPath.addLine(to: CGPoint(x: inset + arm, y: inset))
        bracketPath.move(to: CGPoint(x: size - inset - arm, y: inset))
        bracketPath.addLine(to: CGPoint(x: size - inset, y: inset))
        bracketPath.addLine(to: CGPoint(x: size - inset, y: inset + arm))
        bracketPath.move(to: CGPoint(x: size - inset, y: size - inset - arm))
        bracketPath.addLine(to: CGPoint(x: size - inset, y: size - inset))
        bracketPath.addLine(to: CGPoint(x: size - inset - arm, y: size - inset))
        bracketPath.move(to: CGPoint(x: inset + arm, y: size - inset))
        bracketPath.addLine(to: CGPoint(x: inset, y: size - inset))
        bracketPath.addLine(to: CGPoint(x: inset, y: size - inset - arm))

        for (color, width) in [
            (UIColor.black.withAlphaComponent(0.72), CGFloat(4.2)),
            (UIColor(red: 1.0, green: 0.63, blue: 0.20, alpha: 1), CGFloat(2.0))
        ] {
            let bracket = CAShapeLayer()
            bracket.path = bracketPath
            bracket.strokeColor = color.cgColor
            bracket.fillColor = UIColor.clear.cgColor
            bracket.lineWidth = width
            bracket.lineCap = .round
            bracket.lineJoin = .round
            reticle.addSublayer(bracket)
        }

        let label = CATextLayer()
        label.string = locked ? "AE/AF 已锁定" : "AF"
        label.font = UIFont.systemFont(ofSize: 8, weight: .bold)
        label.fontSize = 8
        label.alignmentMode = .center
        label.foregroundColor = UIColor.white.cgColor
        label.backgroundColor = UIColor.black.withAlphaComponent(0.52).cgColor
        label.cornerRadius = 4
        label.contentsScale = UIScreen.main.scale
        label.frame = CGRect(
            x: -4,
            y: size + 3,
            width: size + 8,
            height: 15
        )
        reticle.addSublayer(label)

        let inner = CALayer()
        let crossSize: CGFloat = 8
        inner.frame = CGRect(
            x: (size - crossSize) / 2,
            y: (size - crossSize) / 2,
            width: crossSize,
            height: crossSize
        )
        inner.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        inner.borderWidth = 0.7
        inner.cornerRadius = crossSize / 2
        reticle.addSublayer(inner)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.28
        scale.toValue = 1
        scale.duration = 0.22
        reticle.add(scale, forKey: "focus-in")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.25
        fade.toValue = 1
        fade.duration = 0.16
        reticle.add(fade, forKey: "focus-fade")
        layer.addSublayer(reticle)
        latestFocusLayer = reticle

        guard !locked else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak reticle] in
            guard let reticle, self?.latestFocusLayer === reticle else { return }
            reticle.removeFromSuperlayer()
        }
    }
}

// MARK: - 相机水平仪 (Leveler)

final class CameraLevelerMotion: ObservableObject {
    @Published var rollAngle: Double = 0.0
    @Published var isLevel: Bool = false

    private let motionManager = CMMotionManager()
    private var lastHapticLevel = false

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self, let motion else { return }
            let gx = motion.gravity.x
            let gy = motion.gravity.y
            // 基于重力矢量计算屏幕 2D 倾斜角度：直立时 gx=0, gy=-1 -> angle=0°，杜绝欧拉角在竖拍时的万向节死锁
            let angleDeg = atan2(gx, -gy) * 180.0 / .pi

            // 计算与最近水平/竖直参考位 (0°, 90°, -90°, 180°) 的角度差
            let nearestCardinal = (angleDeg / 90.0).rounded() * 90.0
            let delta = angleDeg - nearestCardinal

            // 水平判定（带防抖迟滞：进入 <= 1.5°，脱出 > 2.2°）
            let level: Bool
            if self.isLevel {
                level = abs(delta) <= 2.2
            } else {
                level = abs(delta) <= 1.5
            }

            self.rollAngle = delta
            if level != self.isLevel {
                self.isLevel = level
                if level && !self.lastHapticLevel {
                    let impact = UIImpactFeedbackGenerator(style: .rigid)
                    impact.prepare()
                    impact.impactOccurred(intensity: 1.0)
                    AudioServicesPlaySystemSound(1520)
                }
                self.lastHapticLevel = level
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

struct CameraLevelerView: View {
    @ObservedObject var motion: CameraLevelerMotion

    var body: some View {
        ZStack {
            // 中心固定参考短线
            HStack(spacing: 52) {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 22, height: 1)
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 22, height: 1)
            }

            // 动态水平线：根据倾斜角旋转
            HStack(spacing: 4) {
                Rectangle()
                    .fill(motion.isLevel ? Color.green : Color.yellow.opacity(0.85))
                    .frame(width: 32, height: motion.isLevel ? 1.6 : 1.2)
                Circle()
                    .fill(motion.isLevel ? Color.green : Color.yellow.opacity(0.85))
                    .frame(width: 3.5, height: 3.5)
                Rectangle()
                    .fill(motion.isLevel ? Color.green : Color.yellow.opacity(0.85))
                    .frame(width: 32, height: motion.isLevel ? 1.6 : 1.2)
            }
            .rotationEffect(.degrees(-motion.rollAngle))
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.88), value: motion.rollAngle)
            .animation(.easeInOut(duration: 0.15), value: motion.isLevel)

            if !motion.isLevel && abs(motion.rollAngle) >= 1.2 {
                Text(String(format: "%+.0f°", motion.rollAngle))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.yellow.opacity(0.85))
                    .offset(y: 18)
            }
        }
        .allowsHitTesting(false)
    }
}

enum ActiveSliderMode: Equatable {
    case none
    case shutter
    case iso
    case whiteBalance
}

struct CustomScrubSlider<Item: Identifiable & Equatable>: View {
    let title: String
    let items: [Item]
    @Binding var selected: Item
    let defaultItem: Item
    let itemTitle: (Item) -> String
    var onClose: (() -> Void)? = nil
    let onSelect: (Item) -> Void

    @State private var dragKnobX: CGFloat? = nil
    @State private var lastHapticIndex: Int? = nil
    @State private var lastTapTime: TimeInterval = 0
    @State private var startLocation: CGPoint = .zero

    private var currentIndex: Int {
        items.firstIndex(of: selected) ?? 0
    }

    var body: some View {
        VStack(spacing: 5) {
            // 顶部信息条：标题、当前数值回显、重置提示、关闭按钮
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(GrainTheme.accent)
                Text(itemTitle(selected))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(GrainTheme.paper)

                Spacer(minLength: 0)

                Text("双击圆点重置自动")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(GrainTheme.paper.opacity(0.45))

                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(GrainTheme.paper.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // 可左右滑动的自定义滑动条
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let knobDiameter: CGFloat = 22
                let inset: CGFloat = knobDiameter / 2
                let usableWidth = max(width - inset * 2, 1)
                let count = max(items.count - 1, 1)

                let progress = CGFloat(currentIndex) / CGFloat(count)
                let currentKnobX = inset + usableWidth * progress
                let knobX = dragKnobX ?? currentKnobX

                ZStack(alignment: .leading) {
                    // 轨道槽底色
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 5)
                        .padding(.horizontal, inset)

                    // 进度高亮色
                    Capsule()
                        .fill(GrainTheme.accent)
                        .frame(width: max(knobX - inset, 0), height: 5)
                        .padding(.leading, inset)

                    // 离散档位刻度点（最左侧为自动挡）
                    HStack(spacing: 0) {
                        ForEach(0..<items.count, id: \.self) { idx in
                            let isAuto = (items[idx] == defaultItem)
                            Circle()
                                .fill(idx <= currentIndex ? GrainTheme.accent : Color.white.opacity(0.35))
                                .frame(width: isAuto ? 4.5 : 2.5, height: isAuto ? 4.5 : 2.5)
                            if idx < items.count - 1 {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, inset)

                    // 可拖动的圆形滑块（双击恢复默认自动设置）
                    Circle()
                        .fill(GrainTheme.paper)
                        .frame(width: knobDiameter, height: knobDiameter)
                        .shadow(color: .black.opacity(0.38), radius: 2.5, y: 1)
                        .overlay {
                            Circle()
                                .stroke(GrainTheme.line, lineWidth: 0.6)
                        }
                        .overlay {
                            Circle()
                                .fill(selected == defaultItem ? GrainTheme.accent : Color.black.opacity(0.7))
                                .frame(width: 6, height: 6)
                        }
                        .offset(x: knobX - inset)
                        .onTapGesture(count: 2) {
                            selected = defaultItem
                            onSelect(defaultItem)
                            dragKnobX = nil
                            GrainHaptics.mediumImpact(enabled: true)
                            AudioServicesPlaySystemSound(1519)
                        }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            if dragKnobX == nil {
                                startLocation = val.startLocation
                            }
                            let clampedX = min(max(val.location.x, inset), width - inset)
                            dragKnobX = clampedX
                            let pct = (clampedX - inset) / usableWidth
                            let idx = Int((pct * CGFloat(count)).rounded())
                            let safeIdx = min(max(idx, 0), items.count - 1)
                            if safeIdx != lastHapticIndex {
                                lastHapticIndex = safeIdx
                                GrainHaptics.selection(enabled: true)
                            }
                            let item = items[safeIdx]
                            if item != selected {
                                selected = item
                                onSelect(item)
                            }
                        }
                        .onEnded { val in
                            dragKnobX = nil
                            lastHapticIndex = nil
                            let dist = hypot(val.location.x - startLocation.x, val.location.y - startLocation.y)
                            if dist < 8 {
                                let now = Date().timeIntervalSince1970
                                if now - lastTapTime < 0.35 {
                                    selected = defaultItem
                                    onSelect(defaultItem)
                                    GrainHaptics.mediumImpact(enabled: true)
                                    AudioServicesPlaySystemSound(1519)
                                    lastTapTime = 0
                                } else {
                                    lastTapTime = now
                                }
                            }
                        }
                )
            }
            .frame(height: 26)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GrainTheme.line, lineWidth: 0.6))
        .padding(.horizontal, 4)
    }
}

private struct TopBarIconButton: View {
    let systemName: String
    var size: CGFloat = 36
    var isActive: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? GrainTheme.accent : GrainTheme.paper)
            .frame(width: size, height: size)
            .background(GrainTheme.surface.opacity(0.85), in: Circle())
            .overlay(
                Circle().stroke(isActive ? GrainTheme.accent.opacity(0.8) : GrainTheme.line, lineWidth: 0.8)
            )
    }
}

private struct BottomIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var activeColor: Color = GrainTheme.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? activeColor.opacity(0.2) : GrainTheme.surface.opacity(0.85))
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? activeColor : GrainTheme.paper)
        }
        .frame(width: 38, height: 38)
        .overlay(
            Circle().stroke(isActive ? activeColor.opacity(0.85) : GrainTheme.line, lineWidth: 0.8)
        )
    }
}

struct CameraView: View {
    /// 点击左下角刚拍的照片时回调相册标识，由外层负责关闭相机并进入编辑
    var onOpenCapture: ((String) -> Void)? = nil
    /// 启动即进入相机时用它退回图库；此时相机是根视图，dismiss 不起作用
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private func leaveCamera() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
    @ObservedObject private var camera: CameraController = CameraController.shared
    @StateObject private var levelerMotion = CameraLevelerMotion()
    @State private var activeSlider: ActiveSliderMode = .none
    @State private var storageWarningAlert = false
    @State private var isFreezingPreview = false
    @AppStorage("showHistogram") private var showHistogram = true
    @State private var lastExposureHapticStep: Int?
    @State private var lastIntensityHapticStep: Int?
    @State private var format: CameraCaptureFormat = .heif
    @State private var crashReport: String? = UserDefaults.standard.string(forKey: "lastCrashReport")
    @State private var showingCrashReportSheet = false
    @State private var resolution: CameraResolution = .standard24
    @State private var aspect: CameraAspect = .portrait3x4
    @State private var timer: CameraTimer = .off
    @State private var flash: CameraFlashSetting = .off
    @State private var livePhoto = false
    @State private var showGrid = true
    @State private var zoomGestureBase: CGFloat?
    @AppStorage("filmOrder") private var filmOrder = ""
    @AppStorage("frontCameraMirrorEnabled") private var mirrorFront = true
    @AppStorage("focusPeakingColor") private var peakingColorRaw = "red"
    @AppStorage("faceTrackingEnabled") private var faceTrackingEnabled = true
    @State private var cameraProfile: FilmProfile = .neutral
    @State private var cameraIntensity = 1.0
    @State private var didSwipeBack = false
    @State private var showCameraFilters = false
    @State private var isPreparingLivePhoto = false
    @State private var captureMode: CameraMode = .photo
    @State private var videoQuality: VideoQuality = .uhd4k30
    @AppStorage("cameraVideoQuality") private var storedVideoQuality = VideoQuality.uhd4k30.rawValue
    @State private var stabilization: VideoStabilization = .standard
    @AppStorage("cameraVideoStabilization") private var storedStabilization = VideoStabilization.standard.rawValue
    @State private var videoCodec: VideoCodecPreference = .hevc
    @AppStorage("cameraVideoCodec") private var storedVideoCodec = VideoCodecPreference.hevc.rawValue
    @State private var videoContainer: VideoContainerPreference = .mov
    @AppStorage("cameraVideoContainer") private var storedVideoContainer = VideoContainerPreference.mov.rawValue
    /// 录像补光：录像用的是常亮手电筒
    @State private var torchOn = false

    private let zoomOptions: [CGFloat] = [0.5, 1, 2, 4, 8]

    @State private var videoAspect: VideoAspect = .sixteenByNine
    @AppStorage("cameraVideoAspect") private var storedVideoAspect = VideoAspect.sixteenByNine.rawValue
    @State private var manualShutter: ManualShutterOption = .auto
    @State private var manualISO: ManualISOOption = .auto
    @State private var videoWhiteBalance: VideoWhiteBalanceMode = .auto
    @State private var videoColorSpace: VideoColorSpacePreference = .rec709
    @AppStorage("cameraVideoColorSpace") private var storedVideoColorSpace = VideoColorSpacePreference.rec709.rawValue

    private var effectiveAspectRatio: CGFloat {
        captureMode == .video ? videoAspect.portraitRatio : aspect.ratio
    }

    init(
        onClose: (() -> Void)? = nil,
        onOpenCapture: ((String) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onOpenCapture = onOpenCapture
    }

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar

                GeometryReader { proxy in
                    // 取景区域按所选比例裁成一块，其余留黑：
                    // 这样才能做到“看到什么就拍到什么”，而不是始终铺满屏幕。
                    let rect = fittedFrame(for: effectiveAspectRatio, in: proxy.size)
                    ZStack {
                        GrainTheme.black

                        CameraPreviewView(
                            session: camera.session,
                            mirrored: camera.isUsingFrontCamera && mirrorFront,
                            peakingSink: camera.peakingOverlay,
                            trackingSink: camera.trackingSink,
                            onTrackingFocus: { devicePoint in
                                camera.applyTrackingFocus(devicePoint)
                            },
                            isFreezing: isFreezingPreview,
                            onFocus: { devicePoint, lock in
                                camera.focus(at: devicePoint, lock: lock)
                                GrainHaptics.mediumImpact(enabled: true)
                            }
                        )
                        .frame(width: rect.width, height: rect.height)
                        .clipped()
                        .position(x: rect.midX, y: rect.midY)

                        cameraLookOverlay
                        framingOverlay

                        // 拍照与视频界面常驻电子水平仪
                        CameraLevelerView(motion: levelerMotion)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)

                        // 视频模式：右上角展示剩余空间、可拍摄时间与实时麦克风 VU 跳动条
                        if captureMode == .video {
                            VStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    VideoViewfinderInfoOverlay(
                                        freeStorageText: camera.freeStorageString,
                                        remainingTimeText: camera.remainingTimeString(for: videoQuality),
                                        audioLevel: camera.liveAudioLevel,
                                        isRecording: camera.isRecording,
                                        isLowStorage: camera.freeStorageBytes > 0 && camera.freeStorageBytes < CameraController.minimumStorageForRecording
                                    )
                                    .padding(.top, 8)
                                    .padding(.trailing, 8)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                        }

                        // 实时直方图：视频拍摄页面常驻，或由设置开启
                        if (captureMode == .video || showHistogram), let hist = camera.liveHistogram {
                            HistogramView(data: hist)
                                .frame(width: 82, height: 42)
                                .padding(8)
                                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)
                        }

                        // 曝光条：取景框右侧，避开右下角 A/M 与底部倍率条
                        exposureBar
                            .frame(width: 30, height: rect.height * 0.52)
                            .padding(.trailing, 8)
                            .padding(.bottom, 22)
                            .frame(width: rect.width, height: rect.height, alignment: .trailing)
                            .position(x: rect.midX, y: rect.midY)

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                exposureModeButton
                            }
                        }
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            zoomBar
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(pinchToZoomGesture)
                    .animation(.easeInOut(duration: 0.24), value: effectiveAspectRatio)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GrainTheme.black)
                .clipped()

                cameraControls
            }
            .ignoresSafeArea(.container, edges: .bottom)

            if let countdown = camera.countdown {
                Text("\(countdown)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 160, height: 160)
                    .background(GrainTheme.surface.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
                    .transition(.scale.combined(with: .opacity))
            }

            if camera.isRecording {
                VStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(recordingTimeText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(GrainTheme.paper)
                        Text(videoQuality.title)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper.opacity(0.72))
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(GrainTheme.surface.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                    .padding(.top, 62)
                    Spacer()
                }
            }

            if let recordingError = camera.recordingError {
                VStack {
                    Text(recordingError)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(GrainTheme.surface.opacity(0.85), in: Capsule())
                        .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                        .padding(.top, 104)
                    Spacer()
                }
            }

            if let report = crashReport, !report.isEmpty {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 11))
                        Text("检测到上次异常日志")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                        Spacer()
                        Button("查看") {
                            showingCrashReportSheet = true
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(GrainTheme.accent)

                        Button {
                            UserDefaults.standard.removeObject(forKey: "lastCrashReport")
                            crashReport = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(GrainTheme.paper.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(GrainTheme.surface.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.8))
                    .padding(.top, 56)
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .sheet(isPresented: $showingCrashReportSheet) {
                    NavigationStack {
                        ScrollView {
                            Text(report)
                                .font(.system(size: 10, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .navigationTitle("异常日志")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showingCrashReportSheet = false }
                            }
                            ToolbarItem(placement: .destructiveAction) {
                                Button("清除") {
                                    UserDefaults.standard.removeObject(forKey: "lastCrashReport")
                                    crashReport = nil
                                    showingCrashReportSheet = false
                                }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button("复制") {
                                    UIPasteboard.general.string = report
                                    GrainHaptics.lightImpact(enabled: true)
                                }
                            }
                        }
                    }
                }
            }

            if !camera.isReady,
               camera.errorMessage == nil {
                ProgressView()
                    .tint(GrainTheme.paper)
                    .padding(16)
                    .background(GrainTheme.surface.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
            }

            if let error = camera.errorMessage {
                VStack(spacing: 12) {
                    Text(camera.isReady ? "相机出错" : "相机无法启动")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                    Text(error)
                        .font(.system(size: 10, design: .rounded))
                        .multilineTextAlignment(.center)
                    Button("关闭") { leaveCamera() }
                        .foregroundStyle(GrainTheme.black)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(GrainTheme.paper, in: Capsule())
                }
                .foregroundStyle(GrainTheme.paper)
                .padding(22)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                .padding(28)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .task {
            await camera.start()
        }
        .onDisappear {
            camera.stop()
            camera.stopAudioAndStorageMonitoring()
        }
        .onChange(of: format) { _, newValue in
            if newValue == .raw {
                livePhoto = false
                // 只有真正开启过实况照片时才需要重配会话，
                // 否则会在切换 RAW 时触发多余的会话配置。
                if camera.isLivePhotoArmed {
                    Task {
                        _ = await camera.setLivePhotoEnabled(false)
                    }
                }
            }
        }
        .onChange(of: cameraProfile) { _, _ in
            if cameraProfile == .neutral {
                cameraIntensity = 1
            }
        }
        .onChange(of: resolution) { _, value in
            camera.setPhotoResolution(value)
        }
        .onChange(of: mirrorFront) { _, value in
            UserDefaults.standard.set(value, forKey: "frontCameraMirrorEnabled")
            camera.applyFrontMirroring()
        }
        .onAppear {
            levelerMotion.start()
            camera.setPeakingColor(FocusPeakingColor.resolved(peakingColorRaw))
            camera.setFaceTracking(faceTrackingEnabled)
            videoQuality = VideoQuality(rawValue: storedVideoQuality) ?? .uhd4k30
            stabilization = VideoStabilization(rawValue: storedStabilization) ?? .standard
            videoCodec = VideoCodecPreference(rawValue: storedVideoCodec) ?? .hevc
            videoContainer = VideoContainerPreference(rawValue: storedVideoContainer) ?? .mov
            videoAspect = VideoAspect(rawValue: storedVideoAspect) ?? .sixteenByNine
            videoColorSpace = VideoColorSpacePreference(rawValue: storedVideoColorSpace) ?? .rec709
            if captureMode == .video {
                camera.prepareForVideoMode(
                    quality: videoQuality,
                    stabilization: stabilization,
                    codec: videoCodec,
                    colorSpace: videoColorSpace
                )
                camera.startAudioAndStorageMonitoring()
            }
        }
        .onDisappear {
            levelerMotion.stop()
        }
        .onChange(of: captureMode) { _, mode in
            isFreezingPreview = true
            activeSlider = .none
            // 录像模式提前预热音视频输出与专属 16:9 格式，解决开录时屏幕闪烁两下的问题
            if mode == .video {
                if livePhoto {
                    livePhoto = false
                }
                camera.prepareForVideoMode(
                    quality: videoQuality,
                    stabilization: stabilization,
                    codec: videoCodec,
                    colorSpace: videoColorSpace
                )
                camera.startAudioAndStorageMonitoring()
            } else {
                if torchOn {
                    torchOn = false
                    camera.setTorch(false)
                }
                camera.stopAudioAndStorageMonitoring()
                camera.restorePhotoFormat(resolution: resolution)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                isFreezingPreview = false
            }
        }
        .onChange(of: peakingColorRaw) { _, value in
            camera.setPeakingColor(FocusPeakingColor.resolved(value))
        }
        .onChange(of: faceTrackingEnabled) { _, value in
            camera.setFaceTracking(value)
        }
        .onChange(of: camera.isTorchOn) { _, value in
            // 设备不支持或点失败时，UI 跟着回到关闭状态
            torchOn = value
        }
        .onChange(of: camera.isReady) { _, ready in
            if ready {
                camera.setPhotoResolution(resolution)
            }
        }
        .onChange(of: camera.selectedZoom) { _, _ in
            // 保留用户设定的 48MP 分辨率，允许在 2×、4×、8× 变焦下正常使用
        }
        .alert("存储空间不足 10GB", isPresented: $storageWarningAlert) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("当前设备剩余可用空间少于 10GB，为防止内存过爆已禁止开始录像。请清理手机存储空间。")
        }
        .simultaneousGesture(edgeSwipeBackGesture)
    }

    /// 后置相机支持高分辨率时允许开启 48MP（覆盖 1×、2×、4×、8× 全倍率）
    private var is48MPAvailable: Bool {
        !camera.isUsingFrontCamera && (camera.maxPhotoDimensions.width * camera.maxPhotoDimensions.height >= 20_000_000 || camera.isRawSupported)
    }

    private var recordingTimeText: String {
        let minutes = camera.recordingSeconds / 60
        let seconds = camera.recordingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 追焦开启且没有被手动对焦接管时高亮
    private var trackingActive: Bool {
        camera.focusTrackingEnabled && !camera.isManualFocusActive
    }

    // MARK: - 取景框内的常驻控制

    /// 竖直曝光补偿条：取景框右侧，滑块与轨道严格对齐，双击小白点回到 0 EV
    private var exposureBar: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let knobSize: CGFloat = 19
            let inset: CGFloat = knobSize / 2
            let usable = max(height - inset * 2, 1)
            let lower = Double(camera.minimumExposureBias)
            let upper = Double(camera.maximumExposureBias)
            let span = max(upper - lower, 0.001)
            let progress = min(
                max((Double(camera.exposureBias) - lower) / span, 0),
                1
            )
            let knobY = inset + usable * (1 - CGFloat(progress))
            let fill = max(height - inset - knobY, 0)

            ZStack {
                // 轨道背景：精确贴合可用范围，最下方不会出现未使用的灰条
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 4.5, height: usable)
                    .position(x: proxy.size.width / 2, y: inset + usable / 2)

                Capsule()
                    .fill(camera.exposureManual ? GrainTheme.accent : Color.white.opacity(0.72))
                    .frame(width: 4.5, height: fill)
                    .position(x: proxy.size.width / 2, y: height - inset - fill / 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .position(x: proxy.size.width / 2, y: knobY)

                if camera.exposureBias != 0 {
                    Text(String(format: "%+.1f", camera.exposureBias))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .frame(height: 15)
                        .background(Color.black.opacity(0.65), in: Capsule())
                        .position(
                            x: proxy.size.width / 2,
                            y: min(max(knobY - 20, 10), height - 10)
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let position = min(max(value.location.y - inset, 0), usable)
                        let ratio = 1 - Double(position / usable)
                        let targetBias = Float(lower + ratio * span)
                        let newStep = Int((targetBias * 10).rounded())
                        if newStep != lastExposureHapticStep {
                            lastExposureHapticStep = newStep
                            if newStep == 0 {
                                GrainHaptics.mediumImpact()
                            } else {
                                GrainHaptics.selection()
                            }
                        }
                        // 默认 A 档，一拖就切到 M 档（右下角开关同步变 M）
                        camera.setExposureBias(targetBias, fromUser: true)
                    }
                    .onEnded { _ in
                        camera.relockExposure()
                        GrainHaptics.selection()
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2, coordinateSpace: .local)
                    .onEnded { gesture in
                        guard abs(gesture.location.y - knobY) <= 22 else { return }
                        camera.setExposureBias(0)
                        camera.relockExposure()
                        GrainHaptics.mediumImpact()
                    }
            )
        }
    }

    /// 自动 / 手动曝光开关，常驻取景框右下角。
    /// 默认 A 档；动过曝光条会自动变 M，再点一下回到 A 档（补偿归零）。
    private var exposureModeButton: some View {
        Button {
            camera.setExposureManual(!camera.exposureManual)
            GrainHaptics.selection(enabled: true)
        } label: {
            Text(camera.exposureManual ? "M" : "A")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(camera.exposureManual ? GrainTheme.black : GrainTheme.paper)
                .frame(width: 28, height: 28)
                .background(
                    camera.exposureManual ? GrainTheme.accent : GrainTheme.surface.opacity(0.85),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(GrainTheme.line, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            camera.exposureManual ? "手动曝光，点按回到自动" : "自动曝光，点按锁定"
        )
    }

    /// 倍率条：常驻取景框最下方，倍率居中、人脸追焦开关在左侧
    private var zoomBar: some View {
        ZStack {
            HStack(spacing: 4) {
                ForEach(zoomOptions, id: \.self) { zoom in
                    Button {
                        camera.setZoom(zoom)
                    } label: {
                        Text(zoomLabel(zoom))
                            .font(.system(size: zoom == camera.selectedZoom ? 10.5 : 9, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                zoom == camera.selectedZoom ? GrainTheme.black : GrainTheme.paper
                            )
                            .frame(width: zoom == camera.selectedZoom ? 34 : 28, height: 28)
                            .background(
                                zoom == camera.selectedZoom
                                    ? GrainTheme.paper
                                    : GrainTheme.surface.opacity(0.85),
                                in: Circle()
                            )
                            .overlay(
                                Circle().stroke(GrainTheme.line, lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        (zoom < camera.minimumZoom
                            && !(zoom == 0.5 && !camera.isUsingFrontCamera))
                        || zoom > camera.maximumZoom
                    )
                }
            }

            HStack {
                Button {
                    GrainHaptics.selection(enabled: true)
                    if camera.isManualFocusActive {
                        camera.resumeAutoFocus()
                    } else {
                        camera.setFocusTracking(!camera.focusTrackingEnabled)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(
                            systemName: camera.isManualFocusActive
                                ? "hand.tap"
                                : "person.crop.rectangle"
                        )
                            .font(.system(size: 9.5, weight: .semibold))
                        if captureMode != .video {
                            Text(camera.isManualFocusActive ? "手动" : "追焦")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        }
                    }
                    .foregroundStyle(trackingActive ? GrainTheme.black : GrainTheme.paper)
                    .padding(.horizontal, captureMode == .video ? 7 : 8)
                    .frame(height: 26)
                    .background(
                        trackingActive ? GrainTheme.accent : GrainTheme.surface.opacity(0.85),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(GrainTheme.line, lineWidth: 0.6)
                    )
                    .opacity(
                        camera.focusTrackingEnabled || camera.isManualFocusActive
                            ? 1 : 0.5
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    camera.isManualFocusActive
                        ? "恢复自动追焦"
                        : (camera.focusTrackingEnabled ? "关闭自动追焦" : "开启自动追焦")
                )
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 6)
    }

    /// 录像时拍照专用的按钮（实况、倒计时）收起来，位置空出来所以整体放大
    private var topButtonSize: CGFloat { captureMode == .video ? 40 : 38 }

    private var topBar: some View {
        let size = topButtonSize
        return HStack(spacing: 8) {
            Button {
                closeCamera()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: size, height: size)
                    .background(GrainTheme.surface.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            if captureMode == .video {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // 1. 规格：分辨率与帧率（按规则显示：数字数字、4K大写、帧率如 60fps 小写）
                        Menu {
                            ForEach(VideoQuality.allCases) { option in
                                Button {
                                    videoQuality = option
                                    storedVideoQuality = option.rawValue
                                    camera.prepareForVideoMode(
                                        quality: option,
                                        stabilization: stabilization,
                                        codec: videoCodec,
                                        colorSpace: videoColorSpace
                                    )
                                    GrainHaptics.selection(enabled: true)
                                } label: {
                                    HStack {
                                        Text(option.title)
                                        if videoQuality == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(videoQuality.title)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(GrainTheme.paper)
                                .padding(.horizontal, 10)
                                .frame(height: size)
                                .background(GrainTheme.surface.opacity(0.85), in: Capsule())
                                .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                        }
                        .disabled(camera.isRecording)

                        // 2. 画面比例 (4:3, 16:9, 2:1, 2.35:1) - 纯图标
                        Menu {
                            ForEach(VideoAspect.allCases) { aspect in
                                Button {
                                    videoAspect = aspect
                                    storedVideoAspect = aspect.rawValue
                                    GrainHaptics.selection(enabled: true)
                                } label: {
                                    HStack {
                                        Text(aspect.title)
                                        if videoAspect == aspect {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            TopBarIconButton(systemName: "aspectratio", size: size)
                        }
                        .disabled(camera.isRecording)

                        // 3. 色彩空间 (Rec.709, Display P3, Apple Log / HDR) - 纯图标
                        Menu {
                            ForEach(VideoColorSpacePreference.allCases) { pref in
                                Button {
                                    videoColorSpace = pref
                                    storedVideoColorSpace = pref.rawValue
                                    camera.applyColorSpace(pref)
                                    GrainHaptics.selection(enabled: true)
                                } label: {
                                    HStack {
                                        Text(pref.title)
                                        if videoColorSpace == pref {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            TopBarIconButton(systemName: "paintpalette.fill", size: size)
                        }
                        .disabled(camera.isRecording)

                        // 4. 编码格式 (HEVC / H.264) - 纯图标，已移除封装格式选项
                        Menu {
                            ForEach(availableVideoCodecOptions) { codec in
                                Button {
                                    videoCodec = codec
                                    storedVideoCodec = codec.rawValue
                                    camera.prepareForVideoMode(
                                        quality: videoQuality,
                                        stabilization: stabilization,
                                        codec: codec,
                                        colorSpace: videoColorSpace
                                    )
                                } label: {
                                    HStack {
                                        Text(codec.title == "HEVC" ? "HEVC (高效)" : "H.264 (兼容)")
                                        if videoCodec == codec {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            TopBarIconButton(systemName: "film.fill", size: size)
                        }
                        .disabled(camera.isRecording)
                    }
                }
            } else {
                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showCameraFilters.toggle()
                    }
                } label: {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            showCameraFilters ? GrainTheme.accent : GrainTheme.muted
                        )
                        .frame(width: size, height: size)
                        .background(GrainTheme.surface.opacity(0.85), in: Circle())
                        .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }

            lightButton(size: size)

            if camera.isUsingFrontCamera {
                Button {
                    mirrorFront.toggle()
                    GrainHaptics.selection(enabled: true)
                } label: {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            mirrorFront ? GrainTheme.accent : GrainTheme.paper.opacity(0.55)
                        )
                        .frame(width: size, height: size)
                        .background(GrainTheme.surface.opacity(0.85), in: Circle())
                        .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mirrorFront ? "关闭自拍镜像" : "开启自拍镜像")
            }

            if captureMode == .photo {
                Button {
                    guard !isPreparingLivePhoto else { return }
                    isPreparingLivePhoto = true
                    Task {
                        // 实况照片不支持 RAW，若当前处于 RAW 则自动切至 HEIF
                        if format == .raw {
                            format = .heif
                        }
                        let enabled = await camera.setLivePhotoEnabled(!livePhoto)
                        livePhoto = enabled
                        isPreparingLivePhoto = false
                        if enabled {
                            GrainHaptics.lightImpact(enabled: true)
                        }
                    }
                } label: {
                    Group {
                        if isPreparingLivePhoto {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: livePhoto ? "livephoto" : "livephoto.slash")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundStyle(
                        livePhoto ? GrainTheme.accent : GrainTheme.paper.opacity(0.62)
                    )
                    .frame(width: size, height: size)
                    .background(GrainTheme.surface.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .disabled(!camera.isLivePhotoSupported || isPreparingLivePhoto)
            }

            Button {
                showGrid.toggle()
                GrainHaptics.selection(enabled: true)
            } label: {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        showGrid ? GrainTheme.accent : GrainTheme.paper.opacity(0.62)
                    )
                    .frame(width: size, height: size)
                    .background(GrainTheme.surface.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            if captureMode == .photo {
                Menu {
                    ForEach(CameraTimer.allCases) { option in
                        Button(option.title) { timer = option }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "timer")
                            .font(.system(size: 14, weight: .semibold))
                        if timer != .off {
                            Text("\(timer.seconds)")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundStyle(
                        timer == .off ? GrainTheme.paper.opacity(0.62) : GrainTheme.accent
                    )
                    .frame(width: size, height: size)
                    .background(GrainTheme.surface.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    /// 拍照是闪光灯（关/自动/开），录像是常亮补光灯（手电筒）
    private func lightButton(size: CGFloat) -> some View {
        Button {
            if captureMode == .video {
                torchOn.toggle()
                camera.setTorch(torchOn)
            } else if let index = CameraFlashSetting.allCases.firstIndex(of: flash) {
                flash = CameraFlashSetting.allCases[
                    (index + 1) % CameraFlashSetting.allCases.count
                ]
            }
            GrainHaptics.selection(enabled: true)
        } label: {
            Image(systemName: lightSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(lightActive ? GrainTheme.accent : GrainTheme.paper.opacity(0.55))
                .frame(width: size, height: size)
                .background(GrainTheme.surface.opacity(0.85), in: Circle())
                .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            captureMode == .video
                ? (torchOn ? "关闭录像补光" : "开启录像补光")
                : flash.title
        )
    }

    private var lightSymbol: String {
        if captureMode == .video {
            return torchOn ? "flashlight.on.fill" : "flashlight.off.fill"
        }
        return flash.symbol
    }

    private var lightActive: Bool {
        captureMode == .video ? torchOn : flash != .off
    }

    private var cameraControls: some View {
        VStack(spacing: 6) {
            if showCameraFilters {
                cameraFilterTray
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 视频模式下展开的左右滑动调整条（快门 / ISO / 白平衡）
            if captureMode == .video && activeSlider != .none {
                sliderControlRow
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 曝光已改为取景框右侧的常驻竖条，这里不再重复一行
            optionRow

            if let hint = camera.peakingHint {
                Text(hint)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(GrainTheme.paper, in: Capsule())
                    .transition(.opacity)
            }

            captureRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(GrainTheme.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(GrainTheme.line, lineWidth: 0.8)
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var sliderControlRow: some View {
        switch activeSlider {
        case .shutter:
            CustomScrubSlider(
                title: "快门速度",
                items: ManualShutterOption.allCases,
                selected: $manualShutter,
                defaultItem: .auto,
                itemTitle: { $0.title },
                onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeSlider = .none
                    }
                }
            ) { option in
                camera.applyManualExposure(shutter: option, iso: manualISO)
            }
        case .iso:
            CustomScrubSlider(
                title: "ISO 感光度",
                items: ManualISOOption.allCases,
                selected: $manualISO,
                defaultItem: .auto,
                itemTitle: { $0.title },
                onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeSlider = .none
                    }
                }
            ) { option in
                camera.applyManualExposure(shutter: manualShutter, iso: option)
            }
        case .whiteBalance:
            CustomScrubSlider(
                title: "白平衡",
                items: VideoWhiteBalanceMode.allCases,
                selected: $videoWhiteBalance,
                defaultItem: .auto,
                itemTitle: { $0.title },
                onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeSlider = .none
                    }
                }
            ) { mode in
                camera.applyWhiteBalance(mode)
            }
        case .none:
            EmptyView()
        }
    }

    /// 参数行：录像只保留与录像相关的项，纯图标显示，点击快门/ISO/白平衡展开滑动条
    private var optionRow: some View {
        Group {
            if captureMode == .video {
                HStack(spacing: 14) {
                    Spacer(minLength: 0)

                    // 1. 快门速度 - 纯图标，点开展开左右滑动条
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeSlider = (activeSlider == .shutter ? .none : .shutter)
                        }
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        BottomIconButton(
                            systemName: "speedometer",
                            isActive: activeSlider == .shutter || manualShutter != .auto
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.isRecording)

                    // 2. ISO 感光度 - 纯图标，点开展开左右滑动条
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeSlider = (activeSlider == .iso ? .none : .iso)
                        }
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        BottomIconButton(
                            systemName: "camera.aperture",
                            isActive: activeSlider == .iso || manualISO != .auto
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.isRecording)

                    // 3. 白平衡 - 纯图标，点开展开左右滑动条
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeSlider = (activeSlider == .whiteBalance ? .none : .whiteBalance)
                        }
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        BottomIconButton(
                            systemName: "sun.max.fill",
                            isActive: activeSlider == .whiteBalance || videoWhiteBalance != .auto
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.isRecording)

                    // 4. 防抖 (增强, 电影级, 标准, 关) - 纯图标
                    Menu {
                        ForEach(VideoStabilization.allCases) { option in
                            Button {
                                stabilization = option
                                storedStabilization = option.rawValue
                                camera.setVideoStabilization(option, quality: videoQuality)
                            } label: {
                                HStack {
                                    Text(option.title)
                                    if stabilization == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        BottomIconButton(
                            systemName: "hand.raised.fill",
                            isActive: stabilization != .off
                        )
                    }
                    .disabled(camera.isRecording)

                    // 5. 峰值对焦 - 纯图标
                    Button {
                        camera.setFocusPeaking(!camera.isFocusPeakingEnabled)
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        BottomIconButton(
                            systemName: "dot.scope",
                            isActive: camera.isFocusPeakingEnabled
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.isRecording)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 38)
            } else {
                HStack(spacing: 6) {
                    ForEach(CameraResolution.allCases) { option in
                        Button(option.title) {
                            resolution = option
                        }
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(resolution == option ? GrainTheme.black : GrainTheme.paper)
                        .frame(width: 48, height: 30)
                        .background(
                            resolution == option ? GrainTheme.paper : GrainTheme.raised,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(GrainTheme.line, lineWidth: 0.6)
                        )
                        .opacity(
                            livePhoto
                                ? 0.38
                                : (is48MPAvailable || option != .high48 ? 1 : 0.42)
                        )
                        .disabled(livePhoto || (!is48MPAvailable && option == .high48))
                        .buttonStyle(.plain)
                    }

                    // 实况照片固定 12MP（系统限制），明确标出来避免误以为设置未生效
                    if livePhoto {
                        Text("实况 12MP")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(GrainTheme.black)
                            .padding(.horizontal, 5)
                            .frame(height: 24)
                            .background(GrainTheme.accent, in: Capsule())
                    }

                    Menu {
                        ForEach(CameraAspect.allCases) { option in
                            Button(option.title) { aspect = option }
                        }
                    } label: {
                        MenuChip(title: aspect.title, symbol: "rectangle.ratio.4.to.3")
                    }

                    Menu {
                        ForEach(CameraCaptureFormat.allCases) { option in
                            Button(option.title) { format = option }
                        }
                    } label: {
                        MenuChip(title: format.title, symbol: "doc")
                    }

                    peakingButton
                }
            }
        }
    }

    private var peakingButton: some View {
        Button {
            camera.setFocusPeaking(!camera.isFocusPeakingEnabled)
            GrainHaptics.selection(enabled: true)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 10, weight: .semibold))
                Text("峰值")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(
                camera.isFocusPeakingEnabled ? GrainTheme.black : GrainTheme.paper
            )
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                camera.isFocusPeakingEnabled
                    ? GrainTheme.accent
                    : GrainTheme.raised,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(GrainTheme.line, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            camera.isFocusPeakingEnabled ? "关闭峰值对焦" : "开启峰值对焦"
        )
    }

    /// 只列出这台设备真的支持的编码
    private var availableVideoCodecOptions: [VideoCodecPreference] {
        let available = camera.availableVideoCodecs
        guard !available.isEmpty else { return VideoCodecPreference.allCases }
        let filtered = VideoCodecPreference.allCases.filter {
            available.contains($0.codecType)
        }
        return filtered.isEmpty ? VideoCodecPreference.allCases : filtered
    }

    // MARK: - 快门行

    private let shutterOuter: CGFloat = 70
    private let shutterInner: CGFloat = 54
    private let sideButton: CGFloat = 46
    /// 快门两侧随行按钮的水平偏移：贴着快门，不会被左右两端的按钮压住
    private var shutterSideOffset: CGFloat {
        shutterOuter / 2 + 14 + sideButton / 2
    }

    /// 快门严格居中；录像切换 / 暂停 / 抓拍都挂在快门旁边随它一起移动
    private var captureRow: some View {
        ZStack(alignment: .center) {
            HStack(spacing: 0) {
                latestCaptureButton
                Spacer(minLength: 0)
                flipCameraButton
            }

            shutterButton

            if camera.isRecording {
                stillCaptureButton
                    .offset(x: shutterSideOffset)
            } else {
                captureModeButton
                    .offset(x: shutterSideOffset)
            }
        }
        .frame(height: shutterOuter + 8)
    }

    private var shutterButton: some View {
        Button {
            if captureMode == .video {
                if camera.isRecording {
                    camera.stopRecording()
                } else {
                    if camera.freeStorageBytes > 0 && camera.freeStorageBytes < CameraController.minimumStorageForRecording {
                        storageWarningAlert = true
                        GrainHaptics.error(enabled: true)
                        return
                    }
                    camera.startRecording(
                        quality: videoQuality,
                        stabilization: stabilization,
                        codec: videoCodec,
                        container: videoContainer,
                        aspect: videoAspect
                    )
                }
            } else {
                camera.capture(
                    CameraCaptureConfiguration(
                        format: format,
                        resolution: resolution,
                        aspect: aspect,
                        timer: timer,
                        flash: flash,
                        livePhoto: livePhoto
                    )
                )
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(
                        captureMode == .video ? Color.red.opacity(0.85) : GrainTheme.paper,
                        lineWidth: 3.4
                    )
                    .frame(width: shutterOuter, height: shutterOuter)
                if captureMode == .video {
                    Circle()
                        .fill(Color.red)
                        .frame(
                            width: camera.isRecording ? 28 : shutterInner,
                            height: camera.isRecording ? 28 : shutterInner
                        )
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: camera.isRecording)
                } else {
                    Circle()
                        .fill(camera.isCapturing ? GrainTheme.muted : GrainTheme.paper)
                        .frame(width: shutterInner, height: shutterInner)
                }
                if camera.isCapturing, captureMode == .photo {
                    ProgressView()
                        .controlSize(.small)
                        .tint(GrainTheme.black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.isReady || (captureMode == .photo && camera.isCapturing))
    }

    /// 快门右侧随行：拍照 / 录像互切
    private var captureModeButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                captureMode = captureMode == .photo ? .video : .photo
            }
            GrainHaptics.selection(enabled: true)
        } label: {
            Image(systemName: captureMode == .video ? "camera.fill" : "video.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    captureMode == .video ? GrainTheme.accent : GrainTheme.paper
                )
                .frame(width: sideButton, height: sideButton)
                .background(GrainTheme.surface.opacity(0.85), in: Circle())
                .overlay {
                    Circle().stroke(GrainTheme.line, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(camera.isRecording)
        .accessibilityLabel(captureMode == .video ? "切回拍照" : "切换到录像")
    }

    /// 录制中抓拍一张静止照片（AVCapturePhotoOutput 官方支持边录边拍）
    private var stillCaptureButton: some View {
        Button {
            camera.capture(
                CameraCaptureConfiguration(
                    format: format == .raw ? .heif : format,
                    resolution: .standard24,
                    aspect: .portrait16x9,
                    timer: .off,
                    flash: flash,
                    livePhoto: false
                )
            )
        } label: {
            Circle()
                .fill(GrainTheme.paper)
                .frame(width: sideButton - 4, height: sideButton - 4)
                .overlay {
                    Circle().stroke(Color.black.opacity(0.28), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(!camera.isReady || camera.isCapturing)
        .accessibilityLabel("录制中抓拍照片")
    }

    private var latestCaptureButton: some View {
        Button {
            if let identifier = camera.latestCaptureAssetIdentifier {
                openLatestCapture(identifier)
            } else {
                closeCamera()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(GrainTheme.surface.opacity(0.85))
                if let thumbnail = camera.latestCaptureThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: sideButton, height: sideButton)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GrainTheme.paper)
                }
            }
            .frame(width: sideButton, height: sideButton)
            .overlay {
                Circle()
                    .stroke(GrainTheme.line, lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            camera.latestCaptureAssetIdentifier == nil
                ? "打开照片图库"
                : "打开刚拍摄的照片"
        )
    }

    private var flipCameraButton: some View {
        Button {
            camera.toggleCamera()
            GrainHaptics.mediumImpact(enabled: true)
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GrainTheme.paper)
                .frame(width: sideButton, height: sideButton)
                .background(GrainTheme.surface.opacity(0.85), in: Circle())
                .overlay {
                    Circle().stroke(GrainTheme.line, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .disabled(camera.isRecording)
        .opacity(camera.isRecording ? 0.35 : 1)
        .accessibilityLabel("切换前后镜头")
    }

    private var cameraFilterTray: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(cameraProfile.shortName)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(cameraProfile == .neutral ? GrainTheme.muted : GrainTheme.accent)
                    .frame(width: 62, alignment: .leading)
                    .lineLimit(1)
                Slider(value: $cameraIntensity, in: 0...2)
                    .tint(GrainTheme.accent)
                    .disabled(cameraProfile == .neutral)
                    .scaleEffect(0.82, anchor: .center)
                    .frame(height: 22)
                    .onChange(of: cameraIntensity) { _, newVal in
                        let step = Int((newVal * 20).rounded())
                        if step != lastIntensityHapticStep {
                            lastIntensityHapticStep = step
                            GrainHaptics.selection()
                        }
                    }
                Text("\(Int((cameraIntensity * 100).rounded()))%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 28, alignment: .trailing)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(cameraProfiles) { profile in
                        Button {
                            if profile != .neutral, cameraProfile == profile {
                                cameraProfile = .neutral
                            } else {
                                cameraProfile = profile
                                if profile != .neutral {
                                    cameraIntensity = 0.86
                                }
                            }
                            GrainHaptics.selection(enabled: true)
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color(hex: 0x171714))
                                    RadialGradient(
                                        colors: [
                                            profile.uiPalette[1].opacity(0.24),
                                            .clear
                                        ],
                                        center: .center,
                                        startRadius: 2,
                                        endRadius: 28
                                    )
                                    FilmCameraGlyph(
                                        profile: profile,
                                        animated: cameraProfile == profile
                                    )
                                        .padding(.horizontal, 2)
                                        .padding(.vertical, 1)
                                }
                                .frame(width: 48, height: 26)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            cameraProfile == profile
                                                ? GrainTheme.accent
                                                : GrainTheme.line,
                                            lineWidth: cameraProfile == profile ? 1.8 : 0.7
                                        )
                                }

                                Text(profile.shortName)
                                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        cameraProfile == profile
                                            ? GrainTheme.paper
                                            : GrainTheme.muted
                                    )
                                    .lineLimit(1)
                                    .frame(width: 50)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(GrainTheme.line, lineWidth: 0.7)
        }
    }

    private var cameraLookOverlay: some View {
        GeometryReader { proxy in
            let rect = fittedFrame(for: effectiveAspectRatio, in: proxy.size)

            if cameraProfile != .neutral {
                ZStack {
                    LinearGradient(
                        colors: cameraProfile.uiPalette,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.softLight)

                    RadialGradient(
                        colors: [
                            cameraProfile.uiPalette[2].opacity(0.58),
                            .clear
                        ],
                        center: UnitPoint(x: 0.70, y: 0.25),
                        startRadius: 2,
                        endRadius: max(rect.width, rect.height) * 0.58
                    )
                    .blendMode(.screen)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                // 100% 以上继续加深，和编辑页的 200% 上限保持一致
                .opacity(
                    min(cameraIntensity, 1) * 0.27
                        + max(cameraIntensity - 1, 0) * 0.16
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var framingOverlay: some View {
        GeometryReader { proxy in
            let rect = fittedFrame(for: effectiveAspectRatio, in: proxy.size)
            // 三分构图线贴合真实取景区域，四周留黑的区域不画线。
            if showGrid {
                Path { path in
                    for index in 1...2 {
                        let x = rect.minX + rect.width * CGFloat(index) / 3
                        path.move(to: CGPoint(x: x, y: rect.minY))
                        path.addLine(to: CGPoint(x: x, y: rect.maxY))
                        let y = rect.minY + rect.height * CGFloat(index) / 3
                        path.move(to: CGPoint(x: rect.minX, y: y))
                        path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
            }
        }
        .allowsHitTesting(false)
    }

    private func fittedFrame(for ratio: Double, in size: CGSize) -> CGRect {
        let target = CGFloat(ratio)
        let sizeRatio = size.width / max(size.height, 1)
        let fitted: CGSize
        if sizeRatio > target {
            fitted = CGSize(width: size.height * target, height: size.height)
        } else {
            fitted = CGSize(width: size.width, height: size.width / target)
        }
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func zoomLabel(_ zoom: CGFloat) -> String {
        zoom == floor(zoom) ? String(Int(zoom)) : String(format: "%.1f", zoom)
    }

    private var cameraProfiles: [FilmProfile] {
        FilmProfile.resolvedDisplayOrder(from: filmOrder)
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
                GrainHaptics.mediumImpact(enabled: true)
                closeCamera()
            }
            .onEnded { _ in
                didSwipeBack = false
            }
    }

    private func closeCamera() {
        camera.cancelCapture()
        camera.stop()
        leaveCamera()
    }

    /// 带着最近一张照片的相册标识退出相机，外层收到后直接打开编辑页
    private func openLatestCapture(_ identifier: String) {
        camera.cancelCapture()
        camera.stop()
        if let onOpenCapture {
            // 先交给外层记录标识并关闭覆盖视图，避免 dismiss 与回调竞争
            onOpenCapture(identifier)
        } else {
            leaveCamera()
        }
    }

    private var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomGestureBase == nil {
                    zoomGestureBase = camera.selectedZoom
                    GrainHaptics.prepare()
                }
                guard let zoomGestureBase else { return }
                let newZoom = zoomGestureBase * value
                let oldStep = Int(camera.selectedZoom * 2)
                let newStep = Int(newZoom * 2)
                if oldStep != newStep {
                    GrainHaptics.selection()
                }
                camera.setZoom(newZoom)
            }
            .onEnded { _ in
                zoomGestureBase = nil
            }
    }

}

private struct VideoViewfinderInfoOverlay: View {
    let freeStorageText: String
    let remainingTimeText: String
    let audioLevel: Float
    let isRecording: Bool
    var isLowStorage: Bool = false

    private func barColor(index: Int, active: Bool) -> Color {
        guard active else { return Color.white.opacity(0.2) }
        if index >= 4 { return Color.red }
        if index >= 3 { return Color.yellow }
        return Color.green
    }

    private func barHeight(index: Int) -> CGFloat {
        CGFloat(5 + index * 2)
    }

    var body: some View {
        HStack(spacing: 5) {
            if isRecording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            } else if isLowStorage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Text("\(freeStorageText) · \(remainingTimeText)")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isLowStorage ? Color.yellow : GrainTheme.paper)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: 10)

            // 常驻麦克风图标与实时 VU 电平表（待机与录制时均常驻显示）
            HStack(spacing: 3) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(audioLevel > 0.05 ? GrainTheme.accent : GrainTheme.paper.opacity(0.72))

                HStack(spacing: 1.5) {
                    ForEach(0..<5, id: \.self) { barIndex in
                        let active = audioLevel >= (Float(barIndex + 1) / 5.0)
                        RoundedRectangle(cornerRadius: 0.8)
                            .fill(barColor(index: barIndex, active: active))
                            .frame(width: 2.2, height: barHeight(index: barIndex))
                    }
                }
                .frame(height: 14, alignment: .bottom)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.65), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.6))
    }
}

private struct MenuChip: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(GrainTheme.paper)
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(GrainTheme.raised, in: Capsule())
        .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
    }
}
