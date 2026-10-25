import Photos
import PhotosUI
import SwiftUI
import UIKit

// MARK: - 版式

enum CollageTemplate: String, CaseIterable, Identifiable {
    case auto
    case grid
    case vertical
    case horizontal
    case hero

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "自动"
        case .grid: "网格"
        case .vertical: "竖排"
        case .horizontal: "横排"
        case .hero: "主图"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "square.grid.2x2"
        case .grid: "square.grid.3x3"
        case .vertical: "rectangle.split.1x2"
        case .horizontal: "rectangle.split.2x1"
        case .hero: "rectangle.grid.1x2"
        }
    }
}

// MARK: - 画布比例

enum CollageRatio: String, CaseIterable, Identifiable {
    case square
    case portrait4x5
    case portrait3x4
    case story
    case landscape4x3
    case landscape3x2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: "1:1"
        case .portrait4x5: "4:5"
        case .portrait3x4: "3:4"
        case .story: "9:16"
        case .landscape4x3: "4:3"
        case .landscape3x2: "3:2"
        }
    }

    /// 宽 / 高
    var value: CGFloat {
        switch self {
        case .square: 1
        case .portrait4x5: 4.0 / 5
        case .portrait3x4: 3.0 / 4
        case .story: 9.0 / 16
        case .landscape4x3: 4.0 / 3
        case .landscape3x2: 3.0 / 2
        }
    }
}

// MARK: - 背景色

struct CollageBackgroundOption: Identifiable {
    let id: String
    let title: String
    let hex: UInt32

    var color: Color { Color(hex: hex) }

    var uiColor: UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static let all: [CollageBackgroundOption] = [
        CollageBackgroundOption(id: "black", title: "黑", hex: 0x070706),
        CollageBackgroundOption(id: "ink", title: "墨", hex: 0x1D1D1A),
        CollageBackgroundOption(id: "white", title: "白", hex: 0xFFFFFF),
        CollageBackgroundOption(id: "cream", title: "米", hex: 0xF4EDE1),
        CollageBackgroundOption(id: "sand", title: "沙", hex: 0xD9C7A7),
        CollageBackgroundOption(id: "brick", title: "砖", hex: 0xD9774E)
    ]
}

// MARK: - 版式计算

enum CollageLayoutEngine {
    /// 返回归一化后的格子（0…1），顺序对应照片顺序
    static func slots(template: CollageTemplate, count: Int, ratio: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        guard count > 1 else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        switch template {
        case .auto:
            return autoSlots(count: count, ratio: ratio)
        case .grid:
            return gridSlots(count: count, columns: count <= 4 ? 2 : 3)
        case .vertical:
            return gridSlots(count: count, columns: 1)
        case .horizontal:
            return gridSlots(count: count, columns: count)
        case .hero:
            return heroSlots(count: count, ratio: ratio)
        }
    }

    /// 归一化格子 → 实际像素矩形（含间距与圆角所需的留白）
    static func cellRects(
        slots: [CGRect],
        in size: CGSize,
        gapFraction: CGFloat
    ) -> [CGRect] {
        guard size.width > 1, size.height > 1, !slots.isEmpty else { return [] }
        let shortest = min(size.width, size.height)
        let maxGap = shortest / CGFloat(max(slots.count, 1)) * 0.5
        let gap = min(max(gapFraction, 0) * shortest, maxGap)
        let inset = gap / 2
        let available = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)

