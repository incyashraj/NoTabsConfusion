import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController!
    private var tracker: WindowTracker!
    private var prefsWindowController: PreferencesWindowController?

    private let accessItem = NSMenuItem(title: "Allow Window Access…", action: #selector(requestAccess), keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
    private let ignoreItem = NSMenuItem(title: "Ignore Front App", action: #selector(ignoreFrontApp), keyEquivalent: "")
    private let ignoredItem = NSMenuItem(title: "Ignored Apps", action: nil, keyEquivalent: "")
    private let ignoredMenu = NSMenu()
    private let iconItem = NSMenuItem(title: "Show App Icons", action: #selector(toggleIcons), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        for app in running where app.processIdentifier != myPID {
            app.forceTerminate()
        }

        setupStatusItem()

        overlayController = OverlayWindowController()
        overlayController.applyPreferences()

        tracker = WindowTracker(delegate: overlayController)
        tracker.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .preferencesDidChange,
            object: nil
        )
        updateStatusAppearance()
        revealOnLaunch()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "NoTabsConfusion")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = "NoTabs"
        }

        for item in [accessItem, pauseItem, ignoreItem, iconItem, loginItem] {
            item.target = self
        }
        ignoredItem.submenu = ignoredMenu

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(accessItem)
        menu.addItem(pauseItem)
        menu.addItem(ignoreItem)
        menu.addItem(ignoredItem)
        menu.addItem(.separator())
        menu.addItem(iconItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NoTabsConfusion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        accessItem.isHidden = trusted
        pauseItem.title = Prefs.isPaused ? "Resume" : "Pause"
        iconItem.state = Prefs.showsIcon ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleID = app.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier,
           !Prefs.ignoredBundleIDs().contains(bundleID),
           let name = app.localizedName {
            ignoreItem.title = "Ignore \(name)"
            ignoreItem.isEnabled = true
        } else {
            ignoreItem.title = "Ignore Front App"
            ignoreItem.isEnabled = false
        }

        ignoredMenu.removeAllItems()
        let ids = Prefs.ignoredBundleIDs()
        if ids.isEmpty {
            let none = NSMenuItem(title: "None", action: nil, keyEquivalent: "")
            none.isEnabled = false
            ignoredMenu.addItem(none)
        } else {
            let hint = NSMenuItem(title: "Click to include again", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            ignoredMenu.addItem(hint)
            for id in ids {
                let item = NSMenuItem(title: Prefs.displayName(for: id), action: #selector(unignore(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                ignoredMenu.addItem(item)
            }
        }
    }

    @objc private func togglePause() {
        Prefs.isPaused.toggle()
        updateStatusAppearance()
        tracker.applyLimits()
    }

    @objc private func ignoreFrontApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return }
        var ids = Prefs.ignoredBundleIDs()
        if !ids.contains(bundleID) {
            ids.append(bundleID)
            Prefs.setIgnoredBundleIDs(ids)
        }
        tracker.forget(bundleID: bundleID)
    }

    @objc private func unignore(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        var ids = Prefs.ignoredBundleIDs()
        ids.removeAll { $0 == bundleID }
        Prefs.setIgnoredBundleIDs(ids)
    }

    @objc private func toggleIcons() {
        Prefs.showsIcon.toggle()
        overlayController.applyPreferences()
    }

    @objc private func toggleLogin() {
        let enable = SMAppService.mainApp.status != .enabled
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = "Move NoTabsConfusion into Applications, open it from there, and try again."
            alert.runModal()
        }
    }

    private func updateStatusAppearance() {
        statusItem.button?.alphaValue = Prefs.isPaused ? 0.4 : 1
    }

    @objc private func openPreferences() {
        if prefsWindowController == nil {
            prefsWindowController = PreferencesWindowController()
        }
        // A menu-bar-only app has no Dock icon. Become a regular app while
        // the window is open so the window can come forward.
        NSApp.setActivationPolicy(.regular)
        prefsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func revealOnLaunch() {
        openPreferences()
        requestAccessibilityIfNeeded()
    }

    @objc private func requestAccess() {
        requestAccessibilityIfNeeded()
    }

    @objc private func preferencesChanged() {
        overlayController.applyPreferences()
        tracker.applyLimits()
        updateStatusAppearance()
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

extension OverlayWindowController: WindowTrackerDelegate {
    func windowTrackerDidUpdate(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)]) {
        update(slots: slots)
    }
}
