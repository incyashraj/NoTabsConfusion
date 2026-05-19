import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {

    private var colorWell: NSColorWell!
    private var widthSlider: NSSlider!
    private var glowSlider: NSSlider!
    private var widthLabel: NSTextField!
    private var glowLabel: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "FocusBorder Preferences"
        window.center()
        self.init(window: window)
        buildUI()
        loadFromDefaults()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Color row
        let colorLabel = makeLabel("Border color:")
        colorLabel.frame = NSRect(x: 20, y: 160, width: 100, height: 22)

        colorWell = NSColorWell(frame: NSRect(x: 130, y: 155, width: 44, height: 30))
        colorWell.color = .controlAccentColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged)

        // Width row
        let wLabel = makeLabel("Border width:")
        wLabel.frame = NSRect(x: 20, y: 112, width: 100, height: 22)

        widthSlider = NSSlider(value: 4, minValue: 2, maxValue: 20, target: self, action: #selector(widthChanged))
        widthSlider.frame = NSRect(x: 130, y: 112, width: 150, height: 22)
        widthSlider.isContinuous = true

        widthLabel = makeLabel("4 pt")
        widthLabel.frame = NSRect(x: 290, y: 112, width: 40, height: 22)

        // Glow row
        let gLabel = makeLabel("Glow radius:")
        gLabel.frame = NSRect(x: 20, y: 64, width: 100, height: 22)

        glowSlider = NSSlider(value: 12, minValue: 0, maxValue: 40, target: self, action: #selector(glowChanged))
        glowSlider.frame = NSRect(x: 130, y: 64, width: 150, height: 22)
        glowSlider.isContinuous = true

        glowLabel = makeLabel("12 pt")
        glowLabel.frame = NSRect(x: 290, y: 64, width: 40, height: 22)

        // Done button
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(done))
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        doneBtn.frame = NSRect(x: 240, y: 16, width: 80, height: 32)

        [colorLabel, colorWell, wLabel, widthSlider, widthLabel,
         gLabel, glowSlider, glowLabel, doneBtn].forEach { content.addSubview($0) }
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    // MARK: - Actions

    @objc private func colorChanged() {
        saveToDefaults()
    }

    @objc private func widthChanged() {
        let v = Int(widthSlider.doubleValue)
        widthLabel.stringValue = "\(v) pt"
        saveToDefaults()
    }

    @objc private func glowChanged() {
        let v = Int(glowSlider.doubleValue)
        glowLabel.stringValue = "\(v) pt"
        saveToDefaults()
    }

    @objc private func done() {
        saveToDefaults()
        window?.close()
    }

    // MARK: - Persistence

    private func saveToDefaults() {
        let defaults = UserDefaults.standard
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: colorWell.color,
            requiringSecureCoding: false
        ) {
            defaults.set(data, forKey: Prefs.colorKey)
        }
        defaults.set(Float(widthSlider.doubleValue), forKey: Prefs.widthKey)
        defaults.set(Float(glowSlider.doubleValue),  forKey: Prefs.glowKey)
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Prefs.colorKey),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            colorWell.color = color
        }

        let width = defaults.float(forKey: Prefs.widthKey)
        if width > 0 {
            widthSlider.doubleValue = Double(width)
            widthLabel.stringValue = "\(Int(width)) pt"
        }

        let glow = defaults.float(forKey: Prefs.glowKey)
        if glow > 0 {
            glowSlider.doubleValue = Double(glow)
            glowLabel.stringValue = "\(Int(glow)) pt"
        }
    }
}
