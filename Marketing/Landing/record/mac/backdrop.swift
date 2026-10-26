// A plain dark window over the whole main screen, behind whatever is brought to the front after it.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let frame = NSScreen.main!.frame
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.backgroundColor = NSColor(srgbRed: 16 / 255, green: 17 / 255, blue: 20 / 255, alpha: 1)
window.level = .normal
window.isOpaque = true
window.hasShadow = false
window.ignoresMouseEvents = true
window.orderFrontRegardless()
app.run()
