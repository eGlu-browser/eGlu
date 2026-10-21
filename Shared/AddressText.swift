import PadCore
import SwiftUI

/// Where a page is, as the tab that is the address says it along the top,
/// on iPad and Mac, as the iPad's did before: the part of the host that says
/// who you are talking to in bold ("google.com"), what comes before it
/// quieter ("accounts."); a search with the chosen engine, its words.
func addressText(_ url: URL, engine: String, quiet: Color) -> Text {
    if let words = Destination.searchWords(in: url, engine: engine) {
        return Text(words)
    }
    guard let host = url.host() else {
        return Text(Destination.pretty(url))
    }
    let bare = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    let name = Destination.registrable(bare)
    guard bare.hasSuffix(name), name.count < bare.count else {
        return Text(bare).fontWeight(.semibold)
    }
    return Text(String(bare.dropLast(name.count))).foregroundStyle(quiet) + Text(name).fontWeight(.semibold)
}
