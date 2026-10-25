import Foundation

/// How a page that has been read is organised into the file handed off.
///
///      PageReading (markdown.js)
///        blocks[]  kind, Markdown, sizes, hint, group, onScreen, selected
///        facts     counts over the page          things   what it declares
///        focus     the person's selection
///           |
///           |-- Handoff.kind(of:url:)        by counting ----+
///           |-- PageMind.read(brief)         the model, late +--> Handoff.settled --> kind
///           v
///      Handoff.parts(of:)       runs of blocks under one heading with one hint
///      Handoff.role(of:...)     core | supporting | margin | noise
///           v
///      Handoff.compose(...)     core whole, supporting started, margins named, noise left out
///           v
///      Handoff.document(...)    "About this file" (eGlu's words), "From the page" (the page's)
///
/// The rule the rest is built round: a wrong guess never removes writing.
/// Every long paragraph (PageBlock.isProse) outside a part the page itself
/// calls comments, related or legal reaches the file whole, whatever kind
/// the page was taken for. What a wrong kind can cost is
/// short blocks: lists of blurbs, link lists, labels. So a part that is
/// mostly writing is core before any kind's recipe is asked, a trimmed
/// part keeps its long paragraphs, and no kind has a cap on what is core.
extension Handoff {
    /// What a part of the page is to the file.
    public enum Role: String, Sendable {
        /// The page's substance: whole.
        case core
        /// Belongs, but secondary and made of short blocks: started.
        case supporting
        /// Around the substance (comments, related, legal): named, with how it starts.
        case margin
        /// Sharing bars, newsletter boxes, the page's own table of contents: left out.
        case noise
    }

    /// A run of blocks under one heading that share one hint and are, or
    /// are not, the items of one list: the unit a role is given to.
    public struct Part: Equatable, Sendable {
        public var blocks: Range<Int>
        /// Which heading-led stretch of the page it is in, the first 0.
        public var section: Int
        /// The words of the heading over it, empty before the first.
        public var heading: String
        public var hint: PageHint?
        /// The run of repeated siblings its blocks are, where they read as a list (Handoff.lists).
        public var list: Int?
        public var characters = 0
        /// How long its words are without Markdown (PageBlock.plain).
        public var plain = 0
        /// Characters in its long paragraphs.
        public var written = 0
        /// And in those of them that are not mostly links: a row of other posts' titles is long, and is not the page's own writing.
        public var told = 0
        public var links = 0
        public var linked = 0
        public var selected = false
        public var onScreen = false
        /// It has a table or a block of code in it: one thing each, and never a sharing bar's or a list of contents'.
        public var holdsData = false
    }

    /// A part that was set aside, as the file names it.
    public struct Aside: Equatable, Sendable {
        public var name: String
        public var characters: Int
        public var links: Int
        public var start: String

        public init(name: String, characters: Int, links: Int = 0, start: String = "") {
            self.name = name
            self.characters = characters
            self.links = links
            self.start = start
        }
    }

    /// A part the model may be asked to pick (Handoff.candidates).
    public struct Candidate: Equatable, Sendable {
        /// Which part it is (Handoff.parts).
        public var part: Int
        public var name: String
        public var start: String

        public init(part: Int, name: String, start: String = "") {
            self.part = part
            self.name = name
            self.start = start
        }
    }

    /// The page as it goes: its text, and what the file says of how it was put together.
    public struct Composed: Equatable, Sendable {
        public var kind: PageKind
        public var body: String
        /// Parts that were only started.
        public var started = 0
        /// The headings of parts kept whole on a page where others were only started. The page's words.
        public var whole: [String] = []
        public var asides: [Aside] = []
        /// Small boxes left out.
        public var dropped = 0
        /// The items of lists given a line each, and those only counted.
        public var listed = 0
        public var unlisted = 0
        /// Blocks in the file with words of the reader's own in them (PageBlock.note).
        public var notes = 0
        /// A transcript is in the file: what a recording says, on a page that is one's.
        public var transcript = false
        /// What was on screen came first (a web app).
        public var screenFirst = false
        /// The heading the person was at, where the page was scrolled.
        public var onScreen = ""
        public var selection = ""
        public var excerpt = ""
        public var truncated = false

