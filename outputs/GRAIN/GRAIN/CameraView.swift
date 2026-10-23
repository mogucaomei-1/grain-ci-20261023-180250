import AVFoundation
import CoreLocation
import ImageIO
import Photos
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CameraCaptureFormat: String, CaseIterable, Identifiable {
    case heif
    case png
    case raw

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heif: "HEIF"
        case .png: "PNG"
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
    case landscape4x3
    case landscape3x2
    case landscape16x9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait3x4: "3:4"
        case .square: "1:1"
        case .landscape4x3: "4:3"
        case .landscape3x2: "3:2"
        case .landscape16x9: "16:9"
        }
    }

    var ratio: Double {
        switch self {
        case .portrait3x4: 3.0 / 4
        case .square: 1
        case .landscape4x3: 4.0 / 3
        case .landscape3x2: 3.0 / 2
        case .landscape16x9: 16.0 / 9
        }
    }
}

enum CameraTimer: String, CaseIterable, Identifiable {
    case off
    case three
    case ten

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "计时关"
        case .three: "3 秒"
        case .ten: "10 秒"
        }
    }
    var seconds: Int {
        switch self {
        case .off: 0
        case .three: 3
        case .ten: 10
        }
    }
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
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "studio.grain.camera.session")
    private var cameraDevice: AVCaptureDevice?
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

    @Published private(set) var isReady = false
    @Published private(set) var isCapturing = false
    @Published private(set) var countdown: Int?
    @Published private(set) var notice: String?
    @Published private(set) var errorMessage: String?
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

    func setZoom(_ zoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, var device = self.cameraDevice else { return }
            do {
                if device.deviceType != .builtInUltraWideCamera,
                   zoom <= 0.55,
                   let ultraWide = AVCaptureDevice.default(
                       .builtInUltraWideCamera,
                       for: .video,
                       position: .back
                   ),
                   self.replaceVideoInput(with: ultraWide) {
                    device = ultraWide
                } else if device.deviceType == .builtInUltraWideCamera,
                          zoom > 0.55,
                          let backCamera = self.discoverCamera(position: .back),
                          self.replaceVideoInput(with: backCamera) {
                    device = backCamera
                }

                let requestedFactor = device.deviceType == .builtInUltraWideCamera
                    ? 1
                    : zoom
                let hardwareZoom = min(
                    max(requestedFactor, device.minAvailableVideoZoomFactor),
                    device.maxAvailableVideoZoomFactor
                )

                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                device.videoZoomFactor = hardwareZoom
                device.unlockForConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.selectedZoom = zoom
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "无法切换相机倍率。"
                }
            }
        }
    }

    private func replaceVideoInput(with device: AVCaptureDevice) -> Bool {
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
            session.commitConfiguration()
            videoInput = newInput
            cameraDevice = device
            supportsRawCapture = device.position == .back
                && (
                    photoOutput.isAppleProRAWSupported
                    || !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
                )
            publishDeviceCapabilities(
                device,
                liveSupported: device.position == .back,
                rawSupported: supportsRawCapture
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
            guard let cameraDevice = self?.cameraDevice else { return }
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

    func setExposureBias(_ value: Float) {
        sessionQueue.async { [weak self] in
            guard let cameraDevice = self?.cameraDevice else { return }
            let clamped = min(
                max(value, cameraDevice.minExposureTargetBias),
                cameraDevice.maxExposureTargetBias
            )
            do {
                try cameraDevice.lockForConfiguration()
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
            .map { (format: $0, area: maximumPhotoArea($0)) }
            .filter { $0.area > 0 }
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

    func setLivePhotoEnabled(_ enabled: Bool) async -> Bool {
        guard isLivePhotoSupported else { return false }
        if enabled {
            let allowed = await requestMediaAccess(for: .audio)
            guard allowed else {
                DispatchQueue.main.async { [weak self] in
                    self?.errorMessage = "请在系统设置中允许麦克风权限后再使用实况照片。"
                }
                return false
            }
        }

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                self.session.beginConfiguration()
                var hasAudio = !enabled
                if enabled {
                    if let microphone = AVCaptureDevice.default(for: .audio),
                       let input = try? AVCaptureDeviceInput(device: microphone),
                       self.audioInput == nil,
                       self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.audioInput = input
                        hasAudio = true
                    } else if self.audioInput != nil {
                        hasAudio = true
                    }
                } else if let audioInput = self.audioInput {
                    self.session.removeInput(audioInput)
                    self.audioInput = nil
                }
                // ProRAW 与实况照片互斥，必须先关掉 ProRAW 再开启实况照片
                if enabled, self.photoOutput.isAppleProRAWEnabled {
                    self.photoOutput.isAppleProRAWEnabled = false
                }
                // 实况照片最高按 12MP 输出，其余情况回到当前相机满分辨率
                if let device = self.cameraDevice {
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
                self.photoOutput.isLivePhotoCaptureEnabled =
                    enabled && hasAudio && self.photoOutput.isLivePhotoCaptureSupported
                self.session.commitConfiguration()
                let armed = enabled && hasAudio
                    && self.photoOutput.isLivePhotoCaptureSupported
                DispatchQueue.main.async {
                    self.isLivePhotoArmed = armed
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

            cameraDevice = device
            let liveSupported = device.position == .back
            let rawSupported = supportsRawCapture
            let maxDims = captureDimensions
                ?? CMVideoDimensions(width: 0, height: 0)

            session.commitConfiguration()
            didCommitConfiguration = true
            session.startRunning()
            isSessionConfigured = true

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
        rawSupported: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasUltraWide = device.constituentDevices.contains {
                $0.deviceType == .builtInUltraWideCamera
            }
            self.minimumZoom = device.position == .back && hasUltraWide ? 0.5 : 1
            self.maximumZoom = 8
            self.selectedZoom = device.position == .back ? 1 : min(max(1, self.minimumZoom), self.maximumZoom)
            self.minimumExposureBias = device.minExposureTargetBias
            self.maximumExposureBias = device.maxExposureTargetBias
            self.exposureBias = min(max(0, device.minExposureTargetBias), device.maxExposureTargetBias)
            self.isUsingFrontCamera = device.position == .front
            self.isLivePhotoSupported = liveSupported
            self.isRawSupported = rawSupported
        }
    }

    private func performCapture(_ configuration: CameraCaptureConfiguration) {
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
            connection.isVideoMirrored = cameraDevice?.position == .front
        }
        session.commitConfiguration()
        return photoOutputAttached
    }

    private func captureProcessed(_ configuration: CameraCaptureConfiguration) {
        let settings: AVCapturePhotoSettings
        if configuration.livePhoto {
            settings = AVCapturePhotoSettings()
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
            settings.livePhotoVideoCodecType = .hevc
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
                if let size = CameraImageProcessor.pixelSize(of: processed.data) {
                    notice = "已保存 \(size.width)×\(size.height)"
                } else {
                    notice = "已保存到照片图库"
                }
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

            // 解码时留出裁切余量，避免整张 48MP 位图常驻内存。
            // WithTransform 让 ImageIO 直接按 EXIF 方向生成正向像素，
            // 不再自己拼旋转矩阵（此前手写矩阵把竖拍图转了 180°）。
            let decodeLimit = min(sourceLongEdge, (targetPixels * 2).squareRoot().rounded())
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

            // decoded 已按 orientation 转正，裁切与缩放都在正向坐标系里进行
            let image = resized(
                crop(decoded, to: configuration.aspect.ratio),
                targetPixels: targetPixels
            )
            let format: CameraCaptureFormat = configuration.format == .png ? .png : .heif
            let type = format == .png ? UTType.png : UTType.heic
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

            let fileExtension = format == .png ? "png" : "heic"
            return CameraPreparedOutput(
                data: data as Data,
                fileName: "GRAIN-\(timestamp()).\(fileExtension)",
                uniformTypeIdentifier: type.identifier,
                location: output.location,
                livePhotoURL: output.livePhotoURL
            )
        }
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
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    let onFocus: (_ devicePoint: CGPoint, _ lock: Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
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

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        context.coordinator.parent = self
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        if let connection = uiView.previewLayer.connection,
           connection.isVideoMirroringSupported,
           connection.isVideoMirrored != mirrored {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

struct CameraView: View {
    /// 点击左下角刚拍的照片时回调相册标识，由外层负责关闭相机并进入编辑
    var onOpenCapture: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var format: CameraCaptureFormat = .heif
    @State private var resolution: CameraResolution = .standard24
    @State private var aspect: CameraAspect = .portrait3x4
    @State private var timer: CameraTimer = .off
    @State private var flash: CameraFlashSetting = .off
    @State private var livePhoto = false
    @State private var showGrid = true
    @State private var zoomGestureBase: CGFloat?
    @AppStorage("filmOrder") private var filmOrder = ""
    @State private var cameraProfile: FilmProfile = .neutral
    @State private var cameraIntensity = 1.0
    @State private var didSwipeBack = false
    @State private var showCameraFilters = false
    @State private var isPreparingLivePhoto = false

    private let zoomOptions: [CGFloat] = [0.5, 1, 2, 4, 8]

    init(onOpenCapture: ((String) -> Void)? = nil) {
        self.onOpenCapture = onOpenCapture
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar

                ZStack {
                    CameraPreviewView(
                        session: camera.session,
                        mirrored: camera.isUsingFrontCamera,
                        onFocus: { devicePoint, lock in
                            camera.focus(at: devicePoint, lock: lock)
                            GrainHaptics.mediumImpact(enabled: true)
                        }
                    )
                    .simultaneousGesture(pinchToZoomGesture)
                    cameraLookOverlay
                    framingOverlay
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipped()

                cameraControls
            }
            .ignoresSafeArea(.container, edges: .bottom)

            if let countdown = camera.countdown {
                Text("\(countdown)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 160, height: 160)
                    .background(Color.black.opacity(0.48), in: Circle())
                    .transition(.scale.combined(with: .opacity))
            }

            if !camera.isReady,
               camera.errorMessage == nil {
                ProgressView()
                    .tint(GrainTheme.paper)
                    .padding(16)
                    .background(Color.black.opacity(0.62), in: Circle())
            }

            if let notice = camera.notice {
                VStack {
                    Text(notice)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.black)
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(GrainTheme.paper, in: Capsule())
                        .padding(.top, 62)
                    Spacer()
                }
            }

            if let error = camera.errorMessage {
                VStack(spacing: 12) {
                    Text(camera.isReady ? "相机出错" : "相机无法启动")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                    Text(error)
                        .font(.system(size: 10, design: .rounded))
                        .multilineTextAlignment(.center)
                    Button("关闭") { dismiss() }
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
        .statusBarHidden()
        .task {
            await camera.start()
        }
        .onDisappear {
            camera.stop()
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
        .onChange(of: camera.isReady) { _, ready in
            if ready {
                camera.setPhotoResolution(resolution)
            }
        }
        .onChange(of: camera.selectedZoom) { _, _ in
            if !is48MPAvailable, resolution == .high48 {
                resolution = .standard24
            }
        }
        .simultaneousGesture(edgeSwipeBackGesture)
    }

    /// 数码变焦或前置镜头会在传感器上裁切，拿不到 48MP
    private var is48MPAvailable: Bool {
        camera.selectedZoom <= 1.05 && !camera.isUsingFrontCamera
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            Button {
                closeCamera()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    showCameraFilters.toggle()
                }
            } label: {
                Image(systemName: "camera.filters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                            showCameraFilters ? GrainTheme.accent : GrainTheme.muted
                    )
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                if let index = CameraFlashSetting.allCases.firstIndex(of: flash) {
                    flash = CameraFlashSetting.allCases[
                        (index + 1) % CameraFlashSetting.allCases.count
                    ]
                }
            } label: {
                Image(systemName: flash.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        flash == .off ? GrainTheme.paper.opacity(0.55) : GrainTheme.accent
                    )
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                guard !isPreparingLivePhoto else { return }
                isPreparingLivePhoto = true
                Task {
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
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(livePhoto ? GrainTheme.accent : GrainTheme.paper.opacity(0.62))
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!camera.isLivePhotoSupported || format == .raw || isPreparingLivePhoto)

            Button {
                showGrid.toggle()
                GrainHaptics.selection(enabled: true)
            } label: {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(showGrid ? GrainTheme.accent : GrainTheme.paper.opacity(0.62))
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(CameraTimer.allCases) { option in
                    Button(option.title) { timer = option }
                }
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                    if timer != .off {
                        Text("\(timer.seconds)")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                }
                .foregroundStyle(timer == .off ? GrainTheme.paper.opacity(0.62) : GrainTheme.accent)
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.58), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var cameraControls: some View {
        VStack(spacing: 7) {
            if showCameraFilters {
                cameraFilterTray
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 5) {
                ForEach(zoomOptions, id: \.self) { zoom in
                    Button {
                        camera.setZoom(zoom)
                    } label: {
                        Text(zoomLabel(zoom))
                            .font(.system(size: zoom == camera.selectedZoom ? 12 : 10, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                zoom == camera.selectedZoom ? GrainTheme.black : GrainTheme.paper
                            )
                            .frame(width: zoom == camera.selectedZoom ? 42 : 34, height: 34)
                            .background(
                                zoom == camera.selectedZoom
                                    ? GrainTheme.paper
                                    : Color.black.opacity(0.54),
                                in: Circle()
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

            HStack(spacing: 9) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GrainTheme.muted)
                Slider(
                    value: Binding(
                        get: { Double(camera.exposureBias) },
                        set: { camera.setExposureBias(Float($0)) }
                    ),
                    in: Double(camera.minimumExposureBias)...Double(camera.maximumExposureBias),
                    step: 0.1
                )
                .tint(GrainTheme.accent)
                Text(String(format: "%+.1f", camera.exposureBias))
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 34, alignment: .trailing)
                Image(systemName: "sun.max")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GrainTheme.muted)
            }

            HStack(spacing: 8) {
                ForEach(CameraResolution.allCases) { option in
                    Button(option.title) {
                        resolution = option
                    }
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(resolution == option ? GrainTheme.black : GrainTheme.paper)
                    .frame(width: 50, height: 30)
                    .background(
                        resolution == option ? GrainTheme.paper : Color.black.opacity(0.54),
                        in: Capsule()
                    )
                    .opacity(is48MPAvailable || option != .high48 ? 1 : 0.42)
                    .disabled(!is48MPAvailable && option == .high48)
                    .buttonStyle(.plain)
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
            }

            HStack {
                Button {
                    if let identifier = camera.latestCaptureAssetIdentifier {
                        openLatestCapture(identifier)
                    } else {
                        closeCamera()
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.54))
                        if let thumbnail = camera.latestCaptureThumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(GrainTheme.paper)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    camera.latestCaptureAssetIdentifier == nil
                        ? "打开照片图库"
                        : "打开刚拍摄的照片"
                )

                Spacer()

                Button {
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
                } label: {
                    ZStack {
                        Circle()
                            .stroke(GrainTheme.paper, lineWidth: 4)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(camera.isCapturing ? GrainTheme.muted : GrainTheme.paper)
                            .frame(width: 62, height: 62)
                        if camera.isCapturing {
                            ProgressView()
                                .tint(GrainTheme.black)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!camera.isReady || camera.isCapturing)

                Spacer()

                Button {
                    camera.toggleCamera()
                    GrainHaptics.mediumImpact(enabled: true)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(width: 46, height: 46)
                        .background(Color.black.opacity(0.54), in: Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 58)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 0)
    }

    private var cameraFilterTray: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(cameraProfile.shortName)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(cameraProfile == .neutral ? GrainTheme.muted : GrainTheme.accent)
                    .frame(width: 70, alignment: .leading)
                    .lineLimit(1)
                Slider(value: $cameraIntensity, in: 0...1)
                    .tint(GrainTheme.accent)
                    .disabled(cameraProfile == .neutral)
                Text("\(Int((cameraIntensity * 100).rounded()))%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 32, alignment: .trailing)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
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
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color(hex: 0x171714))
                                    RadialGradient(
                                        colors: [
                                            profile.uiPalette[1].opacity(0.24),
                                            .clear
                                        ],
                                        center: .center,
                                        startRadius: 2,
                                        endRadius: 34
                                    )
                                    FilmCameraGlyph(
                                        profile: profile,
                                        animated: cameraProfile == profile
                                    )
                                        .padding(.horizontal, 2)
                                        .padding(.vertical, 1)
                                }
                                .frame(width: 56, height: 31)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(
                                            cameraProfile == profile
                                                ? GrainTheme.accent
                                                : Color.white.opacity(0.08),
                                            lineWidth: cameraProfile == profile ? 2 : 0.7
                                        )
                                }

                                Text(profile.shortName)
                                    .font(.system(size: 7.2, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        cameraProfile == profile
                                            ? GrainTheme.paper
                                            : GrainTheme.muted
                                    )
                                    .lineLimit(1)
                                    .frame(width: 58)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(GrainTheme.line, lineWidth: 0.7)
        }
    }

    private var cameraLookOverlay: some View {
        GeometryReader { proxy in
            let available = CGSize(
                width: proxy.size.width - 18,
                height: proxy.size.height - 18
            )
            let fitted = fittedFrame(for: aspect.ratio, in: available)
            let rect = fitted.offsetBy(dx: 9, dy: 9)

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
                .opacity(cameraIntensity * 0.27)
                .allowsHitTesting(false)
            }
        }
    }

    private var framingOverlay: some View {
        GeometryReader { proxy in
            let available = CGSize(
                width: proxy.size.width - 18,
                height: proxy.size.height - 18
            )
            let fitted = fittedFrame(for: aspect.ratio, in: available)
            let rect = fitted.offsetBy(dx: 9, dy: 9)

            ZStack {
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

                Rectangle()
                    .stroke(Color.white.opacity(0.44), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
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
        dismiss()
    }

    /// 带着最近一张照片的相册标识退出相机，外层收到后直接打开编辑页
    private func openLatestCapture(_ identifier: String) {
        camera.cancelCapture()
        camera.stop()
        if let onOpenCapture {
            // 先交给外层记录标识并关闭覆盖视图，避免 dismiss 与回调竞争
            onOpenCapture(identifier)
        } else {
            dismiss()
        }
    }

    private var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if zoomGestureBase == nil {
                    zoomGestureBase = camera.selectedZoom
                }
                guard let zoomGestureBase else { return }
                camera.setZoom(zoomGestureBase * value)
            }
            .onEnded { _ in
                zoomGestureBase = nil
            }
    }

}

private struct MenuChip: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(GrainTheme.paper)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.black.opacity(0.54), in: Capsule())
    }
}