        return slots.map { slot in
            let rect = CGRect(
                x: available.minX + slot.minX * available.width,
                y: available.minY + slot.minY * available.height,
                width: slot.width * available.width,
                height: slot.height * available.height
            )
            return rect.insetBy(dx: inset, dy: inset)
        }
    }

    private static func autoSlots(count: Int, ratio: CGFloat) -> [CGRect] {
        switch count {
        case 2:
            return gridSlots(count: count, columns: ratio >= 1 ? 2 : 1)
        case 3:
            return heroSlots(count: count, ratio: ratio)
        case 4:
            return gridSlots(count: count, columns: 2)
        case 5, 6:
            return gridSlots(count: count, columns: 2)
        case 7, 8, 9:
            return gridSlots(count: count, columns: 3)
        default:
            return gridSlots(count: count, columns: 2)
        }
    }

    /// 主图版式：第一张占大半，其余平分剩余区域
    private static func heroSlots(count: Int, ratio: CGFloat) -> [CGRect] {
        let bigShare: CGFloat = count <= 3 ? 0.62 : 0.58
        let restCount = max(count - 1, 1)

        if ratio >= 1 {
            let rest = CGRect(x: bigShare, y: 0, width: 1 - bigShare, height: 1)
            let columns = restCount <= 3 ? 1 : 2
            let inner = gridSlots(count: restCount, columns: columns)
            return [CGRect(x: 0, y: 0, width: bigShare, height: 1)]
                + map(inner, into: rest)
        }

        let rest = CGRect(x: 0, y: bigShare, width: 1, height: 1 - bigShare)
        let columns = restCount <= 3 ? restCount : 2
        let inner = gridSlots(count: restCount, columns: max(columns, 1))
        return [CGRect(x: 0, y: 0, width: 1, height: bigShare)]
            + map(inner, into: rest)
    }

    /// 均分网格：每行格子数按总数平分，保证铺满画布、不留空洞
    private static func gridSlots(count: Int, columns: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let columns = max(1, min(columns, count))
        let rows = max(1, Int(ceil(Double(count) / Double(columns))))
        let base = count / rows
        let extra = count % rows

        var rects: [CGRect] = []
        rects.reserveCapacity(count)
        var y: CGFloat = 0
        let height = 1 / CGFloat(rows)

        for row in 0..<rows {
            let cells = base + (row < extra ? 1 : 0)
            let width = 1 / CGFloat(max(cells, 1))
            for column in 0..<cells {
                rects.append(
                    CGRect(
                        x: CGFloat(column) * width,
                        y: y,
                        width: width,
                        height: height
                    )
                )
            }
            y += height
        }
        return rects
    }

    private static func map(_ slots: [CGRect], into rect: CGRect) -> [CGRect] {
        slots.map { slot in
            CGRect(
                x: rect.minX + slot.minX * rect.width,
                y: rect.minY + slot.minY * rect.height,
                width: slot.width * rect.width,
                height: slot.height * rect.height
            )
        }
    }
}

// MARK: - 拼图页