        public init(kind: PageKind, body: String) {
            self.kind = kind
            self.body = body
        }
    }

    // MARK: Limits

    /// How much of a landing page's short blocks goes under each heading, and in all:
    /// of their words, a link's or a picture's address not counted.
    public static let sectionAllowance = 600
    public static let supportingAllowance = 20_000
    /// How much of the short blocks of a product's reviews goes: names, stars, a line each.
    public static let reviewAllowance = 2_000
    /// How many items of lists get a line, and how long a line is.
    public static let listedItems = 60
    public static let itemLine = 160
    /// How much of a part set aside is shown.
    public static let asideStart = 200
    /// The least that is worth leaving out of a part, and saying so.
    public static let leastCut = 300

    private static let noiseHints: Set<PageHint> = [.share, .newsletter, .contents]
    private static let marginHints: Set<PageHint> = [.comments, .related, .legal, .footer]

    // MARK: Hints and lists

    /// What the page calls the part each block is in: what its own
    /// container is called, else what a heading over it says where the
    /// heading says nothing else ("Comments"), down to the next heading of
    /// its own level. The container first, being the nearer: a newsletter
    /// box under the last heading of a page is not what that heading is of.
    ///
    /// A foot is one only at the page's end. Sites call the last row of a
    /// card or of a section its footer too, and what is in one of those is
    /// the page's: an offer in the middle of a phone's page was called so.
    /// So the hint stands only where next to nothing of the page's own
    /// comes after it (200 characters, not counting what is itself called
    /// comments, related, legal, notes or the like).
    public static func hints(in reading: PageReading) -> [PageHint?] {
        var headed: (hint: PageHint, level: Int)?
        var hints: [PageHint?] = reading.blocks.map { block in
            if block.kind == .heading {
                if let over = headed, block.level <= over.level { headed = nil }
                if let hint = PageReading.hint(ofHeading: block.title) { headed = (hint, block.level) }
            }
            return block.hint ?? headed?.hint
        }
        var after = 0
        for index in hints.indices.reversed() {
            if hints[index] == .footer {
                if after > footRoom { hints[index] = nil }
            } else if !(hints[index].map { marginHints.contains($0) || noiseHints.contains($0) || $0 == .footnotes } ?? false) {
                after += reading.blocks[index].plain
            }
        }
        return hints
    }

    /// Under this many characters of words, with no link, what is set aside is not named.
    static let leastAside = 20

    /// Under this many characters of long paragraphs outside its comments, a page has next to no writing of its own.
    static let ownWriting = 400

    /// How much of the page's own may come after its foot: a line, a way back to the top.
    static let footRoom = 200

    /// The runs of repeated siblings that read as lists: five things or
    /// more, small (half of them 400 characters of words or under, a
    /// link's address not counted), most with a link. The page's reader
    /// marks any run of siblings with links, an article's paragraphs
    /// among them; these are the ones made of items.
    public static func lists(in reading: PageReading) -> Set<Int> {
        var groups: [Int: [Int: (characters: Int, linked: Bool)]] = [:]
        for block in reading.blocks {
            guard let group = block.group, let item = block.item else { continue }
            var known = groups[group, default: [:]][item] ?? (0, false)
            known.characters += block.plain
            // A heading that is a link counts no links of its own (markdown.js), and is one all the same.
            known.linked = known.linked || block.links > 0 || block.link != nil
            groups[group, default: [:]][item] = known
        }
        var lists = Set<Int>()
        for (group, items) in groups where items.count >= 5 {
            let sizes = items.values.map(\.characters).sorted()
            let linked = items.values.filter(\.linked).count
            if sizes[sizes.count / 2] <= 400, linked * 10 >= items.count * 6 { lists.insert(group) }
        }
        return lists
    }

    // MARK: Parts and roles

