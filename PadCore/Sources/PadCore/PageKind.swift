import Foundation

/// What kind of page is handed off (Handoff.swift), which decides what of
/// it is its substance (HandoffCompose.swift): a piece of writing goes
/// whole, a page that presents something goes as what it presents, a tool
/// as what it shows, a list as its items, a thread as its replies, a job
/// posting as the whole posting with its terms.
public enum PageKind: String, Sendable, CaseIterable {
    /// One piece of writing to read: news, a post, an essay, an entry, documentation.
    case article
    /// A page that presents a product, a service, a company or an event to its visitors.
    case landing
    /// A tool in use: a board, an editor, an inbox, a dashboard.
    case app
    /// None of these, or not known: handed off as it is.
    case other
    /// One thing for sale: its description, what it costs, what buyers say.
    case product
    /// A question or a post and the replies to it.
    case thread
    /// Many things, each a link with a few words: search results, a feed, an index.
    case listing
    /// A video or a recording, and what the page says around it.
    case media
    /// One job on offer: the role, who offers it, what it asks for and what it gives.
    case job
    /// A document read from a file: Word, OpenDocument text, RTF, EPUB, PDF or plain text.
    case document
    /// A presentation's slides, with the speaker's notes.
    case slides
    /// A spreadsheet: each sheet of a workbook, or a CSV file's one.
    case spreadsheet
    /// Structured data: JSON or XML.
    case data
    /// A ZIP archive: each file in it eGlu reads, and a list of the rest.
    case archive
    /// A picture: the text in it, its own facts, and what it shows where
    /// the on-device model looks at pictures.
    case picture
    /// A recording: what it is called, how long it runs, and a transcript
    /// made on the device where speech can read it.
    case recording

    /// As the file handed off names it.
    public var name: String {
        switch self {
        case .article: return "article"
        case .landing: return "landing page"
        case .app: return "web app"
        case .other: return "page"
        case .product: return "product page"
        case .thread: return "discussion"
        case .listing: return "list of links"
        case .media: return "video or audio page"
        case .job: return "job posting"
        case .document: return "document"
        case .slides: return "presentation"
        case .spreadsheet: return "spreadsheet"
        case .data: return "data file"
        case .archive: return "archive"
        case .picture: return "picture"
        case .recording: return "recording"
        }
    }

    /// Whether it is a file's kind, told by its format (FileFormat.kind)
    /// and never counted on a page: what the file says of it is a file's.
    public var ofFile: Bool {
        switch self {
        case .document, .slides, .spreadsheet, .data, .archive, .picture, .recording: return true
        case .article, .landing, .app, .other, .product, .thread, .listing, .media, .job: return false
        }
    }
}

/// What the page's reader counted on its way through the page and what the
/// page's head says of it (markdown.js), from which its kind is told.
public struct PageFacts: Equatable, Sendable {
    /// The page's own description of itself, for search engines and links
    /// shared: up to 600 characters of it, of which the file shows 300.
    public var description = ""
    /// What the page is called where it is shared (og:title): its own
    /// title, where the one a browser shows was translated for the reader
    /// or has the site's name on it.
    public var titled = ""
    /// What the page says it is to sites it is shared on (og:type).
    public var type = ""
    /// The site's or the app's name, where the page gives one.
    public var site = ""
    /// What the page says it is to search engines (schema.org's names).
    public var schema: [String] = []
    /// The first headings.
    public var headings: [String] = []
    /// How much text was read.
    public var characters = 0
    /// Blocks of 200 characters or more: writing to be read, not labels.
    /// How many, and how much text is in them.
    public var long = 0
    public var written = 0
    /// Links in the text, and the characters inside them.
    public var links = 0
    public var linked = 0
    /// Things to press and things to fill in, over the whole page.
    public var controls = 0
    public var fields = 0
    /// Surfaces the page draws on itself.
    public var drawn = 0
    /// Whether the page says which part of it is its content.
    public var marked = false
    /// Large pictures with no description, how tall they are together in
    /// points, and how tall the window was: what the file cannot hold.
    public var unnamed = 0
    public var unnamedTall = 0
    public var tall = 0
    /// What the reader was never in, by how many characters each says.
    public var left = Left()
    /// How much of the window the page draws on itself, in hundredths: a
    /// document or a sheet in an editor has its words drawn, and none to read.
    public var canvas = 0
    /// The page said it was still loading when it was read.
    public var busy = false
    /// The page had a sheet over it and all the rest marked as hidden from
    /// assistive technology: read all the same.
    public var covered = false
    /// The headings the reader never came to, on a page longer than what is read.
    public var unread: [String] = []

