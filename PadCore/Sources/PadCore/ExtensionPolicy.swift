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
}
