import Cocoa

let app = NSApplication.shared
// Top-level code here runs before the main run loop, so the main-actor delegate is built explicitly on it
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
