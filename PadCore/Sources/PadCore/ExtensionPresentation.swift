import Foundation

/// The access a person approves, without requiring manifest terminology.
public enum ExtensionAccessDescription {
    public static func capability(_ permission: String) -> String {
        let descriptions = [
            "storage": BrowserText.localized("Store its settings and data on this Mac"),
            "unlimitedStorage": BrowserText.localized("Store data without the normal storage limit"),
            "tabs": BrowserText.localized("Read the addresses and titles of your tabs"),
            "activeTab": BrowserText.localized("Read and change the page when you use the extension"),
            "scripting": BrowserText.localized("Run scripts on sites you allow"),
            "declarativeNetRequest": BrowserText.localized("Block or redirect network requests on allowed sites"),
            "declarativeNetRequestWithHostAccess": BrowserText.localized("Block or redirect requests on allowed sites"),
            "declarativeNetRequestFeedback": BrowserText.localized("Read which network rules were applied"),
            "webRequest": BrowserText.localized("Observe network requests on allowed sites"),
            "webRequestBlocking": BrowserText.localized("Block network requests on allowed sites"),
            "bookmarks": BrowserText.localized("Read and change your bookmarks"),
            "history": BrowserText.localized("Read and change your browsing history"),
            "downloads": BrowserText.localized("Manage downloaded files"),
            "notifications": BrowserText.localized("Show notifications"),
            "clipboardRead": BrowserText.localized("Read your clipboard"),
            "clipboardWrite": BrowserText.localized("Write to your clipboard"),
            "nativeMessaging": BrowserText.localized("Communicate with a desktop app you allow"),
            "sidePanel": BrowserText.localized("Show a side panel"),
            "contextMenus": BrowserText.localized("Add items to page menus"),
            "menus": BrowserText.localized("Add items to page menus"),
            "alarms": BrowserText.localized("Schedule background tasks"),
            "offscreen": BrowserText.localized("Run an extension page in the background"),
            "cookies": BrowserText.localized("Cookie access is blocked by eGlu"),
            "identity": BrowserText.localized("Request sign-in for the extension"),
            "tabCapture": BrowserText.localized("Capture a tab after you allow it"),
            "desktopCapture": BrowserText.localized("Request screen sharing"),
            "management": BrowserText.localized("Read or manage installed extensions"),
            "privacy": BrowserText.localized("Request changes to browser privacy settings"),
            "webNavigation": BrowserText.localized("See which pages you go to"),
            "idle": BrowserText.localized("Know when this Mac is idle"),
            "tabGroups": BrowserText.localized("Read and change your tab groups"),
            "browsingData": BrowserText.localized("Clear your browsing data"),
            "topSites": BrowserText.localized("Read the sites you visit most"),
            "sessions": BrowserText.localized("Read your recently closed tabs"),
            "search": BrowserText.localized("Search with your search engine"),
            "geolocation": BrowserText.localized("Use your location after you allow it"),
            "power": BrowserText.localized("Keep this Mac awake"),
            "system.cpu": BrowserText.localized("Read this Mac's processor details"),
            "system.memory": BrowserText.localized("Read this Mac's memory details"),
            "system.display": BrowserText.localized("Read this Mac's display details"),
            "system.storage": BrowserText.localized("Read this Mac's storage details"),
            "fontSettings": BrowserText.localized("Read and change font settings"),
            "proxy": BrowserText.localized("Change the browser's proxy settings"),
            "contentSettings": BrowserText.localized("Change site settings such as pop-ups and cookies"),
            "pageCapture": BrowserText.localized("Save pages as files"),
            "tts": BrowserText.localized("Speak text aloud"),
            "ttsEngine": BrowserText.localized("Provide a voice for speaking text"),
            "declarativeContent": BrowserText.localized("Show its button on certain pages"),
            "gcm": BrowserText.localized("Receive messages from its server"),
            "readingList": BrowserText.localized("Read and change your reading list"),
            "favicon": BrowserText.localized("Read the icons of sites"),
            "userScripts": BrowserText.localized("Run user scripts on sites you allow"),
            "debugger": BrowserText.localized("Inspect and control pages, as developer tools do"),
        ]
        return descriptions[permission] ?? String(format: BrowserText.localized("Request an additional capability (%@)"), permission)
    }

