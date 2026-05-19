import AppKit

// Entry point. Runs as an accessory app — a menu-bar item, no Dock icon.
let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
