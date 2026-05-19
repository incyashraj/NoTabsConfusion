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
        // Rank 0 floats above everything (statusBar level).
        // Ranks 1/2 sit just below normal windows so they're hidden behind the app
        // during regular use, but visible in Mission Control where all windows lift.
        level = rank == 0 ? .statusBar : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) - 1)
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

    // Called with ordered list of (windowID, frame) from most-recent to oldest.
    // All tracked windows always show their border — rank 0 is the animated glow,
    // ranks 1 and 2 are subtle static borders so they're visible in Mission Control
    // without being distracting in normal use.
    func update(slots: [(id: CGWindowID, frame: NSRect)]) {
        for (i, win) in windows.enumerated() {
            if i < slots.count {
                let frame = slots[i].frame.insetBy(dx: -padding, dy: -padding)
                win.setFrame(frame, display: false)
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
