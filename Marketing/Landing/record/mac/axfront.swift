// axfront PID TITLE : that app in front, its window with that title raised and main; prints the front app.
import AppKit
import ApplicationServices
let a = CommandLine.arguments
let pid = pid_t(Int32(a[1])!)
let app = AXUIElementCreateApplication(pid)
AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
var value: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
for w in (value as? [AXUIElement]) ?? [] {
    var t: CFTypeRef?
    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
    if (t as? String) == a[2] {
        AXUIElementPerformAction(w, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
usleep(400_000)
print("front", NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
