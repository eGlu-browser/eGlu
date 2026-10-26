// axsize PID TITLE-PREFIX W H : resizes that app's window whose title starts with that.
import ApplicationServices
import Foundation
let a = CommandLine.arguments
let app = AXUIElementCreateApplication(pid_t(Int32(a[1])!))
var value: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
for w in (value as? [AXUIElement]) ?? [] {
    var t: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
    if (t as? String ?? "").hasPrefix(a[2]) {
        var s = CGSize(width: Double(a[3])!, height: Double(a[4])!)
        print("size", AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!).rawValue)
    }
}