    public static func site(_ pattern: String) -> String {
        if ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"].contains(pattern) {
            if pattern.hasPrefix("https:") { return BrowserText.localized("All HTTPS websites") }
            if pattern.hasPrefix("http:") { return BrowserText.localized("All HTTP websites") }
            return BrowserText.localized("All websites")
        }
        if pattern.hasPrefix("file:") { return BrowserText.localized("Local files you open") }
        guard let scheme = pattern.range(of: "://") else { return pattern }
        let rest = pattern[scheme.upperBound...]
        let host = String(rest.prefix { $0 != "/" })
        let path = String(rest.dropFirst(host.count))
        let domain = host.hasPrefix("*.") ? String(format: BrowserText.localized("%@ and its subdomains"), String(host.dropFirst(2))) : host
        let matching = path.isEmpty || path == "/*" ? nil : path
        if pattern.hasPrefix("https:") {
            return matching.map { String(format: BrowserText.localized("%1$@, pages matching %2$@ over HTTPS"), domain, $0) }
                ?? String(format: BrowserText.localized("%@ over HTTPS"), domain)
        }
        if pattern.hasPrefix("http:") {
            return matching.map { String(format: BrowserText.localized("%1$@, pages matching %2$@ over HTTP"), domain, $0) }
                ?? String(format: BrowserText.localized("%@ over HTTP"), domain)
        }
        return matching.map { String(format: BrowserText.localized("%1$@, pages matching %2$@"), domain, $0) } ?? domain
    }

    public static func lines(for grants: [String]) -> [String] {
        Array(Set(grants.map { $0.hasPrefix("site:") ? site(String($0.dropFirst(5))) : capability($0) })).sorted()
    }
}

/// A zero update count is meaningful only alongside every extension's outcome.
public struct ExtensionUpdateReport: Sendable {
    public enum Status: Sendable { case completed, busy, disabled, notDue, empty }
    public enum Outcome: String, Sendable { case current, updated, failed, declined, deferred }
    public struct Entry: Sendable {
        public let id: String
        public let name: String
        public let outcome: Outcome
        public let detail: String?
        public init(id: String, name: String, outcome: Outcome, detail: String? = nil) {
            self.id = id; self.name = name; self.outcome = outcome; self.detail = detail
        }
    }
    public var status: Status
    public var entries: [Entry]
    public init(status: Status = .completed, entries: [Entry] = []) { self.status = status; self.entries = entries }
    public var fullyChecked: Bool { status == .completed && !entries.isEmpty && entries.allSatisfy { [.current, .updated].contains($0.outcome) } }
    public var summary: String {
        switch status {
        case .busy: return BrowserText.localized("An update check is already running.")
        case .disabled: return BrowserText.localized("Automatic update checks are off.")
        case .notDue: return BrowserText.localized("The next automatic check is not due yet.")
        case .empty: return BrowserText.localized("No Chrome Web Store extensions to check.")
        case .completed: break
        }
        guard !entries.isEmpty else { return BrowserText.localized("The store did not return an update result. Try again.") }
        let updated = entries.filter { $0.outcome == .updated }.count
        if fullyChecked {
            if updated == 0 { return BrowserText.localized("All checked extensions are up to date.") }
            return updated == 1 ? String(format: BrowserText.localized("Updated %lld extension."), updated)
                                : String(format: BrowserText.localized("Updated %lld extensions."), updated)
        }
        let counts = [Outcome.updated, .current, .failed, .declined, .deferred].compactMap { outcome -> String? in
            let count = entries.filter { $0.outcome == outcome }.count
            guard count > 0 else { return nil }
            switch outcome {
            case .updated: return String(format: BrowserText.localized("%lld updated"), count)
            case .current: return String(format: BrowserText.localized("%lld current"), count)
            case .failed: return String(format: BrowserText.localized("%lld failed"), count)
            case .declined: return String(format: BrowserText.localized("%lld declined"), count)
            case .deferred: return String(format: BrowserText.localized("%lld deferred"), count)
            }
        }
        return String(format: BrowserText.localized("%@. Check Again retries failures and declined versions."), counts.joined(separator: ", "))
    }
}
