import CoreGraphics
import Foundation
let start = CGEvent(source: nil)!.location
print("trusted-ish? start", start)
let p = CGPoint(x: start.x + 3, y: start.y)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(150_000)
let after = CGEvent(source: nil)!.location
print("after", after)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(100_000)
print("back", CGEvent(source: nil)!.location)
