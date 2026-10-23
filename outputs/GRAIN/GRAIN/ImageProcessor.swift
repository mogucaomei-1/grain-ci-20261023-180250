import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessorError: LocalizedError {
    case cannotOpenFile
    case unsupportedRAW
    case cannotRender
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile:
            "无法读取这张照片，请确认文件没有损坏。"
        case .unsupportedRAW:
            "当前 iOS 的 RAW 解码器无法读取这个 Sony RAW 版本。请确认选择的是原始 ARW，而不是图库生成的 JPEG 副本；必要时更新 iOS 后重试。"
        case .cannotRender:
            "图像处理没有完成，请重新尝试。"
        case .cannotWrite:
            "无法写入导出文件，请检查可用存储空间。"
        }
    }
}

struct RawImageProcessor {
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any
    ])

    static func metadata(for url: URL) throws -> PhotoAsset {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            throw ImageProcessorError.cannotOpenFile
        }

        let exif = stringKeyedDictionary(properties[kCGImagePropertyExifDictionary])
        let tiff = stringKeyedDictionary(properties[kCGImagePropertyTIFFDictionary])
        let gps = stringKeyedDictionary(properties[kCGImagePropertyGPSDictionary])
        let latitudeValue = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue
        let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String
        let longitudeValue = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue
        let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String
        let latitude = latitudeValue.map { latitudeRef == "S" ? -$0 : $0 }
        let longitude = longitudeValue.map { longitudeRef == "W" ? -$0 : $0 }

        var width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let rawOrientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0

        let rawExtensions = ["arw", "srf", "sr2", "dng", "raw", "nef", "cr2", "cr3", "raf", "orf", "rw2"]
        let isRawFile = rawExtensions.contains(url.pathExtension.lowercased())

        // 部分 RAW（例如单反/微单的 ARW）的 0 号图像其实是内嵌预览
        // （常见 1616×1080），ImageIO 报的尺寸会远小于真实像素。
        // EXIF 里的 PixelXDimension/PixelYDimension 才是整张原图，取更大的那组。
        let exifWidth = (exif[kCGImagePropertyExifPixelXDimension] as? NSNumber)?.intValue ?? 0
        let exifHeight = (exif[kCGImagePropertyExifPixelYDimension] as? NSNumber)?.intValue ?? 0
        if exifWidth > 0, exifHeight > 0, exifWidth * exifHeight > width * height {
            width = exifWidth
            height = exifHeight
        }

        // EXIF 也不可靠时（长边仍不足 2000，明显不可能是相机原图），
        // 用 Core Image 的 RAW 滤镜读一次传感器原生尺寸。
        if isRawFile, max(width, height) > 0, max(width, height) < 2000,
           let rawFilter = CIRAWFilter(imageURL: url) {
            let native = rawFilter.nativeSize
            if Int(native.width) * Int(native.height) > width * height {
                width = Int(native.width)
                height = Int(native.height)
            }
        }

        // 属性里的宽高是传感器方向的；RAW 竖拍要按 EXIF 方向换算，
        // 否则 4000×6000 的竖图会显示成 6000×4000。
        // （HEIF/JPEG 保持原样，避免个别机型已经转正过的尺寸被再交换一次）
        if isRawFile, [5, 6, 7, 8].contains(Int(rawOrientation)) {
            swap(&width, &height)
        }

        let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? tiff[kCGImagePropertyTIFFDateTime] as? String
        let date = dateString.flatMap {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            return formatter.date(from: $0)
        }
        let cameraMake = tiff[kCGImagePropertyTIFFMake] as? String ?? ""
        let cameraModel = tiff[kCGImagePropertyTIFFModel] as? String ?? ""
        let longEdge = max(width, height)
        let shortEdge = max(1, min(width, height))
        let isLikelyScreenshot = cameraMake.isEmpty
            && cameraModel.isEmpty
            && Double(longEdge) / Double(shortEdge) > 1.72

        return PhotoAsset(
            url: url,
            displayName: url.deletingPathExtension().lastPathComponent,
            pixelWidth: width,
            pixelHeight: height,
            fileSize: fileSize,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: exif[kCGImagePropertyExifLensModel] as? String ?? "",
            capturedAt: date,
            hasLocation: !gps.isEmpty,
            latitude: latitude,
            longitude: longitude,
            orientation: rawOrientation,
            isLikelyScreenshot: isLikelyScreenshot
        )
    }

    /// ImageIO 返回的嵌套字典既可能是 [String: Any] 也可能是 [CFString: Any]
    private static func stringKeyedDictionary(_ value: Any?) -> [CFString: Any] {
        if let dictionary = value as? [CFString: Any] {
            return dictionary
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [:]) { result, pair in
                result[pair.key as CFString] = pair.value
            }
        }
        return [:]
    }

    static func renderPreview(
        from url: URL,
        profile: FilmProfile,
        settings: FilmSettings,
        intensity: Double
    ) throws -> (original: CGImage, edited: CGImage) {
        let original = try renderSourcePreview(from: url)
        let asset = try metadata(for: url)
        let edited = try renderGradedPreview(
            source: original,
            profile: profile,
            settings: settings,
            intensity: intensity,
            suppressVignette: asset.isLikelyScreenshot
        )
        return (original, edited)
    }

    static func renderSourcePreview(from url: URL) throws -> CGImage {
        let image = try loadImage(from: url, draft: true)
        let normalized = normalizedExtent(of: image)
        let maxDimension = max(normalized.extent.width, normalized.extent.height)
        // Interactive previews stay just above iPhone display resolution.
        // Export always decodes the RAW again at its native dimensions.
        let scale = min(1, 1280 / maxDimension)
        let preview = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let original = context.createCGImage(preview, from: preview.extent) else {
            throw ImageProcessorError.cannotRender
        }
        return original
    }

    static func renderQuickPreview(from url: URL, maxDimension: Int = 1600) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageProcessorError.cannotOpenFile
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessorError.cannotOpenFile
        }
        return image
    }

    static func renderGradedPreview(
        source: CGImage,
        profile: FilmProfile,
        settings: FilmSettings,
        intensity: Double,
        suppressVignette: Bool = false
    ) throws -> CGImage {
        let preview = CIImage(cgImage: source)
        let graded = applyFilm(
            to: preview,
            profile: profile,
            settings: settings,
            intensity: intensity,
            grainScale: 1,
            suppressVignette: suppressVignette
        )

        guard let edited = context.createCGImage(graded, from: preview.extent) else {
            throw ImageProcessorError.cannotRender
        }
        return edited
    }

    static func renderLivePreview(
        source: CIImage,
        profile: FilmProfile,
        settings: FilmSettings,
        intensity: Double
    ) -> CIImage {
        var liveSettings = settings
        liveSettings.grain = 0
        let normalized = normalizedExtent(of: source)
        let graded = applyFilm(
            to: normalized,
            profile: profile,
            settings: liveSettings,
            intensity: intensity,
            grainScale: 1,
            suppressVignette: false
        )
        return graded.cropped(to: normalized.extent)
    }

    static func renderFullResolutionDisplay(
        from url: URL,
        profile: FilmProfile,
        settings: FilmSettings,
        intensity: Double,
        crop: CropTransform,
        mosaicStrokes: [MosaicStroke]
    ) throws -> CGImage {
        try autoreleasepool {
            let image = try loadImage(from: url, draft: false)
            let normalized = normalizedExtent(of: image)
            let maxDimension = max(normalized.extent.width, normalized.extent.height)
            let sourceAsset = try metadata(for: url)
            let expectedLongEdge = max(sourceAsset.pixelWidth, sourceAsset.pixelHeight)
            if expectedLongEdge > 0, maxDimension < Double(expectedLongEdge) * 0.90 {
                throw ImageProcessorError.unsupportedRAW
            }

            let graded = applyFilm(
                to: normalized,
                profile: profile,
                settings: settings,
                intensity: intensity,
                grainScale: max(1, maxDimension / 1800),
                suppressVignette: sourceAsset.isLikelyScreenshot
            )
            let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)
            guard let gradedImage = context.createCGImage(
                graded,
                from: normalized.extent,
                format: .RGBA8,
                colorSpace: displayP3
            ) else {
                throw ImageProcessorError.cannotRender
            }
            let croppedImage = CropProcessor.apply(crop, to: gradedImage)
            return MosaicProcessor.apply(mosaicStrokes, to: croppedImage)
        }
    }

    static func export(
        from url: URL,
        profile: FilmProfile,
        settings: FilmSettings,
        intensity: Double,
        options: ExportOptions,
        crop: CropTransform = .identity,
        mosaicStrokes: [MosaicStroke] = [],
        textOverlays: [PhotoTextOverlay] = [],
        to outputURL: URL
    ) throws -> ExportResult {
        return try autoreleasepool {
            let image = try loadImage(from: url, draft: false)
            let normalized = normalizedExtent(of: image)
            let maxDimension = max(normalized.extent.width, normalized.extent.height)
            let sourceAsset = try metadata(for: url)
            let expectedLongEdge = max(sourceAsset.pixelWidth, sourceAsset.pixelHeight)
            if expectedLongEdge > 0, maxDimension < Double(expectedLongEdge) * 0.90 {
                // Never export an embedded JPEG or a draft-sized image as "full resolution".
                throw ImageProcessorError.unsupportedRAW
            }
            let graded = applyFilm(
                to: normalized,
                profile: profile,
                settings: settings,
                intensity: intensity,
                grainScale: max(1, maxDimension / 1800),
                suppressVignette: sourceAsset.isLikelyScreenshot
            )

            let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)
            guard let gradedImage = context.createCGImage(
                graded,
                from: normalized.extent,
                format: .RGBA8,
                colorSpace: displayP3
            ) else {
                throw ImageProcessorError.cannotRender
            }
            let croppedImage = CropProcessor.apply(crop, to: gradedImage)
            let mosaickedImage = MosaicProcessor.apply(mosaicStrokes, to: croppedImage)
            let cgImage = TextOverlayRenderer.render(textOverlays, onto: mosaickedImage)
            let framedImage = ExportFrameRenderer.render(
                cgImage,
                options: options,
                dateText: Self.dateStampText(sourceAsset.capturedAt)
            )

            var actualFormat = options.format
            var destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                actualFormat.typeIdentifier,
                1,
                nil
            )

            if destination == nil, actualFormat == .heic {
                actualFormat = .jpeg
                let fallbackURL = outputURL.deletingPathExtension().appendingPathExtension("jpg")
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    try FileManager.default.removeItem(at: fallbackURL)
                }
                destination = CGImageDestinationCreateWithURL(
                    fallbackURL as CFURL,
                    actualFormat.typeIdentifier,
                    1,
                    nil
                )
                guard destination != nil else { throw ImageProcessorError.cannotWrite }
                let properties = exportProperties(
                    sourceURL: url,
                    keepLocation: options.keepLocation,
                    keepCameraMetadata: options.keepCameraMetadata,
                    width: framedImage.width,
                    height: framedImage.height,
                    quality: options.quality
                )
                CGImageDestinationAddImage(destination!, framedImage, properties as CFDictionary)
                guard CGImageDestinationFinalize(destination!) else {
                    throw ImageProcessorError.cannotWrite
                }
                return ExportResult(
                    url: fallbackURL,
                    dimensions: "\(framedImage.width) × \(framedImage.height)",
                    format: actualFormat
                )
            }

            guard let destination else { throw ImageProcessorError.cannotWrite }
            let properties = exportProperties(
                sourceURL: url,
                keepLocation: options.keepLocation,
                keepCameraMetadata: options.keepCameraMetadata,
                width: framedImage.width,
                height: framedImage.height,
                quality: options.quality
            )
            CGImageDestinationAddImage(destination, framedImage, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ImageProcessorError.cannotWrite
            }

            return ExportResult(
                url: outputURL,
                dimensions: "\(framedImage.width) × \(framedImage.height)",
                format: actualFormat
            )
        }
    }

    /// 日期戳：优先用拍摄时间，缺失时用当前时间
    static func dateStampText(_ date: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date ?? Date())
    }

    private static func loadImage(from url: URL, draft: Bool) throws -> CIImage {
        if let rawFilter = CIRAWFilter(imageURL: url) {
            rawFilter.isDraftModeEnabled = draft
            if rawFilter.isLensCorrectionSupported {
                rawFilter.isLensCorrectionEnabled = true
            }
            if rawFilter.isLocalToneMapSupported {
                rawFilter.localToneMapAmount = 0.42
            }
            if rawFilter.isSharpnessSupported {
                rawFilter.sharpnessAmount = 0.24
            }
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let orientationNumber = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value,
               let orientation = CGImagePropertyOrientation(rawValue: orientationNumber) {
                rawFilter.orientation = orientation
            }
            if let output = rawFilter.outputImage {
                return output
            }
            // A recognized RAW container must not silently fall back to its embedded
            // JPEG preview, because that would make a low-resolution "full-size" export.
            throw ImageProcessorError.unsupportedRAW
        }

        let rawExtensions = ["arw", "srf", "sr2", "dng"]
        let fallback = CIImage(
            contentsOf: url,
            options: [.applyOrientationProperty: true]
        )
        guard let fallback else {
            throw ImageProcessorError.unsupportedRAW
        }

        if rawExtensions.contains(url.pathExtension.lowercased()) {
            let sourceAsset = try metadata(for: url)
            let expectedLongEdge = max(sourceAsset.pixelWidth, sourceAsset.pixelHeight)
            let fallbackLongEdge = max(fallback.extent.width, fallback.extent.height)
            if expectedLongEdge > 0, fallbackLongEdge < Double(expectedLongEdge) * 0.90 {
                throw ImageProcessorError.unsupportedRAW
            }
        }
        return fallback
    }

    private static func normalizedExtent(of image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.minX != 0 || extent.minY != 0 else { return image }
        return image.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
    }

    private static func applyFilm(
        to input: CIImage,
        profile: FilmProfile,
        settings: FilmSettings,
        intensity: Double,
        grainScale: Double,
        suppressVignette: Bool = false
    ) -> CIImage {
        // 强度支持 0…2（100% 为标准浓度，150%/200% 为加浓）。
        let amount = min(max(intensity, 0), 2)
        let baseAmount = min(amount, 1)
        // 超过 100% 的部分：在满强度结果上再叠一层同样的胶片底色，
        // 让色彩矩阵、层次和颗粒真正“变浓”，而不是简单拉对比。
        let extraAmount = max(amount - 1, 0)
        let extent = input.extent
        let source = input.clampedToExtent()

        var graded = blend(base: source, with: neutralize(source, profile: profile), amount: baseAmount)

        if extraAmount > 0.001 {
            graded = blend(
                base: graded,
                with: neutralize(graded, profile: profile),
                amount: extraAmount
            )
            graded = graded.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1 + 0.16 * extraAmount,
                kCIInputSaturationKey: 1 + 0.14 * extraAmount,
                kCIInputBrightnessKey: 0
            ])
        }

        // 取样白平衡是手动校正，不受胶片强度影响
        graded = AdvancedGrade.applyWhiteBalance(graded, settings: settings)

        graded = graded.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputEVKey: settings.exposure * amount
        ])

        let targetTemperature = 6500 + (settings.temperature - 6500) * amount
        graded = graded.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: targetTemperature, y: settings.tint * 0.8 * amount)
        ])

        let shadowAmount = min(max((settings.shadows + settings.blacks * 0.35) / 100 * amount, -1), 1)
        let highlightAmount = min(max(1 - (settings.highlights + settings.whites * 0.30) / 100 * 0.65 * amount, 0.25), 1.5)
        graded = graded.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputRadius": 8.0,
            "inputShadowAmount": shadowAmount,
            "inputHighlightAmount": highlightAmount
        ])

        let fade = min(max(settings.fade / 100 * amount, 0), 0.30)
        graded = graded.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": CIVector(x: 0, y: fade),
            "inputPoint1": CIVector(x: 0.25, y: 0.25 + fade * 0.35),
            "inputPoint2": CIVector(x: 0.50, y: 0.50),
            "inputPoint3": CIVector(x: 0.75, y: 0.75 - fade * 0.20),
            "inputPoint4": CIVector(x: 1, y: 1)
        ])

        let contrast = 1 + settings.contrast / 100 * 0.45 * amount
        let saturation = 1 + settings.saturation / 100 * amount
        graded = graded.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: contrast,
            kCIInputSaturationKey: saturation,
            kCIInputBrightnessKey: 0
        ])
        graded = graded.applyingFilter("CIVibrance", parameters: [
            kCIInputAmountKey: settings.vibrance / 100 * amount
        ])

        // 8 段 HSL 与手动曲线：属于精细校正，按满强度应用
        graded = AdvancedGrade.applyHSL(graded, settings: settings)
        graded = AdvancedGrade.applyCurve(graded, settings: settings)

        let clarity = settings.clarity * amount
        if clarity > 0.2 {
            graded = graded.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: max(2, min(extent.width, extent.height) * 0.0022),
                kCIInputIntensityKey: clarity / 100 * 0.62
            ])
        } else if clarity < -0.2 {
            graded = graded
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: min(3, abs(clarity) / 28)
                ])
                .cropped(to: extent)
        }

        let sharpness = settings.sharpness / 100 * amount
        if sharpness > 0.01 {
            graded = graded.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: min(sharpness * 1.4, 1)
            ])
        }

        let vignette = suppressVignette ? 0 : settings.vignette / 100 * amount
        if vignette > 0.001 {
            graded = graded.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: vignette * 1.8,
                kCIInputRadiusKey: min(extent.width, extent.height) * 0.62
            ])
        }

        let grain = settings.grain / 100 * amount
        if grain > 0.001, let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let noise = random
                .transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0),
                    "inputGVector": CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0),
                    "inputBVector": CIVector(x: 0.30, y: 0.30, z: 0.30, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: grain * 0.32)
                ])
                .cropped(to: extent)
            graded = noise.applyingFilter("CISoftLightBlendMode", parameters: [
                kCIInputBackgroundImageKey: graded
            ])
        }

        return graded
            .cropped(to: extent)
            .applyingFilter("CIColorClamp")
    }

    private static func neutralize(_ image: CIImage, profile: FilmProfile) -> CIImage {
        switch profile {
        case .neutral:
            return image
        case .gold:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.04, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.00, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.01, z: 0.94, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .cinestill:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.92, y: 0, z: 0.04, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 0.98, z: 0.04, w: 0),
                "inputBVector": CIVector(x: 0.02, y: 0.06, z: 1.08, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .portra:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.03, y: 0.01, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 0.99, z: 0.01, w: 0),
                "inputBVector": CIVector(x: 0.01, y: 0.01, z: 0.96, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .film135t:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.01, y: 0.02, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.00, y: 0.98, z: 0.03, w: 0),
                "inputBVector": CIVector(x: 0.00, y: 0.04, z: 1.04, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .classicChrome:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.96, y: 0.02, z: 0.02, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 0.98, z: 0.04, w: 0),
                "inputBVector": CIVector(x: 0.01, y: 0.06, z: 0.98, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .pro400h:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.98, y: 0.02, z: 0.02, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.02, z: 0.03, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.01, z: 1.01, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .velvia50:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.06, y: 0.01, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.04, z: 0.01, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.02, z: 0.98, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .ektar100:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.05, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.99, z: 0.01, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.03, z: 1.02, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .superia400:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.98, y: 0.01, z: 0.01, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.04, z: 0.02, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.04, z: 0.99, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .vision250d:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.02, y: 0.01, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.0, z: 0.02, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.03, z: 0.97, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .classicNegative:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.05, y: 0.03, z: -0.02, w: 0),
                "inputGVector": CIVector(x: -0.01, y: 1.00, z: 0.03, w: 0),
                "inputBVector": CIVector(x: -0.03, y: 0.07, z: 1.00, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .nostalgicNeg:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.06, y: 0.02, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.00, z: -0.01, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.04, z: 0.93, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .realaAce:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.02, y: 0.01, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.03, z: 0.01, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.02, z: 0.99, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .eterna:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.95, y: 0.02, z: 0.03, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 0.99, z: 0.03, w: 0),
                "inputBVector": CIVector(x: 0.02, y: 0.05, z: 1.02, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .colorPlus200:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.05, y: 0.01, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.00, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.02, z: 0.92, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .ultramax400:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.06, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.01, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.03, z: 0.94, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .c200:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.98, y: 0.02, z: 0.01, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.04, z: 0.02, w: 0),
                "inputBVector": CIVector(x: 0.01, y: 0.04, z: 0.98, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .ektachrome100:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.04, y: 0, z: 0.01, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.00, z: 0.01, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.02, z: 1.04, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .vision500t:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.03, y: 0.02, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 0.98, z: 0.03, w: 0),
                "inputBVector": CIVector(x: 0.02, y: 0.06, z: 1.08, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .dazzFxnR:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.02, y: 0.01, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.03, z: 0.02, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.02, z: 0.98, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .dazzCCDR:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.04, y: 0.03, z: 0.01, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.00, z: 0.02, w: 0),
                "inputBVector": CIVector(x: 0.02, y: 0.03, z: 0.96, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .dazzDClassic:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.03, y: 0.02, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.99, z: 0.02, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.04, z: 0.94, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .dazzGRDR:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.96, y: 0.02, z: 0.02, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.01, z: 0.03, w: 0),
                "inputBVector": CIVector(x: 0.01, y: 0.03, z: 1.04, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .dazzDFunS:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.06, y: 0.01, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.02, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.02, z: 0.96, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        case .dazzClassicU:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.04, y: 0.02, z: 0, w: 0),
                "inputGVector": CIVector(x: 0.01, y: 1.00, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0.04, z: 0.91, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        default:
            return image
        }
    }

    private static func blend(base: CIImage, with image: CIImage, amount: Double) -> CIImage {
        guard amount < 0.999 else { return image }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: base,
            kCIInputTimeKey: amount
        ])
    }

    private static func exportProperties(
        sourceURL: URL,
        keepLocation: Bool,
        keepCameraMetadata: Bool,
        width: Int,
        height: Int,
        quality: Double
    ) -> [CFString: Any] {
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.7), 1.0),
            kCGImagePropertyOrientation: 1,
            kCGImagePropertyPixelWidth: width,
            kCGImagePropertyPixelHeight: height,
            kCGImageDestinationEmbedThumbnail: true
        ]

        guard keepCameraMetadata,
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return properties
        }

        if let exif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            var clean = exif
            clean[kCGImagePropertyExifPixelXDimension] = width
            clean[kCGImagePropertyExifPixelYDimension] = height
            properties[kCGImagePropertyExifDictionary] = clean
        }

        if let tiff = sourceProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var iptc = sourceProperties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            if !keepLocation {
                iptc.removeValue(forKey: kCGImagePropertyIPTCExtLocationGPSLatitude)
                iptc.removeValue(forKey: kCGImagePropertyIPTCExtLocationGPSLongitude)
                iptc.removeValue(forKey: kCGImagePropertyIPTCExtRatingRegionGPSLatitude)
                iptc.removeValue(forKey: kCGImagePropertyIPTCExtRatingRegionGPSLongitude)
            }
            properties[kCGImagePropertyIPTCDictionary] = iptc
        }
        if keepLocation, let gps = sourceProperties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            properties[kCGImagePropertyGPSDictionary] = gps
        }

        return properties
    }
}

