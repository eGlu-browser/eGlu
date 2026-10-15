import XCTest
@testable import PadCore

final class HandoffTests: XCTestCase {
    private let page = URL(string: "https://example.org/tides/notes?part=2")!

    func testThePromptSaysWhereThePageIsAndLeavesTheQuestion() {
        XCTAssertEqual(Handoff.prompt(url: page), "URL: https://example.org/tides/notes?part=2\nQuestion: ")
        // Without what the address was reached by.
        XCTAssertEqual(Handoff.prompt(url: URL(string: "https://example.org/tides?part=2&utm_source=letter")!),
                       "URL: https://example.org/tides?part=2\nQuestion: ")
    }

    func testTheAddressGoesWithoutWhatFollowsTheReader() throws {
        func clean(_ address: String) throws -> String {
            Tracking.clean(try XCTUnwrap(URL(string: address))).absoluteString
        }
        // What an advertisement, a newsletter or a share button hung on the link, whatever case it is written in.
        XCTAssertEqual(try clean("https://example.org/a?utm_source=x&utm_medium=email&UTM_Campaign=y"), "https://example.org/a")
        XCTAssertEqual(try clean("https://example.org/a?id=7&fbclid=IwAR0&gclid=abc&igshid=1&_ga=2.1&mc_eid=9"), "https://example.org/a?id=7")
        XCTAssertEqual(try clean("https://m.brand.naver.com/airmade/shoppingstory/detail?id=5003091743&NaPm=ct%3Dabc%7Cci%3Ddef&n_media=27758"),
                       "https://m.brand.naver.com/airmade/shoppingstory/detail?id=5003091743")
        // What is kept is as the address wrote it, in its order, with its place on the page.
        XCTAssertEqual(try clean("https://example.org/s?q=tide%20tables&utm_term=z&page=2&empty=&flag#results"),
                       "https://example.org/s?q=tide%20tables&page=2&empty=&flag#results")
        XCTAssertEqual(try clean("https://example.org/s?q=%EA%B0%80%EC%8A%B5%EA%B8%B0&fbclid=1"), "https://example.org/s?q=%EA%B0%80%EC%8A%B5%EA%B8%B0")
        // On YouTube also what its share links and its own apps add; the film and the place in it stay.
        XCTAssertEqual(try clean("https://m.youtube.com/watch?v=SAekvy5Mn_U&si=abc&pp=ygU&ra=m&t=42"), "https://m.youtube.com/watch?v=SAekvy5Mn_U&t=42")
        XCTAssertEqual(try clean("https://youtu.be/SAekvy5Mn_U?si=abc"), "https://youtu.be/SAekvy5Mn_U")
        // Elsewhere those names are the site's own.
        XCTAssertEqual(try clean("https://example.org/a?si=1&pp=2&ra=3&ref=home"), "https://example.org/a?si=1&pp=2&ra=3&ref=home")
        XCTAssertEqual(try clean("https://notyoutube.com/watch?si=1"), "https://notyoutube.com/watch?si=1")
        // Matomo's, HubSpot's and Klaviyo's tags, and what other sites' share buttons add, there alone.
        XCTAssertEqual(try clean("https://example.org/a?pk_campaign=x&mtm_source=y&hsa_acc=1&_kx=2&id=3"), "https://example.org/a?id=3")
        XCTAssertEqual(try clean("https://x.com/user/status/1?s=20&t=AbC"), "https://x.com/user/status/1")
        XCTAssertEqual(try clean("https://www.tiktok.com/@a/video/1?is_from_webapp=1&sender_device=pc&_t=8x&_r=1"), "https://www.tiktok.com/@a/video/1")
        XCTAssertEqual(try clean("https://open.spotify.com/track/1?si=abc"), "https://open.spotify.com/track/1")
        XCTAssertEqual(try clean("https://www.linkedin.com/jobs/view/1?trk=public&refId=x&trackingId=y"), "https://www.linkedin.com/jobs/view/1")
        XCTAssertEqual(try clean("https://www.reddit.com/r/a/comments/1/b/?share_id=x&utm_name=y"), "https://www.reddit.com/r/a/comments/1/b/")
        XCTAssertEqual(try clean("https://example.org/a?s=1&t=2&trk=3&share_id=4"), "https://example.org/a?s=1&t=2&trk=3&share_id=4")
        // Nothing to take out, nothing changed: no query, an empty one, one with nothing known in it.
        for address in ["https://example.org/a", "https://example.org/a?", "https://example.org/a?part=2&utmost=1", "https://example.org/a#utm_source=x"] {
            XCTAssertEqual(try clean(address), address)
        }
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

        // One job on offer, as the page declares it: before writing, which a posting has a lot of and some
        // sites call an article. A board's search declares many, and is a list or nothing. Undeclared, a
        // posting goes as what it is by how much it writes.
        let posting = facts(5_000, long: 4, written: 2_400, links: 12, linked: 200, controls: 6, fields: 0, headings: 6,
                            type: "article", schema: ["JobPosting", "Organization"])
        XCTAssertEqual(Handoff.kind(of: posting, shape: PageShape(jobs: 1), url: page), .job)
        let board = facts(8_000, long: 2, written: 600, links: 80, linked: 2_500, controls: 20, fields: 3, headings: 4, schema: ["JobPosting"])
        XCTAssertEqual(Handoff.kind(of: board, shape: PageShape(items: 20, listed: 5_000, jobs: 20), url: page), .listing)
        XCTAssertEqual(Handoff.kind(of: posting, shape: PageShape(), url: page), .article)
        // A few jobs declared, on a board with fewer than ten in its list.
        XCTAssertEqual(Handoff.kind(of: board, shape: PageShape(items: 6, listed: 2_000, jobs: 6), url: page), .listing)
        // A job declared beside an article that says it is the page's own: the page is the article.
        let beside = PageReading(blocks: [], things: [PageThing(types: ["NewsArticle"], main: true), PageThing(types: ["JobPosting"])])
        XCTAssertEqual(PageShape(beside).jobs, 0)
        XCTAssertEqual(PageShape(PageReading(blocks: [], things: [PageThing(types: ["JobPosting"]), PageThing(types: ["WebSite"])])).jobs, 1)
        XCTAssertEqual(Handoff.handedOff(as: .job, facts: posting, url: page), .job)
        XCTAssertEqual(Handoff.settled(counted: .job, answer: PageAnswer(kind: .landing, about: "A job."), facts: posting), .job)

        // A posting a job board knows by its address, though it declares nothing: one that has closed is a line saying so.
        var unmarked = PageReading(blocks: [])
        unmarked.facts = facts(9_000, long: 6, written: 3_400, links: 5, linked: 60, controls: 20, fields: 14, headings: 3, type: "article")
        let greenhouse = try XCTUnwrap(URL(string: "https://job-boards.greenhouse.io/discord/jobs/8815116002"))
        XCTAssertEqual(Handoff.kind(of: unmarked, url: greenhouse), .job)
        XCTAssertEqual(Handoff.kind(of: unmarked, url: try XCTUnwrap(URL(string: "https://job-boards.greenhouse.io/discord"))), .article)
        var closed = unmarked
        closed.facts = facts(300, long: 0, written: 0, links: 4, linked: 40, controls: 2, fields: 0, headings: 1)
        XCTAssertNotEqual(Handoff.kind(of: closed, url: greenhouse), .job)

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
    /// page measured, with a job posting, which is told by its own declaration alone. A page told as one
    /// of the other two goes as what it is by how much it writes.
    func testOnlyTheKindsThatHeldAreInUse() throws {
        XCTAssertEqual(Handoff.builtKindsInUse, [.listing, .media, .job])
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
        // A news site's front page: long headlines, each a link, which the model calls writing.
        var headlines = written
        headlines.linked = 2_000
        XCTAssertEqual(settled(.other, .article, headlines), .other)
        headlines.linked = 1_999
        XCTAssertEqual(settled(.other, .article, headlines), .article)
        XCTAssertEqual(settled(.other, .landing, written), .landing)
        XCTAssertEqual(settled(.other, .landing, linked), .other)
        // Two steps into its site a page may present something; further down it is as often a case study or a manual, and goes whole.
        func deep(_ address: String) -> PageKind {
            Handoff.settled(counted: .other, answer: PageAnswer(kind: .landing, about: ""), facts: written, url: URL(string: address))
        }
        XCTAssertEqual(deep("https://example.org/"), .landing)
        XCTAssertEqual(deep("https://example.org/kr/iphone-18-pro/"), .landing)
        XCTAssertEqual(deep("https://example.org/en/case-studies/new-connect"), .other)
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
        // What the file says is not in it: pictures with no description, and what the reader left out as the site's.
        let more = PageFacts(["titled": "진짜 무서운 공포 영화 월드컵", "unnamed": 8, "unnamedTall": 3_840, "tall": 800,
                              "left": ["foot": 5_845, "top": 0, "menus": 562, "beside": 113, "other": 9]])
        XCTAssertEqual(more.titled, "진짜 무서운 공포 영화 월드컵")
        XCTAssertEqual([more.unnamed, more.unnamedTall, more.tall], [8, 3_840, 800])
        XCTAssertEqual(more.left, PageFacts.Left(foot: 5_845, top: 0, menus: 562, beside: 113))
        XCTAssertEqual(more.left.all, 6_520)
        XCTAssertEqual(PageFacts(["left": "much", "unnamed": -2]).left, PageFacts.Left())
        XCTAssertEqual(PageFacts(["unnamed": -2]).unnamed, 0)
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
        // the fullest is under 1,500 of them, and each of the others is what is left when that is too many.
        XCTAssertLessThan(briefs[0].count, 6_000)
        XCTAssertLessThan(briefs[1].count, 3_200)
        XCTAssertLessThan(briefs[2].count, 1_700)
        XCTAssertLessThan(Handoff.weight(of: briefs[0]), 2_400)
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
        // Fourteen sections with 120 characters of each, then eight with 60, then none.
        let heading = "Heading 1 " + String(repeating: "h", count: 50)
        XCTAssertTrue(briefs[0].contains("Its sections, each with how it starts:\n- " + heading + ": " + String(repeating: "word ", count: 23) + "word…\n- "))
        XCTAssertTrue(briefs[1].contains("Its sections, each with how it starts:\n- " + heading + ": " + String(repeating: "word ", count: 11) + "word…\n- "))
        XCTAssertEqual(briefs[0].components(separatedBy: "\n- Heading ").count - 1, 14)
        XCTAssertEqual(briefs[1].components(separatedBy: "\n- Heading ").count - 1, 8)
        XCTAssertFalse(briefs[2].contains("Its sections"))
        XCTAssertTrue(briefs[2].contains("Its own description: " + String(repeating: "d", count: 150) + "\n"))
    }

    func testABriefTooHeavyForTheModelIsNotTried() throws {
        // A quarter of a token a character in Latin letters, a token and a half in Korean.
        XCTAssertEqual(Handoff.weight(of: ""), 0)
        XCTAssertTrue((270...271).contains(Handoff.weight(of: String(repeating: "a", count: 1_000))))
        XCTAssertEqual(Handoff.weight(of: String(repeating: "가", count: 1_000)), 1_500)
        XCTAssertEqual(Handoff.weight(of: String(repeating: "é", count: 10) + String(repeating: "я", count: 10)), 9)
        // A page in English is asked with the fullest first, and has the others to fall back on.
        let wordy = wordy
        let english = Handoff.briefs(title: "Tides", url: page, reading: wordy.reading)
        XCTAssertEqual(english.count, 3)
        XCTAssertEqual(english.first, Handoff.brief(title: "Tides", url: page, reading: wordy.reading))
        // One in Korean starts from a brief that fits what the model reads at once.
        var blocks: [PageBlock] = []
        for number in 1...20 {
            blocks.append(PageBlock(kind: .heading, level: 2, text: "## 제목 \(number)", start: "제목 \(number)"))
            blocks.append(PageBlock(text: String(repeating: "가습기는 물을 데워 김을 냅니다. ", count: 20)))
        }
        var korean = PageReading(blocks: blocks)
        korean.facts.description = String(repeating: "쓰기 쉽고 관리가 편한 생활가전을 만듭니다. ", count: 12)
        let tried = Handoff.briefs(title: "가습기", url: page, reading: korean)
        XCTAssertEqual(tried.count, 2)
        XCTAssertGreaterThan(Handoff.weight(of: Handoff.brief(title: "가습기", url: page, reading: korean)), 2_400)
        for brief in tried.dropLast() { XCTAssertLessThanOrEqual(Handoff.weight(of: brief), 2_400) }
        XCTAssertEqual(tried.last, Handoff.brief(title: "가습기", url: page, reading: korean, shortened: 2))
        // The shortest is asked whatever it weighs: something is.
        XCTAssertEqual(Handoff.briefs(title: "가습기", url: page, reading: korean, room: 10),
                       [Handoff.brief(title: "가습기", url: page, reading: korean, shortened: 2)])
    }

    func testTheBriefShowsThePageWholeBeforeItShowsItClose() {
        let reading = PageReading(blocks: [
            PageBlock(kind: .heading, level: 1, text: "# Forma", start: "Forma"), PageBlock(text: "Design together."),
            PageBlock(text: "[Start for free](https://example.org/signup)", plain: 14, links: 1, linked: 14, start: "Start for free"),
            PageBlock(kind: .heading, level: 3, text: "### Frames", start: "Frames"),
            // A picture's description is of the picture: what the section says comes first.
            PageBlock(text: "![A frame laid out](https://example.org/f.png)", plain: 17, start: "A frame laid out"),
            PageBlock(text: String(repeating: "w", count: 150)),
            PageBlock(kind: .heading, level: 4, text: "#### Deep", start: "Deep"), PageBlock(text: String(repeating: "w", count: 30)),
            PageBlock(kind: .heading, level: 2, text: "## [Pricing](https://example.org/p)", start: "Pricing"),
            PageBlock(text: "[Video, 1:30]", note: true), PageBlock(text: String(repeating: "w", count: 250)), PageBlock(text: "12 EUR."),
            PageBlock(kind: .heading, level: 3, text: "### Team", start: "Team"),
            // What the page calls comments, and its foot, are not what it is about.
            PageBlock(kind: .heading, level: 2, text: "## 12 Comments", start: "12 Comments"), PageBlock(text: "A reply."),
            PageBlock(kind: .heading, level: 2, text: "## Below", hint: .footer, start: "Below"), PageBlock(text: "The site's notices.", hint: .footer),
        ])
        XCTAssertEqual(Handoff.digest(of: reading, most: 14, each: 120), [
            "- Forma: Design together. Start for free", "- Frames: " + String(repeating: "w", count: 120) + "…",
            "- Pricing: " + String(repeating: "w", count: 120) + "…", "- Team",
        ])
        // With room for two, the two that say what the page is made of; with less of each, less.
        XCTAssertEqual(Handoff.digest(of: reading, most: 2, each: 10), ["- Forma: Design…", "- Pricing: wwwwwwwwww…"])
        XCTAssertEqual(Handoff.digest(of: reading, most: 3, each: 120).map { $0.prefix(8) }, ["- Forma:", "- Frames", "- Pricin"])
        let brief = Handoff.brief(title: "Forma", url: page, reading: reading)
        XCTAssertTrue(brief.contains("Its sections, each with how it starts:\n- Forma: Design together. Start for free\n- Frames: "))
        XCTAssertTrue(brief.contains("\n- Team\nIts text starts:\n" + String(repeating: "w", count: 250)))
        XCTAssertFalse(brief.contains("Parts to pick from"))
        XCTAssertFalse(brief.contains("Comments") || brief.contains("Below"))
        // A page with no writing starts with whatever it has, a line of the reader's own apart.
        let short = PageReading(blocks: [PageBlock(kind: .heading, level: 1, text: "# Forma", start: "Forma"), PageBlock(text: "[Video]", note: true),
                                         PageBlock(text: "Design together.")])
        XCTAssertTrue(Handoff.brief(title: "", url: page, reading: short).hasSuffix("Its sections, each with how it starts:\n- Forma: Design together.\nIts text starts:\nDesign together."))
    }

    func testTheBriefSaysWhatTheModelLeftOutOrGotWrong() throws {
        // The language, where the page's script says which: the model answered in English by habit, and turned a humidifier into an air purifier.
        func reading(_ words: String, times: Int = 10) -> PageReading {
            PageReading(blocks: [PageBlock(kind: .heading, level: 1, text: "# One", start: "One")] + (0..<times).map { _ in PageBlock(text: words) })
        }
        XCTAssertEqual(Handoff.language(of: reading("에어메이드 가열식 스텐 가습기 더 문 4L THE MOON AMH-401M")), "Korean")
        XCTAssertEqual(Handoff.language(of: reading("新しいカメラと、二日もつバッテリー。Lumen 5 Pro")), "Japanese")
        XCTAssertNil(Handoff.language(of: reading("A battery for two days, and a camera that sees in the dark.")))
        // A page in English that quotes a Korean name is in English, and so is one with a line of Korean and no more.
        XCTAssertNil(Handoff.language(of: reading("The film 진짜 무서운 공포 영화 월드컵 was watched by a great many people in its first week online.")))
        XCTAssertNil(Handoff.language(of: reading("가습기", times: 1)))
        let story = reading("에어메이드 가열식 스텐 가습기 더 문 4L THE MOON AMH-401M 499,000원")
        let korean = Handoff.brief(title: "에어메이드", url: page, reading: story)
        XCTAssertTrue(korean.contains("\nIts language: Korean. Write `about` in Korean.\n"))
        XCTAssertFalse(Handoff.brief(title: "Forma", url: page, reading: reading("Design together.")).contains("Its language"))

        // The name the page is shared by, where the one shown is another.
        var film = reading("113K views")
        film.facts.titled = "진짜 무서운  공포 영화 월드컵"
        XCTAssertTrue(Handoff.brief(title: "The Real Scariest Horror Movie World Cup", url: page, reading: film)
            .contains("\nTitle: The Real Scariest Horror Movie World Cup\nIts title where it is shared: 진짜 무서운 공포 영화 월드컵\n"))
        film.facts.titled = "the real scariest horror movie world cup"
        XCTAssertFalse(Handoff.brief(title: "The Real Scariest Horror Movie World Cup", url: page, reading: film).contains("where it is shared"))

        // What it costs, on a page that presents or sells something: the first two amounts, as the page writes them.
        var phone = PageReading(blocks: [
            PageBlock(kind: .heading, level: 1, text: "# Lumen 5 Pro", start: "Lumen 5 Pro"), PageBlock(kind: .item, text: "- From $999"),
            PageBlock(kind: .heading, level: 2, text: "## Battery", start: "Battery"), PageBlock(text: "Up to 31 hours. ₩1,990,000부터, or 499,000원 a month."),
            PageBlock(kind: .heading, level: 2, text: "## Camera", start: "Camera"), PageBlock(text: "Costs €5 more."),
        ])
        phone.facts.headings = ["Lumen 5 Pro", "Battery", "Camera"]
        phone.facts.characters = 400
        XCTAssertEqual(Handoff.prices(in: phone), ["From $999", "₩1,990,000부터"])
        XCTAssertEqual(Handoff.prices(in: phone, most: 5), ["From $999", "₩1,990,000부터", "499,000원", "€5"])
        XCTAssertTrue(Handoff.brief(title: "Lumen", url: page, reading: phone).contains("\nThe first prices it shows: From $999, ₩1,990,000부터\n"))
        // Not a number that is no price, nor a price in what the page calls comments or its foot, nor in a line of the reader's own.
        let none = PageReading(blocks: [
            PageBlock(text: "3원칙, 2026.10.06., 1588-0000, 4L, 31 hours, $ and 원."), PageBlock(text: "$5 off", hint: .comments),
            PageBlock(text: "9,900원", hint: .footer), PageBlock(text: "[Video: $1 film]", note: true),
        ])
        XCTAssertEqual(Handoff.prices(in: none), [])
        // A price in Korean with what the sentence hangs on it, and one counted in 만.
        func priced(_ words: String) -> [String] {
            Handoff.prices(in: PageReading(blocks: [PageBlock(text: words)]), most: 4)
        }
        XCTAssertEqual(priced("가격은 499,000원입니다. 지금은 449,000원부터, 월 29만 원에."), ["499,000원", "449,000원부터", "29만 원"])
        XCTAssertEqual(priced("3원칙과 2원화, 그리고 12달러와 1500원."), ["12달러", "1500원"])
        // How dear a restaurant is, and how it is rated, is no price: a sign after another is not an amount's.
        XCTAssertEqual(priced("Bakery $$ 4.2 (8,912 reviews), coffee from $4.50"), ["from $4.50"])
        // And not on a page that is writing: a sum an article names is not what the article costs.
        var story2 = PageReading(blocks: [PageBlock(text: String(repeating: "The deal was worth $2 billion. ", count: 40))])
        story2.facts.characters = 1_200
        story2.facts.long = 1
        story2.facts.written = 1_200
        XCTAssertFalse(Handoff.brief(title: "News", url: page, reading: story2).contains("prices"))
    }

    func testTheSummaryGoesOnlyAsFarAsThePageBearsItOut() {
        var story = PageReading(blocks: [
            PageBlock(kind: .heading, level: 4, text: "#### THE MOON 가습기", start: "THE MOON 가습기"),
            PageBlock(text: "**에어메이드 가열식 스텐 가습기 더 문 4L THE MOON AMH-401M**", start: "에어메이드 가열식 스텐 가습기 더 문 4L THE MOON AMH-401M"),
            PageBlock(text: "499,000원"), PageBlock(text: "[생활가전](https://example.org/home)", plain: 4, links: 1, linked: 4, start: "생활가전"),
        ])
        story.facts.description = "우리는 쓰기 쉽고 관리가 편한 생활가전을 만듭니다."
        // The page's own words, with a longer form of one of them and a number written as the page writes it.
        let right = "이 페이지는 생활가전을 판매합니다. 에어메이드 가열식 스텐 가습기 더 문 4L THE MOON AMH-401M은 499,000원입니다."
        XCTAssertEqual(Handoff.grounded(right, in: story, title: "에어메이드"), right)
        // A sentence with a number the page does not have goes, and the rest stays.
        XCTAssertEqual(Handoff.grounded("에어메이드 가습기는 499,000원입니다. 에어메이드 가습기는 399,000원입니다.", in: story, title: ""), "에어메이드 가습기는 499,000원입니다.")
        // A summary in another language than the page has none of its words: an air purifier, where the page sells a humidifier.
        XCTAssertEqual(Handoff.grounded("This page sells an air purifier with a stainless tank.", in: story, title: "에어메이드"), "")

        let film = PageReading(blocks: [PageBlock(kind: .heading, level: 2, text: "## The Real Scariest Horror Movie World Cup",
                                                   start: "The Real Scariest Horror Movie World Cup"), PageBlock(text: "3.7K likes 113K views")])
        // What the model supposed of a film it could not see.
        XCTAssertEqual(Handoff.grounded("The video is a horror movie world cup. It features humorous commentary and clips from several films.",
                                        in: film, title: "YouTube"), "The video is a horror movie world cup.")
        // Words that only frame a summary bear nothing out, and a summary of them alone does not go.
        XCTAssertEqual(Handoff.grounded("This page describes what this website offers.", in: film, title: ""), "")
        XCTAssertEqual(Handoff.grounded("이 페이지는 정보를 제공합니다.", in: story, title: ""), "")
        // Nor do they carry a name the page does not have.
        XCTAssertEqual(Handoff.grounded("이 페이지는 공기청정기를 판매합니다.", in: story, title: "에어메이드"), "")
        // A word the page has a longer or a shorter form of counts: "movies" for "movie", "scary" does not for "scariest".
        XCTAssertEqual(Handoff.grounded("Horror movies compete in a world cup.", in: film, title: ""), "Horror movies compete in a world cup.")
        XCTAssertEqual(Handoff.grounded("", in: film, title: ""), "")
        // Japanese and Chinese do not part their words with spaces: let through unheld.
        XCTAssertEqual(Handoff.grounded("このページは新しいカメラを紹介します。", in: film, title: ""), "このページは新しいカメラを紹介します。")

        // A full stop inside a number or a name ends no sentence.
        XCTAssertEqual(Handoff.sentences(of: "Version 4.2 is out. See example.org today! Is it? 끝났습니다。 and a rest"),
                       ["Version 4.2 is out.", "See example.org today!", "Is it?", "끝났습니다。", "and a rest"])
        // Japanese and Chinese write no space after a sentence.
        XCTAssertEqual(Handoff.sentences(of: "これはペンです。それは本です！本当？はい"), ["これはペンです。", "それは本です！", "本当？", "はい"])

        // A number is the page's however it is parted, and in the parts the page has it in; not where only a part of it is the page's.
        var dated = story
        dated.blocks.append(PageBlock(text: "작성일 2026.10.06. 조회수 30,717"))
        for (sentence, holds) in [("에어메이드 가습기는 499000원입니다.", true), ("에어메이드 가습기는 499,000원입니다.", true), ("에어메이드 가습기는 499원입니다.", true),
                                  ("에어메이드 가습기는 2026년 10월 6일에 나왔습니다.", true), ("에어메이드 가습기 조회수는 30717입니다.", true),
                                  ("에어메이드 가습기는 4990000원입니다.", false), ("에어메이드 가습기는 2027년에 나왔습니다.", false),
                                  ("에어메이드 가습기는 AMH-402M입니다.", false)] {
            XCTAssertEqual(Handoff.grounded(sentence, in: dated, title: "") == sentence, holds, sentence)
        }
        XCTAssertEqual(Handoff.Vocabulary.figures(in: "499,000원, 4.2 and 06, 1. 끝").map(\.whole), ["499000", "42", "6", "1"])
        XCTAssertEqual(Handoff.Vocabulary.figures(in: "2026.10.06.").map(\.runs), [["2026", "10", "6"]])
    }

    func testASummaryStopsAtASentence() {
        let one = String(repeating: "a", count: 199) + "."
        let two = String(repeating: "b", count: 199) + "."
        let three = String(repeating: "c", count: 199) + "."
        XCTAssertEqual(Handoff.sentences(of: one + " " + two, upTo: 500), one + " " + two)
        // The sentence that does not fit is left out, with those after it: never half a word.
        XCTAssertEqual(Handoff.sentences(of: one + " " + two + " " + three + " Short.", upTo: 500), one + " " + two)
        // A first sentence longer than the room is cut at a word, and says so.
        let long = String(repeating: "word ", count: 150) + "end."
        XCTAssertEqual(Handoff.sentences(of: long, upTo: 500), String(repeating: "word ", count: 99) + "word…")
        XCTAssertEqual(Handoff.summaryRoom, 500)
    }

    func testATranscriptIsReadFromWhatTheSitesReaderGave() {
        // Anything that is not an answer is none: the page wrote this, by way of the app's script.
        for nothing in [nil, "read", 7, ["state": "none"], ["state": "odd"], ["lines": [["0:00", "Words"]]], ["state": "read"],
                        ["state": "read", "lines": "many"], ["state": "read", "lines": [["0:00", " "], ["0:01"], "x", 3]]] as [Any?] {
            XCTAssertEqual(Transcript.answer(nothing), .none)
        }
        XCTAssertEqual(Transcript.answer(["state": "absent"]), .absent(captions: nil))
        XCTAssertEqual(Transcript.answer(["state": "absent", "captions": true]), .absent(captions: true))
        XCTAssertEqual(Transcript.answer(["state": "absent", "captions": false]), .absent(captions: false))
        // Another of the site's pages is worth asking unless this one says the video has no captions at all.
        XCTAssertTrue(Transcript.Answer.absent(captions: nil).looksElsewhere && Transcript.Answer.absent(captions: true).looksElsewhere)
        XCTAssertFalse(Transcript.Answer.absent(captions: false).looksElsewhere || Transcript.Answer.none.looksElsewhere)
        XCTAssertFalse(Transcript.Answer.read(Transcript(lines: [])).looksElsewhere)

        let said: [String: Any] = ["state": "read", "generated": true, "lines": [
            ["0:00", " The sea  rises\nand falls. "], ["soon", "Words with no time."], ["1:02:03", "An hour in."], ["0:1", "A time that is none."],
            [3, "A number for a time."], ["0:05"], "not a line", ["0:07", ""], ["0:08", 5], ["12:34", "Twelve minutes in."], ["1:2:03", "No."],
        ] as [Any]]
        XCTAssertEqual(Transcript.answer(said), .read(Transcript(lines: [
            .init(time: "0:00", words: "The sea rises and falls."), .init(words: "Words with no time."), .init(time: "1:02:03", words: "An hour in."),
            .init(words: "A time that is none."), .init(words: "A number for a time."), .init(time: "12:34", words: "Twelve minutes in."), .init(words: "No."),
        ], cut: false, generated: true)))
        // Within limits: a line of any length is 2,000 characters of it, and there are 20,000 lines at the most.
        let long: [String: Any] = ["state": "read", "cut": true, "lines": (0..<20_050).map { _ in ["0:00", String(repeating: "w", count: 2_100)] }]
        guard case .read(let transcript) = Transcript.answer(long) else { return XCTFail("not read") }
        XCTAssertEqual(transcript.lines.count, 20_000)
        XCTAssertEqual(transcript.lines[0].words.count, 2_000)
        XCTAssertTrue(transcript.cut && !transcript.generated)
    }

    func testATranscriptGoesAsParagraphsEachLedByItsTime() {
        // Thirty lines of 100 characters: five to a paragraph of 600, each begun with the time of its first.
        let lines = (0..<30).map { Transcript.Line(time: "\($0):00", words: "Line \($0) " + String(repeating: "w", count: 100 - "Line \($0) ".count)) }
        let blocks = Transcript(lines: lines).blocks(room: 100_000)
        XCTAssertEqual(blocks.count, 7)
        XCTAssertEqual(blocks[0], PageBlock(kind: .heading, level: 2, text: "## Transcript", hint: .transcript, start: "Transcript"))
        XCTAssertTrue(blocks[1].text.hasPrefix("0:00 Line 0 w") && blocks[1].text.contains("w Line 4 w") && !blocks[1].text.contains("Line 5 "))
        XCTAssertTrue(blocks[2].text.hasPrefix("5:00 Line 5 w") && blocks[6].text.hasPrefix("25:00 Line 25 w"))
        XCTAssertEqual(blocks[1].text.count, 5 + 5 * 100 + 4)
        XCTAssertTrue(blocks.dropFirst().allSatisfy { $0.hint == .transcript && $0.kind == .paragraph && $0.isProse && !$0.note && $0.text.count <= 610 })
        // A line with no time begins with its words, and one longer than a paragraph is a paragraph of its own.
        let odd = Transcript(lines: [.init(words: "No time."), .init(time: "0:09", words: String(repeating: "x", count: 700)), .init(time: "0:20", words: "After.")])
        XCTAssertEqual(odd.blocks(room: 100_000).dropFirst().map(\.text), ["No time.", "0:09 " + String(repeating: "x", count: 700), "0:20 After."])
        // No more than there is room for: what fits, then a line that says it goes on. The same where the site's reader stopped short.
        let short = Transcript(lines: lines).blocks(room: 1_200)
        XCTAssertEqual(short.map(\.text.count).reduce(0, +) + 2 * short.count - short.last!.text.count - 2 <= 1_200, true)
        XCTAssertEqual(short.last, PageBlock(text: "[The transcript goes on past here.]", hint: .transcript, note: true))
        XCTAssertTrue(short.count >= 3 && short[1].text.hasPrefix("0:00 Line 0 "))
        XCTAssertEqual(Transcript(lines: Array(lines.prefix(2)), cut: true).blocks(room: 100_000).last?.text, "[The transcript goes on past here.]")
        // Nothing where there is nothing, or no room for a line.
        XCTAssertEqual(Transcript(lines: []).blocks(room: 100_000), [])
        XCTAssertEqual(Transcript(lines: lines).blocks(room: 40), [])
    }

    func testAPageGainsItsTranscriptAfterItsTextAndBeforeItsNotes() {
        let transcript = Transcript(lines: [.init(time: "0:00", words: "The sea rises and falls twice a day."), .init(time: "0:21", words: "This lamp is the moon.")],
                                    generated: true)
        // A page whose transcript panel stood open: the reader's own walk took its lines, a block each, with the time as it is read out.
        let reading = PageReading(blocks: [
            PageBlock(kind: .heading, level: 1, text: "# Tides", start: "Tides"), PageBlock(text: "Harbour School, 18,204 views.[^1]"),
            PageBlock(kind: .heading, level: 2, text: "## Transcript", start: "Transcript"), PageBlock(text: "0 seconds", hint: .transcript),
            PageBlock(text: "The sea rises and falls twice a day.", hint: .transcript),
            PageBlock(kind: .heading, level: 2, text: "## Up next", start: "Up next"), PageBlock(text: "[Springs and neaps](https://example.org/s)", plain: 17, links: 1, linked: 17),
            PageBlock(text: "[^1]: Counted in March.", hint: .footnotes),
        ])
        let whole = reading.adding(transcript)
        XCTAssertEqual(whole.blocks.map(\.text), ["# Tides", "Harbour School, 18,204 views.[^1]", "## Up next", "[Springs and neaps](https://example.org/s)",
                                                  "## Transcript", "0:00 The sea rises and falls twice a day. This lamp is the moon.", "[^1]: Counted in March."])
        XCTAssertEqual(whole.spoken, PageReading.Spoken(lines: 2, generated: true, cut: false))
        XCTAssertEqual(whole.facts, reading.facts)
        // Within the limit for the page and the transcript together, and said where it did not all fit.
        let long = Transcript(lines: (0..<200).map { .init(time: "\($0):00", words: String(repeating: "w", count: 100)) })
        let cut = reading.adding(long, limit: 2_000)
        XCTAssertLessThanOrEqual(cut.blocks.filter { !$0.note }.reduce(0) { $0 + $1.characters + 2 }, 2_000)
        XCTAssertEqual(cut.spoken, PageReading.Spoken(lines: 200, generated: false, cut: true))
        XCTAssertEqual(cut.blocks.suffix(2).map(\.text), ["[The transcript goes on past here.]", "[^1]: Counted in March."])
        // With nothing to add, the page is as it was read: its own transcript stays.
        XCTAssertEqual(reading.adding(Transcript(lines: [])), reading)
        XCTAssertEqual(reading.adding(long, limit: 100), reading)
        XCTAssertNil(reading.spoken)
        // The model is shown the page and not what is said in its recording.
        let brief = Handoff.brief(title: "Tides", url: page, reading: whole)
        XCTAssertTrue(brief.contains("\n- Transcript\n"), brief)
        XCTAssertFalse(brief.contains("The sea rises"))
        XCTAssertTrue(brief.contains("Its text starts:\nHarbour School, 18,204 views."))
    }

    func testTheFileIsNamedForThePage() {
        XCTAssertEqual(Handoff.fileName(title: "Field notes: tides / moon?", url: page), "Field notes tides moon.md")
        XCTAssertEqual(Handoff.fileName(title: "  \n ", url: page), "example.org.md")
        XCTAssertEqual(Handoff.fileName(title: "...hidden", url: page), "hidden.md")
        XCTAssertEqual(Handoff.fileName(title: "피그마 강좌 | 디자인", url: page), "피그마 강좌 디자인.md")
        let long = Handoff.fileName(title: String(repeating: "tide ", count: 40), url: page)
        XCTAssertLessThanOrEqual(long.count, 83)
        XCTAssertTrue(long.hasSuffix(".md"))
        // A file system counts a name in bytes: 80 characters of Hangul fit, 70 emoji or a family of them do not.
        let hangul = String(repeating: "가", count: 90)
        XCTAssertEqual(Handoff.fileName(title: hangul, url: page), String(repeating: "가", count: 80) + ".md")
        for title in [String(repeating: "🌊", count: 70), String(repeating: "👩‍👩‍👧‍👦", count: 30)] {
            let name = Handoff.fileName(title: title, url: page)
            XCTAssertLessThanOrEqual(name.utf8.count, 255, name)
            XCTAssertTrue(name.hasSuffix(".md"))
            // Cut between characters, never inside one.
            XCTAssertTrue(title.hasPrefix(name.dropLast(3)), name)
        }
        // What turns text backwards goes, so a name can't pass for another.
        XCTAssertEqual(Handoff.fileName(title: "notes\u{202E}dm.exe", url: page), "notes dm.exe.md")
    }

    func testTheScriptShipsAsOneFunction() {
        // Page.markdown gives it a name and calls it, so it has to be an expression and nothing after.
        let script = Scripts.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(script.hasSuffix("})"), "markdown.js must end with the function, not a call or a semicolon")
        XCTAssertTrue(script.contains("(function (limit) {"))
        XCTAssertTrue(Scripts.markdownCall.hasSuffix("return run(limit);"))
    }
}
