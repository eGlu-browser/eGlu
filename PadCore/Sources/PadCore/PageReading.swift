import Foundation

/// What the page itself calls the part a block is in (markdown.js): told
/// from the container's own name, its ARIA label and role, its id and
/// class, and from a heading that says nothing else (PageReading.hint).
/// A hint is a claim by the page, right most of the time and wrong some of
/// it, so no rule in HandoffCompose rests on one alone.
public enum PageHint: String, Sendable, CaseIterable {
    case comments, related, legal, newsletter, share, contents, price, faq, transcript, review
    /// A foot the page has inside its content (a box it calls its footer): the shop's notices under a product's story.
    case footer
    /// The notes the text points to, read by the script from wherever the page keeps them.
    case footnotes
}

/// One block of a page as Handoff's reader gives it: its Markdown, and what
/// the walk knew of it.
public struct PageBlock: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case heading, paragraph, item, quote, table, code, rule
    }

    public var kind: Kind
    /// 1 to 6 for a heading, 0 for anything else.
    public var level: Int
    /// The block as Markdown.
    public var text: String
    public var characters: Int
    /// How long its words are without Markdown: a link's address is no part of what a block says.
    public var plain: Int
    /// Links in it, and the characters inside them.
    public var links: Int
    public var linked: Int
    public var hint: PageHint?
    /// The run of repeated siblings it is in (search results, cards,
    /// replies), and which of them.
    public var group: Int?
    public var item: Int?
    /// Whether any of it showed in the window when the page was read.
    public var onScreen: Bool
    /// Whether the person's selection touches it.
    public var selected: Bool
    /// Its first words without Markdown, where that differs from its text:
    /// always for a heading, and for a block with links, emphasis or a list's mark.
    public var start: String?
    /// Its first link's address.
    public var link: String?
    /// It has words of the reader's own in it, in square brackets, where
    /// something of the page was not read or is said of it: a film, a frame
    /// from another site, a tab's name, what is chosen.
    public var note: Bool
    /// How many of its letters are Korean, Japanese or Chinese, each of
    /// which says what two or three of English do (isProse).
    public var wide: Int

    public init(kind: Kind = .paragraph, level: Int = 0, text: String, plain: Int? = nil, links: Int = 0, linked: Int = 0,
                hint: PageHint? = nil, group: Int? = nil, item: Int? = nil, onScreen: Bool = false, selected: Bool = false,
                start: String? = nil, link: String? = nil, note: Bool = false) {
        self.kind = kind
        self.level = level
        self.text = text
        self.characters = text.count
        self.plain = min(plain ?? text.count, text.count)
        self.links = links
        self.linked = linked
        self.hint = hint
        self.group = group
        self.item = item
        self.onScreen = onScreen
        self.selected = selected
        self.start = start
        self.link = link
        self.note = note
        wide = PageBlock.wide(in: text)
    }

    /// The letters of Korean, Japanese or Chinese in a block's words: not
    /// those in the addresses its links go to, which are written with the
    /// letters of their own language (markdown.js) and are no words.
    static func wide(in text: String) -> Int {
        var count = 0
        var address = false
        var last: Unicode.Scalar = " "
        for scalar in text.unicodeScalars {
            if address {
                if scalar == ")" || scalar == "\n" { address = false }
            } else if scalar == "(", last == "]" {
                address = true
            } else if isWide(scalar) {
                count += 1
            }
            last = scalar
        }
        return count
    }

    /// A letter of Hangul, kana or a Chinese character.
    static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7A3: return true
        default: return false
        }
    }

    /// Writing to be read, not a label: a paragraph, a list item or a
    /// quotation of 200 characters or more, which Handoff keeps whole
    /// whatever it takes the page for. By its words: three links with
    /// long addresses are 200 characters of Markdown and no writing. A
    /// letter of Korean, Japanese or Chinese counts as two, as the reader
    /// counts it (markdown.js): a paragraph of a hundred of them is one.
    public var isProse: Bool {
        plain + min(wide, plain) >= PageReading.long && (kind == .paragraph || kind == .item || kind == .quote)
    }

    /// Its words without Markdown, as far as the reader gave them.
    public var words: String {
        start ?? text
    }

    /// A heading's own words.
    public var title: String {
        (start ?? String(text.drop { $0 == "#" || $0 == " " })).trimmingCharacters(in: .whitespaces)
    }

    /// From what the script gave: anything missing is the plainest it can
    /// be, and no number is more than the block's text has room for, so
    /// that nothing added up from blocks can be more than a page is.
    init?(_ said: [String: Any]) {
        guard let text = said["text"] as? String, !text.isEmpty else { return nil }
        let most = text.utf16.count
        func counted(_ key: String) -> Int {
            min(most, max(0, said[key] as? Int ?? 0))
        }
        self.init(kind: (said["kind"] as? String).flatMap(Kind.init(rawValue:)) ?? .paragraph,
                  level: min(6, max(0, said["level"] as? Int ?? 0)), text: text, plain: said["plain"] is Int ? counted("plain") : nil,
                  links: counted("links"), linked: counted("linked"),
                  hint: (said["hint"] as? String).flatMap(PageHint.init(rawValue:)),
                  group: said["group"] as? Int, item: said["item"] as? Int,
                  onScreen: said["onScreen"] as? Bool ?? false, selected: said["selected"] as? Bool ?? false,
                  start: said["start"] as? String, link: said["link"] as? String, note: said["note"] as? Bool ?? false)
        if kind == .heading, level == 0 { level = 1 }
        if kind != .heading { level = 0 }
        // As the script counted it: its characters are what its limits are in.
        if counted("characters") > 0 { characters = counted("characters") }
    }
}

