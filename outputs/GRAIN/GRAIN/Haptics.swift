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
/// 真实快门声音：拍照时播放系统相机标准快门声
enum GrainShutterSound {
    /// 默认开启（跟随设置中的「快门声音」开关）
    static var isEnabled: Bool { GrainFeedbackSound.isEnabled }

    /// 由 AVCapturePhotoCaptureDelegate 的 willCapturePhotoFor 调用
    static func playForCapture() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1108)
    }
}

/// 点击对焦提示音播放器：模拟索尼微单（Sony Alpha）半按快门合焦确认的双响电子提示音（"嘀嘀" / "Pi-Pi"）
final class GrainFocusSoundPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = GrainFocusSoundPlayer()
    private var player: AVAudioPlayer?
    private let lock = NSLock()

    override init() {
        super.init()
        prepare()
    }

    private func prepare() {
        let sampleRate: Double = 44100
        let freq: Double = 2350.0
        let totalSamples = Int(sampleRate * 0.11)
        var samples = [Int16](repeating: 0, count: totalSamples)

        let beep1Count = Int(sampleRate * 0.035) // 第一声 35ms
        let gapCount = Int(sampleRate * 0.030)   // 间隔 30ms
        let beep2Start = beep1Count + gapCount
        let beep2Count = Int(sampleRate * 0.035) // 第二声 35ms

        // 第一声 Beep (35ms, 2350Hz)
        for i in 0..<beep1Count {
            let t = Double(i) / sampleRate
            var env = 1.0
            let ramp = Int(sampleRate * 0.003) // 3ms 平滑淡入淡出，消除杂音
            if i < ramp { env = Double(i) / Double(ramp) }
            else if i > beep1Count - ramp { env = Double(beep1Count - i) / Double(ramp) }
            let sample = sin(2.0 * .pi * freq * t) * env * 28000.0
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
            let sample = sin(2.0 * .pi * freq * t) * env * 28000.0
            samples[idx] = Int16(sample)
        }

        // 构造标准 16-bit Mono WAV
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

        do {
            let p = try AVAudioPlayer(data: wav)
            p.prepareToPlay()
            self.player = p
        } catch {}
    }

    func play() {
        guard GrainFeedbackSound.isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if player == nil { prepare() }
        if let player {
            player.currentTime = 0
            if player.play() {
                return
            }
        }
        AudioServicesPlaySystemSound(1104)
    }
}

/// 点击对焦提示音：模拟索尼微单（Sony Alpha）半按快门合焦提示音（电子双响 "嘀嘀" / "Pi-Pi"）
enum GrainFocusSound {
    /// 播放索尼微单半按快门合焦提示音
    static func playSonyFocusSound() {
        GrainFocusSoundPlayer.shared.play()
    }

    static func playShutterClick() {
        playSonyFocusSound()
    }

    static func playIfEnabled() {
        playSonyFocusSound()
    }
}
