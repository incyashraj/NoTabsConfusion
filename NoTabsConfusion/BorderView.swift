import AppKit
import QuartzCore

// Rank 0, the app you just left, has a bright segment traveling the edge.
// The other two stay still. A faint 1, 2, or 3 sits in the middle.
final class BorderView: NSView {

    var borderColor: NSColor = Prefs.defaultColors[0] { didSet { updateAppearance() } }
    var borderWidth: CGFloat = Prefs.defaultWidth { didSet { updateAppearance() } }
    var glowRadius: CGFloat = Prefs.defaultGlow { didSet { updateAppearance() } }
    var showsIcon: Bool = true { didSet { updateIconLayer() } }
    var appIcon: NSImage? { didSet { updateIconLayer() } }
    var revolves: Bool = false { didSet { syncMotion() } }
    var rankNumber: Int = 1 { didSet { if rankNumber != oldValue { drawnNumberSide = 0; needsLayout = true } } }

    private let rim = CALayer()
    private let stroke = CAShapeLayer()
    private let comet = CAShapeLayer()
    private let ringMask = CAShapeLayer()
    private let numberLayer = CALayer()
    private let icon = CALayer()
    private let iconSize: CGFloat = 32
    private var drawnNumberSide: CGFloat = 0
    private var dashCycle: CGFloat = 1
    private var animatedCycle: CGFloat = -1

    override var isOpaque: Bool { false }

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        layer?.isOpaque = false

        stroke.fillColor = CGColor.clear
        stroke.lineJoin = .round
        stroke.lineCap = .round
        stroke.shadowOffset = .zero
        stroke.shadowPath = nil

        comet.fillColor = CGColor.clear
        comet.lineJoin = .round
        comet.lineCap = .round
        comet.isHidden = true

        ringMask.fillRule = .evenOdd
        rim.mask = ringMask
        rim.addSublayer(stroke)
        rim.addSublayer(comet)
        layer?.addSublayer(rim)

        numberLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(numberLayer)

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
        syncMotion()
        needsLayout = true
    }

    private func syncMotion() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        comet.isHidden = !revolves
        let bright = borderColor.blended(withFraction: 0.6, of: .white) ?? borderColor
        comet.strokeColor = bright.cgColor
        comet.lineWidth = borderWidth + 2
        comet.fillColor = CGColor.clear
        CATransaction.commit()

        guard revolves else {
            comet.removeAnimation(forKey: "revolve")
            animatedCycle = -1
            return
        }
        if comet.animation(forKey: "revolve") != nil, abs(animatedCycle - dashCycle) < 8 {
            return
        }
        comet.removeAnimation(forKey: "revolve")
        let spin = CABasicAnimation(keyPath: "lineDashPhase")
        spin.fromValue = 0
        spin.toValue = dashCycle
        spin.duration = 1.35
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        comet.add(spin, forKey: "revolve")
        animatedCycle = dashCycle
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
        let pathBounds = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(
            roundedRect: pathBounds,
            cornerWidth: 10,
            cornerHeight: 10,
            transform: nil
        )
        rim.frame = bounds
        stroke.frame = bounds
        stroke.path = path
        stroke.fillColor = CGColor.clear
        stroke.shadowPath = nil
        comet.frame = bounds
        comet.path = path
        let loop = max(2 * (pathBounds.width + pathBounds.height), 40)
        let head = min(max(loop * 0.18, 28), loop * 0.32)
        let gap = max(loop - head, 1)
        dashCycle = head + gap
        comet.lineDashPattern = [NSNumber(value: Double(head)), NSNumber(value: Double(gap))]
        comet.lineDashPhase = 0
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
        placeNumber()

        CATransaction.commit()
        syncMotion()
    }

    // A large gray numeral. Alpha stays low so the window preview still shows through.
    private func placeNumber() {
        let shortest = min(bounds.width, bounds.height)
        guard shortest > 36, (1...3).contains(rankNumber) else {
            numberLayer.isHidden = true
            return
        }
        if abs(shortest - drawnNumberSide) > 1 || numberLayer.contents == nil {
            drawnNumberSide = shortest
            let fontSize = shortest * 0.72
            let base = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
            let font = NSFont(descriptor: descriptor, size: fontSize) ?? base
            let text = NSString(string: "\(rankNumber)")
            // Light, so it shows on the dark previews, with a soft dark edge for light ones.
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.55)
            shadow.shadowBlurRadius = max(fontSize * 0.04, 1.5)
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            let color = NSColor(white: 0.96, alpha: 0.58)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .shadow: shadow
            ]
            let size = text.size(withAttributes: attrs)
            let scale: CGFloat = 2
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: max(Int(size.width * scale), 1),
                pixelsHigh: max(Int(size.height * scale), 1),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { return }
            NSGraphicsContext.saveGraphicsState()
            if let gfx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = gfx
                gfx.cgContext.scaleBy(x: scale, y: scale)
                text.draw(at: .zero, withAttributes: attrs)
            }
            NSGraphicsContext.restoreGraphicsState()
            numberLayer.contents = rep.cgImage
            numberLayer.contentsScale = scale
            numberLayer.bounds = CGRect(origin: .zero, size: size)
        }
        let size = numberLayer.bounds.size
        numberLayer.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        numberLayer.isHidden = false
    }
}