    public static func parts(of reading: PageReading) -> [Part] {
        let hints = hints(in: reading)
        let lists = lists(in: reading)
        var parts: [Part] = []
        var section = 0
        var heading = ""
        for (index, block) in reading.blocks.enumerated() {
            if block.kind == .heading {
                if index > 0 { section += 1 }
                heading = block.title
            } else if hints[index] == .footnotes, index > 0, hints[index - 1] != .footnotes {
                // The notes the text points to stand at the page's end under no heading: not under the last one there was.
                section += 1
                heading = ""
            }
            let list = block.group.flatMap { lists.contains($0) ? $0 : nil }
            if var last = parts.last, last.section == section, last.hint == hints[index], last.list == list {
                last.blocks = last.blocks.lowerBound..<(index + 1)
                parts[parts.count - 1] = last
            } else {
                parts.append(Part(blocks: index..<(index + 1), section: section, heading: heading, hint: hints[index], list: list))
            }
            parts[parts.count - 1].characters += block.characters
            parts[parts.count - 1].plain += block.plain
            if block.isProse {
                parts[parts.count - 1].written += block.characters
                if block.linked * 10 <= block.plain * 6 { parts[parts.count - 1].told += block.characters }
            }
            parts[parts.count - 1].links += block.links
            parts[parts.count - 1].linked += block.linked
            parts[parts.count - 1].holdsData = parts[parts.count - 1].holdsData || block.kind == .table || block.kind == .code
            parts[parts.count - 1].selected = parts[parts.count - 1].selected || block.selected
            parts[parts.count - 1].onScreen = parts[parts.count - 1].onScreen || block.onScreen
        }
        return parts
    }

    /// What a page comes to, for the rules that ask how much of it a part is.
    struct Sums: Equatable {
        var characters = 0
        var written = 0
        /// The page's own writing: its long paragraphs that are not mostly links, outside what it calls comments, related, legal or its foot.
        var own = 0
        /// What the page calls comments, related, legal, sharing, a newsletter or contents, each in all its parts.
        var called: [PageHint: (characters: Int, written: Int)] = [:]
        /// Whether lists of links are set aside: where all of them
        /// together are under a quarter of the page, and the page has
        /// 1,500 characters of writing. On a page that is its links
        /// (a feed, search results) they are the page.
        var setsLinksAside = false

        static func == (one: Sums, other: Sums) -> Bool {
            one.characters == other.characters && one.written == other.written && one.own == other.own && one.setsLinksAside == other.setsLinksAside
                && one.called.mapValues(\.characters) == other.called.mapValues(\.characters)
                && one.called.mapValues(\.written) == other.called.mapValues(\.written)
        }
    }

    /// A list of links: over 60% of its words are links, it has no long
    /// paragraph, and it is 300 characters or more (a link or two is not
    /// worth naming in place of: saying so would cost as much).
    static func isLinks(_ part: Part) -> Bool {
        part.linked * 10 > part.plain * 6 && part.written == 0 && part.characters >= leastCut
    }

    static func sums(of parts: [Part]) -> Sums {
        var sums = Sums()
        var links = 0
        for part in parts {
            sums.characters += part.characters
            sums.written += part.written
            if let hint = part.hint, marginHints.contains(hint) || noiseHints.contains(hint) {
                sums.called[hint, default: (0, 0)].characters += part.characters
                sums.called[hint, default: (0, 0)].written += part.written
            }
            if let hint = part.hint, marginHints.contains(hint) { continue }
            // Nor is what a newsletter box or a sharing bar says the page's own writing.
            if !(part.hint.map(noiseHints.contains) ?? false) { sums.own += part.told }
            if isLinks(part) { links += part.characters }
        }
        sums.setsLinksAside = links * 4 < sums.characters && sums.written >= 1_500
        return sums
    }