    /// The parts of a page its reader leaves out for being the site's and
    /// not the page's, each by how much it says.
    public struct Left: Equatable, Sendable {
        /// The site's foot, with whatever menus are in it.
        public var foot = 0
        public var top = 0
        public var menus = 0
        /// What stands beside the content (an aside).
        public var beside = 0

        public init(foot: Int = 0, top: Int = 0, menus: Int = 0, beside: Int = 0) {
            self.foot = foot
            self.top = top
            self.menus = menus
            self.beside = beside
        }

        public var all: Int {
            foot + top + menus + beside
        }
    }

    public init() {}

    /// From what the script gave back. No count is under nothing or over
    /// ten million, which is a hundred times what the script reads: the
    /// rules that tell a page's kind multiply them.
    public init(_ said: [String: Any]) {
        func counted(_ key: String) -> Int {
            min(10_000_000, max(0, said[key] as? Int ?? 0))
        }
        description = said["description"] as? String ?? ""
        titled = said["titled"] as? String ?? ""
        type = said["type"] as? String ?? ""
        site = said["site"] as? String ?? ""
        schema = said["schema"] as? [String] ?? []
        headings = said["headings"] as? [String] ?? []
        characters = counted("characters")
        long = counted("long")
        written = counted("written")
        links = counted("links")
        linked = counted("linked")
        controls = counted("controls")
        fields = counted("fields")
        drawn = counted("drawn")
        marked = said["marked"] as? Bool ?? false
        unnamed = counted("unnamed")
        unnamedTall = counted("unnamedTall")
        tall = counted("tall")
        let out = said["left"] as? [String: Any] ?? [:]
        func leftOut(_ key: String) -> Int {
            min(10_000_000, max(0, out[key] as? Int ?? 0))
        }
        left = Left(foot: leftOut("foot"), top: leftOut("top"), menus: leftOut("menus"), beside: leftOut("beside"))
        canvas = min(100, counted("canvas"))
        busy = said["busy"] as? Bool ?? false
        covered = said["covered"] as? Bool ?? false
        unread = (said["unread"] as? [Any] ?? []).prefix(30).compactMap { ($0 as? String).map { String($0.prefix(80)) } }
    }

    /// How much of the text is inside links: most of a list of links, little of writing.
    public var linkShare: Double {
        characters > 0 ? Double(linked) / Double(characters) : 0
    }
}

/// What a page's blocks come to, for the kinds told by how a page is built
/// and not by how much it writes: counted once from a reading.
public struct PageShape: Equatable, Sendable {
    /// Repeated siblings that read as the items of a list: small, most
    /// with a link. And the characters in them.
    public var items = 0
    public var listed = 0
    /// Characters of writing on the page (PageBlock.isProse), and of
    /// them those in parts the page calls comments.
    public var written = 0
    public var replies = 0
    /// All the characters in parts the page calls comments, long and short.
    public var discussed = 0
    /// Things the page declares as products, and as jobs on offer.
    public var products = 0
    public var jobs = 0

    public init(items: Int = 0, listed: Int = 0, written: Int = 0, replies: Int = 0, discussed: Int = 0, products: Int = 0,
                jobs: Int = 0) {
        self.items = items
        self.listed = listed
        self.written = written
        self.replies = replies
        self.discussed = discussed
        self.products = products
        self.jobs = jobs
    }

