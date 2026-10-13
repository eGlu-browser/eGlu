import XCTest
@testable import PadCore

final class HandoffTests: XCTestCase {
    private let page = URL(string: "https://example.org/tides/notes?part=2")!

    func testThePromptAsksAndSaysWhereThePageIs() {
        XCTAssertEqual(Handoff.prompt(question: "", url: page), "Tell me about this page.\nhttps://example.org/tides/notes?part=2")
        XCTAssertEqual(Handoff.prompt(question: "  Summarise in Korean. \n", url: page),
                       "Summarise in Korean.\nhttps://example.org/tides/notes?part=2")
    }

    /// What markdown.js counted on real pages, as an iPhone is served them, in October 2026.
    private func facts(_ characters: Int, long: Int, written: Int, links: Int, linked: Int, controls: Int, fields: Int,
                       drawn: Int = 0, headings: Int, type: String = "", schema: [String] = []) -> PageFacts {
        var facts = PageFacts()
        facts.characters = characters
        facts.long = long
        facts.written = written
        facts.links = links
        facts.linked = linked
        facts.controls = controls
        facts.fields = fields
        facts.drawn = drawn
        facts.headings = (0..<headings).map { "Heading \($0)" }
        facts.type = type
        facts.schema = schema
        return facts
    }

    /// `kind` is the page's kind of the four told by how much it writes;
    /// `built` where what the page declares makes it another of the eight.
    private var measured: [(address: String, facts: PageFacts, kind: PageKind, built: PageKind?)] {
        [
            ("https://en.wikipedia.org/wiki/Tide", facts(4_144, long: 8, written: 3_456, links: 30, linked: 394, controls: 26, fields: 4, headings: 12, type: "website", schema: ["Article"]), .article, nil),
            ("https://paulgraham.com/greatwork.html", facts(67_167, long: 2, written: 67_038, links: 0, linked: 0, controls: 0, fields: 0, headings: 1), .article, nil),
            ("https://developer.mozilla.org/en-US/docs/Web/CSS/display", facts(38_433, long: 41, written: 17_908, links: 125, linked: 2_653, controls: 9, fields: 0, headings: 12), .article, nil),
            ("https://blog.rust-lang.org/2024/02/08/Rust-1.76.0.html", facts(4_285, long: 6, written: 2_096, links: 19, linked: 338, controls: 1, fields: 0, headings: 7, type: "website"), .article, nil),
            ("https://webkit.org/blog/16574/webkit-features-in-safari-18-4/", facts(68_973, long: 87, written: 39_450, links: 121, linked: 1_957, controls: 32, fields: 8, headings: 12, type: "article"), .article, nil),
            ("https://linear.app/", facts(4_362, long: 1, written: 426, links: 10, linked: 390, controls: 76, fields: 2, headings: 9), .landing, nil),
            ("https://stripe.com/", facts(12_143, long: 13, written: 3_310, links: 49, linked: 1_501, controls: 31, fields: 0, drawn: 2, headings: 12, type: "website", schema: ["WebSite", "Organization"]), .landing, nil),
            ("https://www.apple.com/iphone/", facts(9_282, long: 8, written: 2_726, links: 26, linked: 2_057, controls: 116, fields: 1, headings: 12, type: "website", schema: ["Organization", "Brand"]), .landing, nil),
            ("https://www.figma.com/", facts(5_848, long: 7, written: 1_942, links: 9, linked: 147, controls: 25, fields: 0, headings: 11, type: "website", schema: ["Organization"]), .landing, nil),
            ("https://toss.im/", facts(5_802, long: 1, written: 201, links: 12, linked: 828, controls: 19, fields: 0, drawn: 2, headings: 7), .landing, nil),
            ("https://linear.app/pricing", facts(2_406, long: 0, written: 0, links: 10, linked: 121, controls: 8, fields: 3, headings: 6, schema: ["WebPage"]), .landing, nil),
            ("https://excalidraw.com/", facts(265, long: 0, written: 0, links: 1, linked: 7, controls: 16, fields: 0, drawn: 2, headings: 0, type: "website"), .app, nil),
            ("https://squoosh.app/", facts(721, long: 0, written: 0, links: 0, linked: 0, controls: 6, fields: 1, drawn: 1, headings: 4, type: "website"), .app, nil),
            ("https://www.desmos.com/calculator", facts(290, long: 0, written: 0, links: 0, linked: 0, controls: 47, fields: 31, drawn: 1, headings: 0), .app, nil),
            ("https://translate.google.com/", facts(101, long: 0, written: 0, links: 0, linked: 0, controls: 94, fields: 14, headings: 3), .app, nil),
            ("https://news.ycombinator.com/", facts(15_054, long: 2, written: 740, links: 197, linked: 3_193, controls: 0, fields: 1, headings: 0), .other, nil),
            ("https://duckduckgo.com/?q=tide+tables", facts(8_348, long: 5, written: 1_639, links: 66, linked: 1_554, controls: 27, fields: 3, headings: 11), .other, nil),
            ("https://github.com/WebKit/WebKit", facts(10_893, long: 8, written: 2_123, links: 64, linked: 1_673, controls: 38, fields: 1, headings: 12, type: "object"), .other, nil),
            ("https://www.bbc.com/news", facts(12_319, long: 32, written: 9_614, links: 53, linked: 9_277, controls: 27, fields: 1, headings: 5, type: "website", schema: ["WebPage"]), .other, nil),
            ("https://www.nytimes.com/", facts(15_660, long: 23, written: 7_053, links: 62, linked: 4_265, controls: 19, fields: 1, headings: 9, type: "website", schema: ["WebSite", "NewsMediaOrganization"]), .other, nil),
            ("https://www.theverge.com/", facts(30_456, long: 44, written: 10_468, links: 120, linked: 3_569, controls: 107, fields: 12, headings: 12, type: "website"), .other, nil),
            ("https://www.apple.com/shop/buy-iphone", facts(19_163, long: 35, written: 10_512, links: 44, linked: 2_311, controls: 81, fields: 1, headings: 12, type: "product", schema: ["BreadcrumbList"]), .other, .product),
            ("https://m.youtube.com/watch?v=jNQXAC9IVRw", facts(1_906, long: 1, written: 218, links: 13, linked: 876, controls: 27, fields: 2, headings: 2, type: "video.other", schema: ["VideoObject"]), .other, .media),
        ]
    }

