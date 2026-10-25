import Foundation

/// What kind of file a document handed off is (FileFacts.format), each
/// telling the kind of page it is read as (PageKind): its kind is told by
/// the file's format, never counted and never asked of the model.
public enum FileFormat: String, Sendable, Codable {
    case pdf, word, openText, rtf, epub, powerPoint, openPresentation,
         excel, openSpreadsheet, csv, json, xml, text, zip

    /// The kind of page the file is read as.
    public var kind: PageKind {
        switch self {
        case .pdf, .word, .openText, .rtf, .epub, .text: return .document
        case .powerPoint, .openPresentation: return .slides
        case .excel, .openSpreadsheet, .csv: return .spreadsheet
        case .json, .xml: return .data
        case .zip: return .archive
        }
    }

    /// What the file is called where the person sees it.
    public var name: String {
        switch self {
        case .pdf: return BrowserText.localized("PDF")
        case .word: return BrowserText.localized("Word document")
        case .openText: return BrowserText.localized("OpenDocument text")
        case .rtf: return BrowserText.localized("RTF document")
        case .epub: return BrowserText.localized("EPUB book")
        case .powerPoint: return BrowserText.localized("PowerPoint presentation")
        case .openPresentation: return BrowserText.localized("OpenDocument presentation")
        case .excel: return BrowserText.localized("Excel workbook")
        case .openSpreadsheet: return BrowserText.localized("OpenDocument spreadsheet")
        case .csv: return BrowserText.localized("CSV file")
        case .json: return BrowserText.localized("JSON file")
        case .xml: return BrowserText.localized("XML file")
        case .text: return BrowserText.localized("text file")
        case .zip: return BrowserText.localized("ZIP archive")
        }
    }
}

/// What is known of a file handed off (HandoffJob): its format, what it
/// was called, its size, how many pages, sheets or slides it has, which
/// pages were read from pictures of them or are not in the file at all,
/// and for an archive what is in it and what was not read, with why.
public struct FileFacts: Equatable, Sendable {
    public var format: FileFormat
    /// The file's name, not its whole address.
    public var name = ""
    public var bytes = 0
    /// How many pages a PDF has, or sheets a workbook, or slides a deck.
    public var pages: Int?, sheets: Int?, slides: Int?
    /// The pages whose words were read from pictures of them, on the
    /// device: their words may be wrong in places, and the file says so.
    public var readFromPictures: [Int] = []
    /// The pages of a PDF not read at all, past the limits Handoff keeps.
    public var notRead: [Int] = []
    /// The file's own title, author and when it was made, where it declares them.
    public var title: String?, author: String?, created: String?
    /// What is in an archive (ZIP), in the order it was read.
    public var entries: [String] = []
    /// Files of an archive not read, each as "name (why)".
    public var skipped: [String] = []
    /// The headings of the parts past where the file was cut to fit
    /// Handoff's limit (HandoffDocument.fitted): a workbook's sheets, a
    /// document's sections. The file names them, under "From the file".
    public var unread: [String] = []

    public init(format: FileFormat, name: String = "", bytes: Int = 0) {
        self.format = format
        self.name = name
        self.bytes = bytes
    }

    /// "12 pages", "3 sheets", "24 slides" or, with none of them known,
    /// how big the file is ("340 MB"); "" for nothing to say.
    public var counts: String {
        var parts: [String] = []
        if let pages, pages > 0 {
            parts.append(pages == 1 ? BrowserText.localized("1 page")
                         : String(format: BrowserText.localized("%lld pages"), pages))
        }
        if let sheets, sheets > 0 {
            parts.append(sheets == 1 ? BrowserText.localized("1 sheet")
                         : String(format: BrowserText.localized("%lld sheets"), sheets))
        }
        if let slides, slides > 0 {
            parts.append(slides == 1 ? BrowserText.localized("1 slide")
                         : String(format: BrowserText.localized("%lld slides"), slides))
        }
        // One page read from a picture is "it", of a one-page PDF too.
        if readFromPictures.count == 1 {
            parts.append(BrowserText.localized("1 read from a picture of it"))
        } else if !readFromPictures.isEmpty {
            parts.append(String(format: BrowserText.localized("%lld read from pictures of them"), readFromPictures.count))
        }
        if parts.isEmpty, bytes > 0 { parts.append(Self.size(bytes)) }
        return parts.joined(separator: ", ")
    }

