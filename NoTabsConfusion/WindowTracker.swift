import AppKit

protocol WindowTrackerDelegate: AnyObject {
    func windowTrackerDidUpdate(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)], missionControl: Bool)
}

final class WindowTracker {

    weak var delegate: WindowTrackerDelegate?

    private struct RecentApp {
        var bundleID: String
        var pid: pid_t
        var windowID: CGWindowID
    }

    private struct SnapWindow {
        var id: CGWindowID
        var pid: pid_t
        var layer: Int
        var bounds: CGRect
        var onScreen: Bool
        var owner: String
        var name: String
    }

    private struct Snapshot {
        var windows: [SnapWindow]
        var byID: [CGWindowID: SnapWindow]

        var missionControl: Bool {
            for window in windows where window.onScreen {
                if window.name.contains("Mission Control") || window.name.contains("Expose") {
                    return true
                }
                if window.owner == "WindowManager",
                   window.layer >= 15,
                   window.bounds.width >= 400,
                   window.bounds.height >= 400 {
                    return true
                }
            }
            return false
        }

        // List order is front to back.
        func frontWindow(pid: pid_t) -> SnapWindow? {
            for window in windows where window.onScreen
                && window.pid == pid
                && window.layer == 0
                && window.bounds.width > 48
                && window.bounds.height > 48 {
                return window
            }
            return nil
        }
    }

    private struct SlotKey: Equatable {
        var id: CGWindowID
        var x: Int
        var y: Int
        var w: Int
        var h: Int
    }

