import AppKit

// MainActor.assumeIsolated lets us touch actor-isolated types synchronously
// at program start, before the run loop begins — safe because we're on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