    /// "page 7", or "pages 301 to 412" where the run goes on: pages not read.
    public var missed: String {
        var parts: [String] = []
        var run = (first: 0, last: 0)
        for page in notRead.sorted() {
            if page == run.last + 1 { run.last = page; continue }
            if run.last > 0 { parts.append(Self.range(run.first, run.last)) }
            run = (page, page)
        }
        if run.last > 0 { parts.append(Self.range(run.first, run.last)) }
        return parts.joined(separator: ", ")
    }

    static func range(_ first: Int, _ last: Int) -> String {
        first == last
            ? String(format: BrowserText.localized("page %lld"), first)
            : String(format: BrowserText.localized("pages %lld to %lld"), first, last)
    }

    /// "3, 4 and 9", for "pages 3, 4 and 9" where pictures were read.
    static func listed(_ numbers: [Int]) -> String {
        let words = numbers.map { String($0) }
        guard let last = words.last else { return "" }
        return words.count == 1 ? last
            : words.dropLast().joined(separator: ", ") + BrowserText.localized(" and ") + last
    }

    /// "340 MB" or "12 KB".
    public static func size(_ bytes: Int) -> String {
        bytes >= 1_000_000
            ? String(format: BrowserText.localized("%lld MB"), bytes / 1_000_000)
            : String(format: BrowserText.localized("%lld KB"), max(1, bytes / 1_000))
    }
}

extension FileFacts: Codable {
    private enum Keys: String, CodingKey {
        case format, name, bytes, pages, sheets, slides
        case readFromPictures, notRead, title, author, created, entries, skipped, unread
    }

    /// A fixture's file facts (Tests/handoff): every field but format may
    /// be left out, keeping the JSON to what the fixture is about.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: Keys.self)
        format = try box.decode(FileFormat.self, forKey: .format)
        name = try box.decodeIfPresent(String.self, forKey: .name) ?? ""
        bytes = try box.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
        pages = try box.decodeIfPresent(Int.self, forKey: .pages)
        sheets = try box.decodeIfPresent(Int.self, forKey: .sheets)
        slides = try box.decodeIfPresent(Int.self, forKey: .slides)
        readFromPictures = try box.decodeIfPresent([Int].self, forKey: .readFromPictures) ?? []
        notRead = try box.decodeIfPresent([Int].self, forKey: .notRead) ?? []
        title = try box.decodeIfPresent(String.self, forKey: .title)
        author = try box.decodeIfPresent(String.self, forKey: .author)
        created = try box.decodeIfPresent(String.self, forKey: .created)
        entries = try box.decodeIfPresent([String].self, forKey: .entries) ?? []
        skipped = try box.decodeIfPresent([String].self, forKey: .skipped) ?? []
        unread = try box.decodeIfPresent([String].self, forKey: .unread) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(format, forKey: .format)
        try box.encode(name, forKey: .name)
        try box.encode(bytes, forKey: .bytes)
        try box.encodeIfPresent(pages, forKey: .pages)
        try box.encodeIfPresent(sheets, forKey: .sheets)
        try box.encodeIfPresent(slides, forKey: .slides)
        if !readFromPictures.isEmpty { try box.encode(readFromPictures, forKey: .readFromPictures) }
        if !notRead.isEmpty { try box.encode(notRead, forKey: .notRead) }
        try box.encodeIfPresent(title, forKey: .title)
        try box.encodeIfPresent(author, forKey: .author)
        try box.encodeIfPresent(created, forKey: .created)
        if !entries.isEmpty { try box.encode(entries, forKey: .entries) }
        if !skipped.isEmpty { try box.encode(skipped, forKey: .skipped) }
        if !unread.isEmpty { try box.encode(unread, forKey: .unread) }
    }
}

/// A ZIP archive walked for the handoff (DocumentSource): each file it
/// reads, in order, and the rest named with why (FileFacts.skipped) —
/// at most 20 files and 50 MB unpacked in all (Decided 6), and folders,
/// links and __MACOSX/ not counted as files at all.
public enum HandoffArchive {
    /// The files read at the most.
    public static let fileLimit = 20
    /// Their bytes unpacked at the most, in all.
    public static let sizeLimit = 50_000_000

    /// Which of the archive's items are read and which are named with
    /// why: `known` says whether a name is a kind eGlu reads.
    public static func walk(_ items: [ZipFile.Item], known: (String) -> Bool) -> (read: [String], skipped: [String]) {
        var read: [String] = [], skipped: [String] = [], size = 0
        for item in items where !item.isFolder && !item.isLink && !item.name.hasPrefix("__MACOSX/") {
            guard known(item.name) else {
                skipped.append("\(item.name) (not a kind eGlu reads)")
                continue
            }
            guard size + item.size <= sizeLimit else {
                skipped.append("\(item.name) (too large)")
                continue
            }
            guard read.count < fileLimit else {
                skipped.append("\(item.name) (past the first \(fileLimit) files)")
                continue
            }
            read.append(item.name)
            size += item.size
        }
        return (read, skipped)
    }
}