    /// What a part is to the file, the first of these that fits:
    ///
    ///     touched by the selection                                        core
    ///     called sharing, newsletter or contents, where all the page
    ///       calls that is under a tenth of it, with no long paragraph,
    ///       and the part has no table or code in it                       noise
    ///     called comments, related or legal
    ///       on a thread (its comments), or where all the page calls
    ///       that is over 40% of its writing, or, of comments, of its
    ///       text (the page is its comments, long or short), or, of
    ///       comments, where the page has next to no writing of its own
    ///       and they are a fifth of it (a board's post of a line or a
    ///       picture, and what was said to it)                             core
    ///       else                                                          margin
    ///     mostly long paragraphs                                          core
    ///     a list of links (Handoff.isLinks), on a page where such
    ///       lists are little of it beside writing (Sums.setsLinksAside)   margin
    ///     what the page's kind makes of the rest                          core or supporting
    static func role(of part: Part, kind: PageKind, page: Sums) -> Role {
        if part.selected || part.hint == .footnotes { return .core }
        // Under a job's posting, the form to apply with and the survey that comes with it (Greenhouse's
        // are on the posting's page) are the board's, and not the posting: named and set aside.
        if kind == .job, isApplication(part.heading) { return .margin }
        if let hint = part.hint {
            let all = page.called[hint] ?? (part.characters, part.written)
            // All of it together, not part by part: a class on a wrapper called the whole of a
            // manual its contents, and under each heading it was a small box with no long paragraph.
            if noiseHints.contains(hint), all.characters * 10 < page.characters, all.written == 0, !part.holdsData { return .noise }
            // In a tool nothing is beside the content: what a board heads "Up next" is a column of it.
            if marginHints.contains(hint), !(kind == .app && hint == .related) {
                if kind == .thread, hint == .comments { return .core }
                // By its text too for comments alone: a page that is mostly related links by
                // its text is a video's or a product's, and they are still round what it is about.
                var isThePage = all.written * 10 > page.written * 4 || (hint == .comments && all.characters * 10 > page.characters * 4)
                if hint == .comments, kind != .media, kind != .product {
                    isThePage = isThePage || (page.own < ownWriting && all.characters * 10 > page.characters * 2)
                }
                return isThePage ? .core : .margin
            }
        }
        if part.written * 2 >= part.characters, part.written > 0 { return .core }
        if page.setsLinksAside, isLinks(part) { return .margin }
        switch kind {
        // A job posting goes whole: what it asks for and what it gives are short lines, and the posting is all of them.
        // A file's parts are all the file, as an article's are all the page.
        case .article, .other, .thread, .listing, .media, .job,
             .document, .slides, .spreadsheet, .data, .archive, .picture, .recording:
            return .core
        case .landing:
            return part.hint == .price || part.hint == .faq ? .core : .supporting
        case .app:
            return part.onScreen ? .core : .supporting
        case .product:
            return part.hint == .review ? .supporting : .core
        }
    }

    /// Whether a heading is one a board puts over its form to apply with,
    /// or over the questions it asks for equal opportunity's sake, in
    /// English and Korean.
    static func isApplication(_ heading: String) -> Bool {
        let words = heading.lowercased().replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        let phrases = ["apply for this", "apply now", "submit your application", "submit application", "application form",
                       "self identification", "equal employment", "equal opportunity", "eeo", "지원서", "지원하기", "입사 지원", "입사지원"]
        return phrases.contains { phrase in
            words == phrase || words.hasPrefix(phrase + " ") || words.contains(" " + phrase + " ") || words.hasSuffix(" " + phrase)
        }
    }

    /// The parts the model may pick from: those that would only be started
    /// and have a heading to be picked by, twelve at the most. None on a
    /// page of a kind where nothing is trimmed.
    public static func candidates(in reading: PageReading, kind: PageKind) -> [Candidate] {
        guard kind == .landing || kind == .product || kind == .app else { return [] }
        let parts = parts(of: reading)
        let page = sums(of: parts)
        var found: [Candidate] = []
        for (index, part) in parts.enumerated() where found.count < 12 {
            guard !part.heading.isEmpty, role(of: part, kind: kind, page: page) == .supporting else { continue }
            // One line a heading: a section in several parts is picked as its first, and goes whole in all of them.
            let name = String(part.heading.prefix(60))
            guard !found.contains(where: { $0.name == name }) else { continue }
            let start = reading.blocks[part.blocks].first { $0.kind != .heading }.map { cut(bare($0), to: 80) } ?? ""
            found.append(Candidate(part: index, name: name, start: start))
        }
        return found
    }