    func testAPagesKindIsToldByCounting() throws {
        for page in measured {
            let url = try XCTUnwrap(URL(string: page.address))
            XCTAssertEqual(Handoff.kind(of: page.facts, url: url), page.kind, page.address)
            // With nothing known of how the page is built, what it declares is all that can change its kind.
            XCTAssertEqual(Handoff.kind(of: page.facts, shape: PageShape(), url: url), page.built ?? page.kind, page.address)
        }
        XCTAssertEqual(Handoff.kind(of: PageFacts(), url: page), .other)
        XCTAssertEqual(Handoff.kind(of: PageFacts(), shape: PageShape(), url: page), .other)
    }

    func testAPagesKindIsToldByHowItIsBuilt() throws {
        let forum = facts(6_000, long: 9, written: 3_000, links: 40, linked: 600, controls: 12, fields: 1, headings: 2)
        // A thread: what it declares, or most of its writing being replies.
        XCTAssertEqual(Handoff.kind(of: facts(6_000, long: 2, written: 500, links: 40, linked: 600, controls: 12, fields: 1, headings: 2,
                                              schema: ["QAPage"]), shape: PageShape(), url: page), .thread)
        XCTAssertEqual(Handoff.kind(of: forum, shape: PageShape(written: 3_000, replies: 2_400), url: page), .thread)
        // With as much writing that is not replies, it is the writing it was counted as, with replies under it.
        XCTAssertEqual(Handoff.kind(of: forum, shape: PageShape(written: 3_000, replies: 1_200), url: page), .article)
        XCTAssertEqual(Handoff.kind(of: forum, shape: PageShape(written: 3_000, replies: 1_500), url: page), .article, "1,500 characters of other writing")
        XCTAssertEqual(Handoff.kind(of: forum, shape: PageShape(written: 3_000, replies: 1_501), url: page), .thread)
        let short = facts(900, long: 3, written: 700, links: 4, linked: 60, controls: 0, fields: 0, headings: 1)
        XCTAssertEqual(Handoff.kind(of: short, shape: PageShape(written: 700, replies: 599), url: page), .other)
        // Replies of a line or two each are no writing, and a thread all the same where they are most of the text.
        let chatty = facts(6_000, long: 1, written: 400, links: 40, linked: 600, controls: 12, fields: 1, headings: 2)
        XCTAssertEqual(Handoff.kind(of: chatty, shape: PageShape(written: 400, replies: 0, discussed: 2_401), url: page), .thread)
        XCTAssertEqual(Handoff.kind(of: chatty, shape: PageShape(written: 400, replies: 0, discussed: 2_400), url: page), .other)
        XCTAssertEqual(Handoff.kind(of: short, shape: PageShape(discussed: 599), url: page), .other, "a line that says there are no comments yet")
        // An article with comments under it is an article, however many.
        let commented = facts(20_000, long: 60, written: 16_000, links: 40, linked: 600, controls: 12, fields: 1, headings: 6, type: "article")
        XCTAssertEqual(Handoff.kind(of: commented, shape: PageShape(written: 16_000, replies: 15_000, discussed: 19_000), url: page), .article)
        var undeclared = commented
        undeclared.type = ""
        XCTAssertEqual(Handoff.kind(of: undeclared, shape: PageShape(written: 16_000, replies: 6_000, discussed: 9_000), url: page), .article)

        // One thing for sale. A shelf of them is not.
        let shop = facts(9_000, long: 6, written: 2_000, links: 50, linked: 900, controls: 30, fields: 2, headings: 8, schema: ["Product", "BreadcrumbList"])
        XCTAssertEqual(Handoff.kind(of: shop, shape: PageShape(products: 1), url: page), .product)
        XCTAssertEqual(Handoff.kind(of: shop, shape: PageShape(products: 24), url: page), .other)
        XCTAssertEqual(Handoff.kind(of: shop, shape: PageShape(items: 24, listed: 6_000, products: 24), url: page), .listing)

        // A recording, unless the page is writing with a film in it.
        let film = facts(4_000, long: 3, written: 2_999, links: 20, linked: 300, controls: 10, fields: 1, headings: 2, schema: ["VideoObject"])
        XCTAssertEqual(Handoff.kind(of: film, shape: PageShape(), url: page), .media)
        var essay = film
        essay.written = 3_000
        XCTAssertEqual(Handoff.kind(of: essay, shape: PageShape(), url: page), .article)
        XCTAssertEqual(Handoff.kind(of: facts(900, long: 0, written: 0, links: 9, linked: 90, controls: 3, fields: 0, headings: 1, type: "music.song"),
                                    shape: PageShape(), url: page), .media)

        // A list: what it declares where it has the items, or most of the page being them.
        let results = facts(8_000, long: 5, written: 1_600, links: 66, linked: 1_500, controls: 27, fields: 3, headings: 11)
        XCTAssertEqual(Handoff.kind(of: results, shape: PageShape(items: 10, listed: 4_000), url: page), .listing)
        XCTAssertEqual(Handoff.kind(of: results, shape: PageShape(items: 9, listed: 4_000), url: page), .other)
        XCTAssertEqual(Handoff.kind(of: results, shape: PageShape(items: 10, listed: 3_999), url: page), .other)
        var declared = results
        declared.schema = ["SearchResultsPage"]
        XCTAssertEqual(Handoff.kind(of: declared, shape: PageShape(items: 5, listed: 900), url: page), .listing)
        XCTAssertEqual(Handoff.kind(of: declared, shape: PageShape(items: 4, listed: 900), url: page), .other)
        // A page of writing with a long list in it is still writing, and a tool with one a tool.
        let written = facts(8_000, long: 12, written: 3_300, links: 66, linked: 1_500, controls: 27, fields: 3, headings: 11)
        XCTAssertEqual(Handoff.kind(of: written, shape: PageShape(items: 30, listed: 4_100), url: page), .article)
        let tool = facts(900, long: 0, written: 0, links: 20, linked: 300, controls: 9, fields: 1, headings: 0)
        XCTAssertEqual(Handoff.kind(of: tool, shape: PageShape(items: 20, listed: 800), url: page), .app)
        // A search with a form of many fields over its results is counted a tool, and is a list.
        let search = facts(7_948, long: 0, written: 0, links: 36, linked: 696, controls: 29, fields: 53, headings: 1, type: "website")
        XCTAssertEqual(Handoff.kind(of: search, url: page), .app)
        XCTAssertEqual(Handoff.kind(of: search, shape: PageShape(items: 20, listed: 5_928), url: page), .listing)
        XCTAssertEqual(Handoff.kind(of: search, shape: PageShape(items: 9, listed: 5_928), url: page), .app)
        // And one that would have been taken for a page presenting something is a list where it is one.
        let front = facts(2_900, long: 0, written: 0, links: 18, linked: 500, controls: 1, fields: 1, headings: 12)
        let top = try XCTUnwrap(URL(string: "https://search.example/?q=tides"))
        XCTAssertEqual(Handoff.kind(of: front, url: top), .landing)
        XCTAssertEqual(Handoff.kind(of: front, shape: PageShape(items: 18, listed: 2_800), url: top), .listing)
    }