    public init(_ reading: PageReading) {
        let hints = Handoff.hints(in: reading)
        let lists = Handoff.lists(in: reading)
        var seen = Set<Int>()
        for (index, block) in reading.blocks.enumerated() {
            if let group = block.group, lists.contains(group), let item = block.item {
                if seen.insert(item).inserted { items += 1 }
                listed += block.characters
            }
            if block.isProse { written += block.characters }
            if hints[index] == .comments {
                discussed += block.characters
                if block.isProse { replies += block.characters }
            }
        }
        // The one the page says is its own, where it says: a shop's page for one thing names others beside it.
        let sold = reading.things.filter { $0.isA(["product"]) }
        products = sold.contains(where: \.main) ? sold.filter(\.main).count : sold.count
        let offered = reading.things.filter { $0.isA(Handoff.types(of: .job)) }
        jobs = offered.contains(where: \.main) ? offered.filter(\.main).count : offered.count
        // A page that says its own thing is something else (an article with a job beside it) is that.
        let own = reading.things.filter(\.main)
        if !own.isEmpty, !own.contains(where: { $0.isA(Handoff.types(of: .job)) }) { jobs = 0 }
    }
}

/// What the on-device model made of the page (PageMind.read): its kind, a
/// sentence or two saying what it is, and, where it was asked, which of
/// the parts that would only be started say the most (Handoff.candidates).
public struct PageAnswer: Equatable, Sendable {
    /// A part the model picked from the list it was given: the heading's
    /// words as it copied them out, and the line's number. Both, since a
    /// small model's number alone is often a line off, and its copy of the
    /// words says which line it meant (Handoff.promoted).
    public struct Pick: Equatable, Sendable {
        public var number: Int
        public var name: String

        public init(number: Int, name: String) {
            self.number = number
            self.name = name
        }
    }

    public var kind: PageKind
    public var about: String
    public var picks: [Pick]

    public init(kind: PageKind, about: String, picks: [Pick] = []) {
        self.kind = kind
        self.about = about
        self.picks = picks
    }
}

extension Handoff {
    // MARK: The kind, from what was counted

    private static let articleTypes: Set<String> = [
        "article", "newsarticle", "blogposting", "techarticle", "scholarlyarticle", "report", "liveblogposting",
        "opinionnewsarticle", "analysisnewsarticle", "reportagenewsarticle", "reviewnewsarticle", "socialmediaposting",
    ]
    private static let threadTypes: Set<String> = ["qapage", "discussionforumposting"]
    private static let mediaTypes: Set<String> = ["videoobject", "audioobject", "podcastepisode", "movie", "tvepisode"]
    private static let listingTypes: Set<String> = ["searchresultspage", "collectionpage", "itemlist"]
    private static let jobTypes: Set<String> = ["jobposting"]

    /// The kinds of thing a page of each kind declares itself to be, which
    /// is how the thing the page is about is told from the others it names
    /// (Handoff.declared).
    static func types(of kind: PageKind) -> Set<String> {
        switch kind {
        case .article: return articleTypes
        case .product: return ["product"]
        case .thread: return threadTypes.union(["question"])
        case .media: return mediaTypes
        case .job: return jobTypes
        case .landing, .app: return ["softwareapplication", "webapplication", "mobileapplication"]
        case .listing, .other, .document, .slides, .spreadsheet, .data, .archive, .picture, .recording: return []
        }
    }

    /// Whether the page says itself that it is a piece of writing, and has some.
    private static func saysArticle(_ facts: PageFacts) -> Bool {
        let schema = Set(facts.schema.map { $0.lowercased() })
        return (facts.type.lowercased() == "article" || !schema.isDisjoint(with: articleTypes)) && facts.long >= 2
    }

    /// The page's kind by counting, with no model: what is used where
    /// there is none, and what the model's answer is held against. One of
    /// the four kinds that are told by how much a page writes.
    ///
    /// Writing is told by how much of the text is in paragraphs: nearly
    /// half or more of an article's, a third at the most of a page that
    /// presents something, whose text is headings and a line or two under
    /// each. A tool is told by having next to nothing to read and things
    /// to press. A page that presents something has headings, few links
    /// for its length, and stands at the top of its site or one step down.
    /// What fits none is left as it is, which loses nothing: such a page
    /// goes whole. The numbers are from 35 pages measured in October 2026
    /// (HandoffTests has them).
    public static func kind(of facts: PageFacts, url: URL) -> PageKind {
        if saysArticle(facts) { return .article }
        let share = facts.characters > 0 ? Double(facts.written) / Double(facts.characters) : 0
        let sold = facts.type.lowercased() == "product" || facts.schema.contains { $0.lowercased() == "product" }
        let depth = url.pathComponents.filter { $0 != "/" }.count
        // A site's front page with writing on it is a paper's or a blog's, many pieces begun: more is asked of it.
        let enough = depth == 0 ? 0.6 : 0.4
        if !sold, facts.written >= 1_500, share >= enough, facts.long >= 3 || facts.written >= 5_000, facts.linkShare < 0.4 {
            return .article
        }

        let pressed = facts.controls + facts.fields
        if facts.characters < 1_000, pressed >= 6 { return .app }
        if facts.long == 0, pressed >= 40, facts.headings.count <= 3, depth >= 1 { return .app }

        if presents(facts), depth <= 1 { return .landing }
        return .other
    }

