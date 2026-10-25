import Foundation

// What you type is either a place or nothing. Searching is decided elsewhere
// (Destination, in Commands.swift): this hands back a URL only when the text
// really is an address, so "hello world" or "todo" never become a website.
public enum Address {
    /// Schemes a tab can show itself. Anything else typed with a scheme
    /// (mailto:, another app's link) is somebody else's job and is refused
    /// here rather than opening a blank tab.
    private static let ours: Set<String> = ["http", "https", "file", "about", "data"]

    static func url(from typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        // Written with a scheme, it is taken at its word.
        if let split = text.range(of: "://") {
            let scheme = text[..<split.lowerBound].lowercased()
            guard ours.contains(scheme) else { return nil }
            return URL(string: text)
        }
        if text.lowercased().hasPrefix("about:") || text.lowercased().hasPrefix("data:") {
            return URL(string: text)
        }

        // Everything else has to look like a host before it gets a scheme
        // put in front of it.
        let head = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !head.contains("@") else { return nil }   // an email address
        // This device by its IPv6 address, [::1]:3000, is a place too.
        if head.hasPrefix("[::1]") { return URL(string: "http://" + text) }
        let host = head.split(separator: ":").first.map(String.init) ?? String(head)
        guard looksLikeHost(host) else { return nil }

        // A local server almost never has a certificate, so https there is a
        // connection failure rather than a page. The same goes for a machine
        // on the network by its name or address: a Mac's dev server at
        // 192.168.1.20:3000, printer.local.
        let local = isLocal(host: host)
        return URL(string: (local ? "http://" : "https://") + text)
    }

    /// This machine or the network it is on: a dev server at localhost or
    /// 127.0.0.1, a Mac or a printer on the LAN. Sites like these are where
    /// developer mode turns on by itself, and where https is a connection
    /// failure rather than a page.
    public static func isLocal(host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if let address = ipv4(host) { return localIPv4(address) }
        return localIPv6(host)
    }

    /// The four numbers of a dotted address, or nil for a name: a host
    /// named 10.example.com is somebody's site, not the local network.
    private static func ipv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { UInt8($0) }
        return numbers.count == 4 ? numbers : nil
    }

    /// This machine (127.0.0.0/8), every address it has (0.0.0.0), the
    /// three private ranges (10/8; 172.16/12, where Docker and many offices
    /// put their machines; 192.168/16) and a link's own (169.254/16).
    private static func localIPv4(_ address: [UInt8]) -> Bool {
        switch (address[0], address[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (0, _): return address == [0, 0, 0, 0]
        default: return false
        }
    }

    /// The same for IPv6, with or without the brackets an address puts
    /// round it: this machine (::1), every address it has (::), the unique
    /// local range (fc00::/7) and a link's own (fe80::/10, with or without
    /// its zone, as fe80::1%en0).
    private static func localIPv6(_ host: String) -> Bool {
        var bare = host
        if bare.hasPrefix("["), bare.hasSuffix("]") { bare = String(bare.dropFirst().dropLast()) }
        if let zone = bare.firstIndex(of: "%") { bare = String(bare[..<zone]) }
        guard bare.contains(":"), bare.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) else { return false }
        if bare == "::1" || bare == "::" { return true }
        guard let first = bare.split(separator: ":", omittingEmptySubsequences: false).first,
              !first.isEmpty, first.count <= 4, let group = UInt16(first, radix: 16)
        else { return false }
        return group & 0xfe00 == 0xfc00 || group & 0xffc0 == 0xfe80
    }

    /// Dev servers say they listen on 0.0.0.0, every address the machine
    /// has, and print that as the address to open. WebKit refuses to go
    /// there and shows nothing at all, so it is opened as localhost.
    static func reachable(_ url: URL) -> URL? {
        guard url.host() == "0.0.0.0", ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        parts.host = "localhost"
        return parts.url
    }

    private static func looksLikeHost(_ host: String) -> Bool {
        if host == "localhost" { return true }

        // Four numbers is an address on the local network as often as not.
        let numbers = host.split(separator: ".", omittingEmptySubsequences: false)
        if numbers.count == 4, numbers.allSatisfy({ UInt8($0) != nil }) { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        guard labels.allSatisfy({ label in
            !label.isEmpty
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return false }

        // The last label carries the weight: a dotted thing ending in letters
        // is a domain, a dotted thing ending in digits is a version number.
        let tld = labels[labels.count - 1]
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter }
    }

    /// A page's address as the field shows it for editing: something that,
    /// sent as it is, goes back to the same page. The scheme is left off only
    /// when the field would put that very scheme back, and a bare "/" only
    /// when nothing follows it. A port, a query, a fragment, and plain http
    /// to a host that isn't local all stay.
    static func editable(_ page: URL) -> String {
        let full = page.absoluteString
        guard let scheme = page.scheme, full.lowercased().hasPrefix(scheme.lowercased() + "://") else { return full }
        let short = String(full.dropFirst(scheme.count + 3))
        var candidates = [short]
        if page.path() == "/", page.query() == nil, page.fragment() == nil, short.hasSuffix("/") {
            candidates.insert(String(short.dropLast()), at: 0)
        }
        for candidate in candidates {
            guard let back = url(from: candidate) else { continue }
            if back.absoluteString == full || back.absoluteString + "/" == full { return candidate }
        }
        return full
    }

    /// What a tab says before the page has told it its title: the address,
    /// with the parts nobody reads taken off.
    static func pretty(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path()
        return path.isEmpty || path == "/" ? bare : bare + path
    }
}
