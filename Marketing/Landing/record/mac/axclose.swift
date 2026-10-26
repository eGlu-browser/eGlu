// axclose PID TITLE : presses the close button of that app's window with that title.
import ApplicationServices
let a = CommandLine.arguments
let app = AXUIElementCreateApplication(pid_t(Int32(a[1])!))
var v: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v)
for w in (v as? [AXUIElement]) ?? [] {
    var t: CFTypeRef?; AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
    guard (t as? String) == a[2] else { continue }
    var b: CFTypeRef?; AXUIElementCopyAttributeValue(w, kAXCloseButtonAttribute as CFString, &b)
    if let b { print("close", AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString).rawValue) }
}