/// A document's Markdown made a reading like a page's own (PageReading):
/// its blocks and facts as markdown.js would give them, so HandoffCompose
/// and Handoff.document work unchanged in what they do, and documents are
/// tested on Linux like pages.
public enum HandoffDocument {

    /// The document's Markdown in blocks and facts. `truncated` where the
    /// text was cut at Handoff's limit (Handoff.limit, at a page's, a
    /// sheet's or a slide's boundary).
    public static func reading(markdown: String, facts: FileFacts, truncated: Bool = false) -> PageReading {
        var blocks: [PageBlock] = []
        var headings: [String] = []
        var group = 0, item = 0
        var run = false  // the run of list items a group number covers

        let lines = markdown.components(separatedBy: "\n")
        var i = lines.startIndex
        while i < lines.endIndex {
            let line = lines[i]
            let cut = line.trimmingCharacters(in: .whitespaces)
            i += 1
            guard !cut.isEmpty else { run = false; continue }

            // A fenced code block, kept whole whatever its length.
            if let fence = fence(of: cut) {
                var body = [line]
                while i < lines.endIndex {
                    body.append(lines[i])
                    let done = lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence)
                    i += 1
                    if done { break }
                }
                blocks.append(block(.code, body.joined(separator: "\n")))
                run = false
                continue
            }
            if let level = heading(of: cut) {
                let made = block(.heading, line, level: level)
                blocks.append(made)
                if headings.count < 12 { headings.append(made.title) }
                run = false
                continue
            }
            if isRule(cut) {
                blocks.append(PageBlock(kind: .rule, text: line))
                run = false
                continue
            }
            if cut.hasPrefix(">") {
                var body = [line]
                while i < lines.endIndex, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    body.append(lines[i])
                    i += 1
                }
                blocks.append(block(.quote, body.joined(separator: "\n")))
                run = false
                continue
            }
            if isTableRow(cut) {
                // The whole table one block, as markdown.js gives a page's:
                // blocks are written a blank line apart, and a row apart
                // from the rest is no table.
                var whole = [line]
                while i < lines.endIndex, isTableRow(lines[i].trimmingCharacters(in: .whitespaces)) {
                    whole.append(lines[i])
                    i += 1
                }
                blocks.append(block(.table, whole.joined(separator: "\n")))
                run = false
                continue
            }
            if isItem(cut) {
                if !run { group += 1; run = true }
                item += 1
                blocks.append(block(.item, line, group: group, item: item))
                continue
            }
            // A paragraph: until a blank line or what starts another block.
            var body = [line]
            while i < lines.endIndex {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty { i += 1; break }
                if startsBlock(next) { break }
                body.append(lines[i])
                i += 1
            }
            blocks.append(block(.paragraph, body.joined(separator: "\n")))
            run = false
        }

        var given = PageFacts()
        for each in blocks {
            given.characters += each.characters
            given.links += each.links
            given.linked += each.linked
            if each.isProse {
                given.long += 1
                given.written += each.characters
            }
        }
        given.headings = headings
        given.titled = headings.first ?? facts.title ?? ""
        given.description = ""
        given.unread = facts.unread
        return PageReading(blocks: blocks, facts: given, truncated: truncated)
    }

    /// A JSON file's text in a ```json block, sorted and spaced
    /// (JSONSerialization's prettyPrinted and sortedKeys); the bytes as
    /// they came where they do not parse.
    public static func json(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                       options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            return "```json\n" + String(decoding: data, as: UTF8.self) + "\n```"
        }
        return "```json\n" + text + "\n```"
    }

    /// The Markdown within `room` characters, cut where a part of the file
    /// ends: whole parts, each from a heading of the first two levels (a
    /// workbook's sheet, a section, a titled slide), while they fit, then
    /// as much of the next as fits at a paragraph's or a table row's end,
    /// where what fits so far is under half the room. `unread` are the
    /// headings of the parts not in it at all, which the file names.
    public static func fitted(_ markdown: String, room: Int) -> (markdown: String, unread: [String], truncated: Bool) {
        guard markdown.count > room else { return (markdown, [], false) }
        let parts = self.parts(of: markdown)
        var kept: [String] = []
        var size = 0
        var next = parts.startIndex
        while next < parts.endIndex, size + parts[next].text.count + 2 <= room {
            kept.append(parts[next].text)
            size += parts[next].text.count + 2
            next += 1
        }
        if next < parts.endIndex, size * 2 < room {
            let start = cut(parts[next].text, to: room - size - 2)
            if !start.isEmpty { kept.append(start) }
            next += 1
        }
        let unread = parts[next...].compactMap(\.heading)
        return (kept.joined(separator: "\n\n"), unread, true)
    }

    /// The Markdown in parts, each from a heading of the first two levels
    /// to the next, a fenced block's lines never taken for one; what comes
    /// before the first heading is a part of its own, with none.
    static func parts(of markdown: String) -> [(heading: String?, text: String)] {
        var parts: [(heading: String?, lines: [String])] = []
        var fenced: String?
        for line in markdown.components(separatedBy: "\n") {
            let cut = line.trimmingCharacters(in: .whitespaces)
            if let open = fenced {
                if cut.hasPrefix(open) { fenced = nil }
            } else if let mark = fence(of: cut) {
                fenced = mark
            } else if let level = heading(of: cut), level <= 2 {
                let title = String(cut.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                parts.append((inline(title), [line]))
                continue
            }
            if parts.isEmpty { parts.append((nil, [])) }
            parts[parts.count - 1].lines.append(line)
        }
        return parts.map { ($0.heading, $0.lines.joined(separator: "\n").trimmingCharacters(in: .newlines)) }
            .filter { !$0.text.isEmpty }
    }

    /// A part's start, within `room`: to the last blank line in it, or
    /// where it is a table or code, to the last whole line, a fence that
    /// was open closed again, so no row or line is left half in. Text of
    /// one long line is cut where the room ends: there is no other place.
    static func cut(_ text: String, to room: Int) -> String {
        guard room > 0 else { return "" }
        guard text.count > room else { return text }
        let within = String(text.prefix(room))
        var lines = within.components(separatedBy: "\n")
        // The last line is cut through, unless it is the only one.
        if lines.count > 1 { lines.removeLast() }
        if let blank = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }),
           blank * 2 >= lines.count {
            lines = Array(lines[..<blank])
        }
        // A fence left open is closed, so what follows is not taken for code.
        var open: String?
        for line in lines {
            let cut = line.trimmingCharacters(in: .whitespaces)
            if let mark = open { if cut.hasPrefix(mark) { open = nil } } else { open = fence(of: cut) }
        }
        if let open { lines.append(open) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// How many sheets a workbook's Markdown has: the engines head each
    /// with its name, at the second level, and write nothing else there.
    public static func sheets(in markdown: String) -> Int {
        var count = 0
        var fenced: String?
        for line in markdown.components(separatedBy: "\n") {
            let cut = line.trimmingCharacters(in: .whitespaces)
            if let open = fenced {
                if cut.hasPrefix(open) { fenced = nil }
            } else if let mark = fence(of: cut) {
                fenced = mark
            } else if heading(of: cut) == 2 {
                count += 1
            }
        }
        return count
    }

    /// What an Office file says of itself, in docProps (OOXML's ZIP): its
    /// pages and slides as the app that saved it counted them, its title,
    /// who made it and on what day. Nil for each it doesn't say.
    public static func declared(in data: Data) -> (pages: Int?, slides: Int?, title: String?, author: String?, created: String?) {
        guard ZipFile.isArchive(data) else { return (nil, nil, nil, nil, nil) }
        let app = ZipFile.file(in: data) { $0 == "docProps/app.xml" }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let core = ZipFile.file(in: data) { $0 == "docProps/core.xml" }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let pages = element("Pages", in: app).flatMap { Int($0) }
        let slides = element("Slides", in: app).flatMap { Int($0) }
        let created = element("dcterms:created", in: core).map { String($0.prefix(10)) }
        return (pages.flatMap { $0 > 0 ? $0 : nil }, slides.flatMap { $0 > 0 ? $0 : nil },
                element("dc:title", in: core), element("dc:creator", in: core), created)
    }

    /// An element's text in a docProps file, its entities read; nil where
    /// it is not there or is empty.
    private static func element(_ name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)>") ?? xml.range(of: "<\(name) ", options: .literal).flatMap({ start in
                  xml[start.upperBound...].range(of: ">").map { start.lowerBound..<$0.upperBound } }),
              let close = xml[open.upperBound...].range(of: "</\(name)>") else { return nil }
        let text = xml[open.upperBound..<close.lowerBound]
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// A block as markdown.js gives it: its words without Markdown counted
    /// (`plain`), its links and what of it they say, its first words where
    /// they differ, and its first link's address.
    private static func block(_ kind: PageBlock.Kind, _ text: String, level: Int = 0,
                              group: Int? = nil, item: Int? = nil) -> PageBlock {
        let words = unmarked(text)
        let said = links(in: text)
        return PageBlock(kind: kind, level: level, text: text, plain: words.count,
                         links: said.count, linked: said.linked, group: group, item: item,
                         start: words == text ? nil : String(words.prefix(220)), link: said.first)
    }

    /// The words of a block's text without Markdown: the marks a heading,
    /// a list's item, a quote or a table row starts with, and the marks
    /// of code, emphasis and links, whose addresses are no words.
    private static func unmarked(_ text: String) -> String {
        var words: [String] = []
        for line in text.components(separatedBy: "\n") {
            var cut = line.trimmingCharacters(in: .whitespaces)
            if let level = heading(of: cut) {
                cut = String(cut.dropFirst(level)).trimmingCharacters(in: .whitespaces)
            } else if cut.hasPrefix(">") {
                cut = String(cut.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if let mark = listMark(cut) {
                cut = String(cut.dropFirst(mark)).trimmingCharacters(in: .whitespaces)
            } else if isTableRow(cut) {
                cut = cut.replacingOccurrences(of: "|", with: " ")
            }
            words.append(inline(cut))
        }
        return words.joined(separator: "\n")
            .replacingOccurrences(of: #"\s\n\s"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `text` without the marks code, emphasis and links carry; a link's
    /// or a picture's words kept, its address dropped.
    private static func inline(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(`+)([^`]*)\1"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "~~", with: "")
    }

    /// How many links a block's text has, how much of it they say, and
    /// the first one's address, pictures counting as links.
    private static func links(in text: String) -> (count: Int, linked: Int, first: String?) {
        guard let found = try? NSRegularExpression(pattern: #"!?\[([^\]]+)\]\(([^)\s]+)[^)]*\)"#) else {
            return (0, 0, nil)
        }
        var count = 0, linked = 0
        var first: String?
        for match in found.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            count += 1
            if let label = Range(match.range(at: 1), in: text) { linked += text[label].count }
            if first == nil, let address = Range(match.range(at: 2), in: text) { first = String(text[address]) }
        }
        return (count, linked, first)
    }

    /// Whether a line starts a block of its own inside what would
    /// otherwise be a paragraph's run.
    private static func startsBlock(_ cut: String) -> Bool {
        fence(of: cut) != nil || heading(of: cut) != nil || isRule(cut)
            || cut.hasPrefix(">") || isTableRow(cut) || isItem(cut)
    }

    /// A fence's marks where a line opens or closes code, "```" or "~~~".
    private static func fence(of cut: String) -> String? {
        cut.hasPrefix("```") ? "```" : cut.hasPrefix("~~~") ? "~~~" : nil
    }

    /// A heading's level where a line is one, "#" through "######" plus a space.
    private static func heading(of cut: String) -> Int? {
        var level = 0
        for mark in cut {
            guard mark == "#" else { break }
            level += 1
            guard level <= 6 else { return nil }
        }
        guard level > 0 else { return nil }
        let rest = cut.dropFirst(level)
        return rest.first == " " || rest.isEmpty ? level : nil
    }

    /// A rule's line: three marks of one kind, spaced or not ("---", "* * *").
    private static func isRule(_ cut: String) -> Bool {
        var mark: Character?
        var count = 0
        for each in cut where each != " " {
            if mark == nil { mark = each }
            guard each == mark, each == "-" || each == "*" || each == "_" else { return false }
            count += 1
        }
        return count >= 3
    }

    /// A table's row: GitHub's, starting with a "|" as the engines write them.
    private static func isTableRow(_ cut: String) -> Bool {
        cut.hasPrefix("|")
    }

    /// A list's item: "- ", "* ", "+ " or a number's ("1. ", "2) ").
    private static func isItem(_ cut: String) -> Bool {
        listMark(cut) != nil
    }

    /// How many characters a line's list mark takes, or nil for no item.
    private static func listMark(_ cut: String) -> Int? {
        if let first = cut.first, first == "-" || first == "*" || first == "+" {
            return cut.dropFirst().first == " " ? 2 : nil
        }
        var digits = 0
        for each in cut {
            guard each.isNumber else { break }
            digits += 1
            guard digits <= 3 else { return nil }
        }
        guard digits > 0 else { return nil }
        let rest = cut.dropFirst(digits)
        guard let close = rest.first, close == "." || close == ")",
              rest.dropFirst().first == " " else { return nil }
        return digits + 2
    }
}