    /// What markdown.js read on real pages in October 2026, by address as each loaded, with the kind told by how
    /// the page is built and whether that is what the page is. The first eleven are those the rules were set
    /// on; the last seven were read only after (the 15 held-out pages, less those of the four older kinds).
    private var built: [(address: String, facts: PageFacts, shape: PageShape, kind: PageKind, right: Bool)] {
        [
            ("https://duckduckgo.com/?q=tide+tables&ia=web", facts(8_428, long: 5, written: 1_639, links: 66, linked: 1_619, controls: 27, fields: 3, headings: 11),
             PageShape(items: 16, listed: 7_704, written: 1_655), .listing, true),
            ("https://www.apple.com/shop/buy-iphone", facts(19_161, long: 35, written: 10_512, links: 44, linked: 2_311, controls: 81, fields: 1, headings: 12, type: "product", schema: ["BreadcrumbList"]),
             PageShape(items: 40, listed: 16_946), .product, true),
            ("https://github.com/WebKit/WebKit/pull/1", facts(16_572, long: 18, written: 4_327, links: 109, linked: 6_291, controls: 64, fields: 0, headings: 12, type: "object"),
             PageShape(items: 40, listed: 14_508, written: 301, replies: 301, discussed: 15_891), .thread, true),
            ("https://m.naver.com/", facts(18_517, long: 14, written: 3_723, links: 180, linked: 6_611, controls: 125, fields: 4, headings: 11),
             PageShape(items: 24, listed: 13_682), .listing, true),
            ("https://news.ycombinator.com/item?id=8863", facts(35_870, long: 50, written: 17_179, links: 175, linked: 2_221, controls: 0, fields: 1, headings: 0),
             PageShape(items: 71, listed: 33_743, written: 16_439, replies: 16_439, discussed: 33_743), .thread, true),
            ("https://github.com/rust-lang/rust/issues/1", facts(9_732, long: 4, written: 1_622, links: 88, linked: 3_165, controls: 59, fields: 0, headings: 12, type: "object", schema: ["DiscussionForumPosting"]),
             PageShape(items: 21, listed: 6_990, discussed: 7_739), .thread, true),
            ("https://en.wikipedia.org/wiki/Special:Search?search=tide+table&ns0=1&fulltext=1", facts(7_834, long: 0, written: 0, links: 35, linked: 671, controls: 29, fields: 53, headings: 1, type: "website"),
             PageShape(items: 20, listed: 5_814), .listing, true),
            ("https://www.npmjs.com/search?q=markdown", facts(12_038, long: 0, written: 0, links: 151, linked: 1_374, controls: 4, fields: 1, headings: 2),
             PageShape(items: 20, listed: 11_446), .listing, true),
            // A game's page at a shop that declares nothing: counted as the writing on it, and so it goes whole.
            ("https://store.steampowered.com/app/730/CounterStrike_2/", facts(7_282, long: 9, written: 3_154, links: 43, linked: 922, controls: 26, fields: 54, headings: 8, type: "website"),
             PageShape(written: 1_020), .article, false),
            ("https://vimeo.com/76979871", facts(1_550, long: 1, written: 259, links: 8, linked: 76, controls: 9, fields: 0, headings: 2, type: "video.other", schema: ["VideoObject", "BreadcrumbList"]),
             PageShape(), .media, true),
            ("https://archive.org/details/BigBuckBunny_124", facts(3_432, long: 2, written: 906, links: 24, linked: 537, controls: 15, fields: 7, headings: 6, type: "video.movie", schema: ["BreadcrumbList"]),
             PageShape(written: 577), .media, true),

            ("https://m.youtube.com/watch?v=jNQXAC9IVRw", facts(1_768, long: 1, written: 205, links: 13, linked: 853, controls: 27, fields: 2, headings: 2, type: "video.other", schema: ["BreadcrumbList", "VideoObject"]),
             PageShape(items: 12, listed: 1_576, discussed: 49), .media, true),
            // A thread of one short post and a few replies: of no kind, which is right enough, and whole.
            ("https://news.ycombinator.com/item?id=1", facts(2_029, long: 2, written: 740, links: 31, linked: 299, controls: 0, fields: 1, headings: 0),
             PageShape(discussed: 452), .other, true),
            ("https://www.nytimes.com/", facts(15_968, long: 24, written: 7_295, links: 65, linked: 4_314, controls: 21, fields: 1, headings: 9, type: "website", schema: ["WebSite", "ItemList", "NewsMediaOrganization"]),
             PageShape(items: 30, listed: 12_062, written: 2_330), .listing, true),
            // A question whose own text is long, with answers longer still: not told as a discussion.
            ("https://stackoverflow.com/questions/11227809/why-is-conditional-processing-of-a-sorted-array-faster-than-of-an-unsorted-array", facts(100_000, long: 124, written: 48_732, links: 251, linked: 7_839, controls: 2_238, fields: 38, headings: 12, type: "website", schema: ["WebSite", "Organization"]),
             PageShape(items: 25, listed: 8_965, written: 47_809, replies: 43_772, discussed: 85_612), .article, false),
            // A topic on a forum that calls nothing of itself comments or replies: nor this.
            ("https://meta.discourse.org/t/new-to-discourse-start-here/1", facts(3_764, long: 6, written: 1_572, links: 23, linked: 617, controls: 14, fields: 3, headings: 7, type: "website"),
             PageShape(items: 5, listed: 608, written: 901), .article, false),
            // Asked for as one bookcase's page, which led here: the shop's page of all of them, and a list.
            ("https://www.ikea.com/us/en/cat/billy-bookcases-58288/", facts(47_673, long: 50, written: 41_854, links: 155, linked: 30_375, controls: 119, fields: 113, headings: 12, type: "product.group", schema: ["Organization", "WebSite", "CollectionPage", "ItemList", "BreadcrumbList"]),
             PageShape(items: 6, listed: 47_301, written: 34_813), .listing, true),
            ("https://www.ted.com/talks/sir_ken_robinson_do_schools_kill_creativity", facts(144, long: 0, written: 0, links: 1, linked: 16, controls: 59, fields: 7, headings: 1, type: "video.other", schema: ["VideoObject"]),
             PageShape(), .media, true),
        ]
    }

