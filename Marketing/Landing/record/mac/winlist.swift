// winlist PID : every window of the app, front to back: id, layer, bounds, name, on screen.
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(b["Width"] ?? 0), Int(b["Height"] ?? 0),
          (w[kCGWindowIsOnscreen as String] as? Bool) == true ? "on" : "off", w[kCGWindowName as String] as? String ?? "")
}
