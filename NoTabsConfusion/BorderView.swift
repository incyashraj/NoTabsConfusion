import AppKit
import QuartzCore

// rank 0 — animated gradient glow (purple→blue→cyan), slow rotation
// rank 1 — amber static glow
// rank 2 — teal static glow
final class BorderView: NSView {

    var rank: Int = 0 { didSet { rebuild() } }
    var glowRadius:  CGFloat { rank == 0 ? 18 : (rank == 1 ? 10 : 6) }
    var borderWidth: CGFloat { rank == 0 ? 5  : (rank == 1 ? 3  : 1.5) }

    var appIcon: NSImage? { didSet { updateIconLayer() } }

    private var gradientLayer:  CAGradientLayer?
    private var strokeMask:     CAShapeLayer?
    private var glowLayer:      CAShapeLayer?
    private var staticLayer:    CAShapeLayer?
    private var iconLayer:      CALayer?
    private var rotationTimer:  Timer?

    private let iconSize: CGFloat = 36

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        rebuild()
    }

    private func rebuild() {
        rotationTimer?.invalidate(); rotationTimer = nil
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        gradientLayer = nil; strokeMask = nil; glowLayer = nil; staticLayer = nil; iconLayer = nil

        if rank == 0 { buildAnimatedGlow() }
        else          { buildStaticGlow() }

        buildIconLayer()
        needsLayout = true
    }

    // MARK: - Rank 0: animated gradient

    private func buildAnimatedGlow() {
        let glow = CAShapeLayer()
        glow.fillColor    = CGColor.clear
        glow.strokeColor  = NSColor.systemPurple.withAlphaComponent(0.3).cgColor
        glow.lineWidth    = borderWidth + glowRadius * 0.7
        glow.shadowColor  = NSColor.systemPurple.cgColor
        glow.shadowRadius = glowRadius * 1.2
        glow.shadowOpacity = 0.6
        glow.shadowOffset  = .zero
        layer?.addSublayer(glow)
        glowLayer = glow

        let grad = CAGradientLayer()
        grad.colors = [
            NSColor.systemPurple.cgColor,
            NSColor.systemBlue.cgColor,
            NSColor.systemCyan.cgColor,
            NSColor(red: 0.8, green: 0.85, blue: 1.0, alpha: 1).cgColor,
            NSColor.systemBlue.cgColor,
            NSColor.systemPurple.cgColor,
        ]
        grad.locations  = [0, 0.2, 0.45, 0.5, 0.75, 1.0]
        grad.startPoint = CGPoint(x: 0, y: 0)
        grad.endPoint   = CGPoint(x: 1, y: 1)

        let mask = CAShapeLayer()
        mask.fillColor   = CGColor.clear
        mask.strokeColor = NSColor.white.cgColor
        mask.lineWidth   = borderWidth + 1
        grad.mask = mask

        layer?.addSublayer(grad)
        gradientLayer = grad
        strokeMask    = mask

        addRotationAnimation(to: grad)

        var t: Double = 0
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self, let glow = self.glowLayer else { return }
            t += 0.015
            let s = (sin(t) + 1) / 2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let c = NSColor(red: 0.35 + 0.2 * s, green: 0.1, blue: 0.75 + 0.15 * s, alpha: 0.3)
            glow.strokeColor = c.cgColor
            glow.shadowColor = c.withAlphaComponent(1).cgColor
            CATransaction.commit()
        }
    }

    private func addRotationAnimation(to grad: CAGradientLayer) {
        let dur: CFTimeInterval = 12

        let sp = CAKeyframeAnimation(keyPath: "startPoint")
        sp.values   = [CGPoint(x:0,y:0), CGPoint(x:1,y:0), CGPoint(x:1,y:1), CGPoint(x:0,y:1), CGPoint(x:0,y:0)]
        sp.keyTimes = [0, 0.25, 0.5, 0.75, 1.0]
        sp.duration = dur
        sp.repeatCount = .infinity
        sp.calculationMode = .linear

        let ep = CAKeyframeAnimation(keyPath: "endPoint")
        ep.values   = [CGPoint(x:1,y:1), CGPoint(x:0,y:1), CGPoint(x:0,y:0), CGPoint(x:1,y:0), CGPoint(x:1,y:1)]
        ep.keyTimes = [0, 0.25, 0.5, 0.75, 1.0]
        ep.duration = dur
        ep.repeatCount = .infinity
        ep.calculationMode = .linear

        grad.add(sp, forKey: "startRotation")
        grad.add(ep, forKey: "endRotation")
    }

    // MARK: - Rank 1/2: static glow

    private func buildStaticGlow() {
        // rank 1: warm amber/gold — "just left, still warm"
        // rank 2: cool teal — "further back, fading"
        let color: NSColor = rank == 1
            ? NSColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0)
            : NSColor(red: 0.0, green: 0.85, blue: 0.75, alpha: 1.0)
        let s = CAShapeLayer()
        s.fillColor     = CGColor.clear
        s.strokeColor   = color.cgColor
        s.lineWidth     = borderWidth
        s.shadowColor   = color.cgColor
        s.shadowRadius  = glowRadius
        s.shadowOpacity = 1.0
        s.shadowOffset  = .zero
        layer?.addSublayer(s)
        staticLayer = s
    }

    // MARK: - App icon badge

    private func buildIconLayer() {
        let icon = CALayer()
        icon.contentsGravity = .resizeAspect
        icon.cornerRadius    = 8
        icon.masksToBounds   = true
        // Subtle drop shadow so the icon reads against any background
        icon.shadowColor     = CGColor(gray: 0, alpha: 1)
        icon.shadowOpacity   = 0.5
        icon.shadowRadius    = 4
        icon.shadowOffset    = CGSize(width: 0, height: -2)
        layer?.addSublayer(icon)
        iconLayer = icon
        updateIconLayer()
    }

    private func updateIconLayer() {
        guard let iconLayer else { return }
        if let img = appIcon {
            iconLayer.contents = img
            iconLayer.isHidden = false
        } else {
            iconLayer.isHidden = true
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        guard bounds.width > 4 && bounds.height > 4 else { return }
        updateShapes()
    }

    private func updateShapes() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let inset: CGFloat = borderWidth / 2 + 1
        let path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                          cornerWidth: 9, cornerHeight: 9, transform: nil)

        if rank == 0 {
            glowLayer?.frame    = bounds; glowLayer?.path    = path
            gradientLayer?.frame = bounds
            strokeMask?.frame   = bounds; strokeMask?.path   = path
        } else {
            staticLayer?.frame  = bounds; staticLayer?.path  = path
        }

        // Position icon at top-left corner, half-overlapping the border
        if let iconLayer {
            let offset: CGFloat = iconSize / 2 - borderWidth
            iconLayer.frame = CGRect(x: offset, y: bounds.height - offset - iconSize,
                                     width: iconSize, height: iconSize)
        }

        CATransaction.commit()
    }

    deinit { rotationTimer?.invalidate() }
}
