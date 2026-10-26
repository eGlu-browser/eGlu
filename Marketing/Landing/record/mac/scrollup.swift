// scrollup X Y : moves the pointer there and scrolls up a long way.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(100_000)
for _ in 0..<40 {
    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 400, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    usleep(15_000)
}
