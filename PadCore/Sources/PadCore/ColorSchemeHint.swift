import Foundation

/// The screen's light or dark, for the sites that ask for it as a header.
///
/// Most sites follow `prefers-color-scheme` in their CSS, which WebKit
/// answers. Some decide on their server, from the `Sec-CH-Prefers-Color-Scheme`
/// client hint, which a response asks for in `Accept-CH`: Google's search
/// pages do. Chromium sends the hint to a site that has asked; WebKit never
/// does, and such a site is light on a dark screen. The app sends it, as
/// Chromium does, to the hosts that have asked, and only to them. They are
/// kept for the run and never written down, so they are no record of where
/// anyone went. A page from a host that asks, which came without the hint
/// on a dark screen, is asked for again with it; on a light screen the
/// light page it sent is the right one.
public struct ColorSchemeHint: Sendable {
    public static let header = "Sec-CH-Prefers-Color-Scheme"

    private var hosts: Set<String> = []

    public init() {}

    public static func value(dark: Bool) -> String {
        dark ? "dark" : "light"
    }

    /// Whether a response asks for the hint: its Accept-CH or Critical-CH names it.
    public static func isAsked(acceptCH: String?, criticalCH: String? = nil) -> Bool {
        [acceptCH, criticalCH].contains { list in
            (list ?? "").split(separator: ",").contains {
                $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(header) == .orderedSame
            }
        }
    }

    /// The value a request for a page should go again with: one to a host
    /// that has asked, by GET, made without the hint; nil for any other.
    public func missing(url: URL?, method: String?, headers: [String: String]?, dark: Bool) -> String? {
        guard let host = Self.host(of: url), hosts.contains(host),
              (method ?? "GET").uppercased() == "GET", !Self.carries(headers)
        else { return nil }
        return Self.value(dark: dark)
    }

    /// A page's response came: a host that asks for the hint is kept, and
    /// the value to ask for the page again with is given back when it came
    /// without it on a dark screen, by a request that can be made again.
    public mutating func answered(url: URL?, acceptCH: String?, criticalCH: String?,
                                  requestCarried: Bool, repeatable: Bool, dark: Bool) -> String? {
        guard let host = Self.host(of: url), Self.isAsked(acceptCH: acceptCH, criticalCH: criticalCH) else { return nil }
        hosts.insert(host)
        guard dark, !requestCarried, repeatable else { return nil }
        return Self.value(dark: true)
    }

    /// Whether a request's headers have the hint already.
    public static func carries(_ headers: [String: String]?) -> Bool {
        (headers ?? [:]).keys.contains { $0.caseInsensitiveCompare(header) == .orderedSame }
    }

    /// The hint is per origin; a page of the web's only.
    private static func host(of url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host()?.lowercased()
        else { return nil }
        return host
    }
}
