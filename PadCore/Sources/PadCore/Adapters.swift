import Foundation

/// How the page hears about two fingers moving on the trackpad.
///
/// WebKit's own scrolling is off (see `Scrolling`), and with it off WebKit
/// may stop sending the page wheel events at all. The bridge sends them
/// itself, built from the trackpad's pan, the way a Mac's WebKit would.
public enum WheelMode: String, Codable, CaseIterable, Sendable {
    /// Never: the page gets only what WebKit sends.
    case off
    /// Sent unless the page is already getting WebKit's own wheel events,
    /// checked event by event in the page (bridge.js), so the two never add up.
    case auto
    /// Always sent, even alongside WebKit's own.
    case always
}

/// Keys the system can take for itself on iPad, moving focus between
/// controls or the text cursor, before the page sees them.
public enum RelayKey: String, Codable, CaseIterable, Sendable {
    case tab
    case arrows
}

/// Which of the bridges between the iPad's input and the page are on.
public struct Bridges: Equatable, Codable, Sendable {
    /// A trackpad pinch becomes a wheel event with ctrlKey, what Chrome and
    /// Firefox send for a pinch on a Mac and what Figma zooms on.
    public var pinch: Bool
    /// ⌘ held while scrolling with two fingers zooms the same way.
    public var commandZoom: Bool
    public var wheel: WheelMode
    /// Taken from the system with priority and handed to the page. Tab is
    /// on everywhere: on iPadOS 26 the system's focus system keeps Tab from
    /// the page, so it moves no focus in a form (Apple's forums, thread
    /// 806077), and the page script moves it instead. The arrows stay the
    /// system's unless a site needs them.
    public var keys: Set<RelayKey>
    /// The wheel delta for a pinch, per unit of the natural log of the scale
    /// step. 100 is Chrome's: a pinch to twice the size sends -69.3 in all.
    public var pinchFactor: Double
    /// The page's own cursor images shown in place of the system pointer,
    /// which WebKit on iPad shows whatever the page asks (PageCursor).
    public var cursors: Bool

    public init(pinch: Bool = true, commandZoom: Bool = true, wheel: WheelMode = .auto,
                keys: Set<RelayKey> = [.tab], pinchFactor: Double = 100, cursors: Bool = true) {
        self.pinch = pinch
        self.commandZoom = commandZoom
        self.wheel = wheel
        self.keys = keys
        self.pinchFactor = pinchFactor
        self.cursors = cursors
    }

    public static let standard = Bridges()
}