    /// The kinds told by how a page is built, on pages measured. Three of these are told wrongly, two of them
    /// among the seven the rules were not set on.
    func testTheKindsToldByHowAPageIsBuiltAreAsMeasured() throws {
        for page in built {
            XCTAssertEqual(Handoff.kind(of: page.facts, shape: page.shape, url: try XCTUnwrap(URL(string: page.address))), page.kind, page.address)
        }
        XCTAssertEqual(built.filter { !$0.right }.compactMap { URL(string: $0.address)?.host },
                       ["store.steampowered.com", "stackoverflow.com", "meta.discourse.org"])
    }

    /// The two of those kinds that are in use (Handoff.builtKindsInUse) are the two told rightly on every
    /// page measured. A page told as one of the other two goes as what it is by how much it writes.
    func testOnlyTheKindsThatHeldAreInUse() throws {
        XCTAssertEqual(Handoff.builtKindsInUse, [.listing, .media])
        let inUse = built.filter { Handoff.builtKindsInUse.contains($0.kind) }
        XCTAssertEqual(inUse.filter { $0.kind == .listing }.count, 6)
        XCTAssertEqual(inUse.filter { $0.kind == .media }.count, 4)
        XCTAssertTrue(inUse.allSatisfy(\.right))
        var handedOff: [String: PageKind] = [:]
        for page in built {
            let url = try XCTUnwrap(URL(string: page.address))
            let kind = Handoff.handedOff(as: page.kind, facts: page.facts, url: url)
            if kind != page.kind { handedOff[(url.host ?? "") + url.path] = kind }
        }
        // A shop's page for a phone, a pull request, a thread and an issue: not told as lists for being told as nothing else.
        XCTAssertEqual(handedOff, ["www.apple.com/shop/buy-iphone": .other, "github.com/WebKit/WebKit/pull/1": .other,
                                   "news.ycombinator.com/item": .article, "github.com/rust-lang/rust/issues/1": .other])
        XCTAssertEqual(Handoff.handedOff(as: .landing, facts: PageFacts(), url: page), .landing)
    }

