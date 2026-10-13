import AppKit

let app = NSApplication.shared
let delegate = MenuBarApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