/// What one site needs that others don't: a stylesheet, a script, a user
/// agent, its own choice of bridges, and which of its pages are heavy.
public struct SiteAdapter: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// The site's domains; each covers its subdomains too.
    public let domains: [String]
    /// A whole user agent in place of Mac Safari's, or nil to keep Safari's.
    public let userAgent: String?
    /// Added to every page of the site after the app's own stylesheet.
    public let css: String
    /// Runs at document start in the app's own world, beside bridge.js:
    /// sees the page's DOM, not its variables.
    public let script: String
    /// Runs at document start in the page's own world, for what has to
    /// change the page's view of the browser. Empty when nothing has to.
    public let pageScript: String
    public let bridges: Bridges
    /// Path prefixes of the pages that cost the most memory, a design file
    /// rather than the file browser. A heavy tab is one of these.
    public let heavyPaths: [String]
    /// Run when Handoff reads a page of the site, in the app's own world,
    /// after the reader that every page gets (markdown.js): what the site
    /// keeps where that reader's walk does not come to it. One function,
    /// as markdown.js is, that answers as Transcript.answer reads. Empty
    /// for a site that needs none. Never put into a page: called once,
    /// when Handoff is asked for (Page.transcript).
    public let reader: String
    /// The paths of the site's pages that are each one job's posting, as
    /// regular expressions over the whole path: Handoff hands such a page
    /// off as a job posting whatever it declares (Handoff.kind). Empty
    /// for a site that has none.
    public let postings: [String]

    public init(id: String, name: String, domains: [String], userAgent: String? = nil,
                css: String = "", script: String = "", pageScript: String = "",
                bridges: Bridges = .standard, heavyPaths: [String] = [], reader: String = "", postings: [String] = []) {
        self.id = id
        self.name = name
        self.domains = domains.map { $0.lowercased() }
        self.userAgent = userAgent
        self.css = css
        self.script = script
        self.pageScript = pageScript
        self.bridges = bridges
        self.heavyPaths = heavyPaths
        self.reader = reader
        self.postings = postings
    }

    public func covers(_ url: URL?) -> Bool {
        guard let host = Hosts.host(of: url) else { return false }
        return domains.contains { Hosts.host(host, isWithin: $0) }
    }

    /// Another of the site's pages that has what `reader` looks for, where
    /// the page at `url` has not: read out of sight in its place
    /// (Page.transcript). Nil for a site with no such page.
    public func readerPage(for url: URL?) -> URL? {
        guard covers(url), !reader.isEmpty else { return nil }
        return id == Adapters.youtube.id ? YouTube.desktopPage(for: url) : nil
    }

    /// Whether the page at `url` is one job's posting, by its address (postings).
    public func isPosting(_ url: URL?) -> Bool {
        guard covers(url), !postings.isEmpty, let path = url?.path(percentEncoded: false) else { return false }
        return postings.contains { path.range(of: $0, options: .regularExpression) != nil }
    }

    public func isHeavy(_ url: URL?) -> Bool {
        guard covers(url), let path = url?.path(), !heavyPaths.isEmpty else { return false }
        return heavyPaths.contains { path.hasPrefix($0) }
    }
}

public enum Adapters {
    /// Figma, FigJam, Slides, Make and Sites, all on figma.com.
    ///
    /// Its page script hides the touch screen from the page. A Mac user agent
    /// with five touch points is how sites tell an iPad asking for desktop
    /// pages from a Mac, and a site that tells them apart can switch to touch
    /// handling the bridges don't feed. With no touch points the page gets the
    /// Mac it was told it is. Fingers on the glass still work: WebKit sends
    /// their pointer and mouse events either way.
    ///
    /// Its pinch factor is twice Chrome's because Figma, told it is in
    /// Safari, zooms by e^(-deltaY/200) for each ctrl+wheel event (measured
    /// with Validation/figma-ctrl-wheel.js). At Chrome's 100, a pinch to
    /// twice the size zoomed the canvas only 1.41 times.
    public static let figma = SiteAdapter(
        id: "figma",
        name: "Figma",
        domains: ["figma.com"],
        pageScript: Snippets.noTouchPoints,
        bridges: Bridges(pinch: true, commandZoom: true, wheel: .auto, keys: [.tab], pinchFactor: 200),
        heavyPaths: ["/design/", "/file/", "/board/", "/proto/", "/slides/", "/deck/", "/make/", "/site/", "/buzz/"]
    )

    /// YouTube, for Handoff alone: every bridge as on any other site, and
    /// nothing put into its pages. What it needs is its transcript, which
    /// the site shows in a panel of its own once "Show transcript" is
    /// pressed, and nowhere in the page before that.
    ///
    /// Its reader (youtube.js) presses the site's own button, keeps the
    /// panel see-through and untouchable for the second it is open, reads
    /// its lines and closes it, so the page looks as it did. That is the site as a
    /// computer is served it, which is what an iPad gets. The site as a
    /// phone is served it has no transcript anywhere: there the app loads
    /// the video's page as a computer gets it, out of sight, reads the
    /// transcript from that and lets it go (YouTube.desktopPage,
    /// Page.transcript). The site's captions and its service are not
    /// asked directly: they answer only the site's own player.
    public static let youtube = SiteAdapter(
        id: "youtube",
        name: "YouTube",
        domains: ["youtube.com", "youtu.be"],
        reader: Scripts.youtube
    )

