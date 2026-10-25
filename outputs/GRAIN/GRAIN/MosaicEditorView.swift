import SwiftUI

struct MosaicEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var currentPoints: [MosaicPoint] = []
    @State private var brushSize = 0.08
    @State private var lastBrushHapticSize = 0.08
    @State private var showClearConfirmation = false

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            if let image = editor.editedPreview {
                GeometryReader { proxy in
                    let rect = fittedRect(for: image, in: proxy.size)
                    ZStack {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)

                        Canvas { context, size in
                            for stroke in editor.mosaicStrokes {
                                draw(
                                    stroke.points,
                                    brushSize: stroke.brushSize,
                                    context: &context,
                                    size: size,
                                    committed: true
                                )
                            }
                            draw(
                                currentPoints,
                                brushSize: brushSize,
                                context: &context,
                                size: size,
                                committed: false
                            )
                        }
                        .allowsHitTesting(false)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(drawingGesture(canvasSize: rect.size))
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
            } else {
                ProgressView()
                    .tint(GrainTheme.paper)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomControls
            }
        }
        .statusBarHidden()
        .confirmationDialog(
            "清除全部马赛克？",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                editor.clearMosaicStrokes()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 38, height: 38)
                    .background(GrainTheme.raised, in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("马赛克")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundStyle(GrainTheme.paper)
                Text("用手指涂抹需要隐藏的区域")
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(GrainTheme.muted)
            }

            Spacer()

            Button {
                editor.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(editor.canUndo ? GrainTheme.paper : GrainTheme.muted)
                    .frame(width: 36, height: 36)
                    .background(GrainTheme.raised, in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .disabled(!editor.canUndo)
            .accessibilityLabel("撤销马赛克")

            Button {
                showClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 36, height: 36)
                    .background(GrainTheme.raised, in: Circle())
                    .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .disabled(editor.mosaicStrokes.isEmpty)
            .accessibilityLabel("清除全部马赛克")

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(GrainTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(GrainTheme.muted)
                Slider(value: $brushSize, in: 0.035...0.18)
                    .tint(GrainTheme.accent)
                    .onChange(of: brushSize) { _, value in
                        guard abs(value - lastBrushHapticSize) >= 0.012 else { return }
                        lastBrushHapticSize = value
                        GrainHaptics.selection(enabled: hapticsEnabled)
                    }
                Image(systemName: "circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(GrainTheme.muted)
            }

            Text("松开手指后应用马赛克 · 马赛克会保留在最终导出中")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [.clear, GrainTheme.black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func drawingGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = MosaicPoint(
                    x: min(max(value.location.x / max(canvasSize.width, 1), 0), 1),
                    y: min(max(value.location.y / max(canvasSize.height, 1), 0), 1)
                )
                if let last = currentPoints.last {
                    let dx = point.x - last.x
                    let dy = point.y - last.y
                    if hypot(dx, dy) < 0.0025 {
                        return
                    }
                }
                currentPoints.append(point)
            }
            .onEnded { _ in
                guard !currentPoints.isEmpty else { return }
                let stroke = MosaicStroke(
                    points: currentPoints,
                    brushSize: brushSize
                )
                currentPoints = []
                editor.addMosaicStroke(stroke)
                GrainHaptics.mediumImpact(enabled: hapticsEnabled)
            }
    }

    private func fittedRect(for image: CGImage, in size: CGSize) -> CGRect {
        let imageRatio = CGFloat(image.width) / CGFloat(image.height)
        let sizeRatio = size.width / max(size.height, 1)
        let fitted: CGSize
        if imageRatio > sizeRatio {
            fitted = CGSize(width: size.width, height: size.width / imageRatio)
        } else {
            fitted = CGSize(width: size.height * imageRatio, height: size.height)
        }
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func draw(
        _ points: [MosaicPoint],
        brushSize: Double,
        context: inout GraphicsContext,
        size: CGSize,
        committed: Bool
    ) {
        guard !points.isEmpty else { return }
        let points = points.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        guard let first = points.first else { return }

        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }

        let lineWidth = max(12, brushSize * min(size.width, size.height))
        context.stroke(
            path,
            with: .color(.white.opacity(committed ? 0.10 : 0.25)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
        if !committed {
            context.stroke(
                path,
                with: .color(GrainTheme.paper.opacity(0.58)),
                style: StrokeStyle(lineWidth: 1, dash: [5, 5])
            )
        }
    }
}