    /// The page's kind by counting, of all nine: first the kinds a page
    /// declares itself or shows by how it is built (a job posting, a
    /// thread, a product, a recording, a list), then the four told by how
    /// much it writes.
    ///
    /// A declaration is trusted where search engines hold a page to it
    /// (schema.org's types). Few threads and lists declare themselves, so
    /// both are also told by counting: a thread by where its writing or
    /// most of its text is (in what the page calls comments), a list by
    /// most of the page being repeated small things with a link each.
    /// The numbers are from 31 pages measured in October 2026. Held
    /// against 15 more, they told lists and recordings and not
    /// discussions, so not all four kinds are in use (Handoff.builtKindsInUse).
    public static func kind(of facts: PageFacts, shape: PageShape, url: URL) -> PageKind {
        // One job on offer, as the page declares it: job boards and the tools companies hire with
        // declare each posting to search engines, which list it as a job by that and hold the page
        // to it. Before writing, which a posting has a lot of and some sites call an article. A
        // board's search declares many, and is a list or nothing.
        if shape.jobs == 1 { return .job }
        if saysArticle(facts) { return .article }
        let schema = Set(facts.schema.map { $0.lowercased() })
        let type = facts.type.lowercased()
        if !schema.isDisjoint(with: threadTypes) { return .thread }
        // One thing for sale. A shelf of them declares many, and is a list or nothing.
        if schema.contains("product") || type == "product" || type == "og:product", shape.products <= 1 { return .product }
        if !schema.isDisjoint(with: mediaTypes) || type.hasPrefix("video") || type.hasPrefix("music"), facts.written < 3_000 {
            return .media
        }
        // A page that declares several jobs is a board's list of them, as one that declares a collection is.
        if !schema.isDisjoint(with: listingTypes) || shape.jobs >= 2, shape.items >= 5 { return .listing }

        // A thread: most of the writing is replies, or most of the text is what the page calls
        // comments (replies of a line or two each), and little of its writing is anything else.
        let replied = shape.replies >= 600 && shape.replies * 10 > shape.written * 4
        let discussed = shape.discussed >= 600 && shape.discussed * 10 > facts.characters * 4
        if replied || discussed, shape.written - shape.replies < 1_500 { return .thread }
        let told = kind(of: facts, url: url)
        if told == .article { return told }
        // A tool with next to nothing to read is a tool, whatever is listed in it.
        if told == .app, facts.characters < 1_000 { return told }
        // A list: ten things or more that are most of the page, on a page that is not writing.
        // One with a form of many fields over it (a search with its settings) is still a list.
        if shape.items >= 10, shape.listed * 2 >= facts.characters, facts.written * 10 < facts.characters * 4 { return .listing }
        return told
    }

    /// Which of the four kinds told by how a page is built are in use: a
    /// list and a recording. The rules were set on 31 pages and then held
    /// against 15 others. Every list among the 46 was told (six, two of
    /// them among the 15) and every recording (four, two among the 15),
    /// and no page was given either kind wrongly. A discussion and a
    /// product page are not in use. Discussions were not told on the 15:
    /// a question at Stack Overflow, whose own text is long, and a topic
    /// at Discourse, which calls nothing of itself comments, went as
    /// articles. No product page was among the 15 (the one asked for led
    /// to a category), so nothing says the rule for those holds.
    /// HandoffTests has the rows.
    ///
    /// A job posting is in use as well, told by nothing but its own
    /// declaration (schema.org's JobPosting), which is what search engines
    /// list a job by.
    public static let builtKindsInUse: Set<PageKind> = [.listing, .media, .job]

