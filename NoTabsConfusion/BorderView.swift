import AppKit
import QuartzCore

// rank 0 — animated gradient glow (purple→blue→cyan), slow rotation
// rank 1 — dim blue static glow
// rank 2 — very faint white static glow
final class BorderView: NSView {

    var rank: Int = 0 { didSet { rebuild() } }
    var glowRadius:  CGFloat { rank == 0 ? 16 : (rank == 1 ? 8 : 5) }
    var borderWidth: CGFloat { rank == 0 ? 3  : (rank == 1 ? 1.5 : 1) }

    private var gradientLayer:  CAGradientLayer?
    private var strokeMask:     CAShapeLayer?
    private var glowLayer:      CAShapeLayer?
    private var staticLayer:    CAShapeLayer?
    private var rotationTimer:  Timer?

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
        gradientLayer = nil; strokeMask = nil; glowLayer = nil; staticLayer = nil

        if rank == 0 { buildAnimatedGlow() }
        else          { buildStaticGlow() }
        needsLayout = true
    }

    // MARK: - Rank 0: animated gradient

    private func buildAnimatedGlow() {
        // Outer soft bloom
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

        // Linear gradient (purple→blue→cyan→white→blue→purple) masked to stroke
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

        // Animate startPoint + endPoint to slowly rotate the gradient
        addRotationAnimation(to: grad)

        // Timer to slowly pulse the glow color
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
        // Rotate by animating startPoint around a circle (12s per revolution)
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

    // MARK: - Rank 1/2: static dim glow

    private func buildStaticGlow() {
        // rank 1: visible blue — readable in Mission Control thumbnails
        // rank 2: soft orange-amber — distinct from blue, still subtle in normal view
        let color: NSColor = rank == 1
            ? NSColor.systemBlue.withAlphaComponent(0.85)
            : NSColor(red: 0.95, green: 0.6, blue: 0.1, alpha: 0.7)
        let s = CAShapeLayer()
        s.fillColor     = CGColor.clear
        s.strokeColor   = color.cgColor
        s.lineWidth     = borderWidth
        s.shadowColor   = color.cgColor
        s.shadowRadius  = glowRadius
        s.shadowOpacity = rank == 1 ? 0.8 : 0.6
        s.shadowOffset  = .zero
        layer?.addSublayer(s)
        staticLayer = s
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
        CATransaction.commit()
    }

    deinit { rotationTimer?.invalidate() }
}
