import SwiftUI

/// 进阶调色面板：影调曲线、8 段 HSL、白平衡取样
struct AdvancedGradeSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    let onStartPickingWhiteBalance: () -> Void

    @State private var band = 1

    private let bandTitles = ["红", "橙", "黄", "绿", "青", "蓝", "紫", "品红"]
    private let bandColors: [Color] = [
        Color(hex: 0xC0574F),
        Color(hex: 0xD98544),
        Color(hex: 0xD8B44A),
        Color(hex: 0x6E9B5C),
        Color(hex: 0x4E9B9B),
        Color(hex: 0x4B78B0),
        Color(hex: 0x7C68A8),
        Color(hex: 0xB05C8C)
    ]

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    curveSection
                    hslSection
                    whiteBalanceSection
                    footer
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("进阶调色")
                    .font(.system(size: 25, weight: .bold, design: .serif))
                    .foregroundStyle(GrainTheme.paper)
                Text("曲线 · 分色 HSL · 白平衡取样")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(GrainTheme.muted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(GrainTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GrainTheme.paper)
        }
    }

    private var curveSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("影调曲线")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                Spacer()
                Button("重置") {
                    editor.recordUndoSnapshot()
                    editor.settings.curve = FilmSettings.identityCurve
                    editor.markManualAdjustment()
                    editor.schedulePreview()
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .buttonStyle(.plain)
                .disabled(!editor.settings.hasCustomCurve)
            }

            ToneCurveEditor(
                curve: curveBinding,
                onEditStart: { editor.recordUndoSnapshot() }
            )
            .frame(height: 168)
            .padding(6)
            .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GrainTheme.line, lineWidth: 0.8)
            }

            Text("拖动中间三个控制点：阴影 → 中间调 → 高光")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
        }
    }

    private var hslSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HSL 分色")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                Spacer()
                Button("重置") {
                    editor.recordUndoSnapshot()
                    editor.settings.hueShift = FilmSettings.neutralHSL
                    editor.settings.saturationShift = FilmSettings.neutralHSL
                    editor.settings.luminanceShift = FilmSettings.neutralHSL
                    editor.markManualAdjustment()
                    editor.schedulePreview()
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .buttonStyle(.plain)
                .disabled(!editor.settings.hasHSLAdjustment)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(0..<FilmSettings.hslBandCount, id: \.self) { index in
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                band = index
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(bandColors[index])
                                    .frame(width: 15, height: 15)
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                band == index ? GrainTheme.paper : .clear,
                                                lineWidth: 1.6
                                            )
                                    }
                                Text(bandTitles[index])
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        band == index ? GrainTheme.paper : GrainTheme.muted
                                    )
                            }
                            .frame(width: 32, height: 42)
                            .background(
                                band == index ? GrainTheme.raised : .clear,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GradeSlider(
                title: "色相",
                value: hslBinding(\.hueShift),
                range: -60...60,
                display: String(format: "%+.0f°", value(\.hueShift))
            )
            GradeSlider(
                title: "饱和度",
                value: hslBinding(\.saturationShift),
                range: -100...100,
                display: String(format: "%+.0f", value(\.saturationShift))
            )
            GradeSlider(
                title: "明度",
                value: hslBinding(\.luminanceShift),
                range: -100...100,
                display: String(format: "%+.0f", value(\.luminanceShift))
            )
        }
    }

    private var whiteBalanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("白平衡取样")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(GrainTheme.paper)

            Text(
                editor.settings.hasWhiteBalanceShift
                    ? String(
                        format: "已校正 · R %.2f  G %.2f  B %.2f",
                        editor.settings.whiteBalanceRed,
                        editor.settings.whiteBalanceGreen,
                        editor.settings.whiteBalanceBlue
                    )
                    : "在画面中点击中性色（灰卡、白墙、阴天天空），即可去除色偏"
            )
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(GrainTheme.muted)

            HStack(spacing: 9) {
                Button {
                    onStartPickingWhiteBalance()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eyedropper.halffull")
                        Text("到画面取样")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(GrainTheme.paper, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)

                Button {
                    editor.recordUndoSnapshot()
                    editor.settings.whiteBalanceRed = 1
                    editor.settings.whiteBalanceGreen = 1
                    editor.settings.whiteBalanceBlue = 1
                    editor.markManualAdjustment()
                    editor.schedulePreview()
                } label: {
                    Text("重置")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            editor.settings.hasWhiteBalanceShift
                                ? GrainTheme.paper
                                : GrainTheme.muted
                        )
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .disabled(!editor.settings.hasWhiteBalanceShift)
            }
        }
    }

    private var footer: some View {
        Button {
            editor.resetAdvancedGrade()
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("重置全部进阶调整")
                Spacer()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(
                editor.settings.hasAdvancedGrade ? GrainTheme.danger : GrainTheme.muted
            )
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!editor.settings.hasAdvancedGrade)
    }

    // MARK: - 绑定

    private var curveBinding: Binding<[Double]> {
        Binding(
            get: {
                editor.settings.curve.count == 5
                    ? editor.settings.curve
                    : FilmSettings.identityCurve
            },
            set: { newValue in
                editor.settings.curve = newValue
                editor.markManualAdjustment()
                editor.schedulePreview()
            }
        )
    }

    private func values(_ keyPath: WritableKeyPath<FilmSettings, [Double]>) -> [Double] {
        let stored = editor.settings[keyPath: keyPath]
        guard stored.count == FilmSettings.hslBandCount else {
            return FilmSettings.neutralHSL
        }
        return stored
    }

    private func value(_ keyPath: WritableKeyPath<FilmSettings, [Double]>) -> Double {
        values(keyPath)[min(band, FilmSettings.hslBandCount - 1)]
    }

    private func hslBinding(
        _ keyPath: WritableKeyPath<FilmSettings, [Double]>
    ) -> Binding<Double> {
        Binding(
            get: { value(keyPath) },
            set: { newValue in
                var array = values(keyPath)
                array[min(band, FilmSettings.hslBandCount - 1)] = newValue
                editor.settings[keyPath: keyPath] = array
                editor.markManualAdjustment()
                editor.schedulePreview()
            }
        )
    }
}

