import Foundation

/// Whether a page gets the developer bar and its tools. A site remembers
/// its own choice once made; before that, a local site has it on and any
/// other site has it off. `local` is the "Developer Mode on Local Sites"
/// setting: off, local sites no longer get it by themselves.
public enum DeveloperMode {
    public static func isOn(_ url: URL?, choices: [String: Bool], local: Bool) -> Bool {
        guard let url, let host = url.host() else { return false }
        if let key = SiteMode.siteKey(host), let choice = choices[key] { return choice }
        return local && Address.isLocal(host: host)
    }

    /// The key a site's choice is remembered under, as the rest of the
    /// site's choices are (SiteMode).
    public static func siteKey(_ url: URL?) -> String? {
        url?.host().flatMap { SiteMode.siteKey($0) }
    }

    /// Whether a response's MIME type is JSON (`application/json` or a
    /// `+json` kind, as `application/activity+json`): a page of it gets the
    /// JSON view while Settings formats JSON (Preferences.formatJSON).
    public static func isJSON(mimeType: String?) -> Bool {
        guard let type = mimeType?.lowercased(),
              let subtype = type.split(separator: "/").last else { return false }
        return subtype == "json" || subtype.hasSuffix("+json")
    }
}
