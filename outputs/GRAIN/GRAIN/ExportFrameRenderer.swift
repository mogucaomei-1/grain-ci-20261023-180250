import CoreGraphics
import CoreText
import Foundation

/// 导出时的胶片边框、日期戳与水印。纯 CoreGraphics/CoreText 实现，
/// 不依赖 UIKit，方便单独验证。
enum ExportFrameRenderer {
    static func render(
        _ image: CGImage,
        options: ExportOptions,
        dateText: String?
    ) -> CGImage {
        let hasWatermark = !options.watermark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDate = options.includeDateStamp && (dateText?.isEmpty == false)
        guard options.frame != .none || hasWatermark || hasDate else { return image }

        let longEdge = CGFloat(max(image.width, image.height))
        let metrics = layout(for: options.frame, longEdge: longEdge)

        let canvasWidth = image.width + Int((metrics.horizontal * 2).rounded())
        let canvasHeight = image.height
            + Int((metrics.top + metrics.bottom).rounded())
        guard canvasWidth > 0, canvasHeight > 0, canvasWidth < 40_000, canvasHeight < 40_000 else {
            return image
        }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high

        if options.frame != .none {
            context.setFillColor(metrics.paperColor)
            context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        }

        let contentRect = CGRect(
            x: metrics.horizontal,
            y: metrics.bottom,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        context.draw(image, in: contentRect)

        if hasDate, let dateText {
            drawDateStamp(
                dateText,
                in: contentRect,
                insidePhoto: options.frame == .none,
                context: context
            )
        }

        if hasWatermark {
            drawWatermark(
                options.watermark.trimmingCharacters(in: .whitespacesAndNewlines),
                in: contentRect,
                context: context
            )
        }

        return context.makeImage() ?? image
    }

    // MARK: - 版式

    private struct Layout {
        var horizontal: CGFloat
        var top: CGFloat
        var bottom: CGFloat
        var paperColor: CGColor
    }

    private static func layout(for frame: ExportFrame, longEdge: CGFloat) -> Layout {
        let paper = CGColor(
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [0.965, 0.953, 0.925, 1]
        ) ?? CGColor(gray: 0.96, alpha: 1)

        switch frame {
        case .none:
            return Layout(horizontal: 0, top: 0, bottom: 0, paperColor: paper)
        case .thin:
            let inset = max(10, (longEdge * 0.022).rounded())
            return Layout(
                horizontal: inset,
                top: inset,
                bottom: inset + max(14, (longEdge * 0.014).rounded()),
                paperColor: paper
            )
        case .wide:
            let inset = max(18, (longEdge * 0.06).rounded())
            return Layout(
                horizontal: inset,
                top: inset,
                bottom: inset + max(26, (longEdge * 0.035).rounded()),
                paperColor: paper
            )
        case .instant:
            let inset = max(14, (longEdge * 0.055).rounded())
            return Layout(
                horizontal: inset,
                top: inset,
                bottom: max(56, (longEdge * 0.20).rounded()),
                paperColor: paper
            )
        }
    }

    // MARK: - 文字

    private static func drawDateStamp(
        _ text: String,
        in contentRect: CGRect,
        insidePhoto: Bool,
        context: CGContext
    ) {
        let fontSize = max(9, contentRect.width * 0.019)
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, fontSize, nil)
        let line = makeLine(text, font: font, color: CGColor(gray: 0.28, alpha: 1))

        if insidePhoto {
            // 无边框时贴在照片左下角，加一层暗底保证可读
            let padding = fontSize * 0.7
            let rect = CGRect(
                x: contentRect.minX + padding,
                y: contentRect.minY + padding,
                width: contentRect.width - padding * 2,
                height: fontSize * 1.9
            )
            context.setFillColor(CGColor(gray: 0, alpha: 0.34))
            context.fill(rect)
            draw(
                line,
                in: rect,
                font: font,
                horizontalPadding: padding * 0.55,
                context: context
            )
        } else {
            // 有边框时居中写在下方留白里
            let bandHeight = max(contentRect.minY, fontSize * 1.4)
            let rect = CGRect(
                x: contentRect.minX,
                y: 0,
                width: contentRect.width,
                height: bandHeight
            )
            draw(line, in: rect, font: font, centered: true, context: context)
        }
    }

    private static func drawWatermark(
        _ text: String,
        in contentRect: CGRect,
        context: CGContext
    ) {
        let fontSize = max(9, contentRect.width * 0.017)
        let font = CTFontCreateWithName("HelveticaNeue-Light" as CFString, fontSize, nil)
        let line = makeLine(text, font: font, color: CGColor(gray: 1, alpha: 0.82))

        let padding = fontSize * 0.85
        let rect = CGRect(
            x: contentRect.minX + padding,
            y: contentRect.minY + padding,
            width: contentRect.width - padding * 2,
            height: fontSize * 1.8
        )
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -fontSize * 0.06),
            blur: fontSize * 0.5,
            color: CGColor(gray: 0, alpha: 0.55)
        )
        draw(line, in: rect, font: font, rightAligned: true, context: context)
        context.restoreGState()
    }

    private static func makeLine(
        _ text: String,
        font: CTFont,
        color: CGColor
    ) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        return CTLineCreateWithAttributedString(attributed)
    }

    private static func draw(
        _ line: CTLine,
        in rect: CGRect,
        font: CTFont,
        centered: Bool = false,
        rightAligned: Bool = false,
        horizontalPadding: CGFloat = 0,
        context: CGContext
    ) {
        let typographicWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var x = rect.minX + horizontalPadding
        if centered {
            x = rect.midX - typographicWidth / 2
        } else if rightAligned {
            x = rect.maxX - horizontalPadding - typographicWidth
        }
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let y = rect.midY - (ascent + descent) / 2 + descent

        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}
