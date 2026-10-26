import CoreGraphics
import Foundation
for down in [true, false] {
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
    usleep(60_000)
}
