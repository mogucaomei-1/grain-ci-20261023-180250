import CoreGraphics
import CoreImage
import Foundation

/// 进阶调色：影调曲线、8 段 HSL、白平衡取样。
/// 全部是纯函数，便于在无设备环境下单独验证数学正确性。
enum AdvancedGrade {
    // MARK: - 影调曲线

    /// 用 5 个等距控制点生成 CIToneCurve 参数；非法输入返回 nil（不改变画面）
    static func curveVectors(_ curve: [Double]) -> [CIVector]? {
        guard curve.count == 5 else { return nil }
        let clamped = curve.map { min(max($0, 0), 1) }
        let xs: [Double] = [0, 0.25, 0.5, 0.75, 1]
        return zip(xs, clamped).map { CIVector(x: $0, y: $1) }
    }

    // MARK: - HSL 立方体

    /// 生成 CIColorCube 需要的三维查找表（sRGB 伽马空间，r 变化最快）。
    static func hslCubeData(
        hueShift: [Double],
        saturationShift: [Double],
        luminanceShift: [Double],
        dimension: Int = 32
    ) -> Data? {
        guard hueShift.count == FilmSettings.hslBandCount,
              saturationShift.count == FilmSettings.hslBandCount,
              luminanceShift.count == FilmSettings.hslBandCount,
              dimension >= 2, dimension <= 64
        else { return nil }

        let size = dimension * dimension * dimension * 4
        var cube = [Float](repeating: 0, count: size)
        let denominator = Double(dimension - 1)

        for blueIndex in 0..<dimension {
            let b = Double(blueIndex) / denominator
            for greenIndex in 0..<dimension {
                let g = Double(greenIndex) / denominator
                for redIndex in 0..<dimension {
                    let r = Double(redIndex) / denominator
                    var hsv = rgbToHSV(r: r, g: g, b: b)

                    let weights = bandWeights(hue: hsv.h)
                    var hueOffset = 0.0
                    var saturationFactor = 0.0
                    var luminanceOffset = 0.0
                    for band in 0..<FilmSettings.hslBandCount {
                        let weight = weights[band]
                        guard weight > 0.0001 else { continue }
                        hueOffset += hueShift[band] * weight
                        saturationFactor += saturationShift[band] / 100 * weight
                        luminanceOffset += luminanceShift[band] / 100 * weight
                    }

                    hsv.h = (hsv.h + hueOffset).truncatingRemainder(dividingBy: 360)
                    if hsv.h < 0 { hsv.h += 360 }
                    hsv.s = min(max(hsv.s * (1 + saturationFactor), 0), 1)
                    hsv.v = min(max(hsv.v + luminanceOffset * 0.22, 0), 1)

                    let rgb = hsvToRGB(h: hsv.h, s: hsv.s, v: hsv.v)
                    let offset = ((blueIndex * dimension + greenIndex) * dimension + redIndex) * 4
                    cube[offset] = Float(min(max(rgb.r, 0), 1))
                    cube[offset + 1] = Float(min(max(rgb.g, 0), 1))
                    cube[offset + 2] = Float(min(max(rgb.b, 0), 1))
                    cube[offset + 3] = 1
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// 8 个色带中心（每 45°）之间的三角权重，保证过渡平滑
    private static func bandWeights(hue: Double) -> [Double] {
        var weights = [Double](repeating: 0, count: FilmSettings.hslBandCount)
        let position = hue / 45
        let lower = Int(floor(position)) % FilmSettings.hslBandCount
        let fraction = position - floor(position)
        let upper = (lower + 1) % FilmSettings.hslBandCount
        weights[lower] = 1 - fraction
        weights[upper] = fraction
        return weights
    }

    private static func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum
        var hue = 0.0
        if delta > 0.00001 {
            if maximum == r {
                hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maximum == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }
        let saturation = maximum <= 0.00001 ? 0 : delta / maximum
        return (hue, saturation, maximum)
    }

    private static func hsvToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let chroma = v * s
        let sector = h / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - chroma
        var rgb: (Double, Double, Double)
        switch Int(floor(sector)) % 6 {
        case 0: rgb = (chroma, x, 0)
        case 1: rgb = (x, chroma, 0)
        case 2: rgb = (0, chroma, x)
        case 3: rgb = (0, x, chroma)
        case 4: rgb = (x, 0, chroma)
        default: rgb = (chroma, 0, x)
        }
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }

    // MARK: - 白平衡取样

    /// 从预览位图取一小块的平均色（sRGB 0…1）；坐标原点在左上角
    static func sampleColor(
        from image: CGImage,
        normalizedX: Double,
        normalizedY: Double
    ) -> (red: Double, green: Double, blue: Double)? {
        guard image.width > 1, image.height > 1 else { return nil }
        let side = max(8, min(image.width, image.height) / 64)
        let centerX = Int((min(max(normalizedX, 0), 1) * Double(image.width)).rounded())
        let centerY = Int((min(max(normalizedY, 0), 1) * Double(image.height)).rounded())
        let originX = min(max(centerX - side / 2, 0), max(image.width - side, 0))
        let originY = min(max(centerY - side / 2, 0), max(image.height - side, 0))
        let rect = CGRect(x: originX, y: originY, width: side, height: side)
        guard let patch = image.cropping(to: rect) else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        guard red > 0.02 || green > 0.02 || blue > 0.02 else { return nil }
        return (red, green, blue)
    }

    /// 由取样色计算线性空间增益，使该色接近中性灰，同时尽量保持整体亮度
    static func whiteBalanceGains(
        forSample sample: (red: Double, green: Double, blue: Double)
    ) -> (red: Double, green: Double, blue: Double) {
        let linearRed = max(srgbToLinear(sample.red), 0.004)
        let linearGreen = max(srgbToLinear(sample.green), 0.004)
        let linearBlue = max(srgbToLinear(sample.blue), 0.004)
        let average = (linearRed + linearGreen + linearBlue) / 3

        var red = average / linearRed
        var green = average / linearGreen
        var blue = average / linearBlue

        // 归一化到几何平均 1，避免取样后整体变亮或变暗
        let geometricMean = pow(red * green * blue, 1.0 / 3)
        if geometricMean > 0.0001 {
            red /= geometricMean
            green /= geometricMean
            blue /= geometricMean
        }
        let clamp: (Double) -> Double = { min(max($0, 0.35), 3.0) }
        return (clamp(red), clamp(green), clamp(blue))
    }

    private static func srgbToLinear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    // MARK: - Core Image 应用

    static func applyWhiteBalance(_ image: CIImage, settings: FilmSettings) -> CIImage {
        guard settings.hasWhiteBalanceShift else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: settings.whiteBalanceRed, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: settings.whiteBalanceGreen, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: settings.whiteBalanceBlue, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    static func applyCurve(_ image: CIImage, settings: FilmSettings) -> CIImage {
        guard settings.hasCustomCurve,
              let points = curveVectors(settings.curve)
        else { return image }
        return image.applyingFilter("CIToneCurve", parameters: [
            "inputPoint0": points[0],
            "inputPoint1": points[1],
            "inputPoint2": points[2],
            "inputPoint3": points[3],
            "inputPoint4": points[4]
        ])
    }

    static func applyHSL(_ image: CIImage, settings: FilmSettings) -> CIImage {
        guard settings.hasHSLAdjustment,
              let cube = hslCubeData(
                  hueShift: settings.hueShift,
                  saturationShift: settings.saturationShift,
                  luminanceShift: settings.luminanceShift
              )
        else { return image }

        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
           let filter = CIFilter(name: "CIColorCubeWithColorSpace") {
            filter.setValue(32, forKey: "inputCubeDimension")
            filter.setValue(cube, forKey: "inputCubeData")
            filter.setValue(colorSpace, forKey: "inputColorSpace")
            filter.setValue(image, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                return output
            }
        }
        if let filter = CIFilter(name: "CIColorCube") {
            filter.setValue(32, forKey: "inputCubeDimension")
            filter.setValue(cube, forKey: "inputCubeData")
            filter.setValue(image, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                return output
            }
        }
        return image
    }
}
