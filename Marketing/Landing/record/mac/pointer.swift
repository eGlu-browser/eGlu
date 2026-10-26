// Moves the pointer over Safience for Mac's pinned tiles on the phone recording's clock:
// Hacker News by 0.64 s, Instagram by 1.77, Google by 2.92, Instagram again by 4.07, a click
// there released at 5.15, then off onto the page. Screen points, top-left origin.
//
// pointer park X Y    put the pointer there
// pointer run OUT     the whole path; writes when it started (seconds since 1970) to OUT
import CoreGraphics
import Foundation

struct P { var x: Double; var y: Double }

func post(_ type: CGEventType, _ p: P) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: p.x, y: p.y), mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func minJerk(_ u: Double) -> Double { let u = min(max(u, 0), 1); return u * u * u * (10 - 15 * u + 6 * u * u) }

/// A move from a to b, bowed sideways by `bow` points at its middle, as a wrist swings.
func move(_ a: P, _ b: P, _ u: Double, bow: Double) -> P {
    let s = minJerk(u)
    let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 1)
    let side = bow * sin(Double.pi * s)
    return P(x: a.x + dx * s - dy / len * side, y: a.y + dy * s + dx / len * side)
}

/// A slow drift while resting on a tile.
func drift(_ a: P, _ b: P, _ u: Double) -> P {
    let s = 0.5 - 0.5 * cos(Double.pi * min(max(u, 0), 1))
    return P(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
}

let start = P(x: 1260, y: 676)
let hn0 = P(x: 683, y: 395), hn1 = P(x: 691, y: 390)
let ig0 = P(x: 764, y: 394), ig1 = P(x: 772, y: 390)
let g0 = P(x: 847, y: 395), g1 = P(x: 854, y: 391)
let ig2 = P(x: 771, y: 395), ig3 = P(x: 767, y: 393)
let away = P(x: 1430, y: 610)

/// Where the pointer is at t seconds on the phone recording's clock.
func at(_ t: Double) -> P {
    switch t {
    case ..<0.08: return start
    case ..<0.64: return move(start, hn0, (t - 0.08) / 0.56, bow: -36)
    case ..<1.55: return drift(hn0, hn1, (t - 0.64) / 0.91)
    case ..<1.77: return move(hn1, ig0, (t - 1.55) / 0.22, bow: 4)
    case ..<2.70: return drift(ig0, ig1, (t - 1.77) / 0.93)
    case ..<2.92: return move(ig1, g0, (t - 2.70) / 0.22, bow: 4)
    case ..<3.85: return drift(g0, g1, (t - 2.92) / 0.93)
    case ..<4.07: return move(g1, ig2, (t - 3.85) / 0.22, bow: -4)
    case ..<4.95: return drift(ig2, ig3, (t - 4.07) / 0.88)
    case ..<5.75: return ig3
    case ..<6.45: return move(ig3, away, (t - 5.75) / 0.70, bow: 30)
    default: return away
    }
}

let args = CommandLine.arguments
if args.count >= 4, args[1] == "park" {
    post(.mouseMoved, P(x: Double(args[2])!, y: Double(args[3])!))
    exit(0)
}
guard args.count >= 3, args[1] == "run" else { print("pointer park X Y | pointer run OUT"); exit(1) }

let downAt = 5.03, upAt = 5.15, end = 6.8
post(.mouseMoved, start)
usleep(200_000)
let t0 = DispatchTime.now().uptimeNanoseconds
try! String(Date().timeIntervalSince1970).write(toFile: args[2], atomically: true, encoding: .utf8)
var down = false, up = false
while true {
    let t = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    if t > end { break }
    let p = at(t)
    if !down, t >= downAt { post(.leftMouseDown, p); down = true }
    else if down, !up, t >= upAt { post(.leftMouseUp, p); up = true }
    else { post(down && !up ? .leftMouseDragged : .mouseMoved, p) }
    usleep(4_000)
}
print("done")
