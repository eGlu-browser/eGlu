// The Mac's part of the visibility video: the pointer rests on Settings, goes to Instagram's
// "View on macOS" switch, clicks it off, waits, clicks it on, and comes back to rest.
// Screen points, top-left origin. pointer2 run OUT PID writes when it started to OUT; it clicks only
// while app PID is in front and its window is under the pointer.
import AppKit
import CoreGraphics
import Foundation

struct P { var x: Double; var y: Double }

func post(_ type: CGEventType, _ p: P) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: p.y), mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func minJerk(_ u: Double) -> Double { let u = min(max(u, 0), 1); return u * u * u * (10 - 15 * u + 6 * u * u) }

func move(_ a: P, _ b: P, _ u: Double, bow: Double) -> P {
    let s = minJerk(u)
    let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 1)
    let side = bow * sin(Double.pi * s)
    return P(x: a.x + dx * s - dy / len * side, y: a.y + dy * s + dx / len * side)
}

let rest = P(x: 1262, y: 790)
let sw = P(x: 1369, y: 686), sw2 = P(x: 1371, y: 687)

func at(_ t: Double) -> P {
    switch t {
    case ..<0.3: return rest
    case ..<0.85: return move(rest, sw, (t - 0.3) / 0.55, bow: -18)
    case ..<2.6: return P(x: sw.x + (sw2.x - sw.x) * min((t - 0.85) / 1.7, 1), y: sw.y + (sw2.y - sw.y) * min((t - 0.85) / 1.7, 1))
    case ..<3.6: return sw2
    case ..<4.3: return move(sw2, rest, (t - 3.6) / 0.7, bow: 18)
    default: return rest
    }
}

let clicks: [(down: Double, up: Double)] = [(1.0, 1.12), (2.8, 2.92)]
let end = 4.8
let args = CommandLine.arguments
// Only ever click the test app: it must be in front, and its window must be the one under the pointer.
let owner = pid_t(Int32(args[3])!)
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
guard safe(sw) else { print("not safe: the test app is not in front under the switch"); exit(2) }
post(.mouseMoved, rest)
usleep(250_000)
let t0 = DispatchTime.now().uptimeNanoseconds
try! String(Date().timeIntervalSince1970).write(toFile: args[2], atomically: true, encoding: .utf8)
var state = 0  // events posted: down, up, down, up
while true {
    let t = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    if t > end { break }
    let p = at(t)
    let next = state < 4 ? (state % 2 == 0 ? clicks[state / 2].down : clicks[state / 2].up) : .infinity
    if t >= next {
        if state % 2 == 0, !safe(p) { print("not safe at", t); exit(2) }
        post(state % 2 == 0 ? .leftMouseDown : .leftMouseUp, p)
        state += 1
    } else {
        post(state % 2 == 1 ? .leftMouseDragged : .mouseMoved, p)
    }
    usleep(4_000)
}
print("done")
