import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

protocol WindowTrackerDelegate: AnyObject {
    func windowTrackerDidUpdate(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)])
}

final class WindowTracker {

    weak var delegate: WindowTrackerDelegate?

    private struct RecentApp {
        var bundleID: String
        var pid: pid_t
        var windowID: CGWindowID
    }

    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    // The last real app the user was in. Mission Control must not replace this.
    private var frontPIDToTrack: pid_t = 0
    // Most recent app first. One entry per app, not per window.
    private var recents: [RecentApp] = []
    private var pollTimer: Timer?

    // These own Mission Control chrome and permission dialogs, not apps the user switched to.
    private let systemBundleIDs: Set<String> = [
        "com.apple.WindowManager",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.accessibility.universalAccessAuthWarn"
    ]

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

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.pollFrame()
        }

        seedFromVisibleWindows()
        syncFrontApp()
    }

    func forget(bundleID: String) {
        recents.removeAll { $0.bundleID == bundleID }
        publish()
    }

    func applyLimits() {
        trim()
        publish()
    }

    @objc private func activeAppChanged() {
        // Record it now. A swipe can start before the next poll.
        syncFrontApp()
    }

    private func isTrackable(_ bundleID: String) -> Bool {
        bundleID != Bundle.main.bundleIdentifier
            && !systemBundleIDs.contains(bundleID)
            && !Prefs.ignoredBundleIDs().contains(bundleID)
    }

    // Front-to-back windows already on screen, so the first swipe has something to color.
    private func seedFromVisibleWindows() {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        var seen = Set<String>()
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 80, (bounds["Height"] ?? 0) > 80,
                  let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                  isTrackable(bundleID),
                  !seen.contains(bundleID)
            else { continue }
            seen.insert(bundleID)
            recents.append(RecentApp(bundleID: bundleID, pid: pid, windowID: wid))
            if recents.count == Prefs.recentCount { break }
        }
    }

    private func pollFrame() {
        syncFrontApp()
    }

    // The app in front becomes 1. If its window is not open yet, later polls
    // try again, including the start of Mission Control, so a just-launched
    // app is not left off the list.
    private func syncFrontApp() {
        let shield = MissionControl.isActive
        if !shield {
            noteFrontApp()
        }
        adoptFrontAppIfNeeded(shield: shield)
        repairMissingWindows()
        publish()
    }

    private func noteFrontApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              isTrackable(bundleID),
              !app.isTerminated
        else { return }
        frontPIDToTrack = app.processIdentifier
        if AXIsProcessTrusted(), frontPIDToTrack != observedPID {
            installAXObserver(pid: frontPIDToTrack)
        }
    }

    private func adoptFrontAppIfNeeded(shield: Bool) {
        guard frontPIDToTrack != 0,
              let app = NSRunningApplication(processIdentifier: frontPIDToTrack),
              let bundleID = app.bundleIdentifier,
              isTrackable(bundleID),
              let wid = resolveWindowID(pid: frontPIDToTrack)
        else { return }

        // During the swipe, keep the window we already drew for this app.
        if shield,
           recents.first?.bundleID == bundleID,
           frameForWindowID(recents.first?.windowID ?? 0) != nil {
            return
        }
        if recents.first?.bundleID == bundleID, recents.first?.windowID == wid {
            return
        }
        recents.removeAll { $0.bundleID == bundleID }
        recents.insert(RecentApp(bundleID: bundleID, pid: app.processIdentifier, windowID: wid), at: 0)
        trim()
    }

    // A replaced window used to leave the app in the list with nothing to draw,
    // so an older app showed up as 1.
    private func repairMissingWindows() {
        for index in recents.indices {
            if frameForWindowID(recents[index].windowID) != nil { continue }
            let wid = frontWindowID(pid: recents[index].pid)
            if wid != kCGNullWindowID {
                recents[index].windowID = wid
            }
        }
    }

    private func trim() {
        let limit = Prefs.recentCount
        if recents.count > limit {
            recents = Array(recents.prefix(limit))
        }
    }

    private func publish() {
        recents.removeAll { slot in
            !windowStillExists(slot.windowID)
                && NSRunningApplication(processIdentifier: slot.pid) == nil
        }

        var result: [(id: CGWindowID, frame: NSRect, icon: NSImage?)] = []
        var seenFrames: [NSRect] = []

        for slot in recents {
            guard let frame = frameForWindowID(slot.windowID) else { continue }
            let duplicate = seenFrames.contains {
                abs($0.minX - frame.minX) < 20 &&
                abs($0.minY - frame.minY) < 20 &&
                abs($0.width - frame.width) < 20 &&
                abs($0.height - frame.height) < 20
            }
            if duplicate { continue }
            seenFrames.append(frame)
            let icon = NSRunningApplication(processIdentifier: slot.pid)?.icon
            result.append((id: slot.windowID, frame: frame, icon: icon))
            if result.count == Prefs.recentCount { break }
        }

        delegate?.windowTrackerDidUpdate(slots: result)
    }

    private func resolveWindowID(pid: pid_t) -> CGWindowID? {
        if AXIsProcessTrusted(),
           let element = focusedWindowElement(pid: pid),
           !isMinimized(element) {
            let wid = matchCGWindowID(axElement: element, pid: pid)
            if wid != kCGNullWindowID { return wid }
        }
        let wid = frontWindowID(pid: pid)
        return wid == kCGNullWindowID ? nil : wid
    }

    // List order is front to back, so the first real window is the one in front.
    private func frontWindowID(pid: pid_t) -> CGWindowID {
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 80, (bounds["Height"] ?? 0) > 80
            else { continue }
            return wid
        }
        return kCGNullWindowID
    }

    // MARK: - AX observer

    private func installAXObserver(pid: pid_t) {
        axObserver = nil
        observedPID = pid

        var obs: AXObserver?
        let ref = Unmanaged.passUnretained(self).toOpaque()

        let cb: AXObserverCallback = { _, _, _, refcon in
            guard let ptr = refcon else { return }
            let me = Unmanaged<WindowTracker>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { me.syncFrontApp() }
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
        var pRef: CFTypeRef?
        var sRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sRef) == .success,
              let pRef, let sRef else { return nil }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        AXValueGetValue(pRef as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sRef as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }

    private func matchCGWindowID(axElement: AXUIElement, pid: pid_t) -> CGWindowID {
        var wid: CGWindowID = kCGNullWindowID
        _ = _AXUIElementGetWindow(axElement, &wid)
        if wid != kCGNullWindowID { return wid }

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

    private func windowStillExists(_ wid: CGWindowID) -> Bool {
        let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == wid }
    }

    // CGWindow bounds use the top-left of the main display. AppKit uses the bottom-left.
    private func frameForWindowID(_ wid: CGWindowID) -> NSRect? {
        let onScreen = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []

        guard let info = onScreen.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == wid }),
              let bd = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }

        if let pid = info[kCGWindowOwnerPID as String] as? pid_t,
           let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
           Prefs.ignoredBundleIDs().contains(bundleID) {
            return nil
        }

        let cg = CGRect(
            x: bd["X"] ?? 0,
            y: bd["Y"] ?? 0,
            width: bd["Width"] ?? 0,
            height: bd["Height"] ?? 0
        )
        guard cg.width > 1, cg.height > 1 else { return nil }

        let primary = NSScreen.screens.first { $0.displayID == CGMainDisplayID() } ?? NSScreen.main
        guard let primary else { return nil }
        return NSRect(
            x: primary.frame.minX + cg.origin.x,
            y: primary.frame.maxY - cg.origin.y - cg.height,
            width: cg.width,
            height: cg.height
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return 0
    }
}