/// 5 点影调曲线编辑器：两端固定，中间三点可上下拖动
private struct ToneCurveEditor: View {
    @Binding var curve: [Double]
    let onEditStart: () -> Void

    @State private var activeIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 12
            let width = max(proxy.size.width - inset * 2, 1)
            let height = max(proxy.size.height - inset * 2, 1)

            ZStack(alignment: .topLeading) {
                ForEach(1..<4, id: \.self) { step in
                    Rectangle()
                        .fill(GrainTheme.line)
                        .frame(width: 0.7, height: height)
                        .position(x: inset + width * CGFloat(step) / 4, y: inset + height / 2)
                    Rectangle()
                        .fill(GrainTheme.line)
                        .frame(width: width, height: 0.7)
                        .position(x: inset + width / 2, y: inset + height * CGFloat(step) / 4)
                }

                curvePath(inset: inset, width: width, height: height)
                    .stroke(GrainTheme.accent, lineWidth: 2)

                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index == activeIndex ? GrainTheme.accent : GrainTheme.paper)
                        .frame(width: index == 0 || index == 4 ? 8 : 11)
                        .overlay {
                            Circle().stroke(GrainTheme.black.opacity(0.35), lineWidth: 0.8)
                        }
                        .position(
                            x: inset + width * CGFloat(index) / 4,
                            y: inset + height * (1 - CGFloat(pointValue(index)))
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if activeIndex == nil {
                            onEditStart()
                            activeIndex = nearestIndex(
                                to: gesture.startLocation.x,
                                inset: inset,
                                width: width
                            )
                        }
                        guard let index = activeIndex, index > 0, index < 4 else { return }
                        let raw = 1 - (gesture.location.y - inset) / height
                        update(index: index, to: Double(raw))
                    }
                    .onEnded { _ in
                        activeIndex = nil
                    }
            )
        }
    }

    private func pointValue(_ index: Int) -> Double {
        guard curve.count == 5 else { return Double(index) / 4 }
        return min(max(curve[index], 0), 1)
    }

    private func nearestIndex(to x: CGFloat, inset: CGFloat, width: CGFloat) -> Int {
        let normalized = (x - inset) / width
        let raw = Int((normalized * 4).rounded())
        return min(max(raw, 1), 3)
    }

    private func update(index: Int, to value: Double) {
        guard curve.count == 5 else { return }
        var updated = curve
        let lower = updated[index - 1] + 0.008
        let upper = updated[index + 1] - 0.008
        updated[index] = min(max(value, lower), max(upper, lower))
        curve = updated
    }

    private func curvePath(inset: CGFloat, width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let samples = 64
            for step in 0...samples {
                let t = CGFloat(step) / CGFloat(samples)
                let value = CGFloat(interpolated(at: t))
                let point = CGPoint(
                    x: inset + width * t,
                    y: inset + height * (1 - min(max(value, 0), 1))
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    /// Catmull-Rom 采样，让 5 个控制点连成平滑曲线
    private func interpolated(at t: CGFloat) -> Double {
        let values = (0..<5).map { pointValue($0) }
        let scaled = t * 4
        let segment = min(Int(scaled), 3)
        let local = Double(scaled - CGFloat(segment))
        let p0 = values[max(segment - 1, 0)]
        let p1 = values[segment]
        let p2 = values[min(segment + 1, 4)]
        let p3 = values[min(segment + 2, 4)]

        let t2 = local * local
        let t3 = t2 * local
        return 0.5 * (
            (2 * p1)
            + (-p0 + p2) * local
            + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
            + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }
}

/// 紧凑滑杆，用于 HSL 三个通道
private struct GradeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .frame(width: 38, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(GrainTheme.accent)

            Text(display)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(GrainTheme.paper)
                .frame(width: 46, alignment: .trailing)
        }
        .frame(height: 30)
    }
}
