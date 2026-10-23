import SwiftUI
import UIKit

struct TextOverlayInteractionView: UIViewRepresentable {
    let overlays: [PhotoTextOverlay]
    let selectedID: UUID?
    let canvasSize: CGSize
    let hapticsEnabled: Bool
    let onSelect: (UUID?) -> Void
    let onEdit: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onMoveStart: () -> Void
    let onMove: (UUID, CGPoint) -> Void
    let onTapEmpty: () -> Void
    /// 双击位置（照片画布坐标）：未放大时放大到该点，已放大时复位
    let onDoubleTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> TextOverlayCanvasUIView {
        let view = TextOverlayCanvasUIView()
        update(view)
        return view
    }

    func updateUIView(_ uiView: TextOverlayCanvasUIView, context: Context) {
        update(uiView)
    }

    private func update(_ view: TextOverlayCanvasUIView) {
        view.configure(
            overlays: overlays,
            selectedID: selectedID,
            canvasSize: canvasSize,
            hapticsEnabled: hapticsEnabled,
            onSelect: onSelect,
            onEdit: onEdit,
            onDelete: onDelete,
            onMoveStart: onMoveStart,
            onMove: onMove,
            onTapEmpty: onTapEmpty,
            onDoubleTap: onDoubleTap
        )
    }
}

final class TextOverlayCanvasUIView: UIView, UIGestureRecognizerDelegate {
    private var overlays: [PhotoTextOverlay] = []
    private var itemViews: [UUID: TextOverlayItemUIView] = [:]
    private var canvasSize = CGSize.zero
    private var hapticsEnabled = true
    private var activeDragID: UUID?

    private var onSelect: ((UUID?) -> Void)?
    private var onEdit: ((UUID) -> Void)?
    private var onDelete: ((UUID) -> Void)?
    private var onMoveStart: (() -> Void)?
    private var onMove: ((UUID, CGPoint) -> Void)?
    private var onTapEmpty: (() -> Void)?
    private var onDoubleTap: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleEmptyTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)

        // 双击恒可用：未放大时放大到双击点，已放大时复位
        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        overlays: [PhotoTextOverlay],
        selectedID: UUID?,
        canvasSize: CGSize,
        hapticsEnabled: Bool,
        onSelect: @escaping (UUID?) -> Void,
        onEdit: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onMoveStart: @escaping () -> Void,
        onMove: @escaping (UUID, CGPoint) -> Void,
        onTapEmpty: @escaping () -> Void,
        onDoubleTap: @escaping (CGPoint) -> Void
    ) {
        self.overlays = overlays
        self.canvasSize = canvasSize
        self.hapticsEnabled = hapticsEnabled
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onMoveStart = onMoveStart
        self.onMove = onMove
        self.onTapEmpty = onTapEmpty
        self.onDoubleTap = onDoubleTap

        let validIDs = Set(overlays.map(\.id))
        for (id, item) in itemViews where !validIDs.contains(id) {
            item.removeFromSuperview()
            itemViews.removeValue(forKey: id)
        }

        for overlay in overlays {
            let item: TextOverlayItemUIView
            if let existing = itemViews[overlay.id] {
                item = existing
            } else {
                item = TextOverlayItemUIView()
                itemViews[overlay.id] = item
                addSubview(item)
                wire(item, id: overlay.id)
            }

            item.configure(
                overlay: overlay,
                selected: selectedID == overlay.id,
                canvasSize: canvasSize,
                hapticsEnabled: hapticsEnabled
            )

            if activeDragID != overlay.id {
                item.center = CGPoint(
                    x: overlay.x * canvasSize.width,
                    y: overlay.y * canvasSize.height
                )
            }
        }

        if let selectedID, let selectedItem = itemViews[selectedID] {
            bringSubviewToFront(selectedItem)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        let point = touch.location(in: self)
        return !itemViews.values.contains { $0.frame.contains(point) }
    }

    private func wire(_ item: TextOverlayItemUIView, id: UUID) {
        item.onTap = { [weak self] in
            guard let self else { return }
            if self.itemViews[id]?.isSelected == true {
                self.onEdit?(id)
            } else {
                self.onSelect?(id)
            }
        }
        item.onDelete = { [weak self] in
            self?.onDelete?(id)
        }
        item.onDragStart = { [weak self] in
            self?.activeDragID = id
            self?.onSelect?(id)
        }
        item.onDragEnd = { [weak self] normalizedCenter in
            guard let self else { return }
            self.activeDragID = nil
            self.onMoveStart?()
            self.onMove?(id, normalizedCenter)
        }
    }

    @objc private func handleEmptyTap() {
        onSelect?(nil)
        onTapEmpty?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        onDoubleTap?(gesture.location(in: self))
    }
}

private final class TextOverlayItemUIView: UIView {
    private let label = UILabel()
    private let borderView = UIView()
    private let deleteButton = UIButton(type: .custom)

    private var canvasSize = CGSize.zero
    private var hapticsEnabled = true
    private var dragOrigin = CGPoint.zero
    private var lastHapticDistance: CGFloat = 0
    private var lastGridKey: String?
    private var labelFrame = CGRect.zero

