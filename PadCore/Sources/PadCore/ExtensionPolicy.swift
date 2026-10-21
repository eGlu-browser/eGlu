import Foundation

/// What every extension is held to, whatever it asks for and whatever the
/// person grants it: Google's sign-in stays untouched (HandsOff).
///
/// An extension's content script on accounts.google.com would be exactly
/// the injected listener Google's sign-in looks for, so every extension
/// context denies the hands-off hosts, which in WebKit beats any site it was
/// granted, all sites included. A click on an extension's button would
/// grant the tab before that denial is read, so on a hands-off page the
/// click grants nothing. And the cookies accounts.google.com receives are
/// set for .google.com, which an extension let on any Google site could
/// read through `chrome.cookies`, so no extension gets that permission.
public enum ExtensionPolicy {
    /// Match patterns every extension context denies: each hands-off host
    /// and the hosts within it.
    public static var deniedSites: [String] {
        HandsOff.hosts.map { "*://*.\($0)/*" }
    }

    /// Permissions every extension context denies.
    public static let deniedPermissions: Set<String> = ["cookies"]

    /// Whether a click on an extension's button may grant it the page it
    /// was clicked on.
    public static func grantsOnClick(_ url: URL?) -> Bool {
        !HandsOff.covers(url)
    }

    /// Whether Safience's own answer to an extension (its shims) may delete
    /// or read the data of sites under `domain`: not those whose cookies go
    /// to a hands-off host. A shim that clears browsing data leaves them.
    public static func mayTouchData(ofDomain domain: String) -> Bool {
        !HandsOff.covers(cookieDomain: domain) && !HandsOff.covers(host: domain)
    }

    /// Whether an extension's own content security policy lets it connect
    /// to `url`, as WebKit checks a connection the extension makes itself:
    /// its `connect-src`, or `default-src` without one. A connection
    /// Safience makes for it (its worker's WebSocket) is held to the same.
    /// No policy, or neither directive, lets everything through, as in
    /// Chrome. 'self' is the extension's own origin, which no socket is.
    public static func allowsConnection(to url: URL, policy: String?) -> Bool {
        guard let policy else { return true }
        var directives: [String: [String]] = [:]
        for part in policy.split(separator: ";") {
            let words = part.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
            guard let name = words.first, directives[name] == nil else { continue }
            directives[name] = Array(words.dropFirst())
        }
        guard let sources = directives["connect-src"] ?? directives["default-src"] else { return true }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host()?.lowercased() ?? ""
        let web = ["http", "https", "ws", "wss"]
        // A secure scheme is let through by its plain one's name too: https
        // covers wss, and http covers ws (CSP Level 3).
        func schemeMatches(_ source: String) -> Bool {
            source == scheme || (source == "https" && scheme == "wss") || (source == "http" && (scheme == "ws" || scheme == "https" || scheme == "wss"))
                || (source == "ws" && scheme == "wss")
        }
        for source in sources {
            if source == "*" {
                if web.contains(scheme) { return true }
                continue
            }
            if source.hasPrefix("'") { continue }
            if source.hasSuffix(":"), !source.contains("/") {
                if schemeMatches(String(source.dropLast())) { return true }
                continue
            }
            var rest = Substring(source)
            if let separator = rest.range(of: "://") {
                guard schemeMatches(String(rest[..<separator.lowerBound])) else { continue }
                rest = rest[separator.upperBound...]
            } else if !web.contains(scheme) {
                continue
            }
            // The source's path, if it names one: a folder (ending in /)
            // takes what is under it, anything else that one address (CSP
            // Level 3's path-part match).
            var sourcePath = ""
            if let slash = rest.firstIndex(of: "/") {
                sourcePath = String(rest[slash...])
                rest = rest[..<slash]
            }
            if !sourcePath.isEmpty {
                let path = url.path(percentEncoded: true).isEmpty ? "/" : url.path(percentEncoded: true)
                if sourcePath.hasSuffix("/") ? !path.hasPrefix(sourcePath) : path != sourcePath { continue }
            }
            var sourceHost = String(rest)
            if let colon = sourceHost.lastIndex(of: ":") {
                let port = sourceHost[sourceHost.index(after: colon)...]
                sourceHost = String(sourceHost[..<colon])
                let actual = url.port ?? (["https", "wss"].contains(scheme) ? 443 : 80)
                if port != "*", Int(port) != actual { continue }
            }
            if sourceHost.hasPrefix("*.") {
                if host.hasSuffix(String(sourceHost.dropFirst(1))) { return true }
            } else if sourceHost == host {
                return true
            }
        }
        return false
    }
}