    func testTheShapeOfAPageIsCountedFromItsBlocks() {
        let long = String(repeating: "w", count: 250)
        let reading = PageReading(blocks: [
            PageBlock(kind: .heading, level: 2, text: "## Comments", start: "Comments"), PageBlock(text: long), PageBlock(text: "Short."),
            PageBlock(kind: .heading, level: 2, text: "## Notes", start: "Notes"), PageBlock(text: long, hint: .comments), PageBlock(text: long),
        ], things: [PageThing(types: ["Product"]), PageThing(types: ["product", "Thing"], main: true), PageThing(types: ["Offer"])])
        // The thing the page says is its own, where it says: the others are beside it.
        XCTAssertEqual(PageShape(reading), PageShape(written: 750, replies: 500, discussed: 517, products: 1))
        XCTAssertEqual(PageShape(PageReading(blocks: reading.blocks, things: [PageThing(types: ["Product"]), PageThing(types: ["Product"])])).products, 2)
        XCTAssertEqual(Handoff.kind(of: reading, url: page), .other)
    }

    func testTheModelsAnswerIsHeldAgainstTheCount() throws {
        func settled(_ address: String, _ said: PageKind) throws -> PageKind {
            let page = try XCTUnwrap(measured.first { $0.address == address })
            return Handoff.settled(counted: page.kind, answer: PageAnswer(kind: said, about: ""), facts: page.facts)
        }
        // Where the model can't be asked, the count stands.
        XCTAssertEqual(Handoff.settled(counted: .landing, answer: nil, facts: PageFacts()), .landing)
        // What the model said of these pages on a Mac, and what goes of them. It is right about pages that present something.
        XCTAssertEqual(try settled("https://stripe.com/", .landing), .landing)
        XCTAssertEqual(try settled("https://linear.app/", .landing), .landing)
        // It calls a tool's own page one that presents the tool, since the page's description does.
        XCTAssertEqual(try settled("https://excalidraw.com/", .landing), .app)
        XCTAssertEqual(try settled("https://translate.google.com/", .landing), .app)
        // And lists of other people's things too, which are not cut to an outline for it.
        XCTAssertEqual(try settled("https://news.ycombinator.com/", .landing), .other)
        XCTAssertEqual(try settled("https://news.ycombinator.com/", .article), .other)
        XCTAssertEqual(try settled("https://duckduckgo.com/?q=tide+tables", .landing), .other)
        XCTAssertEqual(try settled("https://github.com/WebKit/WebKit", .landing), .other)
        // A page of documentation it called neither stays the writing it was counted as.
        XCTAssertEqual(try settled("https://developer.mozilla.org/en-US/docs/Web/CSS/display", .other), .article)
        XCTAssertEqual(try settled("https://paulgraham.com/greatwork.html", .article), .article)
        // What it did not say, but might: writing is not cut as a tool's text is, and a page with little of it may be.
        XCTAssertEqual(try settled("https://webkit.org/blog/16574/webkit-features-in-safari-18-4/", .landing), .article)
        XCTAssertEqual(try settled("https://webkit.org/blog/16574/webkit-features-in-safari-18-4/", .app), .article)
        XCTAssertEqual(try settled("https://www.theverge.com/", .app), .other)
        XCTAssertEqual(try settled("https://m.youtube.com/watch?v=jNQXAC9IVRw", .app), .app)
    }