    /// Whether the model is also asked which of the parts that are only
    /// started say the most (Handoff.candidates). Not yet: it waits on the
    /// kinds above, and measured on 12 pages in October 2026 it named a
    /// part it had been given in 28 of 34 picks, picked three whatever the
    /// page, and took 5.8 seconds where the question without took 3.4.
    public static let asksForPicks = false

    /// The kind a page is handed off as, before the model is asked. A
    /// page a site's adapter knows by its address for one job's posting is
    /// one (SiteAdapter.postings), where it has a posting's worth of text:
    /// a posting that has closed is a line saying so, at the same address.
    public static func kind(of reading: PageReading, url: URL) -> PageKind {
        if Adapters.adapter(for: url).isPosting(url), reading.facts.characters >= postingText { return .job }
        return handedOff(as: kind(of: reading.facts, shape: PageShape(reading), url: url), facts: reading.facts, url: url)
    }

    /// How much text a job's posting has at the least, in characters. The ones measured had 3,800 to 14,000.
    static let postingText = 800

    /// The kind told by how a page is built, where that kind is in use.
    /// A page told as one that is not goes as one of the four told by
    /// how much it writes, which loses nothing: such pages go whole. It
    /// is not asked again whether it is a kind that is in use: a
    /// discussion's replies are repeated things with a link each, and it
    /// is no list.
    static func handedOff(as told: PageKind, facts: PageFacts, url: URL) -> PageKind {
        let built: Set<PageKind> = [.product, .thread, .listing, .media, .job]
        return built.contains(told) && !builtKindsInUse.contains(told) ? kind(of: facts, url: url) : told
    }

    /// Whether the page is built as one that presents something is:
    /// headings, and neither a list of links nor long enough to be one.
    private static func presents(_ facts: PageFacts) -> Bool {
        facts.headings.count >= 3 && facts.links < 60 && facts.linkShare < 0.4 && facts.characters < 30_000
    }

    /// The kind to go by, of the count's and the model's.
    ///
    /// The model keeps to four kinds: asked for more, a small model is
    /// right less often, and it called tools, search results and a forum
    /// pages that present something when measured (its answer goes by the
    /// page's description of itself). So a kind told by how the page is
    /// built stands whatever the model says, and so does an article. The
    /// model's word counts where the count had none, a page of no kind in
    /// particular, and only as far as what was counted bears it out.
    ///
    ///     counted                                   model      goes as
    ///     app, product, thread, listing, media, job anything   as counted
    ///     article                                   anything   article
    ///     landing                                   article    article with 800 characters of writing, else landing
    ///     landing                                   the rest   landing
    ///     other                                     article    article with 800 characters of writing and under half its text in links, else other
    ///     other                                     landing    landing if built as one and no more than two steps into its site, else other
    ///     other                                     app        app with 2 long paragraphs or fewer, else other
    public static func settled(counted: PageKind, answer: PageAnswer?, facts: PageFacts, url: URL? = nil) -> PageKind {
        guard let answer else { return counted }
        let depth = url.map { $0.pathComponents.filter { $0 != "/" }.count } ?? 0
        switch counted {
        // A file's kinds are told by its format, never asked of the model.
        case .app, .product, .thread, .listing, .media, .job, .article,
             .document, .slides, .spreadsheet, .data, .archive, .picture, .recording:
            return counted
        case .landing:
            return answer.kind == .article && facts.written >= 800 ? .article : .landing
        case .other:
            switch answer.kind {
            // Not a page most of whose text is links, however long each is: a news site's front page, which the model calls writing.
            case .article: return facts.written >= 800 && facts.linkShare < 0.5 ? .article : .other
            // Far down a site, what the model takes for a page that presents something is as often a case
            // study or a manual. Taken for a landing page it would be started, and as a page it goes whole.
            case .landing: return presents(facts) && depth <= 2 ? .landing : .other
            case .app: return facts.long <= 2 ? .app : .other
            default: return .other
            }
        }
    }

    // MARK: What the model is asked

