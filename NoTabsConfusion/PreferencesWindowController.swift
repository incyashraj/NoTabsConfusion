import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {

    private var colorWells: [NSColorWell] = []
    private var widthSlider: NSSlider!
    private var glowSlider: NSSlider!
    private var widthLabel: NSTextField!
    private var glowLabel: NSTextField!
    private var iconCheckbox: NSButton!
    private var countControl: NSSegmentedControl!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 392),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "NoTabsConfusion"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        loadFromDefaults()
    }

    override func showWindow(_ sender: Any?) {
        loadFromDefaults()
        super.showWindow(sender)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let colors = Prefs.defaultColors
        for index in 0..<3 {
            let label = makeLabel(Prefs.colorLabels[index])
            label.frame = NSRect(x: 20, y: 340 - index * 48, width: 110, height: 22)
            let well = NSColorWell(frame: NSRect(x: 144, y: 334 - index * 48, width: 52, height: 30))
            well.color = colors[index]
            well.tag = index
            well.target = self
            well.action = #selector(colorChanged(_:))
            colorWells.append(well)
            content.addSubview(label)
            content.addSubview(well)
        }

        let widthTitle = makeLabel("Border width:")
        widthTitle.frame = NSRect(x: 20, y: 196, width: 110, height: 22)
        widthSlider = NSSlider(value: Double(Prefs.defaultWidth), minValue: 2, maxValue: 16, target: self, action: #selector(widthChanged))
        widthSlider.frame = NSRect(x: 144, y: 196, width: 190, height: 22)
        widthSlider.isContinuous = true
        widthLabel = makeLabel("4 pt")
        widthLabel.alignment = .left
        widthLabel.frame = NSRect(x: 344, y: 196, width: 56, height: 22)

        let glowTitle = makeLabel("Glow:")
        glowTitle.frame = NSRect(x: 20, y: 150, width: 110, height: 22)
        glowSlider = NSSlider(value: Double(Prefs.defaultGlow), minValue: 0, maxValue: 32, target: self, action: #selector(glowChanged))
        glowSlider.frame = NSRect(x: 144, y: 150, width: 190, height: 22)
        glowSlider.isContinuous = true
        glowLabel = makeLabel("14 pt")
        glowLabel.alignment = .left
        glowLabel.frame = NSRect(x: 344, y: 150, width: 56, height: 22)

        iconCheckbox = NSButton(checkboxWithTitle: "Show app icons", target: self, action: #selector(iconChanged))
        iconCheckbox.frame = NSRect(x: 142, y: 108, width: 180, height: 22)

        let countTitle = makeLabel("Recent apps:")
        countTitle.frame = NSRect(x: 20, y: 66, width: 110, height: 22)
        countControl = NSSegmentedControl(labels: ["2", "3"], trackingMode: .selectOne, target: self, action: #selector(countChanged))
        countControl.frame = NSRect(x: 144, y: 62, width: 120, height: 28)
        countControl.selectedSegment = 1

        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 316, y: 16, width: 84, height: 32)

        [widthTitle, widthSlider, widthLabel, glowTitle, glowSlider, glowLabel,
         iconCheckbox, countTitle, countControl, done].forEach { content.addSubview($0) }
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        Prefs.setColor(sender.color, at: sender.tag)
        notify()
    }

    @objc private func widthChanged() {
        let value = widthSlider.doubleValue
        widthLabel.stringValue = "\(Int(value.rounded())) pt"
        UserDefaults.standard.set(Float(value), forKey: Prefs.widthKey)
        notify()
    }

    @objc private func glowChanged() {
        let value = glowSlider.doubleValue
        glowLabel.stringValue = "\(Int(value.rounded())) pt"
        UserDefaults.standard.set(Float(value), forKey: Prefs.glowKey)
        notify()
    }

    @objc private func iconChanged() {
        Prefs.showsIcon = iconCheckbox.state == .on
        notify()
    }

    @objc private func countChanged() {
        Prefs.recentCount = countControl.selectedSegment == 0 ? 2 : 3
        notify()
    }

    @objc private func done() {
        window?.close()
    }

    private func notify() {
        NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
    }

    private func loadFromDefaults() {
        let colors = Prefs.colors()
        for (index, well) in colorWells.enumerated() where index < colors.count {
            well.color = colors[index]
        }

        let width = Prefs.width()
        widthSlider.doubleValue = Double(width)
        widthLabel.stringValue = "\(Int(width.rounded())) pt"

        let glow = Prefs.glow()
        glowSlider.doubleValue = Double(glow)
        glowLabel.stringValue = "\(Int(glow.rounded())) pt"

        iconCheckbox.state = Prefs.showsIcon ? .on : .off
        countControl.selectedSegment = Prefs.recentCount == 2 ? 0 : 1
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
