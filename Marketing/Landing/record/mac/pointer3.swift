// The Mac's part of the Handoff video: the pointer rests on the page, opens More beside the address,
// picks Send to App, rests near the panel while the page is read, and clicks the panel's Send to App
// once it is enabled; the share menu opens. Screen points, top-left origin.
// pointer3 OUT PID : writes its clock's start and each event's time to OUT; clicks only while app PID
// is in front and its window is under the pointer.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct P { var x: Double; var y: Double }

func post(_ type: CGEventType, _ p: P) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: p.y), mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func minJerk(_ u: Double) -> Double { let u = min(max(u, 0), 1); return u * u * u * (10 - 15 * u + 6 * u * u) }

func lerp(_ a: P, _ b: P, _ u: Double, bow: Double) -> P {
    let s = minJerk(u)
    let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 1)
    let side = bow * sin(Double.pi * s)
    return P(x: a.x + dx * s - dy / len * side, y: a.y + dy * s + dx / len * side)
}

let args = CommandLine.arguments
let owner = pid_t(Int32(args[2])!)
func safe(_ p: P) -> Bool {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == owner else { return false }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
        guard let b = w[kCGWindowBounds as String] as? [String: Double] else { continue }
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        if r.contains(CGPoint(x: p.x, y: p.y)) { return (w[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) } == owner }
    }
    return false
}

// The panel's Send to App button, enabled once the page is read.
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, k as CFString, &v); return v }
func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
    if (attr(e, kAXRoleAttribute) as? String) == "AXButton", (attr(e, kAXDescriptionAttribute) as? String) == "Send to App",
       let v = attr(e, kAXSizeAttribute) { var s = CGSize.zero; AXValueGetValue(v as! AXValue, .cgSize, &s); if s.width > 200 { return e } }
    guard depth < 20 else { return nil }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = find(c, depth + 1) { return f } }
    return nil
}
func panelReady() -> Bool {
    let app = AXUIElementCreateApplication(owner)
    for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        if let b = find(w, 0) { return (attr(b, kAXEnabledAttribute) as? Bool) == true }
    }
    return false
}

let rest = P(x: 1150, y: 560)
let more = P(x: 844, y: 346), more2 = P(x: 845, y: 347)
let tile = P(x: 930, y: 408)
let near = P(x: 1720, y: 990)
let send = P(x: 1699, y: 1027)

guard safe(more) else { print("not safe: the test app is not in front under More"); exit(2) }
post(.mouseMoved, rest)
usleep(250_000)
let t0 = DispatchTime.now().uptimeNanoseconds
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9 }
var log = "start \(Date().timeIntervalSince1970)\n"
func note(_ s: String) { log += "\(s) \(String(format: "%.3f", now()))\n"; try? log.write(toFile: args[1], atomically: true, encoding: .utf8) }
note("clock")

func glide(_ a: P, _ b: P, from: Double, dur: Double, bow: Double) {
    while true {
        let t = now()
        if t >= from + dur { post(.mouseMoved, b); return }
        post(.mouseMoved, t < from ? a : lerp(a, b, (t - from) / dur, bow: bow))
        usleep(4_000)
    }
}
func click(_ p: P, _ name: String) {
    guard safe(p) else { print("not safe at", name); exit(2) }
    post(.leftMouseDown, p); note("down \(name) \(Int(p.x)),\(Int(p.y))")
    usleep(110_000)
    post(.leftMouseUp, p)
}
func hold(_ p: P, until: Double) { while now() < until { post(.mouseMoved, p); usleep(8_000) } }

glide(rest, more, from: 0.3, dur: 0.6, bow: -16)
hold(more, until: 1.05)
click(more, "more")
hold(more, until: 1.35)
glide(more, tile, from: 1.35, dur: 0.45, bow: 10)
hold(tile, until: 1.95)
click(tile, "tile")
hold(tile, until: 2.3)
glide(tile, near, from: 2.3, dur: 0.9, bow: -30)
// Rest near the panel while the page is read.
while !panelReady() {
    if now() > 200 { print("panel never ready"); exit(3) }
    hold(near, until: now() + 0.25)
}
note("ready")
let r = now()
hold(near, until: r + 0.9)
glide(near, send, from: r + 0.9, dur: 0.45, bow: 6)
hold(send, until: r + 1.55)
click(send, "send")
hold(send, until: r + 5.5)
note("end")
print("done")