    /// The parts the model's picks stand for. A pick counts when the words
    /// it copied are the name of the line it numbered, or its start, or
    /// start with it; else when exactly one line has those words, the
    /// number being a line off. A pick of words that are on no line is the
    /// model writing something of its own, and is passed over.
    public static func promoted(_ picks: [PageAnswer.Pick], among candidates: [Candidate]) -> Set<Int> {
        func plain(_ text: String) -> String {
            String(text.lowercased().filter { $0.isLetter || $0.isNumber })
        }
        var parts = Set<Int>()
        for pick in picks.prefix(3) {
            let name = plain(pick.name)
            guard name.count >= 2 else { continue }
            if pick.number >= 1, pick.number <= candidates.count {
                let title = plain(candidates[pick.number - 1].name)
                if !title.isEmpty, title.hasPrefix(name) || name.hasPrefix(title) {
                    parts.insert(candidates[pick.number - 1].part)
                    continue
                }
            }
            let named = candidates.filter { plain($0.name) == name }
            if named.count == 1 { parts.insert(named[0].part) }
        }
        return parts
    }

    // MARK: Composing

    /// The page organised for its kind. `promoted` are parts the model
    /// picked (Handoff.promoted): one that would only be started goes
    /// whole. A pick raises a part and lowers none.
    public static func compose(_ reading: PageReading, kind: PageKind, promoted: Set<Int> = []) -> Composed {
        let parts = parts(of: reading)
        let page = sums(of: parts)
        var roles = parts.map { role(of: $0, kind: kind, page: page) }
        // A pick is of what is under a heading: every part of it that would only be started, a
        // box in the middle of it or not.
        let picked = Set(promoted.filter(parts.indices.contains).map { parts[$0].section })
        for index in parts.indices where picked.contains(parts[index].section) && roles[index] == .supporting { roles[index] = .core }
        // A heading with nothing under it but what was set aside goes with it: one whose
        // section has other parts, none of which goes into the file.
        var others: [Int: (all: Int, aside: Int)] = [:]
        let headings = parts.map { part in reading.blocks[part.blocks].allSatisfy { $0.kind == .heading } }
        for index in parts.indices where !headings[index] {
            others[parts[index].section, default: (0, 0)].all += 1
            if roles[index] == .margin || roles[index] == .noise { others[parts[index].section, default: (0, 0)].aside += 1 }
        }
        for index in parts.indices where headings[index] && roles[index] != .margin && roles[index] != .noise {
            if let under = others[parts[index].section], under.all == under.aside { roles[index] = .noise }
        }
        // A heading the page ends on, with nothing after it that goes into the file but the
        // notes: what was under it was the site's (a menu, a foot), and the heading alone says nothing.
        // Not on a page that is nothing but headings, where they are all there is to say.
        let hasText = parts.indices.contains { !headings[$0] && parts[$0].hint != .footnotes && (roles[$0] == .core || roles[$0] == .supporting) }
        for index in parts.indices.reversed() where hasText && (roles[index] == .core || roles[index] == .supporting) {
            if parts[index].hint == .footnotes { continue }
            guard headings[index] else { break }
            roles[index] = .noise
        }

        var composed = Composed(kind: kind, body: "")
        var out: [String] = []
        var spent = 0
        var spentBySection: [Int: Int] = [:]
        var spentOnReviews = 0
        // Sections whose first block under the heading has been come to.
        var begun = Set<Int>()
        // The lines of a list being written, one an item, which go as one block.
        var lines: [String] = []
        func put(_ text: String) {
            if !lines.isEmpty { out.append(lines.joined(separator: "\n")) }
            lines = []
            out.append(text)
        }

        func supporting(_ part: Part) {
            var kept: [Bool] = []
            var left = 0
            for index in part.blocks {
                let block = reading.blocks[index]
                let first = block.kind != .heading && begun.insert(part.section).inserted
                // Always: a heading, a long paragraph, a table or a block of code (each is one thing, and
                // no line of a table says anything without the rest), a line of the reader's own,
                // and on a landing page what a section starts with.
                var keeps = block.kind == .heading || block.isProse || block.kind == .table || block.kind == .code || block.note
                    || (first && kind == .landing)
                if !keeps, part.hint == .review {
                    // What buyers say, a line each: as far as the allowance for all of them goes.
                    keeps = spentOnReviews + block.plain <= reviewAllowance
                    if keeps { spentOnReviews += block.plain }
                } else if !keeps {
                    let room = kind == .landing ? sectionAllowance - spentBySection[part.section, default: 0] : Int.max
                    keeps = block.plain <= room && spent + block.plain <= supportingAllowance
                    if keeps {
                        spent += block.plain
                        spentBySection[part.section, default: 0] += block.plain
                    }
                }
                kept.append(keeps)
                if !keeps { left += block.plain }
            }
            // A line or two over is not worth leaving out, and saying so costs as much:
            // it goes, and counts against the allowance like the rest.
            if left > 0, left < leastCut {
                kept = kept.map { _ in true }
                if part.hint == .review {
                    spentOnReviews += left
                } else {
                    spent += left
                    spentBySection[part.section, default: 0] += left
                }
                left = 0
            }
            for (keeps, index) in zip(kept, part.blocks) where keeps {
                put(reading.blocks[index].text)
                if reading.blocks[index].note { composed.notes += 1 }
            }
            if left > 0 {
                put("[\(grouped(left)) more characters here.]")
                composed.started += 1
            }
        }

        func listing(_ part: Part) {
            // The blocks of each item, in order.
            var items: [(item: Int, blocks: [PageBlock])] = []
            for block in reading.blocks[part.blocks] {
                if let last = items.last, last.item == block.item {
                    items[items.count - 1].blocks.append(block)
                } else {
                    items.append((block.item ?? -1, [block]))
                }
            }
            for item in items {
                // An item with writing in it is kept as it is.
                if item.blocks.contains(where: \.isProse) {
                    item.blocks.forEach { put($0.text) }
                } else if composed.listed < listedItems {
                    let line = line(of: item.blocks)
                    guard !line.isEmpty else { continue }
                    lines.append("- " + line)
                    composed.listed += 1
                } else {
                    composed.unlisted += 1
                }
            }
        }

        // On a web app what was on screen comes first, where the rest was not.
        var order = Array(parts.indices)
        if kind == .app, parts.contains(where: \.onScreen), parts.contains(where: { !$0.onScreen }) {
            order = order.filter { parts[$0].onScreen } + order.filter { !parts[$0].onScreen }
            composed.screenFirst = true
        }
        var shown = false
        // The part before, where it was set aside: one thing set aside is named once, in however many parts it came.
        var aside: (part: Int, name: String)?
        // A heading set aside with nothing under it yet: counted with what comes next under the same name.
        var lone: (part: Int, name: String, characters: Int)?
        for index in order {
            let part = parts[index]
            if composed.screenFirst, shown, !part.onScreen {
                put("[On screen down to here. The rest of the page follows.]")
                shown = false
            }
            switch roles[index] {
            case .core:
                if kind == .listing, part.list != nil {
                    listing(part)
                } else {
                    if part.hint == .transcript { composed.transcript = true }
                    for block in reading.blocks[part.blocks] {
                        put(block.text)
                        if block.note { composed.notes += 1 }
                        if block.kind != .heading { begun.insert(part.section) }
                    }
                    // Named as kept whole: what the model picked, and what a visitor came for, once
                    // for all of its parts (the plans under "Pricing" are not each named).
                    let asked = part.hint == .price || part.hint == .faq
                    let named = picked.contains(part.section) || (asked && !(index > 0 && parts[index - 1].hint == part.hint))
                    if named, !part.heading.isEmpty, !composed.whole.contains(part.heading) { composed.whole.append(part.heading) }
                }
            case .supporting:
                supporting(part)
            case .margin:
                let inner = reading.blocks[part.blocks].filter { $0.kind != .heading }
                let start = cut(inner.map(bare).joined(separator: " "), to: asideStart)
                let name = name(of: part)
                // Under one heading or several: a foot with headings of its own is still one foot.
                if let last = aside, last.part == index - 1, last.name == name, var joined = composed.asides.last {
                    joined.characters += part.characters
                    joined.links += part.links
                    if joined.start.isEmpty { joined.start = start }
                    composed.asides[composed.asides.count - 1] = joined
                    aside = (index, name)
                } else if inner.isEmpty {
                    // A heading alone is not a part to name: it is counted with what is under it, if that is set aside too.
                    lone = (index, name, part.characters + (lone.flatMap { $0.part == index - 1 && $0.name == name ? $0.characters : nil } ?? 0))
                } else if part.links > 0 || inner.reduce(0, { $0 + $1.plain }) >= leastAside {
                    let over = lone.flatMap { $0.part == index - 1 && $0.name == name ? $0.characters : nil } ?? 0
                    composed.asides.append(Aside(name: name, characters: over + part.characters, links: part.links, start: start))
                    aside = (index, name)
                }
                // Else a word or two with no link ("Loading", in a box of comments not yet come): not a part to name.
            case .noise:
                composed.dropped += reading.blocks[part.blocks].contains { $0.kind != .heading } ? 1 : 0
            }
            if composed.screenFirst, part.onScreen { shown = true }
        }
        if composed.unlisted > 0 { put("[And \(grouped(composed.unlisted)) more items.]") }
        if reading.truncated { put("[The page goes on. Only its first \(grouped(limit)) characters were read.]") }
        if !lines.isEmpty { out.append(lines.joined(separator: "\n")) }
        // What was kept whole is worth naming only beside what was not.
        if composed.started == 0 { composed.whole = [] }
        composed.body = out.joined(separator: "\n\n")
        composed.truncated = reading.truncated
        composed.selection = reading.focus?.selection ?? ""
        composed.excerpt = reading.focus?.excerpt ?? ""

        // Where the person was, if not at the top: the heading over the first block that showed.
        if !composed.screenFirst, let first = reading.blocks.firstIndex(where: \.onScreen), first > 0,
           let part = parts.first(where: { $0.blocks.contains(first) }), part.section > 0 {
            composed.onScreen = part.heading
        }
        return composed
    }

