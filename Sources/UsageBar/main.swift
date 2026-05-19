import AppKit
import SwiftUI

if let flag = CommandLine.arguments.firstIndex(of: "--screenshot") {
    // Headless mode: render the popover to a PNG (used for the README).
    let outPath = CommandLine.arguments.indices.contains(flag + 1)
        ? CommandLine.arguments[flag + 1]
        : "/tmp/aiusage-screenshot.png"

    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    application.appearance = NSAppearance(named: .darkAqua)

    let store = UsageStore()
    store.refresh(force: true)
    // The claude.ai webview needs a moment to load — re-query while it does.
    for delay in [3.0, 6.0, 9.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { store.refresh(force: true) }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
        let content = ContentView(store: store)
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.13, green: 0.13, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: outPath))
        }
        exit(0)
    }
    application.run()
} else {
    // Normal mode: a menu-bar accessory app, no Dock icon.
    let appDelegate = AppDelegate()
    let application = NSApplication.shared
    application.delegate = appDelegate
    application.setActivationPolicy(.accessory)
    application.run()
}
