import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var overlayController: OverlayWindowController!
    private var tracker: WindowTracker!
    private var prefsWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Terminate any pre-existing instance so only one runs at a time.
        let myPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        for app in running where app.processIdentifier != myPID {
            app.forceTerminate()
        }

        requestAccessibilityIfNeeded()
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
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scope", accessibilityDescription: "FocusBorder")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit FocusBorder",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openPreferences() {
        if prefsWindowController == nil {
            prefsWindowController = PreferencesWindowController()
        }
        prefsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func preferencesChanged() {
        overlayController.applyPreferences()
    }

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            FocusBorder needs Accessibility access to detect which window is focused.

            Please grant access in:
            System Settings → Privacy & Security → Accessibility

            Then relaunch the app.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - WindowTrackerDelegate

extension OverlayWindowController: WindowTrackerDelegate {
    func windowTrackerDidUpdate(slots: [(id: CGWindowID, frame: NSRect, icon: NSImage?)]) {
        update(slots: slots)
    }
}