    /// An item of a list as one line: what it leads with as a link where
    /// that is one (a result's title), and the rest of its words after.
    private static func line(of blocks: [PageBlock]) -> String {
        let words = blocks.map(bare).filter { !$0.isEmpty }
        guard let first = words.first else { return "" }
        guard let link = blocks.first?.link, !bare(blocks[0]).isEmpty else {
            let all = cut(words.joined(separator: " "), to: itemLine)
            return all + (blocks.lazy.compactMap(\.link).first.map { " <" + $0 + ">" } ?? "")
        }
        let title = cut(first, to: itemLine)
        let rest = words.dropFirst().joined(separator: " ")
        let room = itemLine - title.count
        return "[" + title + "](" + link + ")" + (rest.isEmpty || room < 20 ? "" : ": " + cut(rest, to: room))
    }

    /// What a part set aside is called: what the page calls it, else its heading, else what it is.
    private static func name(of part: Part) -> String {
        switch part.hint {
        case .comments: return "Comments"
        case .related: return "Related"
        case .legal: return "Legal"
        case .footer: return "Footer"
        default: return part.heading.isEmpty ? "A list of links" : String(part.heading.prefix(60))
        }
    }

    /// A block's words without Markdown, as far as its reader gave them, and without a list item's mark.
    static func bare(_ block: PageBlock) -> String {
        var words = Substring(block.words)
        if block.kind == .item, block.start == nil {
            words = words.drop { $0 == " " }
            if words.hasPrefix("- ") {
                words = words.dropFirst(2)
            } else if let dot = words.firstIndex(of: "."), words[..<dot].allSatisfy(\.isNumber), !words[..<dot].isEmpty {
                words = words[words.index(after: dot)...]
            }
        }
        return words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Words cut to about `room` characters, at a word's end where that
    /// leaves most of the room used (text written without spaces has none), and saying so.
    static func cut(_ words: String, to room: Int) -> String {
        guard words.count > room else { return words }
        let head = words.prefix(room)
        let whole = head.lastIndex(where: \.isWhitespace).map { head[..<$0] } ?? head
        return (whole.count * 2 >= room ? whole : head).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// A count as it is written: 3,200.
    static func grouped(_ number: Int) -> String {
        var digits = String(number.magnitude)
        var out = ""
        while digits.count > 3 {
            out = "," + digits.suffix(3) + out
            digits.removeLast(3)
        }
        return (number < 0 ? "-" : "") + digits + out
    }
}