    /// Every row of the table over Handoff.settled.
    func testEachKindCountedIsSettledAsTheTableSays() {
        let written = facts(4_000, long: 4, written: 800, links: 10, linked: 100, controls: 2, fields: 0, headings: 3)
        var thin = written
        thin.written = 799
        var busy = written
        busy.long = 2
        var linked = written
        linked.links = 60
        let model: [PageKind] = [.article, .landing, .app, .other]
        // What is told by how the page is built stands, and so does an article.
        for counted in [PageKind.app, .product, .thread, .listing, .media, .article] {
            for said in model {
                XCTAssertEqual(Handoff.settled(counted: counted, answer: PageAnswer(kind: said, about: ""), facts: written), counted)
            }
        }
        func settled(_ counted: PageKind, _ said: PageKind, _ facts: PageFacts) -> PageKind {
            Handoff.settled(counted: counted, answer: PageAnswer(kind: said, about: "", picks: [PageAnswer.Pick(number: 1, name: "Pricing")]), facts: facts)
        }
        XCTAssertEqual(settled(.landing, .article, written), .article)
        XCTAssertEqual(settled(.landing, .article, thin), .landing)
        XCTAssertEqual(settled(.landing, .landing, written), .landing)
        XCTAssertEqual(settled(.landing, .app, written), .landing)
        XCTAssertEqual(settled(.landing, .other, written), .landing)
        XCTAssertEqual(settled(.other, .article, written), .article)
        XCTAssertEqual(settled(.other, .article, thin), .other)
        XCTAssertEqual(settled(.other, .landing, written), .landing)
        XCTAssertEqual(settled(.other, .landing, linked), .other)
        XCTAssertEqual(settled(.other, .app, busy), .app)
        XCTAssertEqual(settled(.other, .app, written), .other)
        XCTAssertEqual(settled(.other, .other, written), .other)
    }

