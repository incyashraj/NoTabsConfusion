import AppKit

final class OverlayWindow: NSWindow {

    let borderView: BorderView

    init(rank: Int) {
        borderView = BorderView()
        borderView.borderColor = Prefs.defaultColors[rank]
        super.init(contentRect: .zero, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: -

final class OverlayWindowController {

    private let windows = [
        OverlayWindow(rank: 0),
        OverlayWindow(rank: 1),
        OverlayWindow(rank: 2)
    ]

    private let padding: CGFloat = 6
    private var normalSizes: [CGWindowID: CGSize] = [:]

    func update(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)]) {
        let inMissionControl = isMissionControlActive(slots: slots)

        if !inMissionControl {
            for slot in slots where slot.frame.width > 40 && slot.frame.height > 40 {
                normalSizes[slot.id] = slot.frame.size
            }
        }

        let visible = inMissionControl && !Prefs.isPaused
        let limit = min(slots.count, Prefs.recentCount, windows.count)

        for (i, win) in windows.enumerated() {
            if visible && i < limit {
                let slot = slots[i]
                win.setFrame(slot.frame.insetBy(dx: -padding, dy: -padding), display: false)
                win.borderView.appIcon = slot.icon
                if !win.isVisible { win.orderFront(nil) }
            } else {
                win.orderOut(nil)
            }
        }
    }

    func hideAll() {
        windows.forEach { $0.orderOut(nil) }
    }

    func applyPreferences() {
        let colors = Prefs.colors()
        let width = Prefs.width()
        let glow = Prefs.glow()
        let showIcon = Prefs.showsIcon
        for (i, win) in windows.enumerated() {
            win.borderView.borderColor = colors[i]
            win.borderView.borderWidth = width
            win.borderView.glowRadius = glow
            win.borderView.showsIcon = showIcon
        }
    }

    // Current macOS draws the four-finger view as WindowManager windows
    // (ExposeShieldWindow, Spaces Bar), not a Dock window named "Mission Control".
    // If those are missing, fall back to two or more tracked windows shrinking at once.
    // One window resized by hand is not enough.
    private func isMissionControlActive(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)]) -> Bool {
        if Self.systemIsShowingMissionControl() { return true }

        let shrunk = slots.filter { slot in
            guard let normal = normalSizes[slot.id], normal.width > 1, normal.height > 1 else { return false }
            let ratio = (slot.frame.width * slot.frame.height) / (normal.width * normal.height)
            return ratio < 0.45
        }
        return shrunk.count >= 2
    }

    private static func systemIsShowingMissionControl() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let name = info[kCGWindowName as String] as? String ?? ""
            if name.contains("Mission Control") || name.contains("Expose") {
                return true
            }
            // Name can be blank. The shield is a large WindowManager window above the desktop.
            guard owner == "WindowManager",
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= 15,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let width = bounds["Width"] ?? 0
            let height = bounds["Height"] ?? 0
            if width >= 400, height >= 400 { return true }
        }
        return false
    }
}

// MARK: - Preference keys

enum Prefs {
    static let colorKeys = ["borderColor0", "borderColor1", "borderColor2"]
    static let legacyColorKey = "borderColor"
    static let widthKey = "borderWidth"
    static let glowKey = "glowRadius"
    static let showIconKey = "showAppIcon"
    static let recentCountKey = "recentCount"
    static let pausedKey = "paused"
    static let ignoredKey = "ignoredBundleIDs"

    static let defaultWidth: CGFloat = 4
    static let defaultGlow: CGFloat = 14
    static let defaultIgnored = ["com.yashraj.SmartNotch"]

    static let defaultColors: [NSColor] = [
        NSColor(srgbRed: 0.56, green: 0.34, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.10, alpha: 1),
        NSColor(srgbRed: 0.00, green: 0.72, blue: 0.66, alpha: 1)
    ]

    static let colorLabels = ["Just left:", "Before that:", "Earlier:"]

    static func colors() -> [NSColor] {
        colorKeys.enumerated().map { index, key in
            if let color = color(forKey: key) { return color }
            if index == 0, let legacy = color(forKey: legacyColorKey) { return legacy }
            return defaultColors[index]
        }
    }

    static func setColor(_ color: NSColor, at index: Int) {
        guard colorKeys.indices.contains(index),
              let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
        else { return }
        UserDefaults.standard.set(data, forKey: colorKeys[index])
    }

    static func width() -> CGFloat {
        guard UserDefaults.standard.object(forKey: widthKey) != nil else { return defaultWidth }
        return CGFloat(UserDefaults.standard.float(forKey: widthKey))
    }

    static func glow() -> CGFloat {
        guard UserDefaults.standard.object(forKey: glowKey) != nil else { return defaultGlow }
        return CGFloat(UserDefaults.standard.float(forKey: glowKey))
    }

    static var showsIcon: Bool {
        get {
            guard UserDefaults.standard.object(forKey: showIconKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: showIconKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showIconKey) }
    }

    static var recentCount: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: recentCountKey)
            return stored == 2 ? 2 : 3
        }
        set { UserDefaults.standard.set(newValue == 2 ? 2 : 3, forKey: recentCountKey) }
    }

    static var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: pausedKey) }
    }

    static func ignoredBundleIDs() -> [String] {
        if let stored = UserDefaults.standard.stringArray(forKey: ignoredKey) { return stored }
        return defaultIgnored
    }

    static func setIgnoredBundleIDs(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: ignoredKey)
    }

    static func displayName(for bundleID: String) -> String {
        if let name = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?
            .localizedName {
            return name
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    private static func color(forKey key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("com.yashraj.NoTabsConfusion.preferencesDidChange")
}