    /// Greenhouse, Ashby and Workday, the tools most companies hire with,
    /// for Handoff alone: every bridge as on any other site, and nothing
    /// put into their pages. A page of one of their job boards at the
    /// address of one job is that job's posting (SiteAdapter.postings),
    /// which Greenhouse's do not declare to search engines, and Ashby's
    /// and Workday's do once their scripts have run. Their boards' own
    /// pages, a company's list of jobs, are not.
    ///
    /// Greenhouse: job-boards.greenhouse.io/<company>/jobs/<number>, and
    /// boards.greenhouse.io as it was, in Europe under eu. Measured on two
    /// companies' postings in October 2026.
    public static let greenhouse = SiteAdapter(
        id: "greenhouse",
        name: "Greenhouse",
        // The boards alone: the company's own site, www.greenhouse.io, has paths of that shape that are not jobs.
        domains: ["job-boards.greenhouse.io", "boards.greenhouse.io", "job-boards.eu.greenhouse.io", "boards.eu.greenhouse.io"],
        postings: [#"^/[^/]+/jobs/[0-9]+/?$"#]
    )

    /// Ashby: jobs.ashbyhq.com/<company>/<the job's id>, and its form to apply with under it.
    public static let ashby = SiteAdapter(
        id: "ashby",
        name: "Ashby",
        domains: ["jobs.ashbyhq.com"],
        postings: [#"^/[^/]+/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(/application)?/?$"#]
    )

    /// Workday: <company>.wd<n>.myworkdayjobs.com/<language>/<site>/job/<place>/<title>_<requisition>,
    /// the place left out by some; myworkdaysite.com is the same boards' other address.
    public static let workday = SiteAdapter(
        id: "workday",
        name: "Workday",
        domains: ["myworkdayjobs.com", "myworkdaysite.com"],
        postings: [#"/job/(?:[^/]+/)?[^/]+_[A-Za-z0-9-]+/?$"#]
    )

    /// Every site no adapter covers: every bridge on, nothing added.
    public static let standard = SiteAdapter(id: "standard", name: "Every other site", domains: [])

    /// Asked in this order, the first that covers a page wins. Figma first.
    public static let all: [SiteAdapter] = [figma, youtube, greenhouse, ashby, workday]

    public static func adapter(for url: URL?) -> SiteAdapter {
        all.first { $0.covers(url) } ?? standard
    }
}

/// Scripts more than one adapter can use.
public enum Snippets {
    /// `navigator.maxTouchPoints` as a Mac has it, for the page's own world.
    public static let noTouchPoints = """
    (() => {
      try {
        Object.defineProperty(Navigator.prototype, 'maxTouchPoints', {
          configurable: true, enumerable: true, get() { return 0; }
        });
      } catch (_) {}
    })();
    """
}

/// Where YouTube keeps a video, and which of its pages has the video's transcript.
public enum YouTube {
    /// The video a page of the site is of: the one being watched, a short
    /// or a live one, on the site as a computer or a phone is served it,
    /// or by its short address. Nil for every other page of the site (its
    /// front page, a channel, its music and studio sites) and every other site.
    public static func video(at url: URL?) -> String? {
        guard let url, let host = Hosts.host(of: url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = parts.path.split(separator: "/").map(String.init)
        var found: String?
        if host == "youtu.be" {
            found = path.first
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) {
            if path == ["watch"] {
                found = parts.queryItems?.first { $0.name == "v" }?.value
            } else if path.count == 2, ["shorts", "live"].contains(path[0]) {
                found = path[1]
            }
        }
        // As the site writes one: letters, digits, "-" and "_", eleven of them today.
        guard let found, (6...20).contains(found.count),
              found.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return found
    }

    /// The video's page as a computer is served it, which is the one with
    /// a transcript in it. With nothing of the address it was reached by:
    /// not the place in the video, not a playlist, and no word to the site
    /// to keep serving this device the computer's pages.
    public static func desktopPage(for url: URL?) -> URL? {
        video(at: url).flatMap { URL(string: "https://www.youtube.com/watch?v=" + $0) }
    }
}
