// axmove PID TITLE X Y : moves that app's window with that title to (X, Y), top-left screen points.
import ApplicationServices
import Foundation
let a = CommandLine.arguments
print("trusted", AXIsProcessTrusted())
let app = AXUIElementCreateApplication(pid_t(Int32(a[1])!))
var value: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
for w in (value as? [AXUIElement]) ?? [] {
    var t: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
    let title = t as? String ?? ""
    if title == a[2] {
        var p = CGPoint(x: Double(a[3])!, y: Double(a[4])!)
        let v = AXValueCreate(.cgPoint, &p)!
        print("move", title, AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v).rawValue)
    }
}
