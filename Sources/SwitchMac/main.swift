import AppKit

// Entry point — run as a menu bar-only app (no Dock icon)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
