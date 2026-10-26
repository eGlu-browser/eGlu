import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
    if owner.contains("Safience") {
        print(pid, owner, w[kCGWindowNumber as String] ?? "", w[kCGWindowLayer as String] ?? "", w[kCGWindowBounds as String] ?? "", w[kCGWindowName as String] ?? "")
    }
}
