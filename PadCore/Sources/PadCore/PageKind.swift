import Foundation

/// What kind of page is handed off (Handoff.swift), which decides what of
/// it is its substance (HandoffCompose.swift): a piece of writing goes
/// whole, a page that presents something goes as what it presents, a tool
/// as what it shows, a list as its items, a thread as its replies.
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
        }
    }
}

/// What the page's reader counted on its way through the page and what the
/// page's head says of it (markdown.js), from which its kind is told.
public struct PageFacts: Equatable, Sendable {
    /// The page's own description of itself, for search engines and links shared.
    public var description = ""
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

    public init() {}

    /// From what the script gave back. No count is under nothing or over
    /// ten million, which is a hundred times what the script reads: the
    /// rules that tell a page's kind multiply them.
    public init(_ said: [String: Any]) {
        func counted(_ key: String) -> Int {
            min(10_000_000, max(0, said[key] as? Int ?? 0))
        }
        description = said["description"] as? String ?? ""
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
    /// Things the page declares as products.
    public var products = 0

    public init(items: Int = 0, listed: Int = 0, written: Int = 0, replies: Int = 0, discussed: Int = 0, products: Int = 0) {
        self.items = items
        self.listed = listed
        self.written = written
        self.replies = replies
        self.discussed = discussed
        self.products = products
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

    /// The kinds of thing a page of each kind declares itself to be, which
    /// is how the thing the page is about is told from the others it names
    /// (Handoff.declared).
    static func types(of kind: PageKind) -> Set<String> {
        switch kind {
        case .article: return articleTypes
        case .product: return ["product"]
        case .thread: return threadTypes.union(["question"])
        case .media: return mediaTypes
        case .landing, .app: return ["softwareapplication", "webapplication", "mobileapplication"]
        case .listing, .other: return []
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

    /// The page's kind by counting, of all eight: first the kinds a page
    /// declares itself or shows by how it is built (a thread, a product, a
    /// recording, a list), then the four told by how much it writes.
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
        if saysArticle(facts) { return .article }
        let schema = Set(facts.schema.map { $0.lowercased() })
        let type = facts.type.lowercased()
        if !schema.isDisjoint(with: threadTypes) { return .thread }
        // One thing for sale. A shelf of them declares many, and is a list or nothing.
        if schema.contains("product") || type == "product" || type == "og:product", shape.products <= 1 { return .product }
        if !schema.isDisjoint(with: mediaTypes) || type.hasPrefix("video") || type.hasPrefix("music"), facts.written < 3_000 {
            return .media
        }
        if !schema.isDisjoint(with: listingTypes), shape.items >= 5 { return .listing }

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
    public static let builtKindsInUse: Set<PageKind> = [.listing, .media]

    /// Whether the model is also asked which of the parts that are only
    /// started say the most (Handoff.candidates). Not yet: it waits on the
    /// kinds above, and measured on 12 pages in October 2026 it named a
    /// part it had been given in 28 of 34 picks, picked three whatever the
    /// page, and took 5.8 seconds where the question without took 3.4.
    public static let asksForPicks = false

    /// The kind a page is handed off as, before the model is asked.
    public static func kind(of reading: PageReading, url: URL) -> PageKind {
        handedOff(as: kind(of: reading.facts, shape: PageShape(reading), url: url), facts: reading.facts, url: url)
    }

    /// The kind told by how a page is built, where that kind is in use.
    /// A page told as one that is not goes as one of the four told by
    /// how much it writes, which loses nothing: such pages go whole. It
    /// is not asked again whether it is a kind that is in use: a
    /// discussion's replies are repeated things with a link each, and it
    /// is no list.
    static func handedOff(as told: PageKind, facts: PageFacts, url: URL) -> PageKind {
        let built: Set<PageKind> = [.product, .thread, .listing, .media]
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
    ///     app, product, thread, listing, media      anything   as counted
    ///     article                                   anything   article
    ///     landing                                   article    article with 800 characters of writing, else landing
    ///     landing                                   the rest   landing
    ///     other                                     article    article with 800 characters of writing, else other
    ///     other                                     landing    landing if built as one, else other
    ///     other                                     app        app with 2 long paragraphs or fewer, else other
    public static func settled(counted: PageKind, answer: PageAnswer?, facts: PageFacts) -> PageKind {
        guard let answer else { return counted }
        switch counted {
        case .app, .product, .thread, .listing, .media, .article:
            return counted
        case .landing:
            return answer.kind == .article && facts.written >= 800 ? .article : .landing
        case .other:
            switch answer.kind {
            case .article: return facts.written >= 800 ? .article : .other
            case .landing: return presents(facts) ? .landing : .other
            case .app: return facts.long <= 2 ? .app : .other
            default: return .other
            }
        }
    }

    // MARK: What the model is asked

    public static let kindInstructions = """
    You are shown facts about a web page, its headings, the start of its text and, when there is one, a picture of \
    it as it shows on a phone. Say what the page is, then which kind of page it is.

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

    /// What the model reads: the page's own account of itself, what was
    /// counted, its headings with how much is under each, and the start of
    /// its writing. Bounded, since the model reads 4,096 tokens at once,
    /// its instructions, a picture and its own answer among them:
    ///
    ///     the page's account of itself, and the counts    about 900 characters at the most
    ///     headings, the first two levels before the third 24, of 60 characters each, 1,400 in all
    ///     the start of the writing                        600 characters
    ///     the parts it may pick from                      12, each a name of 60 characters and 80 of how it starts
    ///
    /// `shortened` is the same with less, for a prompt that was too long
    /// (text in Korean or Japanese is a token or two a character, where
    /// English is four characters a token): once, 10 headings in 600
    /// characters, 300 of the writing, and the parts by name alone; twice,
    /// no headings, half the description, 150 of the writing, and 40
    /// characters of each name. The parts keep their numbers throughout.
    public static func brief(title: String, url: URL, reading: PageReading, candidates: [Candidate] = [], shortened: Int = 0) -> String {
        let facts = reading.facts
        var lines: [String] = []
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Address: " + String(url.absoluteString.prefix(200)))
        if !name.isEmpty { lines.append("Title: " + String(name.prefix(150))) }
        if !facts.site.isEmpty { lines.append("Site: " + String(facts.site.prefix(80))) }
        if !facts.description.isEmpty { lines.append("Its own description: " + String(facts.description.prefix(shortened >= 2 ? 150 : 300))) }
        let says = ([facts.type] + facts.schema).filter { !$0.isEmpty }
        if !says.isEmpty { lines.append("It says it is: " + says.prefix(6).map { String($0.prefix(40)) }.joined(separator: ", ")) }
        lines.append("Counted: \(facts.characters) characters of text, \(facts.long) long paragraphs, "
            + "\(facts.links) links, \(facts.controls) buttons, \(facts.fields) fields to fill in")

        let headings = shortened >= 2 ? [] : outline(of: reading, most: shortened == 1 ? 10 : 24, room: shortened == 1 ? 600 : 1_400)
        if !headings.isEmpty { lines.append("Headings, with the characters under each:\n" + headings.joined(separator: "\n")) }

        // Its writing where it has some, else whatever it starts with.
        let prose = reading.blocks.filter(\.isProse)
        let start = (prose.isEmpty ? reading.blocks.filter { $0.kind != .heading } : prose).lazy.map(\.words)
            .joined(separator: " ").split(whereSeparator: \.isNewline).joined(separator: " ").prefix([600, 300, 150][min(max(shortened, 0), 2)])
        if !start.isEmpty { lines.append("Its text starts:\n" + start) }

        if !candidates.isEmpty {
            lines.append("Parts to pick from:\n" + candidates.prefix(12).enumerated().map { index, candidate in
                let line = "\(index + 1). " + candidate.name.prefix(shortened >= 2 ? 40 : 60)
                return line + (candidate.start.isEmpty || shortened >= 1 ? "" : ": " + candidate.start.prefix(80))
            }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    /// The page's headings for the model, each with how much is under it:
    /// the first two levels in the order they come, then the third where
    /// there is room, so a long page is seen whole before it is seen close.
    static func outline(of reading: PageReading, most: Int, room: Int) -> [String] {
        var found: [(index: Int, level: Int, line: String)] = []
        var open: Int?
        var under = 0
        func close() {
            if let open { found[open].line += " (\(under))" }
        }
        for (index, block) in reading.blocks.enumerated() {
            guard block.kind == .heading else {
                under += block.characters
                continue
            }
            close()
            under = 0
            let title = block.title
            guard !title.isEmpty, block.level <= 3 else {
                open = nil
                continue
            }
            found.append((index, block.level, "- " + String(title.prefix(60))))
            open = found.count - 1
        }
        close()
        var kept = found.filter { $0.level <= 2 }.prefix(most).map { $0 }
        if kept.count < most { kept += found.filter { $0.level == 3 }.prefix(most - kept.count) }
        var lines: [String] = []
        var size = 0
        for heading in kept.sorted(by: { $0.index < $1.index }) {
            if size + heading.line.count > room { break }
            lines.append(heading.line)
            size += heading.line.count + 1
        }
        return lines
    }
}
