import Photos
import PhotosUI
import SwiftUI
import UIKit
import ImageIO
import CoreLocation

// MARK: - 照片单元格手势变换数据模型
struct PhotoCellTransform: Equatable {
    var scale: CGFloat = 1.0
    var normalizedOffset: CGSize = .zero
}

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

// MARK: - 编辑工作台分类与相框/水印模型

enum EditorDeckTab: String, CaseIterable, Identifiable {
    case layout = "排版边距"
    case filmFrame = "胶片相框"
    case watermark = "水印数据"
    case addText = "添加文字"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .layout: return "square.grid.2x2"
        case .filmFrame: return "film"
        case .watermark: return "character.cursor.ibeam"
        case .addText: return "textformat"
        }
    }
}

enum FilmFrameStyle: String, CaseIterable, Identifiable {
    case none = "无边框"
    case polaroid = "拍立得"
    case blackPolaroid = "黑卡拍立得"
    case sprocket35mm = "35mm齿孔"
    case kodakGold = "柯达Gold200"
    case fujiSuperia = "富士Superia"
    case mediumFormat = "哈苏中画幅"
    case disposable = "一次性相机"
    case ilfordHP5 = "伊尔福黑白"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none: return "slash.circle"
        case .polaroid: return "rectangle.portrait"
        case .blackPolaroid: return "rectangle.portrait.fill"
        case .sprocket35mm: return "film"
        case .kodakGold: return "film.stack"
        case .fujiSuperia: return "sparkles.tv"
        case .mediumFormat: return "viewfinder"
        case .disposable: return "camera.metering.matrix"
        case .ilfordHP5: return "circle.lefthalf.filled"
        }
    }
}

/// 胶片相框内挖空蒙版形状（确保哈苏中画幅与一次性相机等相框内孔具有平滑连续内圆角，与外边框及照片圆角浑然一体，绝无生硬直角）
struct FilmCutoutFrame: Shape {
    var borderWidth: CGFloat
    var innerCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let innerRect = rect.insetBy(dx: borderWidth, dy: borderWidth)
        if innerRect.width > 0 && innerRect.height > 0 {
            path.addPath(Path(roundedRect: innerRect, cornerRadius: innerCornerRadius, style: .continuous))
        }
        return path
    }
}

struct EditorSticker: Identifiable, Equatable {
    let id: UUID
    var text: String
    var position: CGPoint // 归一化坐标 0...1
    var scale: CGFloat

    init(id: UUID = UUID(), text: String, position: CGPoint = CGPoint(x: 0.5, y: 0.5), scale: CGFloat = 1.0) {
        self.id = id
        self.text = text
        self.position = position
        self.scale = scale
    }
}

struct PhotoEXIFInfo: Equatable {
    var cameraModel: String = "GRAIN OPTICS"
    var focalLength: String = "24mm"
    var aperture: String = "f/1.8"
    var shutterSpeed: String = "1/250s"
    var iso: String = "ISO 100"
    var dateString: String = "2026.10.25"
    var locationString: String = "TOKYO, JAPAN"

    static func formatCity(from place: CLPlacemark) -> String {
        let admin = place.administrativeArea
        let locality = place.locality
        let sub = place.subLocality

        // 中文地址：省/直辖市 + 城市（如 河南省登封市，或 郑州市，或 北京市）
        if place.isoCountryCode == "CN" || (admin?.contains("省") == true || admin?.contains("市") == true) {
            if let admin = admin {
                if let sub = sub, sub.hasSuffix("市") {
                    return "\(admin)\(sub)"
                } else if let loc = locality {
                    if admin == loc {
                        return loc
                    } else {
                        return "\(admin)\(loc)"
                    }
                } else if let sub = sub {
                    return "\(admin)\(sub)"
                } else {
                    return admin
                }
            } else if let loc = locality {
                return loc
            } else if let sub = sub {
                return sub
            }
        } else {
            let parts = [locality ?? admin, place.country].compactMap { $0 }
            if !parts.isEmpty {
                return parts.joined(separator: ", ")
            }
        }
        return ""
    }

