import AppKit

final class OverlayWindow: NSWindow {

    let borderView: BorderView

    init(rank: Int) {
        borderView = BorderView()
        borderView.rank = rank
        super.init(contentRect: .zero, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // All ranks at statusBar level — borders only show during Mission Control anyway.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: -

final class OverlayWindowController {

    // 3 overlay windows: index 0 = most recent, 1 = second, 2 = third
    private let windows = [OverlayWindow(rank: 0),
                           OverlayWindow(rank: 1),
                           OverlayWindow(rank: 2)]

    private var padding: CGFloat { 6 }
    private var normalSizes: [CGWindowID: CGSize] = [:]

    // Called with ordered list of (windowID, frame) from most-recent to oldest.
    // All borders are hidden during normal use — they only appear in Mission Control.
    func update(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)]) {
        let inMissionControl = isMissionControlActive(slots: slots)

        for (i, win) in windows.enumerated() {
            if i < slots.count && inMissionControl {
                let slot = slots[i]
                let frame = slot.frame.insetBy(dx: -padding, dy: -padding)
                win.setFrame(frame, display: false)
                win.borderView.appIcon = slot.icon
                if !win.isVisible { win.orderFront(nil) }
            } else {
                win.orderOut(nil)
            }
        }

        if !inMissionControl {
            for slot in slots { normalSizes[slot.id] = slot.frame.size }
        }
    }

    private func isMissionControlActive(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)]) -> Bool {
        guard let slot = slots.first, let normal = normalSizes[slot.id] else { return false }
        let ratio = (slot.frame.width * slot.frame.height) / (normal.width * normal.height)
        return ratio < 0.85
    }

    func hideAll() {
        windows.forEach { $0.orderOut(nil) }
    }

    func applyPreferences() {
        // Preferences currently only affect rank-0 border color.
        // Future: add per-rank customization.
    }
}

// MARK: - Preference keys

enum Prefs {
    static let colorKey = "borderColor"
    static let widthKey = "borderWidth"
    static let glowKey  = "glowRadius"
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("com.yashraj.NoTabsConfusion.preferencesDidChange")
}