/// A thing the page declares to search engines (schema.org, as JSON-LD):
/// what kinds of thing it is, whether the page says it is the page's own,
/// and the few facts a reader would ask of it.
public struct PageThing: Equatable, Sendable {
    public var types: [String]
    public var main: Bool
    public var facts: [String: String]

    public init(types: [String], main: Bool = false, facts: [String: String] = [:]) {
        self.types = types
        self.main = main
        self.facts = facts
    }

    public func isA(_ types: Set<String>) -> Bool {
        self.types.contains { types.contains($0.lowercased()) }
    }
}

/// What the person had selected, read on its own, and the words around a
/// place the reader's walk never came to: a selection in a part left out,
/// or a window past where a very long page was read to.
public struct PageFocus: Equatable, Sendable {
    public var selection: String
    public var excerpt: String

    public init(selection: String = "", excerpt: String = "") {
        self.selection = selection
        self.excerpt = excerpt
    }
}

/// A page as Handoff's reader gives it (markdown.js): its blocks in order,
/// what was counted for its kind, what it declares, and where the person
/// was in it.
///
/// Everything in it comes from the page, by way of a script of the app's
/// own. It is read leniently and within limits: a block the script gave
/// oddly is taken as a plain paragraph, and past 3,000 blocks the script
/// has already made the rest one.
public struct PageReading: Equatable, Sendable {
    public var blocks: [PageBlock]
    public var facts: PageFacts
    public var things: [PageThing]
    public var focus: PageFocus?
    /// The page went on past what was read.
    public var truncated: Bool
    /// What is said in the page's recording was added to its text, by the site's own reader (Transcript).
    public var spoken: Spoken?

    /// From this many characters a paragraph is writing (PageBlock.isProse).
    public static let long = 200

    public init(blocks: [PageBlock], facts: PageFacts = PageFacts(), things: [PageThing] = [], focus: PageFocus? = nil,
                truncated: Bool = false) {
        self.blocks = blocks
        self.facts = facts
        self.things = things
        self.focus = focus
        self.truncated = truncated
    }