    // The last real app the user was in. Mission Control must not replace this.
    private var frontPIDToTrack: pid_t = 0
    // Most recent app first. One entry per app, not per window.
    private var recents: [RecentApp] = []
    private var pollTimer: Timer?
    private var bundleIDs: [pid_t: String] = [:]
    private var icons: [pid_t: NSImage] = [:]
    private var primaryFrame: NSRect = .zero
    private var lastKeys: [SlotKey] = []
    private var lastShield = false

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
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(activeAppChanged),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(activeAppChanged),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        refreshPrimaryFrame()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pollFrame()
        }
        timer.tolerance = 1.0 / 120.0
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        let snapshot = capture()
        seed(from: snapshot)
        syncFrontApp(snapshot)
    }

    func forget(bundleID: String) {
        recents.removeAll { $0.bundleID == bundleID }
        publish(capture(), force: true)
    }

    func applyLimits() {
        trim()
        publish(capture(), force: true)
    }

    @objc private func activeAppChanged() {
        // Record it now. A swipe can start before the next frame.
        syncFrontApp(capture())
    }

    @objc private func screenChanged() {
        refreshPrimaryFrame()
        publish(capture(), force: true)
    }

    private func pollFrame() {
        syncFrontApp(capture())
    }

    private func isTrackable(_ bundleID: String, ignored: Set<String>) -> Bool {
        bundleID != Bundle.main.bundleIdentifier
            && !systemBundleIDs.contains(bundleID)
            && !ignored.contains(bundleID)
    }

    // Front-to-back windows already on screen, so the first swipe has something to color.
    private func seed(from snapshot: Snapshot) {
        let ignored = Set(Prefs.ignoredBundleIDs())
        var seen = Set<String>()
        for window in snapshot.windows {
            guard window.onScreen, window.layer == 0,
                  window.bounds.width > 48, window.bounds.height > 48,
                  let bundleID = bundleID(for: window.pid),
                  isTrackable(bundleID, ignored: ignored),
                  !seen.contains(bundleID)
            else { continue }
            seen.insert(bundleID)
            recents.append(RecentApp(bundleID: bundleID, pid: window.pid, windowID: window.id))
            if recents.count == Prefs.recentCount { break }
        }
    }

    // The app in front becomes 1. If its window is not open yet, the next
    // frames try again, including the start of Mission Control.
    private func syncFrontApp(_ snapshot: Snapshot) {
        let shield = snapshot.missionControl
        let ignored = Set(Prefs.ignoredBundleIDs())
        if !shield {
            noteFrontApp(ignored: ignored)
        }
        adoptFrontAppIfNeeded(snapshot, shield: shield, ignored: ignored)
        if !shield {
            repairMissingWindows(snapshot)
        }
        publish(snapshot, force: false)
    }

    private func noteFrontApp(ignored: Set<String>) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              isTrackable(bundleID, ignored: ignored),
              !app.isTerminated
        else { return }
        frontPIDToTrack = app.processIdentifier
        bundleIDs[frontPIDToTrack] = bundleID
    }

    private func adoptFrontAppIfNeeded(_ snapshot: Snapshot, shield: Bool, ignored: Set<String>) {
        guard frontPIDToTrack != 0,
              let app = NSRunningApplication(processIdentifier: frontPIDToTrack),
              let bundleID = app.bundleIdentifier,
              isTrackable(bundleID, ignored: ignored),
              let window = snapshot.frontWindow(pid: frontPIDToTrack)
        else { return }
        bundleIDs[app.processIdentifier] = bundleID

        // During the swipe, keep the window already chosen for this app.
        if shield,
           recents.first?.bundleID == bundleID,
           snapshot.byID[recents.first?.windowID ?? 0]?.onScreen == true {
            return
        }
        if recents.first?.bundleID == bundleID, recents.first?.windowID == window.id {
            return
        }
        recents.removeAll { $0.bundleID == bundleID }
        recents.insert(RecentApp(bundleID: bundleID, pid: app.processIdentifier, windowID: window.id), at: 0)
        trim()
    }

    // A replaced window used to leave the app in the list with nothing to draw,
    // so an older app showed up as 1.
    private func repairMissingWindows(_ snapshot: Snapshot) {
        for index in recents.indices {
            if snapshot.byID[recents[index].windowID]?.onScreen == true { continue }
            if let window = snapshot.frontWindow(pid: recents[index].pid) {
                recents[index].windowID = window.id
            }
        }
    }

    private func trim() {
        let limit = Prefs.recentCount
        if recents.count > limit {
            recents = Array(recents.prefix(limit))
        }
    }

    private func publish(_ snapshot: Snapshot, force: Bool) {
        let shield = snapshot.missionControl
        recents.removeAll { slot in
            if snapshot.byID[slot.windowID] != nil { return false }
            let alive = NSRunningApplication(processIdentifier: slot.pid) != nil
            if !alive {
                bundleIDs[slot.pid] = nil
                icons[slot.pid] = nil
            }
            return !alive
        }

        var result: [(id: CGWindowID, frame: NSRect, icon: NSImage?)] = []
        var seenIDs = Set<CGWindowID>()
        let ignored = Set(Prefs.ignoredBundleIDs())

        for slot in recents {
            guard !seenIDs.contains(slot.windowID),
                  let frame = frame(slot.windowID, snapshot: snapshot, ignored: ignored)
            else { continue }
            seenIDs.insert(slot.windowID)
            result.append((id: slot.windowID, frame: frame, icon: icon(for: slot.pid)))
            if result.count == Prefs.recentCount { break }
        }

        let keys = result.map {
            SlotKey(id: $0.id,
                    x: Int($0.frame.minX.rounded()),
                    y: Int($0.frame.minY.rounded()),
                    w: Int($0.frame.width.rounded()),
                    h: Int($0.frame.height.rounded()))
        }
        if !force && shield == lastShield && keys == lastKeys { return }
        lastShield = shield
        lastKeys = keys
        delegate?.windowTrackerDidUpdate(slots: result, missionControl: shield)
    }

    private func bundleID(for pid: pid_t) -> String? {
        if let cached = bundleIDs[pid] { return cached }
        guard let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
        bundleIDs[pid] = id
        return id
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let cached = icons[pid] { return cached }
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        icons[pid] = image
        return image
    }

    private func refreshPrimaryFrame() {
        let screen = NSScreen.screens.first { $0.displayID == CGMainDisplayID() } ?? NSScreen.main
        primaryFrame = screen?.frame ?? .zero
    }

    // CGWindow bounds use the top-left of the main display. AppKit uses the bottom-left.
    private func frame(_ wid: CGWindowID, snapshot: Snapshot, ignored: Set<String>) -> NSRect? {
        guard let window = snapshot.byID[wid], window.onScreen else { return nil }
        if let bundleID = bundleID(for: window.pid), ignored.contains(bundleID) { return nil }
        let cg = window.bounds
        guard cg.width > 1, cg.height > 1, primaryFrame.width > 1 else { return nil }
        return NSRect(
            x: primaryFrame.minX + cg.origin.x,
            y: primaryFrame.maxY - cg.origin.y - cg.height,
            width: cg.width,
            height: cg.height
        )
    }

    private func capture() -> Snapshot {
        let raw = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var windows: [SnapWindow] = []
        windows.reserveCapacity(raw.count)
        var byID: [CGWindowID: SnapWindow] = [:]
        byID.reserveCapacity(raw.count)
        for info in raw {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let onScreen: Bool
            if let flag = info[kCGWindowIsOnscreen as String] as? Bool {
                onScreen = flag
            } else if let flag = info[kCGWindowIsOnscreen as String] as? Int {
                onScreen = flag != 0
            } else {
                onScreen = false
            }
            let window = SnapWindow(
                id: id,
                pid: pid,
                layer: info[kCGWindowLayer as String] as? Int ?? 0,
                bounds: CGRect(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0,
                    height: bounds["Height"] ?? 0
                ),
                onScreen: onScreen,
                owner: info[kCGWindowOwnerName as String] as? String ?? "",
                name: info[kCGWindowName as String] as? String ?? ""
            )
            windows.append(window)
            byID[id] = window
        }
        return Snapshot(windows: windows, byID: byID)
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
