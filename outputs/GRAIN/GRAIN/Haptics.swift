import AudioToolbox
import UIKit

enum GrainFeedbackSound {
    /// 提示音统一跟随「设置 → 快门声音」开关，关掉就整体静音
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "shutterSoundEnabled") as? Bool ?? true
    }
}

enum GrainHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static func prepare() {
        selectionGenerator.prepare()
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    static func selection(enabled: Bool = true) {
        guard enabled && isEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func lightImpact(enabled: Bool = true) {
        guard enabled && isEnabled else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }

    static func mediumImpact(enabled: Bool = true) {
        guard enabled && isEnabled else { return }
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
    }
}

/// 快门声音开关。
/// AVFoundation 在拍照时会自动播放系统快门声（SystemSoundID 1108），
/// 它不提供公开的静音接口；这里在 willCapturePhotoFor 中接管：
/// 开启时播放同一段系统快门音文件（自己注册的 ID），关闭时释放 1108 让系统不发声。
enum GrainShutterSound {
    private static let lock = NSLock()
    private static var customID: SystemSoundID = 0
    private static var customReady: Bool?

    /// 默认开启
    static var isEnabled: Bool { GrainFeedbackSound.isEnabled }

    /// 由 AVCapturePhotoCaptureDelegate 的 willCapturePhotoFor 调用
    static func playForCapture() {
        let enabled = isEnabled
        lock.lock()
        defer { lock.unlock() }

        if enabled {
            guard ensureCustomSoundLocked() else {
                // 读不到系统音源时保持系统默认快门声，避免“开着却没声音”
                return
            }
            AudioServicesPlaySystemSound(customID)
        }
        AudioServicesDisposeSystemSoundID(1108)
    }

    private static func ensureCustomSoundLocked() -> Bool {
        if let customReady {
            return customReady
        }
        let url = URL(
            fileURLWithPath: "/System/Library/Audio/UISounds/photoShutter.caf"
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            customReady = false
            return false
        }
        var id: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
        guard status == kAudioServicesNoError, id != 0 else {
            customReady = false
            return false
        }
        customID = id
        customReady = true
        return true
    }
}

/// 点击对焦提示音：点按取景框时播放快门声，确认对焦接管
enum GrainFocusSound {
    private static let lock = NSLock()
    private static var soundID: SystemSoundID = 0
    private static var ready: Bool?

    /// 点击对焦播放快门声（支持设置开关控制）
    static func playShutterClick() {
        guard GrainFeedbackSound.isEnabled else { return }
        AudioServicesPlaySystemSound(1108)
    }

    static func playIfEnabled() {
        playShutterClick()
    }

    private static func ensureLocked() -> Bool {
        if let ready { return ready }
        let candidates = [
            "/System/Library/Audio/UISounds/key_press_click.caf",
            "/System/Library/Audio/UISounds/Tock.caf",
            "/System/Library/Audio/UISounds/photoShutter.caf"
        ]
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            var id: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(
                URL(fileURLWithPath: path) as CFURL,
                &id
            )
            if status == kAudioServicesNoError, id != 0 {
                soundID = id
                ready = true
                return true
            }
        }
        ready = false
        return false
    }
}