    /// From what the script gave back. Nil where there is nothing to read.
    public init?(_ said: [String: Any]) {
        // One by one: a thing in the list that is no block must not cost the blocks beside it.
        let blocks = (said["blocks"] as? [Any] ?? []).prefix(3_000).compactMap { ($0 as? [String: Any]).flatMap(PageBlock.init) }
        guard !blocks.isEmpty else { return nil }
        self.blocks = blocks
        facts = PageFacts(said["facts"] as? [String: Any] ?? [:])
        things = (said["things"] as? [Any] ?? []).prefix(12).compactMap { one in
            guard let thing = one as? [String: Any], let types = thing["types"] as? [String], !types.isEmpty else { return nil }
            let facts = (thing["facts"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            return PageThing(types: types, main: thing["main"] as? Bool ?? false, facts: facts)
        }
        if let focus = said["focus"] as? [String: Any] {
            let selection = String((focus["selection"] as? String ?? "").prefix(4_000))
            let excerpt = String((focus["excerpt"] as? String ?? "").prefix(4_000))
            self.focus = selection.isEmpty && excerpt.isEmpty ? nil : PageFocus(selection: selection, excerpt: excerpt)
        }
        truncated = said["truncated"] as? Bool ?? false
    }

    /// The page as one text, every block in order.
    public var text: String {
        blocks.map(\.text).joined(separator: "\n\n")
    }

    /// Whether the person had something selected.
    public var hasSelection: Bool {
        !(focus?.selection.isEmpty ?? true)
    }

    // MARK: Headings that say what follows is

    /// What a heading says of the blocks under it, where it says nothing
    /// else: "Comments", "12 Comments", "Related articles", "FAQ". The
    /// whole heading, not a word in it: "Related work" heads a section of a
    /// paper, and "Comments on the method" a section of an essay. What a
    /// heading adds in brackets at its end is a note on it and not part of
    /// its name: "Transcript (64 languages)".
    public static func hint(ofHeading title: String) -> PageHint? {
        let named = title.replacingOccurrences(of: #"\s*\([^()]*\)\s*$"#, with: "", options: .regularExpression)
        var words = named.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").map(String.init)
        // A count before or after it: "12 comments", "comments 12".
        var counted = title.range(of: #"\(\s*\d[\d,.]*\s*\)\s*$"#, options: .regularExpression) != nil
        if let first = words.first, Int(first) != nil { words.removeFirst() }
        if let last = words.last, Int(last) != nil {
            words.removeLast()
            counted = true
        }
        let name = words.joined(separator: " ")
        // A word that heads a part of the writing as often as what readers wrote under it
        // ("Discussion", of a paper's results): only with a count after it, in brackets or not.
        // A number before it is the section's own ("4 Discussion"), and a paper has those.
        if onlyCounted.contains(name), !counted { return nil }
        return headings[name]
    }

    private static let onlyCounted: Set<String> = ["discussion", "responses", "의견"]

    private static let headings: [String: PageHint] = {
        let said: [(PageHint, [String])] = [
            (.comments, ["comments", "comment", "responses", "replies", "discussion", "댓글", "전체 댓글", "댓글 목록", "댓글목록", "의견"]),
            (.related, ["related", "related articles", "related posts", "related stories", "related content", "related links",
                        "you may also like", "you might also like", "recommended", "recommended for you", "more like this",
                        "read more", "read next", "more stories", "up next", "관련 기사", "관련기사", "관련 뉴스", "관련뉴스", "관련 글", "관련글",
                        "연관 기사", "연관기사", "추천 글", "추천글", "추천 기사", "추천기사", "추천", "많이 본 뉴스", "많이 본 기사",
                        "많이 본 글", "인기 기사", "인기기사", "인기 글", "인기글", "랭킹 뉴스", "랭킹뉴스", "함께 본 상품",
                        "함께 보면 좋은 글", "이 기사를 본 사람들이 본 기사"]),
            (.legal, ["legal", "disclaimer", "legal notice", "법적 고지", "법적고지"]),
            (.footnotes, ["footnotes", "각주"]),
            (.newsletter, ["newsletter", "subscribe to our newsletter", "뉴스레터"]),
            (.share, ["share", "share this", "share this article", "share this post", "공유", "공유하기"]),
            (.contents, ["contents", "table of contents", "on this page", "in this article", "목차"]),
            (.price, ["pricing", "plans", "plans and pricing", "pricing and plans", "prices", "요금", "요금제", "가격"]),
            (.faq, ["faq", "faqs", "frequently asked questions", "questions and answers", "common questions", "자주 묻는 질문"]),
            (.transcript, ["transcript", "full transcript", "스크립트"]),
            (.review, ["reviews", "customer reviews", "ratings and reviews", "ratings reviews", "testimonials",
                       "what customers say", "what our customers say", "리뷰", "후기", "고객 후기"]),
        ]
        var table: [String: PageHint] = [:]
        for (hint, titles) in said {
            for title in titles { table[title] = hint }
        }
        return table
    }()
}