    func testFactsAreReadFromWhatTheScriptGives() {
        let facts = PageFacts(["description": "About tides.", "type": "article", "schema": ["Article"], "headings": ["One", "Two"],
                               "characters": NSNumber(value: 5_000), "long": 9, "written": 4_000, "links": 3, "linked": 250,
                               "controls": 2, "fields": 1, "drawn": 0, "marked": true])
        XCTAssertEqual(facts.characters, 5_000)
        XCTAssertEqual(facts.written, 4_000)
        XCTAssertEqual(facts.linkShare, 0.05, accuracy: 0.001)
        XCTAssertTrue(facts.marked)
        // What is missing, or of another shape, is nothing: the page wrote this, not the app.
        XCTAssertEqual(PageFacts(["characters": "many", "schema": "Article"]), PageFacts())
        XCTAssertEqual(PageFacts([:]).linkShare, 0)
        // Nor is any count more than a page can come to: the rules multiply them.
        let absurd = PageFacts(["characters": Int.max, "written": Int.max, "long": -3, "links": Int.min, "linked": Int.max, "controls": Int.max])
        XCTAssertEqual(absurd.characters, 10_000_000)
        XCTAssertEqual(absurd.long, 0)
        XCTAssertEqual(absurd.links, 0)
        // Told as something, with nothing to overflow on the way: as a tool, having no long paragraph and ten million buttons.
        XCTAssertEqual(Handoff.kind(of: absurd, shape: PageShape(items: Int.max / 100, listed: Int.max / 100), url: page), .app)
        XCTAssertEqual(Handoff.kind(of: absurd, url: page), .app)
    }

    /// A page with as much of everything as a brief can take.
    private var wordy: (reading: PageReading, candidates: [Handoff.Candidate]) {
        var blocks: [PageBlock] = []
        for number in 1...40 {
            let title = "Heading \(number) " + String(repeating: "h", count: 70)
            blocks.append(PageBlock(kind: .heading, level: number % 3 + 1, text: "## " + title, start: title))
            blocks.append(PageBlock(text: String(repeating: "word ", count: 80)))
        }
        var reading = PageReading(blocks: blocks)
        reading.facts.description = String(repeating: "d", count: 400)
        reading.facts.site = String(repeating: "s", count: 100)
        reading.facts.type = "website"
        reading.facts.schema = ["Organization", "WebSite"] + (0..<8).map { "Type\($0)" + String(repeating: "t", count: 60) }
        reading.facts.characters = 90_000
        let candidates = (0..<14).map { Handoff.Candidate(part: $0, name: "Part \($0) " + String(repeating: "n", count: 80), start: String(repeating: "s", count: 100)) }
        return (reading, candidates)
    }

