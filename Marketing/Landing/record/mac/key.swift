// key CODE [cmd] : posts one key press, with Command if asked.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let code = CGKeyCode(Int(a[1])!)
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
    if a.count > 2 { e?.flags = .maskCommand }
    e?.post(tap: .cghidEventTap)
    usleep(60_000)
}
