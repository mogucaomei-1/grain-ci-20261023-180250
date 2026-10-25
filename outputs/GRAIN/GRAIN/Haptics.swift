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

/// 点击对焦提示音：模拟索尼微单（Sony Alpha）半按快门合焦提示音（电子双响 "嘀嘀" / "Pi-Pi"）
enum GrainFocusSound {
    private static let lock = NSLock()
    private static var sonySoundID: SystemSoundID = 0
    private static var isReady = false

    /// 播放索尼微单合焦提示音
    static func playSonyFocusSound() {
        guard GrainFeedbackSound.isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if !isReady {
            isReady = prepareSonySound()
        }
        if isReady && sonySoundID != 0 {
            AudioServicesPlaySystemSound(sonySoundID)
        } else {
            AudioServicesPlaySystemSound(1104)
        }
    }

    static func playShutterClick() {
        playSonyFocusSound()
    }

    static func playIfEnabled() {
        playSonyFocusSound()
    }

    private static func prepareSonySound() -> Bool {
        let sampleRate: Double = 44100
        let freq: Double = 2350.0
        let totalSamples = Int(sampleRate * 0.105)
        var samples = [Int16](repeating: 0, count: totalSamples)

        let beep1Count = Int(sampleRate * 0.035) // 35ms
        let gapCount = Int(sampleRate * 0.030)   // 30ms
        let beep2Start = beep1Count + gapCount
        let beep2Count = Int(sampleRate * 0.035) // 35ms

        // 第一声 Beep (35ms, 2350Hz)
        for i in 0..<beep1Count {
            let t = Double(i) / sampleRate
            var env = 1.0
            let ramp = Int(sampleRate * 0.003) // 3ms 平滑淡入淡出，消除杂音
            if i < ramp { env = Double(i) / Double(ramp) }
            else if i > beep1Count - ramp { env = Double(beep1Count - i) / Double(ramp) }
            let sample = sin(2.0 * .pi * freq * t) * env * 24000.0
            samples[i] = Int16(sample)
        }

        // 第二声 Beep (35ms, 2350Hz)
        for i in 0..<beep2Count {
            let idx = beep2Start + i
            let t = Double(i) / sampleRate
            var env = 1.0
            let ramp = Int(sampleRate * 0.003)
            if i < ramp { env = Double(i) / Double(ramp) }
            else if i > beep2Count - ramp { env = Double(beep2Count - i) / Double(ramp) }
            let sample = sin(2.0 * .pi * freq * t) * env * 24000.0
            samples[idx] = Int16(sample)
        }

        // 构造标准 16-bit Mono WAV 格式
        let dataSize = samples.count * 2
        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + dataSize).littleEndian
        wav.append(Data(bytes: &chunkSize, count: 4))
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        var subchunk1Size = UInt32(16).littleEndian
        wav.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian // PCM
        wav.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(1).littleEndian // 单声道
        wav.append(Data(bytes: &numChannels, count: 2))
        var sRate = UInt32(sampleRate).littleEndian
        wav.append(Data(bytes: &sRate, count: 4))
        var byteRate = UInt32(sampleRate * 2).littleEndian
        wav.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian
        wav.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        wav.append(Data(bytes: &bitsPerSample, count: 2))
        wav.append(contentsOf: "data".utf8)
        var subchunk2Size = UInt32(dataSize).littleEndian
        wav.append(Data(bytes: &subchunk2Size, count: 4))

        samples.withUnsafeBufferPointer { ptr in
            wav.append(Data(buffer: ptr))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("grain_sony_focus.wav")
        do {
            try wav.write(to: tempURL)
            var id: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(tempURL as CFURL, &id)
            if status == kAudioServicesNoError, id != 0 {
                sonySoundID = id
                return true
            }
        } catch {}
        return false
    }
}