enum MosaicProcessor {
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any
    ])

    static func apply(_ strokes: [MosaicStroke], to image: CGImage) -> CGImage {
        guard !strokes.isEmpty else { return image }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

        let source = CIImage(cgImage: image)
        let minDimension = Double(min(width, height))
        let blockSize = max(7, floor(minDimension * 0.032))
        let pixelated = source
            .applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: blockSize,
                kCIInputCenterKey: CIVector(x: source.extent.midX, y: source.extent.midY)
            ])
            .cropped(to: source.extent)

        guard let mask = makeMask(strokes, width: width, height: height),
              let blend = CIFilter(name: "CIBlendWithMask")
        else {
            return image
        }
        blend.setValue(pixelated, forKey: kCIInputImageKey)
        blend.setValue(source, forKey: kCIInputBackgroundImageKey)
        blend.setValue(CIImage(cgImage: mask), forKey: kCIInputMaskImageKey)

        guard let output = blend.outputImage?.cropped(to: source.extent),
              let result = context.createCGImage(output, from: source.extent)
        else {
            return image
        }
        return result
    }

    private static func makeMask(
        _ strokes: [MosaicStroke],
        width: Int,
        height: Int
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setFillColor(gray: 1, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let minDimension = CGFloat(min(width, height))
        for stroke in strokes {
            let points = stroke.points.map {
                CGPoint(
                    x: CGFloat($0.x) * CGFloat(width),
                    y: (1 - CGFloat($0.y)) * CGFloat(height)
                )
            }
            let lineWidth = max(6, CGFloat(stroke.brushSize) * minDimension)
            context.setLineWidth(lineWidth)

            if points.count == 1, let point = points.first {
                let radius = lineWidth / 2
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: lineWidth,
                        height: lineWidth
                    )
                )
            } else if let first = points.first {
                context.beginPath()
                context.move(to: first)
                for point in points.dropFirst() {
                    context.addLine(to: point)
                }
                context.strokePath()
            }
        }
        return context.makeImage()
    }
}