    public static let kindInstructions = """
    You are shown facts about a web page: its address, its title, its own description, what was counted on it, its \
    sections with how each starts and, when there is one, a picture of it as it shows on a phone. Say what the page \
    is for, then which kind of page it is.

    In `about`, write two or three plain sentences. First what the page is and what it is for: what it sells, \
    announces, explains, argues or lets a visitor do. Then its main points, with the names, models, numbers, prices \
    and dates the page gives. Write in the language the page is written in. Use only what is given here. Do not add \
    what a page of this kind usually says, do not turn a name into another word, and do not guess what a film or a \
    picture shows. If there is too little here to say more than the page's title, say only what the title says.

    article: one piece of writing by one author or publisher, to be read from start to end: a news story, a blog \
    post, an essay, an encyclopedia entry, a page of documentation.
    landing: a page where a company or a project presents one product, service, app or event of its own to \
    visitors, and invites them to try it, buy it, download it or sign up.
    app: a tool the visitor is using on this page: an editor, a calculator, a converter, a translator, a dashboard, \
    an inbox, a board, a map. It has little text and many buttons or fields.
    other: anything else, above all a page that lists many separate things: search results, a feed, a forum, a news \
    site's front page, a shop's shelf, a list of issues or files, a video, a profile.

    Go by what the page says and shows. Do not guess at what is not there.
    """

    /// Added where the model is also asked which parts say the most (Handoff.candidates).
    public static let pickInstructions = """

    The numbered list at the end names parts of the page. Pick up to three of them that say the most about what \
    the page offers, such as what it costs or the questions it answers. Copy each one's name from the list and \
    give its number. Pick none if none stands out.
    """

    /// Asked for a picture handed off or a large one on a page that says
    /// nothing of itself (PageMind.describe).
    public static let pictureInstructions = """
    Describe what this picture shows in two or three plain sentences, for someone who can't see it. \
    Mention text only if it is large. Never say who a person is.
    """

