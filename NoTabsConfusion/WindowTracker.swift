import AppKit
import ApplicationServices

// Private API to get CGWindowID directly from an AXUIElement
@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

protocol WindowTrackerDelegate: AnyObject {
    // Called with up to 3 (windowID, frame, icon) tuples, most-recent first
    func windowTrackerDidUpdate(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)])
}

final class WindowTracker {

    weak var delegate: WindowTrackerDelegate?

    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var lastFrontmostPID: pid_t = 0
    // Most-recent first, max 3 entries, no duplicates
    private var windowHistory: [CGWindowID] = []
    // Maps CGWindowID → owning pid so we can look up the app icon
    private var windowPID: [CGWindowID: pid_t] = [:]
    private var pollTimer: Timer?

    init(delegate: WindowTrackerDelegate) {
        self.delegate = delegate
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pollFrame()
        }

        refreshTrackedWindow()
    }

    // MARK: - Called on every app switch

    @objc private func activeAppChanged() {
        // Small delay so frontmostApplication is updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.refreshTrackedWindow()
        }
    }

    // MARK: - Find and lock onto the frontmost window

    private func refreshTrackedWindow() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !app.isTerminated
        else { return }

        let pid = app.processIdentifier

        if pid != observedPID {
            installAXObserver(pid: pid)
        }

        guard let winElement = focusedWindowElement(pid: pid),
              !isMinimized(winElement) else { return }

        let wid = matchCGWindowID(axElement: winElement, pid: pid)
        guard wid != kCGNullWindowID else { return }

        // Push to front of history, deduplicate, keep max 3
        windowHistory.removeAll { $0 == wid }
        windowHistory.insert(wid, at: 0)
        if windowHistory.count > 3 { windowHistory = Array(windowHistory.prefix(3)) }
        windowPID[wid] = pid

        delegate?.windowTrackerDidUpdate(slots: resolvedSlots())
    }

    // MARK: - Poll: detect app switches + update positions

    private func pollFrame() {
        let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        if currentPID != lastFrontmostPID && currentPID != 0 {
            lastFrontmostPID = currentPID
            refreshTrackedWindow()
            return
        }
        guard !windowHistory.isEmpty else { return }
        delegate?.windowTrackerDidUpdate(slots: resolvedSlots())
    }

    // Resolve window history to (id, frame, icon) tuples, pruning dead windows
    // and deduplicating overlapping frames so two overlays never stack.
    private func resolvedSlots() -> [(id: CGWindowID, frame: NSRect, icon: NSImage?)] {
        // Deduplicate IDs first (insurance against any race that inserts the same ID twice)
        var seen = Set<CGWindowID>()
        windowHistory = windowHistory.filter { seen.insert($0).inserted }

        // Prune IDs that no longer exist on screen
        windowHistory = windowHistory.filter { frameForWindowID($0) != nil }

        var result: [(id: CGWindowID, frame: NSRect, icon: NSImage?)] = []
        for wid in windowHistory {
            guard let frame = frameForWindowID(wid) else { continue }
            // Skip if another slot already covers the same screen area (within 20pt on all edges)
            let duplicate = result.contains {
                abs($0.frame.minX - frame.minX) < 20 &&
                abs($0.frame.minY - frame.minY) < 20 &&
                abs($0.frame.width - frame.width) < 20 &&
                abs($0.frame.height - frame.height) < 20
            }
            if !duplicate {
                let icon = windowPID[wid].flatMap {
                    NSRunningApplication(processIdentifier: $0)?.icon
                }
                result.append((id: wid, frame: frame, icon: icon))
            }
            if result.count == 3 { break }
        }
        return result
    }

    // MARK: - AX observer (for window move/resize/tab-switch within same app)

    private func installAXObserver(pid: pid_t) {
        axObserver = nil
        observedPID = pid

        var obs: AXObserver?
        let ref = Unmanaged.passUnretained(self).toOpaque()

        let cb: AXObserverCallback = { _, _, _, refcon in
            guard let ptr = refcon else { return }
            let me = Unmanaged<WindowTracker>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { me.refreshTrackedWindow() }
        }

        guard AXObserverCreate(pid, cb, &obs) == .success, let obs else { return }

        let appEl = AXUIElementCreateApplication(pid)
        for note in [kAXFocusedWindowChangedNotification,
                     kAXWindowMovedNotification,
                     kAXWindowResizedNotification] {
            AXObserverAddNotification(obs, appEl, note as CFString, ref)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        axObserver = obs
    }

    // MARK: - AX helpers

    private func focusedWindowElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &val) == .success else { return nil }
        return (val as! AXUIElement)
    }

    private func isMinimized(_ el: AXUIElement) -> Bool {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMinimizedAttribute as CFString, &val) == .success else { return false }
        return (val as? Bool) ?? false
    }

    private func axFrame(_ el: AXUIElement) -> CGRect? {
        var pRef: CFTypeRef?; var sRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sRef) == .success,
              let pRef, let sRef else { return nil }
        var pt = CGPoint.zero; var sz = CGSize.zero
        AXValueGetValue(pRef as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sRef as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    // MARK: - CGWindowList helpers

    // Match AX window to a CGWindowID by comparing screen position
    private func matchCGWindowID(axElement: AXUIElement, pid: pid_t) -> CGWindowID {
        // Use _AXUIElementGetWindow to get the CGWindowID directly from the AXUIElement —
        // no coordinate matching needed, works regardless of Mission Control state.
        var wid: CGWindowID = kCGNullWindowID
        _ = _AXUIElementGetWindow(axElement, &wid)
        if wid != kCGNullWindowID { return wid }

        // Fallback: match by size since position differs in Mission Control
        guard let ax = axFrame(axElement) else { return kCGNullWindowID }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let w = info[kCGWindowNumber as String] as? CGWindowID,
                  let bd = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            if abs((bd["Width"] ?? 0) - ax.width) < 4 && abs((bd["Height"] ?? 0) - ax.height) < 4 {
                return w
            }
        }
        return kCGNullWindowID
    }

    // Get the current screen rect for a window ID.
    // Only returns a frame if the window is visible on the current screen or in Mission Control.
    // Never returns frames for windows on other spaces (prevents ghost borders).
    private func frameForWindowID(_ wid: CGWindowID) -> NSRect? {
        let onScreen = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []

        // Only show border if window is actually on screen — no fallback to other spaces.
        guard let info = onScreen.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == wid }),
              let bd = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }

        // CGWindowBounds: top-left origin. NSWindow: bottom-left origin.
        let h = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
              ?? NSScreen.main!.frame.height
        return NSRect(x: bd["X"] ?? 0,
                      y: h - (bd["Y"] ?? 0) - (bd["Height"] ?? 0),
                      width:  bd["Width"]  ?? 0,
                      height: bd["Height"] ?? 0)
    }
}
