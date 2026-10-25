import Foundation

/// Whether a page's typing is checked, by site.
///
/// `writingOffSites` keeps the sites the person turned off, by site key
/// (`SiteMode.siteKey`, as unblockedSites and siteModes keep them), so
/// www.example.com and example.com are the same choice. A second list is
/// the app's own: sites whose fields are not text to check because they
/// draw it themselves (Google Docs draws its text, it is not in the DOM),
/// where checking could never see the words.
public enum WritingSites {
    /// Sites checking never runs on, whatever the settings say.
    public static let never = ["docs.google.com"]

    /// Whether a page at `url` is off: on a `never` host or one the person
    /// turned off (or a host under either, as HandsOff.covers matches).
    public static func isOff(_ url: URL?, sites: [String]) -> Bool {
        guard let host = Hosts.normal(url?.host()) else { return false }
        return (never + sites).contains { site in
            guard let domain = Hosts.normal(site) else { return false }
            return Hosts.host(host, isWithin: domain)
        }
    }
}
