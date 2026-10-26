// axdump PID [DEPTH] : the app's windows and their elements, with role, title or description, and frame (screen points).
import AppKit
import ApplicationServices
let a = CommandLine.arguments
let pid = pid_t(Int32(a[1])!)
let maxDepth = a.count > 2 ? Int(a[2])! : 12
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, k as CFString, &v); return v }
func frame(_ e: AXUIElement) -> String {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))"
}
func walk(_ e: AXUIElement, _ d: Int) {
    let role = attr(e, kAXRoleAttribute) as? String ?? ""
    let title = attr(e, kAXTitleAttribute) as? String ?? ""
    let desc = attr(e, kAXDescriptionAttribute) as? String ?? ""
    let ident = attr(e, kAXIdentifierAttribute) as? String ?? ""
    let value = (attr(e, kAXValueAttribute) as? String).map { String($0.prefix(40)) } ?? ""
    if !(title.isEmpty && desc.isEmpty && ident.isEmpty && value.isEmpty) || role == "AXWindow" || role == "AXPopover" || role == "AXSheet" {
        print(String(repeating: " ", count: d), role, "t=\(title)", "d=\(desc)", ident.isEmpty ? "" : "id=\(ident)", value.isEmpty ? "" : "v=\(value)", frame(e))
    }
    guard d < maxDepth else { return }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, d + 1) }
}
let app = AXUIElementCreateApplication(pid)
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(w, 0) }
