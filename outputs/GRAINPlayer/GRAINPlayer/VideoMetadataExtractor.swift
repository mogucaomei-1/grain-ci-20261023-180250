import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import UIKit

// MARK: - 视频底层专业技术元数据提取器

public enum VideoMetadataExtractor {
    public static func extract(from asset: AVAsset, fileURL: URL? = nil, fallbackDuration: TimeInterval = 0) async -> VideoMetadata {
        var meta = VideoMetadata()

        // 1. 读取时长
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            meta.duration = seconds.isNaN || seconds.isInfinite ? fallbackDuration : seconds
        } else {
            meta.duration = fallbackDuration
        }

        // 2. 读取文件大小
        if let fileURL {
            if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = resources.fileSize {
                meta.fileSize = Int64(size)
            }
        }

        // 3. 提取视频轨道参数
        if let videoTracks = try? await asset.loadTracks(withMediaType: .video),
           let videoTrack = videoTracks.first {

            // 分辨率与转向处理
            let naturalSize = (try? await videoTrack.load(.naturalSize)) ?? .zero
            let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity

            // 依据 transform 判断是否为竖拍
            let isPortrait = abs(transform.b) == 1.0 && abs(transform.c) == 1.0
            if isPortrait {
                meta.naturalSize = CGSize(width: naturalSize.height, height: naturalSize.width)
            } else {
                meta.naturalSize = naturalSize
            }

            // 帧率
            if let fps = try? await videoTrack.load(.nominalFrameRate) {
                meta.frameRate = fps
            }

            // 码率
            if let bitrate = try? await videoTrack.load(.estimatedDataRate) {
                meta.nominalBitrate = bitrate
            }

            // 解码器与色彩空间 / HDR 识别
            if let descriptions = try? await videoTrack.load(.formatDescriptions) {
                for desc in descriptions {
                    let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                    meta.codecName = parseCodecName(fourCC: mediaSubType)

                    // 检查 HDR / 色彩原色
                    if let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] {
                        if let primaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String {
                            meta.colorPrimaries = parseColorPrimaries(primaries)
                        }
                        if let transfer = extensions[kCVImageBufferTransferFunctionKey as String] as? String {
                            if transfer.contains("2084") || transfer.contains("HLG") || transfer.contains("ITU_R_2100") {
                                meta.isHDR = true
                            }
                        }
                    }
                }
            }
        }

        // 4. 提取音频轨道参数
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let audioTrack = audioTracks.first {
            if let descriptions = try? await audioTrack.load(.formatDescriptions) {
                for desc in descriptions {
                    let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                    meta.audioFormat = parseAudioCodec(fourCC: mediaSubType)
                    if let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                        meta.audioChannels = Int(streamDesc.pointee.mChannelsPerFrame)
                    }
                }
            }
        }

        return meta
    }

    private static func parseCodecName(fourCC: FourCharCode) -> String {
        switch fourCC {
        case kCMVideoCodecType_HEVC:
            return "HEVC (H.265)"
        case kCMVideoCodecType_HEVCWithAlpha:
            return "HEVC + Alpha"
        case kCMVideoCodecType_H264:
            return "H.264 (AVC)"
        case kCMVideoCodecType_AppleProRes422:
            return "Apple ProRes 422"
        case kCMVideoCodecType_AppleProRes422HQ:
            return "Apple ProRes 422 HQ"
        case kCMVideoCodecType_AppleProRes422LT:
            return "Apple ProRes 422 LT"
        case kCMVideoCodecType_AppleProRes422Proxy:
            return "Apple ProRes 422 Proxy"
        case kCMVideoCodecType_AppleProRes4444:
            return "Apple ProRes 4444"
        case kCMVideoCodecType_AppleProRes4444XQ:
            return "Apple ProRes 4444 XQ"
        case kCMVideoCodecType_JPEG:
            return "Motion JPEG"
        default:
            let bytes = [
                UInt8((fourCC >> 24) & 0xff),
                UInt8((fourCC >> 16) & 0xff),
                UInt8((fourCC >> 8) & 0xff),
                UInt8(fourCC & 0xff)
            ]
            let code = String(bytes: bytes, encoding: .ascii) ?? "Unknown"
            return code.uppercased()
        }
    }

    private static func parseColorPrimaries(_ primaries: String) -> String {
        if primaries.contains("2020") {
            return "ITU-R BT.2020"
        } else if primaries.contains("709") {
            return "ITU-R BT.709"
        } else if primaries.contains("P3") || primaries.contains("DCI") {
            return "Display P3"
        }
        return primaries
    }

    private static func parseAudioCodec(fourCC: FourCharCode) -> String {
        switch fourCC {
        case kAudioFormatMPEG4AAC:
            return "AAC"
        case kAudioFormatLinearPCM:
            return "PCM"
        case kAudioFormatAppleLossless:
            return "ALAC"
        case kAudioFormatAC3:
            return "Dolby AC-3"
        case kAudioFormatEnhancedAC3:
            return "Dolby Digital Plus (E-AC-3)"
        case kAudioFormatFLAC:
            return "FLAC"
        default:
            return "Audio"
        }
    }
}
