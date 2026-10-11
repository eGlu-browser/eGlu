import Foundation

/// Sites that keep their context menus to themselves.
///
/// A link has the app's menu at a long press or a secondary click
/// (Page.linkMenu). A web app that draws a menu of its own there would then
/// show two. A secondary click the page keeps is heard through the bridge
/// and needs no list; a finger held down sends the page no such event, so
/// nothing can tell that the page will answer it. For that there is this
/// list: on a site in it the app's menu is off, and WebKit's callouts with
/// it, as they were everywhere before links had a menu.
///
/// The list is the built-in sites below and, over them, what Settings ›
/// Link menu and the page's menu say for a site (Preferences.ownMenuSites):
/// a site of one's own added, or a built-in one let go. Only the choices are
/// saved, not the list, so a site added here in a later version reaches
/// everyone who didn't say otherwise.
public enum OwnMenus {
    public struct Site: Equatable, Sendable {
        public let name: String
        /// The host its web app runs on, without `www.`: it covers that host
        /// and every host under it, and nothing beside it, so `docs.google.com`
        /// leaves Google's search alone.
        public let host: String
    }

    /// Web apps that draw their own menu at a secondary click, a long press,
    /// or both, by the host the app itself runs on. From a survey of each
    /// app's own help pages (October 2026), kept to hosts that are the app's
    /// and not the whole company's: `docs.google.com`, not `google.com`.
    /// Where a host also carries the company's other pages (figma.com,
    /// notion.so), those lose the app's link menu too, which Settings can
    /// give back. Left out on purpose: sites whose menu covers one part of a
    /// page (YouTube's player) or whose app shares a host with pages of
    /// links (Google Maps, GitLab's Web IDE).
    public static let builtIn: [Site] = [
        Site(name: "Figma", host: "figma.com"),
        Site(name: "Canva", host: "canva.com"),
        Site(name: "Miro", host: "miro.com"),
        Site(name: "Mural", host: "app.mural.co"),
        Site(name: "Framer", host: "framer.com"),
        Site(name: "Webflow", host: "webflow.com"),
        Site(name: "Penpot", host: "design.penpot.app"),
        Site(name: "Lucid", host: "lucid.app"),
        Site(name: "diagrams.net", host: "app.diagrams.net"),
        Site(name: "Whimsical", host: "whimsical.com"),
        Site(name: "Excalidraw", host: "excalidraw.com"),
        Site(name: "tldraw", host: "tldraw.com"),
        Site(name: "Photopea", host: "photopea.com"),
        Site(name: "Spline", host: "app.spline.design"),
        Site(name: "Pitch", host: "app.pitch.com"),
        Site(name: "Photoshop", host: "photoshop.adobe.com"),
        Site(name: "Onshape", host: "cad.onshape.com"),
        Site(name: "Google Docs, Sheets and Slides", host: "docs.google.com"),
        Site(name: "Google Drive", host: "drive.google.com"),
        Site(name: "Gmail", host: "mail.google.com"),
        Site(name: "Outlook", host: "outlook.live.com"),
        Site(name: "Outlook for work", host: "outlook.office.com"),
        Site(name: "Outlook for work (Office 365)", host: "outlook.office365.com"),
        Site(name: "OneDrive", host: "onedrive.live.com"),
        Site(name: "SharePoint", host: "sharepoint.com"),
        Site(name: "Notion", host: "notion.so"),
        Site(name: "Coda", host: "coda.io"),
        Site(name: "Airtable", host: "airtable.com"),
        Site(name: "Box", host: "app.box.com"),
        Site(name: "iCloud", host: "icloud.com"),
        Site(name: "Proton Mail", host: "mail.proton.me"),
        Site(name: "Proton Drive", host: "drive.proton.me"),
        Site(name: "Linear", host: "linear.app"),
        Site(name: "Jira and Confluence", host: "atlassian.net"),
        Site(name: "Asana", host: "app.asana.com"),
        Site(name: "ClickUp", host: "app.clickup.com"),
        Site(name: "Shortcut", host: "app.shortcut.com"),
        Site(name: "Slack", host: "app.slack.com"),
        Site(name: "Discord", host: "discord.com"),
        Site(name: "Microsoft Teams", host: "teams.microsoft.com"),
        Site(name: "Telegram", host: "web.telegram.org"),
        Site(name: "WhatsApp", host: "web.whatsapp.com"),
        Site(name: "VS Code for the Web", host: "vscode.dev"),
        Site(name: "github.dev", host: "github.dev"),
        Site(name: "StackBlitz", host: "stackblitz.com"),
        Site(name: "Replit", host: "replit.com"),
        Site(name: "Overleaf", host: "overleaf.com"),
        Site(name: "Google Colab", host: "colab.research.google.com"),
        Site(name: "Spotify", host: "open.spotify.com"),
    ]

    /// Whether `host` is `entry` or under it.
    static func covers(_ entry: String, _ host: String) -> Bool {
        host == entry || host.hasSuffix("." + entry)
    }

    /// The built-in site a host belongs to, the most particular first.
    public static func builtIn(covering host: String?) -> Site? {
        guard let host = SiteMode.siteKey(host) else { return nil }
        return builtIn.filter { covers($0.host, host) }.max { $0.host.count < $1.host.count }
    }

    /// What someone typed as a site, as a host to keep: the host of an
    /// address or a bare host, lowercased, without `www.`; nil for anything
    /// that isn't one.
    public static func host(typed text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let address = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URLComponents(string: address)?.host, host.contains("."),
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") })
        else { return nil }
        return SiteMode.siteKey(host)
    }
}

extension Preferences {
    /// Whether the site at `host` keeps its own menus, the app's link menu
    /// off there: what was chosen for the host or, failing that, for the
    /// nearest host above it; else whether it is one of the built-in sites.
    public func keepsOwnMenus(onHost host: String?) -> Bool {
        guard var rest = SiteMode.siteKey(host) else { return false }
        while true {
            if let chosen = ownMenuSites[rest] { return chosen }
            guard let dot = rest.firstIndex(of: ".") else { break }
            rest = String(rest[rest.index(after: dot)...])
        }
        return OwnMenus.builtIn(covering: host) != nil
    }

    /// The site at `host` keeps its own menus, or doesn't. A built-in site
    /// is answered as a whole, under its own host; any other under the host
    /// given. A choice that only says what holds anyway, by the list or by a
    /// choice for a host above it, isn't kept.
    public mutating func setKeepsOwnMenus(_ keeps: Bool, onHost host: String?) {
        guard let site = SiteMode.siteKey(host) else { return }
        let builtIn = OwnMenus.builtIn(covering: site)
        let key = builtIn?.host ?? site
        // Choices for hosts under the one answered would outvote it.
        for chosen in ownMenuSites.keys where chosen != key && OwnMenus.covers(key, chosen) {
            ownMenuSites[chosen] = nil
        }
        ownMenuSites[key] = nil
        if keepsOwnMenus(onHost: key) != keeps { ownMenuSites[key] = keeps }
    }

    /// The sites added in Settings or from a page's menu, beyond the built-in ones.
    public var addedOwnMenuSites: [String] {
        ownMenuSites.filter { $0.value && OwnMenus.builtIn(covering: $0.key) == nil }.keys.sorted()
    }
}