struct CollageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAssets: [PHAsset]
    @State private var template: CollageTemplate = .auto
    @State private var ratio: CollageRatio = .square
    @State private var spacing: Double = 6
    @State private var corner: Double = 8
    @State private var backgroundID: String? = nil
    @State private var previewImages: [String: UIImage] = [:]
    @State private var isLoading = true
    @State private var isRendering = false
    @State private var exportURL: URL?
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickerError: String?
    @State private var notice: String?
    @State private var errorMessage: String?

    init(assets: [PHAsset]) {
        _selectedAssets = State(initialValue: Array(assets.prefix(10)))
        _isLoading = State(initialValue: !assets.isEmpty)
    }

    private var effectiveBackgroundID: String {
        backgroundID ?? (colorScheme == .light ? "white" : "black")
    }

    private var background: CollageBackgroundOption {
        CollageBackgroundOption.all.first { $0.id == effectiveBackgroundID }
            ?? CollageBackgroundOption.all[0]
    }

    var body: some View {
        ZStack {
            GrainBackground()

            VStack(spacing: 0) {
                topBar
                preview
                photoStrip
                controls
            }
            .padding(.bottom, 6)

            if isLoading || isRendering {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(GrainTheme.paper)
                    Text(isRendering ? "正在生成拼图" : "正在读取照片")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.78), in: Capsule())
            }

            if let notice {
                VStack {
                    Text(notice)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.black)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(GrainTheme.paper, in: Capsule())
                        .padding(.top, 62)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .statusBarHidden()
        .simultaneousGesture(backSwipeGesture)
        .task {
            await loadPreviewImages()
        }
        .onChange(of: pickerItems) { _, items in
            Task { await addPickedAssets(items) }
        }
        .onDisappear {
            if let exportURL {
                try? FileManager.default.removeItem(at: exportURL)
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareURL = nil }) {
            if let shareURL {
                GrainShareSheet(items: [shareURL])
                    .ignoresSafeArea()
            }
        }
        .alert(
            "拼图处理失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            "无法添加照片",
            isPresented: Binding(
                get: { pickerError != nil },
                set: { if !$0 { pickerError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(pickerError ?? "")
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 36, height: 36)
                    .background(GrainTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("拼图")
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(GrainTheme.paper)
                Text("\(selectedAssets.count) 张 · 最多 10 张")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(GrainTheme.muted)
            }

            Spacer()

            if selectedAssets.count > 1 {
                Button {
                    shuffleOrder()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GrainTheme.muted)
                        .frame(width: 34, height: 34)
                        .background(GrainTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打乱照片顺序")
            }

            if selectedAssets.count < 10 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, 10 - selectedAssets.count),
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("添加")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(GrainTheme.raised, in: Capsule())
                }
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GrainTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(GrainTheme.raised, in: Circle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: 画布预览

    private var preview: some View {
        GeometryReader { proxy in
            let size = fittedCanvas(in: proxy.size)
            let slots = CollageLayoutEngine.slots(
                template: template,
                count: selectedAssets.count,
                ratio: ratio.value
            )
            let rects = CollageLayoutEngine.cellRects(
                slots: slots,
                in: size,
                gapFraction: CGFloat(spacing) / 320
            )

            ZStack(alignment: .topLeading) {
                background.color

                if selectedAssets.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(rects.enumerated()), id: \.offset) { item in
                        if item.offset < selectedAssets.count {
                            collageCell(
                                asset: selectedAssets[item.offset],
                                rect: item.element
                            )
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(GrainTheme.line, lineWidth: 0.8)
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .animation(.snappy(duration: 0.26), value: template)
            .animation(.snappy(duration: 0.26), value: ratio)
            .animation(.snappy(duration: 0.18), value: spacing)
            .animation(.snappy(duration: 0.18), value: corner)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func fittedCanvas(in available: CGSize) -> CGSize {
        guard available.width > 1, available.height > 1 else {
            return CGSize(width: 1, height: 1)
        }
        let ratioValue = max(ratio.value, 0.2)
        var width = available.width
        var height = width / ratioValue
        if height > available.height {
            height = available.height
            width = height * ratioValue
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(GrainTheme.muted)
            Text("添加照片开始制作拼图")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 10,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("从照片图库添加")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(GrainTheme.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func collageCell(asset: PHAsset, rect: CGRect) -> some View {
        ZStack {
            background.color
            if let image = previewImages[asset.localIdentifier] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: rect.width, height: rect.height)
                    .clipped()
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(GrainTheme.muted)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: min(CGFloat(corner), min(rect.width, rect.height) / 2),
                style: .continuous
            )
        )
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: 照片条

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedAssets.enumerated()), id: \.element.localIdentifier) { item in
                    photoChip(asset: item.element, index: item.offset)
                }

                if selectedAssets.count < 10 {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: max(1, 10 - selectedAssets.count),
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(GrainTheme.muted)
                            .frame(width: 48, height: 48)
                            .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
        .frame(height: 66)
    }

    private func photoChip(asset: PHAsset, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                makeCover(asset)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    chipImage(asset: asset)
                    Text("\(index + 1)")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(GrainTheme.black)
                        .frame(width: 14, height: 14)
                        .background(GrainTheme.paper, in: Circle())
                        .padding(3)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            index == 0 ? GrainTheme.accent : Color.white.opacity(0.14),
                            lineWidth: index == 0 ? 1.4 : 0.7
                        )
                }
            }
            .buttonStyle(.plain)

            Button {
                remove(asset)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 16, height: 16)
                    .background(Color.black.opacity(0.78), in: Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .frame(width: 48, height: 48)
        .contextMenu {
            Button("设为封面") { makeCover(asset) }
            Button("前移") { move(asset, offset: -1) }
            Button("后移") { move(asset, offset: 1) }
            Divider()
            Button("移除", role: .destructive) { remove(asset) }
        }
    }

    @ViewBuilder
    private func chipImage(asset: PHAsset) -> some View {
        if let image = previewImages[asset.localIdentifier] {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipped()
        } else {
            GrainTheme.surface
                .frame(width: 48, height: 48)
        }
    }

    // MARK: 控制区

    private var controls: some View {
        VStack(spacing: 7) {
            templateRow
            ratioRow
            sliderRow(
                title: "间距",
                value: Binding(
                    get: { spacing },
                    set: { spacing = $0 }
                ),
                range: 0...20,
                display: "\(Int(spacing))"
            )
            sliderRow(
                title: "圆角",
                value: Binding(
                    get: { corner },
                    set: { corner = $0 }
                ),
                range: 0...24,
                display: "\(Int(corner))"
            )
            backgroundRow
            actionRow
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var templateRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(CollageTemplate.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            template = item
                        }
                        GrainHaptics.selection(enabled: true)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(
                            template == item ? GrainTheme.black : GrainTheme.muted
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            template == item ? GrainTheme.paper : GrainTheme.raised,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAssets.isEmpty)
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 30)
    }

    private var ratioRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(CollageRatio.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            ratio = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(
                                ratio == item ? GrainTheme.black : GrainTheme.muted
                            )
                            .frame(width: 44, height: 26)
                            .background(
                                ratio == item ? GrainTheme.paper : GrainTheme.raised,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 26)
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .frame(width: 30, alignment: .leading)
            Slider(value: value, in: range)
                .tint(GrainTheme.accent)
                .onChange(of: value.wrappedValue) { _, _ in
                    GrainHaptics.selection()
                }
            Text(display)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(GrainTheme.paper)
                .frame(width: 28, alignment: .trailing)
        }
        .frame(height: 30)
        .padding(.horizontal, 18)
    }

    private var backgroundRow: some View {
        HStack(spacing: 9) {
            Text("背景")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
                .frame(width: 30, alignment: .leading)

            ForEach(CollageBackgroundOption.all) { option in
                Button {
                    backgroundID = option.id
                    GrainHaptics.selection(enabled: true)
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 21, height: 21)
                        .overlay {
                            Circle().stroke(
                                effectiveBackgroundID == option.id
                                    ? GrainTheme.accent
                                    : GrainTheme.line,
                                lineWidth: effectiveBackgroundID == option.id ? 1.8 : 0.8
                            )
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(height: 30)
        .padding(.horizontal, 18)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                saveToLibrary()
            } label: {
                Label("存到图库", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(GrainTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isRendering || selectedAssets.isEmpty)

            Button {
                prepareShare()
            } label: {
                Label("分享", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(GrainTheme.paper, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isRendering || selectedAssets.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
    }

    // MARK: 手势

    /// 从屏幕最左侧往右滑返回主页
    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onEnded { value in
                guard value.startLocation.x <= 26,
                      value.translation.width > 88,
                      abs(value.translation.height) < 110,
                      abs(value.translation.width) > abs(value.translation.height) * 1.8
                else { return }
                dismiss()
            }
    }

    // MARK: 数据

    @MainActor
    private func loadPreviewImages() async {
        guard !selectedAssets.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        for asset in selectedAssets where previewImages[asset.localIdentifier] == nil {
            let image = await CollageImageLoader.image(
                for: asset,
                targetSize: CGSize(width: 900, height: 900)
            )
            if let image {
                previewImages[asset.localIdentifier] = image
            }
        }
        isLoading = false
    }

    @MainActor
    private func addPickedAssets(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        let identifiers = items.compactMap(\.itemIdentifier)
        let fetched = PHAsset.fetchAssets(
            withLocalIdentifiers: identifiers,
            options: nil
        )
        var lookup: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in
            lookup[asset.localIdentifier] = asset
        }
        let additions = identifiers.compactMap { lookup[$0] }.filter { asset in
            !selectedAssets.contains { $0.localIdentifier == asset.localIdentifier }
        }
        guard !additions.isEmpty else {
            pickerError = "没有找到可添加的照片，请重新选择。"
            pickerItems = []
            return
        }
        selectedAssets.append(contentsOf: additions.prefix(10 - selectedAssets.count))
        pickerItems = []
        await loadPreviewImages()
    }

    private func makeCover(_ asset: PHAsset) {
        guard let index = selectedAssets.firstIndex(where: {
            $0.localIdentifier == asset.localIdentifier
        }), index > 0 else { return }
        withAnimation(.snappy(duration: 0.22)) {
            let item = selectedAssets.remove(at: index)
            selectedAssets.insert(item, at: 0)
        }
        GrainHaptics.lightImpact(enabled: true)
    }

    private func move(_ asset: PHAsset, offset: Int) {
        guard let index = selectedAssets.firstIndex(where: {
            $0.localIdentifier == asset.localIdentifier
        }) else { return }
        let target = index + offset
        guard selectedAssets.indices.contains(target) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            selectedAssets.swapAt(index, target)
        }
        GrainHaptics.lightImpact(enabled: true)
    }

    private func remove(_ asset: PHAsset) {
        withAnimation(.snappy(duration: 0.22)) {
            selectedAssets.removeAll { $0.localIdentifier == asset.localIdentifier }
            previewImages[asset.localIdentifier] = nil
        }
        GrainHaptics.lightImpact(enabled: true)
    }

    private func shuffleOrder() {
        guard selectedAssets.count > 1 else { return }
        withAnimation(.snappy(duration: 0.24)) {
            selectedAssets.shuffle()
        }
        GrainHaptics.selection(enabled: true)
    }

    // MARK: 生成与保存

    private func saveToLibrary() {
        guard !isRendering else { return }
        isRendering = true
        errorMessage = nil

        Task {
            do {
                let url = try await renderCollage()
                try await saveCollageToLibrary(url)
                replaceExportURL(with: url)
                showNotice("拼图已保存到照片图库")
            } catch {
                errorMessage = error.localizedDescription
            }
            isRendering = false
        }
    }

    private func prepareShare() {
        guard !isRendering else { return }
        isRendering = true
        errorMessage = nil

        Task {
            do {
                let url = try await renderCollage()
                replaceExportURL(with: url)
                shareURL = url
                showShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isRendering = false
        }
    }

    private func renderCollage() async throws -> URL {
        let assets = selectedAssets
        let templateValue = template
        let ratioValue = ratio.value
        let spacingValue = spacing
        let cornerValue = corner
        let backgroundValue = background

        guard !assets.isEmpty, assets.count <= 10 else {
            throw CollageError.invalidPhotoCount
        }

        let maxLongEdge: CGFloat = 3000
        let canvasSize: CGSize
        if ratioValue >= 1 {
            canvasSize = CGSize(
                width: maxLongEdge,
                height: (maxLongEdge / ratioValue).rounded()
            )
        } else {
            canvasSize = CGSize(
                width: (maxLongEdge * ratioValue).rounded(),
                height: maxLongEdge
            )
        }

        let slots = CollageLayoutEngine.slots(
            template: templateValue,
            count: assets.count,
            ratio: ratioValue
        )
        let rects = CollageLayoutEngine.cellRects(
            slots: slots,
            in: canvasSize,
            gapFraction: CGFloat(spacingValue) / 320
        )
        guard rects.count >= assets.count else {
            throw CollageError.renderFailed
        }

        var maxCell = CGSize(width: 1, height: 1)
        for rect in rects {
            maxCell.width = max(maxCell.width, rect.width)
            maxCell.height = max(maxCell.height, rect.height)
        }
        let target = CGSize(
            width: min(maxCell.width, 2200),
            height: min(maxCell.height, 2200)
        )

        var images: [UIImage] = []
        images.reserveCapacity(assets.count)
        for asset in assets {
            guard let image = await CollageImageLoader.image(
                for: asset,
                targetSize: target
            ) else {
                throw CollageError.imageUnavailable
            }
            images.append(image)
        }

        let cornerPixels = CGFloat(cornerValue) * (canvasSize.width / 356)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let collage = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(backgroundValue.uiColor.cgColor)
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            for (index, image) in images.enumerated() where index < rects.count {
                let rect = rects[index]
                let radius = min(cornerPixels, min(rect.width, rect.height) / 2)
                cg.saveGState()
                let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
                cg.addPath(path.cgPath)
                cg.clip()
                drawAspectFill(image, in: rect, context: cg)
                cg.restoreGState()
            }
        }

        guard let data = collage.jpegData(compressionQuality: 1.0) else {
            throw CollageError.renderFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GRAIN-collage-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func drawAspectFill(
        _ image: UIImage,
        in rect: CGRect,
        context: CGContext
    ) {
        let scale = max(
            rect.width / max(image.size.width, 1),
            rect.height / max(image.size.height, 1)
        )
        let drawSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    private func saveCollageToLibrary(_ url: URL) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) {
                    continuation.resume(returning: $0 == .authorized || $0 == .limited)
                }
            }
            guard granted else { throw CollageError.photoLibraryDenied }
        } else if status != .authorized, status != .limited {
            throw CollageError.photoLibraryDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "GRAIN-collage.jpg"
                options.uniformTypeIdentifier = "public.jpeg"
                request.addResource(with: .photo, fileURL: url, options: options)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? CollageError.saveFailed
                    )
                }
            }
        }
    }

    private func showNotice(_ text: String) {
        withAnimation(.easeOut(duration: 0.16)) {
            notice = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeIn(duration: 0.16)) {
                notice = nil
            }
        }
    }

    private func replaceExportURL(with url: URL) {
        if let exportURL, exportURL != url {
            try? FileManager.default.removeItem(at: exportURL)
        }
        exportURL = url
    }
}

private enum CollageImageLoader {
    static func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let gate = CollageImageContinuation(continuation)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.version = .current
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                    return
                }
                gate.finish(image)
            }
        }
    }
}

private final class CollageImageContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: image)
    }
}

private enum CollageError: LocalizedError {
    case invalidPhotoCount
    case imageUnavailable
    case renderFailed
    case photoLibraryDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidPhotoCount:
            "请选择 1 到 10 张照片制作拼图。"
        case .imageUnavailable:
            "部分照片无法从 iCloud 读取，请检查网络后重试。"
        case .renderFailed:
            "无法生成拼图，请减少照片数量后重试。"
        case .photoLibraryDenied:
            "请在系统设置中允许 GRAIN 向照片图库添加照片。"
        case .saveFailed:
            "拼图保存失败，请检查存储空间后重试。"
        }
    }
}

struct GrainShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
