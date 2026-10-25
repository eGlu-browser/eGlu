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
    // A local server is told apart by its port: localhost:5173 keeps it.
    let port = Address.isLocal(host: host) ? url.port.map { ":\($0)" } ?? "" : ""
    let name = Destination.registrable(bare)
    guard bare.hasSuffix(name), name.count < bare.count else {
        return Text(bare + port).fontWeight(.semibold)
    }
    let quieter = Text(String(bare.dropLast(name.count))).foregroundStyle(quiet)
    return Text("\(quieter)\(Text(name + port).fontWeight(.semibold))")
}