    static func extract(from asset: PHAsset) async -> PhotoEXIFInfo {
        var info = PhotoEXIFInfo()
        let date = asset.creationDate ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        info.dateString = formatter.string(from: date)

        if let loc = asset.location {
            let lat = abs(loc.coordinate.latitude)
            let lon = abs(loc.coordinate.longitude)
            let latDir = loc.coordinate.latitude >= 0 ? "N" : "S"
            let lonDir = loc.coordinate.longitude >= 0 ? "E" : "W"
            info.locationString = String(format: "%.2f°%@ %.2f°%@", lat, latDir, lon, lonDir)

            let geocoder = CLGeocoder()
            if let placemarks = try? await geocoder.reverseGeocodeLocation(loc),
               let place = placemarks.first {
                let city = formatCity(from: place)
                if !city.isEmpty {
                    info.locationString = city
                }
            }
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.deliveryMode = .fastFormat

        await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                if let data = data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                    if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
                       let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                        info.cameraModel = model.replacingOccurrences(of: "iPhone ", with: "IPHONE ")
                    }
                    if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                        if let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double {
                            info.aperture = String(format: "f/%.1f", fNumber)
                        }
                        if let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                            if exposureTime >= 1.0 {
                                info.shutterSpeed = String(format: "%.1fs", exposureTime)
                            } else if exposureTime > 0 {
                                info.shutterSpeed = "1/\(Int((1.0 / exposureTime).rounded()))s"
                            }
                        }
                        if let isos = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let firstISO = isos.first {
                            info.iso = "ISO \(firstISO)"
                        }
                        if let focal = exif[kCGImagePropertyExifFocalLength as String] as? Double {
                            info.focalLength = "\(Int(focal.rounded()))mm"
                        }
                    }
                }
                continuation.resume()
            }
        }
        return info
    }
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

    /// 归一化格子 → 实际像素矩形（含间距与圆角所需的留白，支持 0...100 自由调节）
    static func cellRects(
        slots: [CGRect],
        in size: CGSize,
        gapFraction: CGFloat
    ) -> [CGRect] {
        guard size.width > 1, size.height > 1, !slots.isEmpty else { return [] }
        let shortest = min(size.width, size.height)
        let maxGap = shortest * (slots.count == 1 ? 0.38 : (0.50 / CGFloat(max(slots.count, 1))))
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

// MARK: - 照片与拼图编辑工作台

struct CollageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAssets: [PHAsset]
    @State private var template: CollageTemplate = .auto
    @State private var ratio: CollageRatio = .square
    @State private var spacing: Double = 8
    @State private var corner: Double = 10
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

    // 新增：编辑工作台状态
    @State private var activeTab: EditorDeckTab = .layout
    @State private var filmFrame: FilmFrameStyle = .none
    @State private var showDateStamp: Bool = false
    @State private var dateStampStyle: Int = 0 // 0: 橙色石英点阵, 1: 极简现代, 2: 经典英文
    @State private var showLocationStamp: Bool = false
    @State private var locationText: String = ""
    @State private var showEXIFBar: Bool = false
    @State private var stickers: [EditorSticker] = []
    @State private var exifInfo: PhotoEXIFInfo = PhotoEXIFInfo()

    // 水印自由拖拽位置（归一化坐标 0...1）
    @State private var exifBarPosition: CGPoint = CGPoint(x: 0.5, y: 0.92)
    @State private var dateStampPosition: CGPoint = CGPoint(x: 0.82, y: 0.92)
    @State private var locationStampPosition: CGPoint = CGPoint(x: 0.22, y: 0.92)

    // 照片单元格双指缩放与拖拽平移状态
    @State private var cellTransforms: [String: PhotoCellTransform] = [:]
    @State private var gestureScale: [String: CGFloat] = [:]
    @State private var gestureOffset: [String: CGSize] = [:]

    // 自定义添加文字输入
    @State private var customTextInput: String = ""

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
                    Text(isRendering ? "正在渲染高清成品" : "正在读取照片")
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
            if let first = selectedAssets.first {
                exifInfo = await PhotoEXIFInfo.extract(from: first)
            }
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
            "编辑处理失败",
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

    // MARK: 顶栏（将“拼图”升级为“编辑”）

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
                Text("编辑")
                    .font(.system(size: 23, weight: .bold, design: .serif))
                    .foregroundStyle(GrainTheme.paper)
                Text(selectedAssets.isEmpty ? "未选择照片" : "\(selectedAssets.count) 张 · 最多 10 张")
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

    // MARK: 画布预览与多图层合成

    private var preview: some View {
        GeometryReader { proxy in
            let size = fittedCanvas(in: proxy.size)
            let slots = CollageLayoutEngine.slots(
                template: template,
                count: selectedAssets.count,
                ratio: ratio.value
            )
            let gapFraction = CGFloat(spacing) / 100.0 * (selectedAssets.count <= 1 ? 0.38 : (0.50 / CGFloat(max(slots.count, 1))))
            let rects = CollageLayoutEngine.cellRects(
                slots: slots,
                in: size,
                gapFraction: gapFraction
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
                                rect: item.element,
                                canvasSize: size
                            )
                        }
                    }
                }

                // 1. 胶片模拟相框 (拍立得、35mm齿孔、哈苏中画幅等)
                filmFrameOverlay(size: size)

                // 2. EXIF 拍摄参数白条 / 铭牌
                if showEXIFBar {
                    exifBarOverlay(size: size)
                }

                // 3. 经典橙色石英点阵日期印记
                if showDateStamp {
                    dateStampOverlay(size: size)
                }

                // 4. 拍摄地点水印
                if showLocationStamp {
                    locationStampOverlay(size: size)
                }

                // 5. 表情包与贴纸自由放置层
                ForEach(stickers) { sticker in
                    stickerView(sticker: sticker, canvasSize: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(GrainTheme.line, lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.38), radius: 14, y: 6)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .animation(.snappy(duration: 0.26), value: template)
            .animation(.snappy(duration: 0.26), value: ratio)
            .animation(.snappy(duration: 0.18), value: spacing)
            .animation(.snappy(duration: 0.18), value: corner)
            .animation(.snappy(duration: 0.22), value: filmFrame)
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
            Text("添加照片开启复古工作台")
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

    private func collageCell(asset: PHAsset, rect: CGRect, canvasSize: CGSize) -> some View {
        let maxRadius = min(rect.width, rect.height) / 2
        let calculatedRadius = min(CGFloat(corner) / 100.0 * maxRadius, maxRadius)
        let id = asset.localIdentifier
        let baseTransform = cellTransforms[id] ?? PhotoCellTransform()
        let activeScale = (gestureScale[id] ?? 1.0) * baseTransform.scale
        let activeOffset = CGSize(
            width: baseTransform.normalizedOffset.width * rect.width + (gestureOffset[id]?.width ?? 0),
            height: baseTransform.normalizedOffset.height * rect.height + (gestureOffset[id]?.height ?? 0)
        )

        return ZStack {
            background.color
            if let image = previewImages[id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(activeScale)
                    .offset(activeOffset)
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
                cornerRadius: calculatedRadius,
                style: .continuous
            )
        )
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { val in
                        gestureScale[id] = val
                    }
                    .onEnded { val in
                        let current = cellTransforms[id] ?? PhotoCellTransform()
                        let newScale = min(max(current.scale * val, 0.5), 5.0)
                        cellTransforms[id] = PhotoCellTransform(
                            scale: newScale,
                            normalizedOffset: current.normalizedOffset
                        )
                        gestureScale[id] = 1.0
                    },
                DragGesture()
                    .onChanged { val in
                        gestureOffset[id] = val.translation
                    }
                    .onEnded { val in
                        let current = cellTransforms[id] ?? PhotoCellTransform()
                        let newNormW = current.normalizedOffset.width + val.translation.width / max(rect.width, 1)
                        let newNormH = current.normalizedOffset.height + val.translation.height / max(rect.height, 1)
                        cellTransforms[id] = PhotoCellTransform(
                            scale: current.scale,
                            normalizedOffset: CGSize(width: newNormW, height: newNormH)
                        )
                        gestureOffset[id] = .zero
                    }
            )
        )
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - 胶片模拟相框覆盖层

    @ViewBuilder
    private func filmFrameOverlay(size: CGSize) -> some View {
        switch filmFrame {
        case .none:
            EmptyView()
        case .polaroid:
            // 拍立得经典白底边框与宽下巴
            let borderT = size.width * 0.05
            let borderB = size.height * 0.16
            let innerRadius: CGFloat = 6.0
            ZStack(alignment: .bottom) {
                FilmCutoutFrame(borderWidth: borderT, innerCornerRadius: innerRadius)
                    .fill(Color.white, style: FillStyle(eoFill: true))
                Rectangle()
                    .fill(Color.white)
                    .frame(height: borderB)
                HStack {
                    Text(exifInfo.dateString)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.65))
                    Spacer()
                    Text("POLAROID · GRAIN")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.40))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, borderB * 0.28)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

        case .blackPolaroid:
            // 复古黑卡拍立得（黑色边框、宽下巴、金色石英日期印记）
            let borderT = size.width * 0.05
            let borderB = size.height * 0.16
            let innerRadius: CGFloat = 6.0
            ZStack(alignment: .bottom) {
                FilmCutoutFrame(borderWidth: borderT, innerCornerRadius: innerRadius)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.09), style: FillStyle(eoFill: true))
                Rectangle()
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
                    .frame(height: borderB)
                HStack {
                    Text(exifInfo.dateString)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.35))
                    Spacer()
                    Text("BLACK POLAROID · GRAIN")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, borderB * 0.28)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

        case .sprocket35mm:
            // 35mm 胶卷上下齿孔与底片编码
            let barH = size.height * 0.09
            VStack(spacing: 0) {
                // 上齿孔带
                sprocketBar(width: size.width, height: barH, text: "KODAK PORTRA 400 · 36")
                Spacer()
                // 下齿孔带
                sprocketBar(width: size.width, height: barH, text: "FILM 135 · 36A · DX 400")
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

        case .kodakGold:
            // 柯达经典 Gold 200 金黄齿孔带与暗房打标
            let barH = size.height * 0.09
            VStack(spacing: 0) {
                sprocketBar(width: size.width, height: barH, text: "KODAK GOLD 200 · 24 EXP", textColor: Color(red: 1.0, green: 0.78, blue: 0.12))
                Spacer()
                sprocketBar(width: size.width, height: barH, text: "SAFETY FILM · 24A · DX 200", textColor: Color(red: 1.0, green: 0.78, blue: 0.12))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

        case .fujiSuperia:
            // 富士 Superia 400 翡翠绿经典齿孔底片
            let barH = size.height * 0.09
            VStack(spacing: 0) {
                sprocketBar(width: size.width, height: barH, text: "FUJIFILM SUPERIA X-TRA 400", textColor: Color(red: 0.25, green: 0.88, blue: 0.45))
                Spacer()
                sprocketBar(width: size.width, height: barH, text: "SUPERIA 400 · CN-16 · 36A", textColor: Color(red: 0.25, green: 0.88, blue: 0.45))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

        case .mediumFormat:
            // 哈苏 6x6 中画幅遮光框（内圆弧平滑过渡，与外边框及照片圆角浑然一致，告别生硬直角）
            let border = size.width * 0.045
            let innerRadius: CGFloat = 16.0
            ZStack {
                FilmCutoutFrame(borderWidth: border, innerCornerRadius: innerRadius)
                    .fill(Color.black, style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    .padding(border)
                VStack {
                    HStack {
                        Text("HASSELBLAD 6X6")
                            .font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .padding(.horizontal, border + 4)
                            .padding(.top, 4)
                        Spacer()
                        Text("120 FILM")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .padding(.horizontal, border + 4)
                            .padding(.top, 4)
                    }
                    Spacer()
                }
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

        case .disposable:
            // 一次性相机纸质取景框（内孔平滑圆角，与边缘圆圈保持一致）
            let border = size.width * 0.040
            let innerRadius: CGFloat = 14.0
            ZStack {
                FilmCutoutFrame(borderWidth: border, innerCornerRadius: innerRadius)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.13), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                    .stroke(GrainTheme.accent.opacity(0.35), lineWidth: 0.6)
                    .padding(border)
                VStack {
                    Spacer()
                    HStack {
                        Text("QUICKSNAP 400")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .padding(.horizontal, border + 4)
                            .padding(.bottom, 3)
                        Spacer()
                        Text("DISPOSABLE")
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .foregroundStyle(GrainTheme.accent)
                            .padding(.horizontal, border + 4)
                            .padding(.bottom, 3)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)

        case .ilfordHP5:
            // 伊尔福 HP5 Plus 经典黑白印相底片框（内圆弧平滑过渡）
            let border = size.width * 0.042
            let innerRadius: CGFloat = 14.0
            ZStack {
                FilmCutoutFrame(borderWidth: border, innerCornerRadius: innerRadius)
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.05), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                    .padding(border)
                VStack {
                    HStack {
                        Text("ILFORD HP5 PLUS")
                            .font(.system(size: 7.5, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, border + 4)
                            .padding(.top, 4)
                        Spacer()
                        Text("ISO 400")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .padding(.horizontal, border + 4)
                            .padding(.top, 4)
                    }
                    Spacer()
                    HStack {
                        Text("B&W DARKROOM PRINT")
                            .font(.system(size: 6.5, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.40))
                            .padding(.horizontal, border + 4)
                            .padding(.bottom, 3)
                        Spacer()
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    private func sprocketBar(width: CGFloat, height: CGFloat, text: String, textColor: Color = Color(red: 1.0, green: 0.72, blue: 0.15)) -> some View {
        ZStack {
            Color.black
            HStack(spacing: 7) {
                ForEach(0..<max(1, Int(width / 16)), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 8, height: height * 0.45)
                }
            }
            HStack {
                Text(text)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 8)
                Spacer()
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - EXIF 拍摄参数铭牌横幅

    private var exifParamText: String {
        "\(exifInfo.cameraModel) · \(exifInfo.focalLength) · \(exifInfo.aperture) · \(exifInfo.shutterSpeed) · \(exifInfo.iso)"
    }

    private func exifBarOverlay(size: CGSize) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 8.5, weight: .bold))
            Text(exifParamText)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(Color.black.opacity(0.72), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
        .shadow(color: Color.black.opacity(0.4), radius: 3, y: 1)
        .position(x: exifBarPosition.x * size.width, y: exifBarPosition.y * size.height)
        .gesture(
            DragGesture()
                .onChanged { val in
                    let newX = min(max(val.location.x / size.width, 0.05), 0.95)
                    let newY = min(max(val.location.y / size.height, 0.05), 0.95)
                    exifBarPosition = CGPoint(x: newX, y: newY)
                }
        )
    }

    // MARK: - 日期水印印记 (经典石英橙色点阵，支持自由拖动)

    private func dateStampOverlay(size: CGSize) -> some View {
        let displayDate: String = {
            switch dateStampStyle {
            case 0:
                // 经典 90 年代胶片橙色缩写: '26 10 25
                let parts = exifInfo.dateString.split(separator: ".")
                if parts.count == 3 {
                    let yy = String(parts[0].suffix(2))
                    return "'\(yy) \(parts[1]) \(parts[2])"
                }
                return "'26 10 25"
            case 1:
                return exifInfo.dateString
            default:
                return "OCT 25 '26"
            }
        }()

        return Text(displayDate)
            .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.08))
            .shadow(color: Color(red: 1.0, green: 0.40, blue: 0.0).opacity(0.85), radius: 3, y: 1)
            .padding(6)
            .position(x: dateStampPosition.x * size.width, y: dateStampPosition.y * size.height)
            .gesture(
                DragGesture()
                    .onChanged { val in
                        let newX = min(max(val.location.x / size.width, 0.05), 0.95)
                        let newY = min(max(val.location.y / size.height, 0.05), 0.95)
                        dateStampPosition = CGPoint(x: newX, y: newY)
                    }
            )
    }

    // MARK: - 地址水印 (支持自由拖动)

    private func locationStampOverlay(size: CGSize) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 8, weight: .bold))
            Text(locationText.isEmpty ? exifInfo.locationString : locationText)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color.black.opacity(0.65), in: Capsule())
        .shadow(color: Color.black.opacity(0.4), radius: 3, y: 1)
        .position(x: locationStampPosition.x * size.width, y: locationStampPosition.y * size.height)
        .gesture(
            DragGesture()
                .onChanged { val in
                    let newX = min(max(val.location.x / size.width, 0.05), 0.95)
                    let newY = min(max(val.location.y / size.height, 0.05), 0.95)
                    locationStampPosition = CGPoint(x: newX, y: newY)
                }
        )
    }

    // MARK: - 贴纸交互视图 (支持拖动排版与轻触移除)

    private func stickerView(sticker: EditorSticker, canvasSize: CGSize) -> some View {
        let posX = sticker.position.x * canvasSize.width
        let posY = sticker.position.y * canvasSize.height

        return ZStack(alignment: .topTrailing) {
            Text(sticker.text)
                .font(.system(size: sticker.text.count > 2 ? 11 : 24, weight: .black, design: .rounded))
                .foregroundStyle(GrainTheme.paper)
                .padding(sticker.text.count > 2 ? 5 : 0)
                .background(sticker.text.count > 2 ? GrainTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .shadow(color: Color.black.opacity(0.4), radius: 3, y: 1)

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    stickers.removeAll { $0.id == sticker.id }
                }
                GrainHaptics.selection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .background(Color.white, in: Circle())
            }
            .offset(x: 6, y: -6)
        }
        .position(x: posX, y: posY)
        .gesture(
            DragGesture()
                .onChanged { val in
                    if let idx = stickers.firstIndex(where: { $0.id == sticker.id }) {
                        let newX = min(max(val.location.x / canvasSize.width, 0.05), 0.95)
                        let newY = min(max(val.location.y / canvasSize.height, 0.05), 0.95)
                        stickers[idx].position = CGPoint(x: newX, y: newY)
                    }
                }
        )
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
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 17, height: 17)
                    .background(Color.black.opacity(0.82), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
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

    // MARK: - 控制区与模块化功能 Deck

    private var controls: some View {
        VStack(spacing: 8) {
            // 顶层 4 大功能分类 Deck 切换条
            categoryDeck

            switch activeTab {
            case .layout:
                layoutControls
            case .filmFrame:
                filmFrameControls
            case .watermark:
                watermarkControls
            case .addText:
                addTextControls
            }

            actionRow
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var categoryDeck: some View {
        HStack(spacing: 6) {
            ForEach(EditorDeckTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        activeTab = tab
                    }
                    GrainHaptics.selection(enabled: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 9.5, weight: .bold))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(activeTab == tab ? GrainTheme.black : GrainTheme.paper)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(activeTab == tab ? GrainTheme.accent : GrainTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }

    // 1. 排版与边距控制面板
    private var layoutControls: some View {
        VStack(spacing: 6) {
            templateRow
            ratioRow
            sliderRow(
                title: "间距",
                value: Binding(get: { spacing }, set: { spacing = $0 }),
                range: 0...100,
                display: "\(Int(spacing))"
            )
            sliderRow(
                title: "圆角",
                value: Binding(get: { corner }, set: { corner = $0 }),
                range: 0...100,
                display: "\(Int(corner))"
            )
            backgroundRow
        }
    }

    // 2. 胶片相框控制面板
    private var filmFrameControls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilmFrameStyle.allCases) { style in
                        Button {
                            withAnimation(.snappy(duration: 0.22)) {
                                filmFrame = style
                            }
                            GrainHaptics.selection(enabled: true)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: style.icon)
                                    .font(.system(size: 14, weight: .bold))
                                Text(style.rawValue)
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(filmFrame == style ? GrainTheme.black : GrainTheme.paper)
                            .frame(width: 70, height: 50)
                            .background(filmFrame == style ? GrainTheme.accent : GrainTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(height: 54)

            Text("胶片相框模拟经典暗房相纸、35mm 齿孔胶卷底片与拍立得白框")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(GrainTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
        }
    }

    // 3. 水印与数据面板 (日期、地址、EXIF 拍摄参数)
    private var watermarkControls: some View {
        VStack(spacing: 6) {
            // 日期开关与样式切换
            HStack(spacing: 8) {
                Button {
                    withAnimation { showDateStamp.toggle() }
                    GrainHaptics.selection(enabled: true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showDateStamp ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(showDateStamp ? GrainTheme.accent : GrainTheme.muted)
                        Text("日期印记")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(GrainTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain)

                if showDateStamp {
                    HStack(spacing: 5) {
                        Button("石英点阵") { dateStampStyle = 0 }
                            .font(.system(size: 9, weight: dateStampStyle == 0 ? .bold : .medium))
                            .foregroundStyle(dateStampStyle == 0 ? GrainTheme.accent : GrainTheme.muted)
                        Text("·").foregroundStyle(GrainTheme.muted)
                        Button("现代极简") { dateStampStyle = 1 }
                            .font(.system(size: 9, weight: dateStampStyle == 1 ? .bold : .medium))
                            .foregroundStyle(dateStampStyle == 1 ? GrainTheme.accent : GrainTheme.muted)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(GrainTheme.surface, in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 18)

            // 地址水印开关
            HStack(spacing: 8) {
                Button {
                    withAnimation { showLocationStamp.toggle() }
                    GrainHaptics.selection(enabled: true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showLocationStamp ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(showLocationStamp ? GrainTheme.accent : GrainTheme.muted)
                        Text("拍摄地址")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(GrainTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain)

                if showLocationStamp {
                    TextField("输入地址或城市", text: $locationText)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(GrainTheme.surface, in: Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 18)

            // EXIF 拍摄参数铭牌开关
            HStack(spacing: 8) {
                Button {
                    withAnimation { showEXIFBar.toggle() }
                    GrainHaptics.selection(enabled: true)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showEXIFBar ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(showEXIFBar ? GrainTheme.accent : GrainTheme.muted)
                        Text("EXIF 拍摄数据")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(GrainTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain)

                if showEXIFBar {
                    Text(exifParamText)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(GrainTheme.muted)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
        }
    }

    // 4. 添加文字面板（全面支持自定义输入、预设词条与表情，并保留照片编辑里的文字）
    private var addTextControls: some View {
        VStack(spacing: 8) {
            // 自定义文字输入与添加按钮
            HStack(spacing: 8) {
                TextField("输入照片上的文字...", text: $customTextInput)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(GrainTheme.surface, in: Capsule())
                    .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))

                Button {
                    let trimmed = customTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    addSticker(trimmed)
                    customTextInput = ""
                    GrainHaptics.selection(enabled: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("添加文字")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(customTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? GrainTheme.muted : GrainTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(customTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let labelStickers = ["FILM", "RAW", "35MM", "PORTRA", "FUJIFILM", "CINEMA", "MEMORY", "SUMMER", "VINTAGE", "GRAIN"]
                    ForEach(labelStickers, id: \.self) { badge in
                        Button {
                            addSticker(badge)
                        } label: {
                            Text(badge)
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(GrainTheme.paper)
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }

                    let emojiStickers = ["🎞️", "📷", "📸", "⚡️", "☀️", "🌙", "📼", "🌈", "☕️", "🖤", "✨", "🎬"]
                    ForEach(emojiStickers, id: \.self) { emoji in
                        Button {
                            addSticker(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 16))
                                .frame(width: 30, height: 30)
                                .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .frame(height: 32)

            HStack {
                Text("轻按添加文字，在照片上可任意拖拽排版")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GrainTheme.muted)
                Spacer()
                if !stickers.isEmpty {
                    Button("清空文字") {
                        withAnimation { stickers.removeAll() }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.red)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func addSticker(_ text: String) {
        let newX = Double.random(in: 0.35...0.65)
        let newY = Double.random(in: 0.35...0.65)
        let s = EditorSticker(text: text, position: CGPoint(x: newX, y: newY))
        withAnimation(.snappy(duration: 0.2)) {
            stickers.append(s)
        }
        GrainHaptics.selection(enabled: true)
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
        .frame(height: 28)
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
        .frame(height: 28)
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
        .padding(.top, 4)
    }

    // MARK: 手势与交互

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                if value.startLocation.x < 36, value.translation.width > 80 {
                    dismiss()
                }
            }
    }

    private func shuffleOrder() {
        withAnimation(.snappy(duration: 0.26)) {
            selectedAssets.shuffle()
        }
        GrainHaptics.mediumImpact(enabled: true)
        showNotice("已打乱照片顺序")
    }

    private func makeCover(_ asset: PHAsset) {
        guard let index = selectedAssets.firstIndex(of: asset), index > 0 else { return }
        withAnimation(.snappy(duration: 0.24)) {
            selectedAssets.remove(at: index)
            selectedAssets.insert(asset, at: 0)
        }
        GrainHaptics.selection(enabled: true)
        showNotice("已设为封面")
    }

    private func move(_ asset: PHAsset, offset: Int) {
        guard let index = selectedAssets.firstIndex(of: asset) else { return }
        let target = index + offset
        guard target >= 0, target < selectedAssets.count else { return }
        withAnimation(.snappy(duration: 0.24)) {
            selectedAssets.remove(at: index)
            selectedAssets.insert(asset, at: target)
        }
        GrainHaptics.selection(enabled: true)
    }

    private func remove(_ asset: PHAsset) {
        withAnimation(.snappy(duration: 0.24)) {
            selectedAssets.removeAll { $0 == asset }
            previewImages.removeValue(forKey: asset.localIdentifier)
        }
        GrainHaptics.selection(enabled: true)
        showNotice("已移除照片")
    }

    private func addPickedAssets(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        pickerError = nil
        let ids = items.compactMap(\.itemIdentifier)
        guard !ids.isEmpty else {
            pickerError = "未能读取所选照片的标识符"
            return
        }

        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var added: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in
            if !self.selectedAssets.contains(asset) {
                added.append(asset)
            }
        }

        let capacity = max(0, 10 - selectedAssets.count)
        let trimmed = Array(added.prefix(capacity))
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            selectedAssets.append(contentsOf: trimmed)
            pickerItems.removeAll()
        }

        for asset in trimmed {
            if let img = await CollageImageLoader.image(for: asset, targetSize: CGSize(width: 480, height: 480)) {
                await MainActor.run {
                    previewImages[asset.localIdentifier] = img
                }
            }
        }
        GrainHaptics.selection(enabled: true)
        showNotice("已添加 \(trimmed.count) 张照片")
    }

    private func loadPreviewImages() async {
        isLoading = true
        for asset in selectedAssets {
            if previewImages[asset.localIdentifier] == nil {
                if let img = await CollageImageLoader.image(
                    for: asset,
                    targetSize: CGSize(width: 480, height: 480)
                ) {
                    await MainActor.run {
                        previewImages[asset.localIdentifier] = img
                    }
                }
            }
        }
        isLoading = false
    }

    private func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                if notice == text {
                    notice = nil
                }
            }
        }
    }

    private func replaceExportURL(with url: URL) {
        if let existing = exportURL, existing != url {
            try? FileManager.default.removeItem(at: existing)
        }
        exportURL = url
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
                showNotice("作品已保存到照片图库")
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

    // MARK: - 高清渲染与多层导出

    private func renderCollage() async throws -> URL {
        let assets = selectedAssets
        let templateValue = template
        let ratioValue = ratio.value
        let spacingValue = spacing
        let cornerValue = corner
        let backgroundValue = background
        let filmFrameValue = filmFrame
        let showDateStampValue = showDateStamp
        let dateStampStyleValue = dateStampStyle
        let showLocationStampValue = showLocationStamp
        let locationTextValue = locationText
        let showEXIFBarValue = showEXIFBar
        let stickersValue = stickers
        let exifInfoValue = exifInfo
        let exifBarPositionValue = exifBarPosition
        let dateStampPositionValue = dateStampPosition
        let locationStampPositionValue = locationStampPosition
        let cellTransformsValue = cellTransforms

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
        let gapFraction = CGFloat(spacingValue) / 100.0 * (assets.count <= 1 ? 0.38 : (0.50 / CGFloat(max(slots.count, 1))))
        let rects = CollageLayoutEngine.cellRects(
            slots: slots,
            in: canvasSize,
            gapFraction: gapFraction
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
            width: min(maxCell.width, 2400),
            height: min(maxCell.height, 2400)
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
                let maxRadius = min(rect.width, rect.height) / 2
                let radius = min(CGFloat(cornerValue) / 100.0 * maxRadius, maxRadius)
                let transform = cellTransformsValue[assets[index].localIdentifier] ?? PhotoCellTransform()
                cg.saveGState()
                let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
                cg.addPath(path.cgPath)
                cg.clip()
                drawAspectFill(image, in: rect, context: cg, transform: transform)
                cg.restoreGState()
            }

            // 1. 胶片模拟相框
            drawFilmFrame(filmFrameValue, in: canvasSize, context: cg, exifInfo: exifInfoValue)

            // 2. EXIF 拍摄参数横幅（使用用户拖拽的位置）
            if showEXIFBarValue {
                drawEXIFBar(exifInfoValue, in: canvasSize, context: cg, position: exifBarPositionValue)
            }

            // 3. 日期印记（使用用户拖拽的位置）
            if showDateStampValue {
                drawDateStamp(exifInfoValue.dateString, in: canvasSize, context: cg, style: dateStampStyleValue, position: dateStampPositionValue)
            }

            // 4. 地址水印（使用用户拖拽的位置）
            if showLocationStampValue {
                drawLocationStamp(locationTextValue.isEmpty ? exifInfoValue.locationString : locationTextValue, in: canvasSize, context: cg, position: locationStampPositionValue)
            }

            // 5. 贴纸与表情包
            drawStickers(stickersValue, in: canvasSize, context: cg)
        }

        guard let data = collage.jpegData(compressionQuality: 0.98) else {
            throw CollageError.renderFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GRAIN-edit-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func drawAspectFill(
        _ image: UIImage,
        in rect: CGRect,
        context: CGContext,
        transform: PhotoCellTransform = PhotoCellTransform()
    ) {
        let baseScale = max(
            rect.width / max(image.size.width, 1),
            rect.height / max(image.size.height, 1)
        ) * max(transform.scale, 0.2)
        let drawSize = CGSize(
            width: image.size.width * baseScale,
            height: image.size.height * baseScale
        )
        let offsetX = transform.normalizedOffset.width * rect.width
        let offsetY = transform.normalizedOffset.height * rect.height
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2 + offsetX,
            y: rect.midY - drawSize.height / 2 + offsetY,
            width: drawSize.width,
            height: drawSize.height
        )
        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    // MARK: - 导出绘制辅助

    private func drawFilmFrame(_ style: FilmFrameStyle, in size: CGSize, context: CGContext, exifInfo: PhotoEXIFInfo) {
        switch style {
        case .none:
            break
        case .polaroid:
            let borderT = size.width * 0.05
            let borderB = size.height * 0.16
            let innerRadius = borderT * 0.8
            context.saveGState()

            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: size))
            let innerRect = CGRect(x: borderT, y: borderT, width: size.width - borderT * 2, height: size.height - borderT - borderB)
            let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerRadius)
            path.addPath(innerPath.cgPath)
            context.addPath(path)
            context.setFillColor(UIColor.white.cgColor)
            context.drawPath(using: .eoFill)

            let dateText = NSString(string: exifInfo.dateString)
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.024, weight: .bold),
                .foregroundColor: UIColor.black.withAlphaComponent(0.68)
            ]
            dateText.draw(at: CGPoint(x: borderT * 1.5, y: size.height - borderB * 0.55), withAttributes: dateAttrs)

            let brandText = NSString(string: "POLAROID · GRAIN")
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.020, weight: .heavy),
                .foregroundColor: UIColor.black.withAlphaComponent(0.42)
            ]
            let brandSize = brandText.size(withAttributes: brandAttrs)
            brandText.draw(at: CGPoint(x: size.width - borderT * 1.5 - brandSize.width, y: size.height - borderB * 0.55), withAttributes: brandAttrs)
            context.restoreGState()

        case .blackPolaroid:
            let borderT = size.width * 0.05
            let borderB = size.height * 0.16
            let innerRadius = borderT * 0.8
            context.saveGState()

            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: size))
            let innerRect = CGRect(x: borderT, y: borderT, width: size.width - borderT * 2, height: size.height - borderT - borderB)
            let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerRadius)
            path.addPath(innerPath.cgPath)
            context.addPath(path)
            context.setFillColor(UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0).cgColor)
            context.drawPath(using: .eoFill)

            let dateText = NSString(string: exifInfo.dateString)
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.024, weight: .bold),
                .foregroundColor: UIColor(red: 0.95, green: 0.78, blue: 0.35, alpha: 1.0)
            ]
            dateText.draw(at: CGPoint(x: borderT * 1.5, y: size.height - borderB * 0.55), withAttributes: dateAttrs)

            let brandText = NSString(string: "BLACK POLAROID · GRAIN")
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.020, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.48)
            ]
            let brandSize = brandText.size(withAttributes: brandAttrs)
            brandText.draw(at: CGPoint(x: size.width - borderT * 1.5 - brandSize.width, y: size.height - borderB * 0.55), withAttributes: brandAttrs)
            context.restoreGState()

        case .sprocket35mm:
            drawSprocketFrame(in: size, context: context, topText: "KODAK PORTRA 400 · 36", bottomText: "FILM 135 · 36A · DX 400", textColor: UIColor(red: 1.0, green: 0.72, blue: 0.15, alpha: 1.0))

        case .kodakGold:
            drawSprocketFrame(in: size, context: context, topText: "KODAK GOLD 200 · 24 EXP", bottomText: "SAFETY FILM · 24A · DX 200", textColor: UIColor(red: 1.0, green: 0.78, blue: 0.12, alpha: 1.0))

        case .fujiSuperia:
            drawSprocketFrame(in: size, context: context, topText: "FUJIFILM SUPERIA X-TRA 400", bottomText: "SUPERIA 400 · CN-16 · 36A", textColor: UIColor(red: 0.25, green: 0.88, blue: 0.45, alpha: 1.0))

        case .mediumFormat:
            // 哈苏 6x6 中画幅（内圆弧平滑过渡，告别生硬直角）
            let border = size.width * 0.045
            let innerRadius = border * 1.25
            context.saveGState()

            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: size))
            let innerRect = CGRect(x: border, y: border, width: size.width - border * 2, height: size.height - border * 2)
            let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerRadius)
            path.addPath(innerPath.cgPath)
            context.addPath(path)
            context.setFillColor(UIColor.black.cgColor)
            context.drawPath(using: .eoFill)

            let txtAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.016, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65)
            ]
            NSString(string: "HASSELBLAD 6X6 - 120 FILM").draw(at: CGPoint(x: border * 1.5, y: border * 0.25), withAttributes: txtAttrs)
            context.restoreGState()

        case .disposable:
            // 一次性相机纸质取景框（内孔平滑圆角）
            let border = size.width * 0.040
            let innerRadius = border * 1.15
            context.saveGState()

            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: size))
            let innerRect = CGRect(x: border, y: border, width: size.width - border * 2, height: size.height - border * 2)
            let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerRadius)
            path.addPath(innerPath.cgPath)
            context.addPath(path)
            context.setFillColor(UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0).cgColor)
            context.drawPath(using: .eoFill)

            let txtAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.015, weight: .bold),
                .foregroundColor: UIColor(red: 0.98, green: 0.42, blue: 0.18, alpha: 1.0)
            ]
            NSString(string: "QUICKSNAP 400 · DISPOSABLE").draw(at: CGPoint(x: border * 1.5, y: size.height - border * 0.8), withAttributes: txtAttrs)
            context.restoreGState()

        case .ilfordHP5:
            // 伊尔福 HP5 Plus 经典黑白印相底片框
            let border = size.width * 0.042
            let innerRadius = border * 1.2
            context.saveGState()

            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: size))
            let innerRect = CGRect(x: border, y: border, width: size.width - border * 2, height: size.height - border * 2)
            let innerPath = UIBezierPath(roundedRect: innerRect, cornerRadius: innerRadius)
            path.addPath(innerPath.cgPath)
            context.addPath(path)
            context.setFillColor(UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0).cgColor)
            context.drawPath(using: .eoFill)

            let txtAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.016, weight: .black),
                .foregroundColor: UIColor.white
            ]
            NSString(string: "ILFORD HP5 PLUS - 400").draw(at: CGPoint(x: border * 1.5, y: border * 0.25), withAttributes: txtAttrs)
            let btmAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.014, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.45)
            ]
            NSString(string: "B&W DARKROOM PRINT").draw(at: CGPoint(x: border * 1.5, y: size.height - border * 0.8), withAttributes: btmAttrs)
            context.restoreGState()
        }
    }

    private func drawSprocketFrame(in size: CGSize, context: CGContext, topText: String, bottomText: String, textColor: UIColor) {
        let barH = size.height * 0.09
        context.saveGState()
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: barH))
        context.fill(CGRect(x: 0, y: size.height - barH, width: size.width, height: barH))

        // 齿孔
        let holeW = size.width * 0.024
        let holeH = barH * 0.52
        let count = Int(size.width / (holeW * 1.8))
        let step = size.width / CGFloat(max(count, 1))

        context.setFillColor(UIColor.white.withAlphaComponent(0.24).cgColor)
        for i in 0..<count {
            let x = CGFloat(i) * step + step * 0.2
            let topHole = CGRect(x: x, y: barH * 0.24, width: holeW, height: holeH)
            let btmHole = CGRect(x: x, y: size.height - barH + barH * 0.24, width: holeW, height: holeH)
            let p1 = UIBezierPath(roundedRect: topHole, cornerRadius: 3)
            context.addPath(p1.cgPath)
            context.fillPath()
            let p2 = UIBezierPath(roundedRect: btmHole, cornerRadius: 3)
            context.addPath(p2.cgPath)
            context.fillPath()
        }

        let txtAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.018, weight: .bold),
            .foregroundColor: textColor
        ]
        NSString(string: topText).draw(at: CGPoint(x: 24, y: barH * 0.62), withAttributes: txtAttrs)
        NSString(string: bottomText).draw(at: CGPoint(x: 24, y: size.height - barH * 0.38), withAttributes: txtAttrs)
        context.restoreGState()
    }

    private func drawEXIFBar(_ info: PhotoEXIFInfo, in size: CGSize, context: CGContext, position: CGPoint = CGPoint(x: 0.5, y: 0.92)) {
        let text = NSString(string: "\(info.cameraModel) · \(info.focalLength) · \(info.aperture) · \(info.shutterSpeed) · \(info.iso)")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.021, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let pillRect = CGRect(
            x: position.x * size.width - (textSize.width + 40) / 2,
            y: position.y * size.height - (textSize.height + 16) / 2,
            width: textSize.width + 40,
            height: textSize.height + 16
        )

        context.saveGState()
        context.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
        let path = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
        context.addPath(path.cgPath)
        context.fillPath()

        text.draw(at: CGPoint(x: pillRect.minX + 20, y: pillRect.minY + 8), withAttributes: attrs)
        context.restoreGState()
    }

    private func drawDateStamp(_ dateString: String, in size: CGSize, context: CGContext, style: Int, position: CGPoint = CGPoint(x: 0.82, y: 0.92)) {
        let display: String = {
            switch style {
            case 0:
                let parts = dateString.split(separator: ".")
                if parts.count == 3 {
                    let yy = String(parts[0].suffix(2))
                    return "'\(yy) \(parts[1]) \(parts[2])"
                }
                return "'26 10 25"
            case 1:
                return dateString
            default:
                return "OCT 25 '26"
            }
        }()

        let text = NSString(string: display)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: size.width * 0.030, weight: .heavy),
            .foregroundColor: UIColor(red: 1.0, green: 0.48, blue: 0.08, alpha: 1.0)
        ]
        let textSize = text.size(withAttributes: attrs)
        let pt = CGPoint(
            x: position.x * size.width - textSize.width / 2,
            y: position.y * size.height - textSize.height / 2
        )

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0.85).cgColor)
        text.draw(at: pt, withAttributes: attrs)
        context.restoreGState()
    }

    private func drawLocationStamp(_ location: String, in size: CGSize, context: CGContext, position: CGPoint = CGPoint(x: 0.22, y: 0.92)) {
        guard !location.isEmpty else { return }
        let text = NSString(string: "📍 " + location)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size.width * 0.021, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attrs)
        let pillRect = CGRect(
            x: position.x * size.width - (textSize.width + 24) / 2,
            y: position.y * size.height - (textSize.height + 14) / 2,
            width: textSize.width + 24,
            height: textSize.height + 14
        )

        context.saveGState()
        context.setFillColor(UIColor.black.withAlphaComponent(0.68).cgColor)
        let path = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
        context.addPath(path.cgPath)
        context.fillPath()

        text.draw(at: CGPoint(x: pillRect.minX + 12, y: pillRect.minY + 7), withAttributes: attrs)
        context.restoreGState()
    }

    private func drawStickers(_ stickers: [EditorSticker], in size: CGSize, context: CGContext) {
        for sticker in stickers {
            let pt = CGPoint(x: sticker.position.x * size.width, y: sticker.position.y * size.height)
            let isLabel = sticker.text.count > 2
            let text = NSString(string: sticker.text)
            let fontSize = isLabel ? size.width * 0.028 : size.width * 0.060
            let attrs: [NSAttributedString.Key: Any] = [
                .font: isLabel ? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .heavy) : UIFont.systemFont(ofSize: fontSize),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attrs)
            let drawRect = CGRect(x: pt.x - textSize.width / 2, y: pt.y - textSize.height / 2, width: textSize.width, height: textSize.height)

            context.saveGState()
            if isLabel {
                let bgRect = drawRect.insetBy(dx: -10, dy: -6)
                context.setFillColor(UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 0.95).cgColor)
                let p = UIBezierPath(roundedRect: bgRect, cornerRadius: 6)
                context.addPath(p.cgPath)
                context.fillPath()
            }
            text.draw(in: drawRect, withAttributes: attrs)
            context.restoreGState()
        }
    }

    private func saveCollageToLibrary(_ url: URL) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    continuation.resume(returning: newStatus == .authorized || newStatus == .limited)
                }
            }
            guard granted else { throw CollageError.photoLibraryDenied }
        } else if status != .authorized && status != .limited {
            throw CollageError.photoLibraryDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: url, options: options)
            }) { success, error in
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
}

// MARK: - 辅助图片加载

private enum CollageImageLoader {
    static func image(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            let gate = CollageImageContinuation(continuation)

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let img, !degraded {
                    gate.resume(with: img)
                } else if img == nil {
                    gate.resume(with: nil)
                }
            }
        }
    }
}

private final class CollageImageContinuation: @unchecked Sendable {
    private let continuation: CheckedContinuation<UIImage?, Never>
    private var isResumed = false
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<UIImage?, Never>) {
        self.continuation = continuation
    }

    func resume(with image: UIImage?) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        continuation.resume(returning: image)
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
            return "请选择 1 到 10 张照片进行编辑"
        case .imageUnavailable:
            return "未能从图库下载并解码所选照片的高清图"
        case .renderFailed:
            return "生成图片失败，请检查设备内存后重试"
        case .photoLibraryDenied:
            return "未获得写入照片图库的权限，请在系统设置中允许访问"
        case .saveFailed:
            return "保存到照片图库失败，请稍后重试"
        }
    }
}

// MARK: - 系统通用分享面板 (GrainShareSheet)
struct GrainShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