    /// What the model reads: the page's own account of itself, what was
    /// counted, its sections with how each starts, and the start of its
    /// writing. Bounded, since the model reads 4,096 tokens at once, its
    /// instructions, a picture and its own answer among them:
    ///
    ///     the page's account of itself, and the counts    about 1,100 characters at the most
    ///     sections, the first two levels before the third 14, each a heading of 60 characters and 120 of what is under it
    ///     the start of the writing                        300 characters
    ///     the parts it may pick from                      12, each a name of 60 characters and 80 of how it starts
    ///
    /// The sections are what a summary of the whole page is made from: with
    /// the start of the text alone, the model said the first paragraph over
    /// again and left out what the page goes on to (measured in October
    /// 2026: a phone's page summarised without its larger model, its price
    /// or its battery, all of them under later headings).
    ///
    /// `shortened` is the same with less, for a prompt that was too long
    /// (text in Korean or Japanese is a token or two a character, where
    /// English is four characters a token): once, 8 sections with 60
    /// characters each, 200 of the writing, and the parts by name alone;
    /// twice, no sections, half the description, 150 of the writing, and
    /// 40 characters of each name. The parts keep their numbers throughout.
    ///
    /// A recording's transcript, where the page shows one, is not given
    /// apart: lines from six places through it were tried in October 2026
    /// on a talk and on a long video, and the summary was no better for
    /// them on the one and worse on the other, where the model gave its
    /// own instructions back. The transcript is in the file, for the
    /// assistant that reads the file.
    public static func brief(title: String, url: URL, reading: PageReading, candidates: [Candidate] = [], shortened: Int = 0) -> String {
        let facts = reading.facts
        let level = min(max(shortened, 0), 2)
        var lines: [String] = []
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Address: " + String(Tracking.clean(url).absoluteString.prefix(200)))
        if !name.isEmpty { lines.append("Title: " + String(name.prefix(150))) }
        let shared = oneLine(facts.titled, upTo: 150)
        if !shared.isEmpty, shared.lowercased() != name.lowercased() { lines.append("Its title where it is shared: " + shared) }
        if !facts.site.isEmpty { lines.append("Site: " + String(facts.site.prefix(80))) }
        if !facts.description.isEmpty { lines.append("Its own description: " + String(facts.description.prefix(level == 2 ? 150 : 300))) }
        let says = ([facts.type] + facts.schema).filter { !$0.isEmpty }
        if !says.isEmpty { lines.append("It says it is: " + says.prefix(6).map { String($0.prefix(40)) }.joined(separator: ", ")) }
        lines.append("Counted: \(facts.characters) characters of text, \(facts.long) long paragraphs, "
            + "\(facts.links) links, \(facts.controls) buttons, \(facts.fields) fields to fill in")
        if let language = language(of: reading) { lines.append("Its language: \(language). Write `about` in \(language).") }

        // On a page that presents or sells something, what it costs: the model leaves a price out
        // that stands in a line of its own between two headings, and it is the first thing asked.
        let prices = presents(facts) || [.landing, .product].contains(kind(of: reading, url: url)) ? prices(in: reading) : []
        if !prices.isEmpty { lines.append("The first prices it shows: " + prices.joined(separator: ", ")) }

        let sections = level == 2 ? [] : digest(of: reading, most: level == 1 ? 8 : 14, each: level == 1 ? 60 : 120)
        if !sections.isEmpty { lines.append("Its sections, each with how it starts:\n" + sections.joined(separator: "\n")) }

        // Its writing where it has some, else whatever it starts with. Not what is said in a recording:
        // a transcript's first minute is no account of the page, and the model made worse summaries with it.
        // Nor the notes its text points to, which stand at its end and are of no part of it.
        let said = hints(in: reading)
        let own = reading.blocks.indices.filter { said[$0] != .transcript && said[$0] != .footnotes }.map { reading.blocks[$0] }
        let prose = own.filter(\.isProse)
        let start = (prose.isEmpty ? own.filter { $0.kind != .heading && !$0.note } : prose).lazy.map { spoken($0) }
            .joined(separator: " ").split(whereSeparator: \.isNewline).joined(separator: " ").prefix([300, 200, 150][level])
        if !start.isEmpty { lines.append("Its text starts:\n" + start) }

        if !candidates.isEmpty {
            lines.append("Parts to pick from:\n" + candidates.prefix(12).enumerated().map { index, candidate in
                let line = "\(index + 1). " + candidate.name.prefix(level == 2 ? 40 : 60)
                return line + (candidate.start.isEmpty || level >= 1 ? "" : ": " + candidate.start.prefix(80))
            }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    /// The briefs to try, from the fullest to the shortest, without those
    /// that by their weight would not fit what the model reads at once
    /// (Handoff.weight): a page in Korean starts from a shorter one. The
    /// shortest always, since something is asked.
    public static func briefs(title: String, url: URL, reading: PageReading, candidates: [Candidate] = [], room: Int = 2_400) -> [String] {
        let all = (0...2).map { brief(title: title, url: url, reading: reading, candidates: candidates, shortened: $0) }
        let fitting = all.filter { weight(of: $0) <= room }
        return fitting.isEmpty ? Array(all.suffix(1)) : fitting
    }

    /// About how many of the model's tokens a text is: a quarter of a token
    /// a character in Latin letters and digits, a token and a half for a
    /// character of Korean, Japanese or Chinese. Near enough to choose a
    /// brief by where the system does not count (before iOS 26.4).
    public static func weight(of text: String) -> Int {
        var tokens = 0.0
        for scalar in text.unicodeScalars {
            tokens += scalar.value < 0x250 ? 0.27 : (scalar.value >= 0x1100 ? 1.5 : 0.6)
        }
        return Int(tokens.rounded(.up))
    }

    /// The language the model is told to answer in, where the page's script
    /// says which: a page in Hangul is in Korean, one with kana in Japanese.
    /// Told, because the model answers in English by habit, and put a
    /// humidifier's Korean name into English as an air purifier. For a
    /// page in Latin letters nothing is told: the script does not say
    /// which language, and the model follows the text.
    static func language(of reading: PageReading) -> String? {
        var hangul = 0, kana = 0, latin = 0
        var seen = 0
        for block in reading.blocks where !block.note {
            for scalar in spoken(block).unicodeScalars {
                switch scalar.value {
                case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
                case 0x3040...0x30FF: kana += 1
                case 0x41...0x5A, 0x61...0x7A: latin += 1
                default: break
                }
            }
            seen += block.characters
            if seen > 6_000 { break }
        }
        // A page of another language quotes Korean now and then: its own script is most of its letters.
        if hangul * 3 >= latin, hangul >= 40 { return "Korean" }
        if kana * 6 >= latin, kana >= 40 { return "Japanese" }
        return nil
    }

    /// The first amounts of money the page shows, as it writes them: a sign
    /// and a number (₩1,990,000, $19.99) or a number and a currency's name
    /// (499,000원), with the word that says it is where prices start ("from",
    /// "부터"). Two at the most, from the page's own parts and its first 150
    /// blocks: further down are other things' prices.
    ///
    /// A number before a currency's name is a price where it is written as
    /// one: three digits or more, or thousands parted by commas, or so many
    /// 만. "3원칙" is a word, and "499,000원입니다" has a price in it. A sign
    /// after another is no price's: "$$ 4.2" is how dear a restaurant is,
    /// and how it is rated.
    static func prices(in reading: PageReading, most: Int = 2) -> [String] {
        let hints = hints(in: reading)
        var found: [String] = []
        for (index, block) in reading.blocks.prefix(150).enumerated() where !block.note && (hints[index] == nil || hints[index] == .price) {
            let words = spoken(block)
            var from = words.startIndex
            while found.count < most, let match = words.range(of: Self.priced, options: .regularExpression, range: from..<words.endIndex) {
                let price = String(words[match])
                if !found.contains(price) { found.append(price) }
                from = match.upperBound
            }
            if found.count >= most { break }
        }
        return found
    }

    private static let priced = #"(?:(?i:from|starting at)\s)?(?:(?<![₩$€£¥])[₩$€£¥]\s?\d[\d,.]*\d|(?<![₩$€£¥])[₩$€£¥]\s?\d"#
        + #"|(?:\d{1,3}(?:,\d{3})+|\d{3,}|\d{1,4}(?:\.\d)?\s?만)\s?(?:원|円|엔)|\d[\d,.]*\s?(?:달러|유로))(?:\s?부터)?"#

    /// A block's words for the model: without Markdown where the reader
    /// gave them so, and without the addresses its links go to.
    static func spoken(_ block: PageBlock) -> String {
        if block.kind == .heading { return block.title }
        guard block.links > 0 || block.text.contains("](") else { return block.text }
        return block.text.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\]\([^)]*\)"#, with: "", options: .regularExpression)
    }

    /// The page's sections for the model: each heading with the start of
    /// what is under it, the first two levels in the order they come and
    /// then the third where there is room, so that a long page is seen
    /// whole before it is seen close. A section the page calls comments,
    /// related, legal or its foot is not one of them, and a transcript is
    /// named and not started.
    static func digest(of reading: PageReading, most: Int, each: Int) -> [String] {
        let hints = hints(in: reading)
        let aside: Set<PageHint> = [.comments, .related, .legal, .footer, .footnotes, .share, .newsletter, .contents]
        var found: [(index: Int, level: Int, title: String, under: String)] = []
        var open: Int?
        for (index, block) in reading.blocks.enumerated() {
            if block.kind == .heading {
                open = nil
                let title = block.title
                guard !title.isEmpty, block.level <= 3, !(hints[index].map(aside.contains) ?? false) else { continue }
                found.append((index, block.level, String(title.prefix(60)), ""))
                open = found.count - 1
            } else if let at = open, !block.note, found[at].under.count < each, block.kind != .code, block.kind != .rule,
                      hints[index] != .transcript, hints[index] != .footnotes {
                let words = spoken(block).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                // A picture's description is of the picture, and long: what the section says comes first.
                guard !words.isEmpty, !block.text.hasPrefix("![") else { continue }
                found[at].under += (found[at].under.isEmpty ? "" : " ") + words
            }
        }
        var kept = found.filter { $0.level <= 2 }.prefix(most).map { $0 }
        if kept.count < most { kept += found.filter { $0.level == 3 }.prefix(most - kept.count) }
        return kept.sorted { $0.index < $1.index }.map { section in
            "- " + section.title + (section.under.isEmpty ? "" : ": " + cut(section.under, to: each))
        }
    }
}
