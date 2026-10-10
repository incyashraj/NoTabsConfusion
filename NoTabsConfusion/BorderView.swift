import AppKit
import QuartzCore

// One steady border. Rank 0, 1, and 2 differ only by the color they are given.
final class BorderView: NSView {

    var borderColor: NSColor = Prefs.defaultColors[0] { didSet { updateAppearance() } }
    var borderWidth: CGFloat = Prefs.defaultWidth { didSet { updateAppearance() } }
    var glowRadius: CGFloat = Prefs.defaultGlow { didSet { updateAppearance() } }
    var showsIcon: Bool = true { didSet { updateIconLayer() } }
    var appIcon: NSImage? { didSet { updateIconLayer() } }

    private let stroke = CAShapeLayer()
    private let ringMask = CAShapeLayer()
    private let icon = CALayer()
    private let iconSize: CGFloat = 32

    override var isOpaque: Bool { false }

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        layer?.isOpaque = false

        stroke.fillColor = CGColor.clear
        stroke.lineJoin = .round
        stroke.shadowOffset = .zero
        stroke.shadowPath = nil
        ringMask.fillRule = .evenOdd
        stroke.mask = ringMask
        layer?.addSublayer(stroke)

        icon.contentsGravity = .resizeAspect
        icon.cornerRadius = 7
        icon.masksToBounds = true
        layer?.addSublayer(icon)

        updateAppearance()
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.fillColor = CGColor.clear
        stroke.strokeColor = borderColor.cgColor
        stroke.lineWidth = borderWidth
        stroke.shadowColor = borderColor.cgColor
        stroke.shadowRadius = glowRadius
        stroke.shadowOpacity = glowRadius > 0 ? 0.85 : 0
        stroke.shadowPath = nil
        CATransaction.commit()
        needsLayout = true
    }

    private func updateIconLayer() {
        icon.contents = appIcon
        icon.isHidden = !showsIcon || appIcon == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 4, bounds.height > 4 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let inset = borderWidth / 2 + 1
        let path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        stroke.frame = bounds
        stroke.path = path
        stroke.fillColor = CGColor.clear
        stroke.shadowPath = nil
        // The glow is a shadow. Without a hole it paints the whole window.
        // Keep a ring at the edge and leave the middle empty.
        let ring = CGMutablePath()
        ring.addRect(bounds)
        let reach = borderWidth + glowRadius + 1
        let limit = min(bounds.width, bounds.height) / 2 - 2
        let hole = min(reach, max(limit, 0))
        if hole > 1 {
            let inner = bounds.insetBy(dx: hole, dy: hole)
            if inner.width > 2, inner.height > 2 {
                ring.addRoundedRect(in: inner, cornerWidth: 8, cornerHeight: 8)
            }
        }
        ringMask.frame = bounds
        ringMask.path = ring

        let offset = iconSize / 2 - borderWidth
        icon.frame = CGRect(
            x: offset,
            y: bounds.height - offset - iconSize,
            width: iconSize,
            height: iconSize
        )
        icon.isHidden = !showsIcon || appIcon == nil

        CATransaction.commit()
    }
}
