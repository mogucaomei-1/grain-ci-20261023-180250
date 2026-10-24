import SwiftUI

struct CropEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var crop = CropTransform.identity
    @State private var displayImage: CGImage?

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                GeometryReader { proxy in
                    if let displayImage {
                        let bounds = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 16, dy: 18)
                        let imageRect = fittedRect(for: displayImage, in: bounds)
                        ZStack {
                            Image(decorative: displayImage, scale: 1)
                                .resizable()
                                .scaledToFit()
                                .frame(width: imageRect.width, height: imageRect.height)
                                .position(x: imageRect.midX, y: imageRect.midY)

                            CropSelectionOverlay(
                                crop: $crop,
                                displaySize: imageRect.size
                            )
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)
                        }
                    } else {
                        ProgressView().tint(GrainTheme.paper)
                    }
                }

                controls
            }
        }
        .onAppear {
            crop = editor.crop
            updateDisplayImage()
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button("取消") { dismiss() }
                .foregroundStyle(GrainTheme.muted)
            Spacer()
            Text("裁剪与构图")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
            Button("完成") {
                editor.updateCrop(crop)
                dismiss()
            }
            .fontWeight(.bold)
            .foregroundStyle(GrainTheme.accent)
        }
        .font(.system(size: 12, design: .rounded))
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(CropAspect.allCases) { aspect in
                        Button {
                            applyAspect(aspect)
                        } label: {
                            Text(aspect.title)
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(crop.aspect == aspect ? GrainTheme.black : GrainTheme.paper)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(
                                    crop.aspect == aspect ? GrainTheme.paper : GrainTheme.raised,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 28) {
                toolButton("rotate.right") {
                    crop.rotationQuarterTurns = (crop.rotationQuarterTurns + 1) % 4
                    updateDisplayImage()
                }
                toolButton("arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    crop.flipHorizontal.toggle()
                    updateDisplayImage()
                }
                toolButton("arrow.up.and.down.righttriangle.up.righttriangle.down") {
                    crop.flipVertical.toggle()
                    updateDisplayImage()
                }
                toolButton("arrow.counterclockwise") {
                    crop = .identity
                    updateDisplayImage()
                }
            }
            .padding(.bottom, 18)
        }
        .padding(.top, 10)
        .background(GrainTheme.surface)
    }

    private func toolButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(GrainTheme.paper)
                .frame(width: 44, height: 38)
                .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private func updateDisplayImage() {
        guard let full = editor.fullGradedPreview ?? editor.editedPreview ?? editor.originalPreview else {
            displayImage = nil
            return
        }
        var orientationOnly = crop
        orientationOnly.aspect = .original
        orientationOnly.normalizedX = 0
        orientationOnly.normalizedY = 0
        orientationOnly.normalizedWidth = 1
        orientationOnly.normalizedHeight = 1
        displayImage = CropProcessor.apply(orientationOnly, to: full)
    }

    private func applyAspect(_ aspect: CropAspect) {
        crop.aspect = aspect
        if aspect == .original {
            crop.normalizedX = 0
            crop.normalizedY = 0
            crop.normalizedWidth = 1
            crop.normalizedHeight = 1
        } else if let ratio = aspect.ratio, let displayImage {
            let imageRatio = Double(displayImage.width) / Double(displayImage.height)
            var width = 1.0
            var height = imageRatio / ratio
            if height > 1 {
                height = 1
                width = ratio / imageRatio
            }
            crop.normalizedX = (1 - width) / 2
            crop.normalizedY = (1 - height) / 2
            crop.normalizedWidth = width
            crop.normalizedHeight = height
        }
    }

    private func fittedRect(for image: CGImage, in bounds: CGRect) -> CGRect {
        let imageRatio = CGFloat(image.width) / CGFloat(image.height)
        let boundsRatio = bounds.width / max(bounds.height, 1)
        let size: CGSize
        if imageRatio > boundsRatio {
            size = CGSize(width: bounds.width, height: bounds.width / imageRatio)
        } else {
            size = CGSize(width: bounds.height * imageRatio, height: bounds.height)
        }
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct CropSelectionOverlay: View {
    @Binding var crop: CropTransform
    let displaySize: CGSize
    @State private var dragOrigin: CropTransform?
    @State private var lastHapticStep: Int = 0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let rect = CGRect(
                x: crop.normalizedX * width,
                y: crop.normalizedY * height,
                width: crop.normalizedWidth * width,
                height: crop.normalizedHeight * height
            )

            ZStack {
                Canvas { context, size in
                    var outside = Path(CGRect(origin: .zero, size: size))
                    outside.addRect(rect)
                    context.fill(
                        outside,
                        with: .color(.black.opacity(0.54)),
                        style: FillStyle(eoFill: true)
                    )
                }

                Rectangle()
                    .stroke(Color.white, lineWidth: 1.2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                cropGrid(rect: rect)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(moveGesture(rect: rect, width: width, height: height))

                ForEach(Corner.allCases, id: \.self) { corner in
                    Circle()
                        .fill(GrainTheme.paper)
                        .overlay(Circle().stroke(GrainTheme.black, lineWidth: 1))
                        .frame(width: 24, height: 24)
                        .position(corner.point(in: rect))
                        .gesture(resizeGesture(corner, rect: rect, width: width, height: height))
                }
            }
        }
    }

    @ViewBuilder
    private func cropGrid(rect: CGRect) -> some View {
        Path { path in
            for fraction in [1.0 / 3, 2.0 / 3] {
                let x = rect.minX + rect.width * fraction
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                let y = rect.minY + rect.height * fraction
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.38), lineWidth: 0.6)
    }

    private func moveGesture(rect: CGRect, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = crop
                    GrainHaptics.prepare()
                }
                guard let origin = dragOrigin else { return }
                crop.normalizedX = min(
                    max(origin.normalizedX + Double(value.translation.width / width), 0),
                    1 - crop.normalizedWidth
                )
                crop.normalizedY = min(
                    max(origin.normalizedY + Double(value.translation.height / height), 0),
                    1 - crop.normalizedHeight
                )
                let step = Int((crop.normalizedX * 50 + crop.normalizedY * 50).rounded())
                if step != lastHapticStep {
                    lastHapticStep = step
                    GrainHaptics.selection()
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func resizeGesture(
        _ corner: Corner,
        rect: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = crop
                    GrainHaptics.prepare()
                }
                guard let origin = dragOrigin else { return }
                let dx = Double(value.translation.width / width)
                let dy = Double(value.translation.height / height)
                var x = origin.normalizedX
                var y = origin.normalizedY
                var w = origin.normalizedWidth
                var h = origin.normalizedHeight

                if corner.isLeft {
                    x = min(max(x + dx, 0), x + w - 0.08)
                    w = origin.normalizedX + origin.normalizedWidth - x
                } else {
                    w = min(max(origin.normalizedWidth + dx, 0.08), 1 - x)
                }
                if corner.isTop {
                    y = min(max(y + dy, 0), y + h - 0.08)
                    h = origin.normalizedY + origin.normalizedHeight - y
                } else {
                    h = min(max(origin.normalizedHeight + dy, 0.08), 1 - y)
                }
                crop.normalizedX = x
                crop.normalizedY = y
                crop.normalizedWidth = w
                crop.normalizedHeight = h
                let step = Int((w * 50 + h * 50).rounded())
                if step != lastHapticStep {
                    lastHapticStep = step
                    GrainHaptics.selection()
                }
            }
            .onEnded { _ in
                if let ratio = crop.aspect.ratio, displaySize.width > 0, displaySize.height > 0 {
                    normalizeAspect(ratio, displaySize: displaySize)
                }
                dragOrigin = nil
            }
    }

    private func normalizeAspect(_ ratio: Double, displaySize: CGSize) {
        let imageRatio = Double(displaySize.width / displaySize.height)
        var width = crop.normalizedWidth
        var height = width * imageRatio / ratio
        if height > 1 {
            height = 1
            width = height * ratio / imageRatio
        }
        let centerX = crop.normalizedX + crop.normalizedWidth / 2
        let centerY = crop.normalizedY + crop.normalizedHeight / 2
        crop.normalizedWidth = min(max(width, 0.08), 1)
        crop.normalizedHeight = min(max(height, 0.08), 1)
        crop.normalizedX = min(max(centerX - crop.normalizedWidth / 2, 0), 1 - crop.normalizedWidth)
        crop.normalizedY = min(max(centerY - crop.normalizedHeight / 2, 0), 1 - crop.normalizedHeight)
    }
}

enum Corner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: isLeft ? rect.minX : rect.maxX,
            y: isTop ? rect.minY : rect.maxY
        )
    }
}