    func testTheBriefIsShortEnoughForTheModel() throws {
        let wordy = wordy
        let address = try XCTUnwrap(URL(string: "https://example.org/" + String(repeating: "a", count: 400)))
        let briefs = (0...2).map {
            Handoff.brief(title: String(repeating: "t", count: 400), url: address, reading: wordy.reading, candidates: wordy.candidates, shortened: $0)
        }
        // 4,096 tokens hold the instructions, the picture and the answer as well: at four characters a token
        // the fullest is under 1,300 of them, and each of the others is what is left when that is too many.
        XCTAssertLessThan(briefs[0].count, 5_000)
        XCTAssertLessThan(briefs[1].count, 2_900)
        XCTAssertLessThan(briefs[2].count, 1_700)
        XCTAssertTrue(briefs[0].hasPrefix("Address: https://example.org/aaaa"))
        XCTAssertTrue(briefs[0].contains("\nTitle: tttt"))
        XCTAssertTrue(briefs[0].contains("It says it is: website, Organization, WebSite, Type0"))
        XCTAssertTrue(briefs[0].contains("Its text starts:\nword word"))
        // Twelve parts at the most, by their numbers in every one: with how each starts, by name, by the start of its name.
        for brief in briefs {
            XCTAssertTrue(brief.contains("Parts to pick from:\n1. Part 0 nnnn"))
            XCTAssertTrue(brief.contains("\n12. Part 11 nnnn"))
            XCTAssertFalse(brief.contains("\n13. "))
        }
        XCTAssertTrue(briefs[0].contains("1. Part 0 " + String(repeating: "n", count: 53) + ": " + String(repeating: "s", count: 80) + "\n2. "))
        XCTAssertTrue(briefs[1].contains("1. Part 0 " + String(repeating: "n", count: 53) + "\n2. "))
        XCTAssertTrue(briefs[2].contains("1. Part 0 " + String(repeating: "n", count: 33) + "\n2. "))
        XCTAssertTrue(briefs[1].contains("Headings, with the characters under each:"))
        XCTAssertFalse(briefs[2].contains("Headings"))
    }

    func testTheBriefShowsThePageWholeBeforeItShowsItClose() {
        let reading = PageReading(blocks: [
            PageBlock(kind: .heading, level: 1, text: "# Forma", start: "Forma"), PageBlock(text: "Design together."),
            PageBlock(kind: .heading, level: 3, text: "### Frames", start: "Frames"), PageBlock(text: String(repeating: "w", count: 120)),
            PageBlock(kind: .heading, level: 4, text: "#### Deep", start: "Deep"), PageBlock(text: String(repeating: "w", count: 30)),
            PageBlock(kind: .heading, level: 2, text: "## [Pricing](https://example.org/p)", start: "Pricing"),
            PageBlock(text: String(repeating: "w", count: 250)), PageBlock(text: "12 EUR."),
            PageBlock(kind: .heading, level: 3, text: "### Team", start: "Team"),
        ])
        XCTAssertEqual(Handoff.outline(of: reading, most: 24, room: 1_400), ["- Forma (16)", "- Frames (120)", "- Pricing (257)", "- Team (0)"])
        // With room for two, the two that say what the page is made of.
        XCTAssertEqual(Handoff.outline(of: reading, most: 2, room: 1_400), ["- Forma (16)", "- Pricing (257)"])
        XCTAssertEqual(Handoff.outline(of: reading, most: 3, room: 1_400), ["- Forma (16)", "- Frames (120)", "- Pricing (257)"])
        XCTAssertEqual(Handoff.outline(of: reading, most: 24, room: 30), ["- Forma (16)", "- Frames (120)"])
        let brief = Handoff.brief(title: "Forma", url: page, reading: reading)
        XCTAssertTrue(brief.contains("Headings, with the characters under each:\n- Forma (16)\n- Frames (120)\n- Pricing (257)\n- Team (0)\nIts text starts:\n" + String(repeating: "w", count: 250)))
        XCTAssertFalse(brief.contains("Parts to pick from"))
        // A page with no writing starts with whatever it has.
        XCTAssertTrue(Handoff.brief(title: "", url: page, reading: PageReading(blocks: Array(reading.blocks.prefix(2)))).hasSuffix("Its text starts:\nDesign together."))
    }

    func testTheFileIsNamedForThePage() {
        XCTAssertEqual(Handoff.fileName(title: "Field notes: tides / moon?", url: page), "Field notes tides moon.md")
        XCTAssertEqual(Handoff.fileName(title: "  \n ", url: page), "example.org.md")
        XCTAssertEqual(Handoff.fileName(title: "...hidden", url: page), "hidden.md")
        XCTAssertEqual(Handoff.fileName(title: "피그마 강좌 | 디자인", url: page), "피그마 강좌 디자인.md")
        let long = Handoff.fileName(title: String(repeating: "tide ", count: 40), url: page)
        XCTAssertLessThanOrEqual(long.count, 83)
        XCTAssertTrue(long.hasSuffix(".md"))
    }

    func testTheScriptShipsAsOneFunction() {
        // Page.markdown gives it a name and calls it, so it has to be an expression and nothing after.
        let script = Scripts.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(script.hasSuffix("})"), "markdown.js must end with the function, not a call or a semicolon")
        XCTAssertTrue(script.contains("(function (limit) {"))
        XCTAssertTrue(Scripts.markdownCall.hasSuffix("return run(limit);"))
    }
}