    var isSelected = false
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.backgroundColor = .clear
        label.isUserInteractionEnabled = false
        addSubview(label)

        borderView.backgroundColor = .clear
        borderView.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        borderView.layer.borderWidth = 0.9
        borderView.layer.cornerRadius = 5
        borderView.isUserInteractionEnabled = false
        addSubview(borderView)

        deleteButton.backgroundColor = UIColor(red: 0.714, green: 0.271, blue: 0.196, alpha: 1)
        deleteButton.layer.cornerRadius = 11
        deleteButton.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
        deleteButton.layer.borderWidth = 0.7
        deleteButton.tintColor = .white
        deleteButton.setImage(
            UIImage(systemName: "xmark")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            ),
            for: .normal
        )
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        addSubview(deleteButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        tap.require(toFail: pan)
        addGestureRecognizer(tap)
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        overlay: PhotoTextOverlay,
        selected: Bool,
        canvasSize: CGSize,
        hapticsEnabled: Bool
    ) {
        self.canvasSize = canvasSize
        self.hapticsEnabled = hapticsEnabled
        self.isSelected = selected

        let pointSize = max(
            10,
            min(canvasSize.width, canvasSize.height) * overlay.fontSize
        )
        label.font = overlay.font.grainUIFont(size: pointSize)
        label.textColor = UIColor(
            red: overlay.red,
            green: overlay.green,
            blue: overlay.blue,
            alpha: overlay.alpha
        )
        label.text = overlay.text.isEmpty ? " " : overlay.text

        let maxWidth = max(44, canvasSize.width * 0.78)
        let measured = label.sizeThatFits(
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        )
        let contentSize = CGSize(
            width: min(maxWidth, max(14, ceil(measured.width))),
            height: max(16, ceil(measured.height))
        )
        bounds.size = CGSize(
            width: contentSize.width + 28,
            height: contentSize.height + 28
        )
        labelFrame = CGRect(
            x: 14,
            y: 14,
            width: contentSize.width,
            height: contentSize.height
        )

        borderView.isHidden = !selected
        deleteButton.isHidden = !selected
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = labelFrame
        borderView.frame = labelFrame
        deleteButton.frame = CGRect(
            x: labelFrame.maxX - 11,
            y: labelFrame.minY - 11,
            width: 22,
            height: 22
        )
    }

    @objc private func tapped() {
        onTap?()
    }

    @objc private func deleteTapped() {
        GrainHaptics.lightImpact(enabled: hapticsEnabled)
        onDelete?()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragOrigin = center
            lastHapticDistance = 0
            lastGridKey = nil
            borderView.isHidden = false
            deleteButton.isHidden = false
            onDragStart?()

        case .changed:
            let translation = gesture.translation(in: superview)
            let desired = CGPoint(
                x: dragOrigin.x + translation.x,
                y: dragOrigin.y + translation.y
            )
            let snapped = snappedCenter(desired)
            center = snapped.center

            let distance = hypot(translation.x, translation.y)
            let enteredGridPoint = snapped.gridKey != nil && snapped.gridKey != lastGridKey
            if snapped.gridKey != lastGridKey {
                lastGridKey = snapped.gridKey
                if enteredGridPoint {
                    lastHapticDistance = distance
                    GrainHaptics.lightImpact(enabled: hapticsEnabled)
                }
            }
            if !enteredGridPoint, distance - lastHapticDistance >= 18 {
                lastHapticDistance = distance
                GrainHaptics.selection(enabled: hapticsEnabled)
            }

        case .ended, .cancelled, .failed:
            let normalized = CGPoint(
                x: min(max(center.x / max(canvasSize.width, 1), 0.04), 0.96),
                y: min(max(center.y / max(canvasSize.height, 1), 0.04), 0.96)
            )
            onDragEnd?(normalized)

        default:
            break
        }
    }

    private func snappedCenter(_ point: CGPoint) -> (center: CGPoint, gridKey: String?) {
        let anchors: [CGFloat] = [0.15, 0.50, 0.85]
        let distance: CGFloat = 20
        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2

        var x = min(max(point.x, halfWidth), max(halfWidth, canvasSize.width - halfWidth))
        var y = min(max(point.y, halfHeight), max(halfHeight, canvasSize.height - halfHeight))
        var xIndex: Int?
        var yIndex: Int?

        for (index, anchor) in anchors.enumerated() {
            let target = anchor * canvasSize.width
            if abs(x - target) <= distance {
                x = target
                xIndex = index
                break
            }
        }
        for (index, anchor) in anchors.enumerated() {
            let target = anchor * canvasSize.height
            if abs(y - target) <= distance {
                y = target
                yIndex = index
                break
            }
        }

        let gridKey: String?
        if let xIndex, let yIndex {
            gridKey = "\(xIndex)-\(yIndex)"
        } else {
            gridKey = nil
        }
        return (CGPoint(x: x, y: y), gridKey)
    }
}

private extension PhotoTextFont {
    func grainUIFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let design: UIFontDescriptor.SystemDesign
        switch self {
        case .rounded:
            design = .rounded
        case .serif:
            design = .serif
        case .monospaced:
            design = .monospaced
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
