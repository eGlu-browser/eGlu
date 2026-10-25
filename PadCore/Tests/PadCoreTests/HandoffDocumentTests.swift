import Foundation
import Testing
@testable import PadCore

/// A document's Markdown made a reading (HandoffDocument): its blocks and
/// facts as markdown.js would give them, and the file each kind of file
/// comes to, kept beside it under Tests/handoff.
struct HandoffDocumentTests {

    private static func facts(_ format: FileFormat = .word) -> FileFacts {
        FileFacts(format: format, name: "notes.docx", bytes: 4_000)
    }

    /// Headings keep their levels and feed the facts' first headings and title.
    @Test func headings() {
        let reading = HandoffDocument.reading(
            markdown: "# One\n\nText.\n\n## Two\n\nMore.\n\n### Three",
            facts: Self.facts())
        #expect(reading.blocks.map(\.kind) == [.heading, .paragraph, .heading, .paragraph, .heading])
        #expect(reading.blocks.filter { $0.kind == .heading }.map(\.level) == [1, 2, 3])
        #expect(reading.facts.headings == ["One", "Two", "Three"])
        #expect(reading.facts.titled == "One")
        // A heading's first words are always given without its marks.
        #expect(reading.blocks[0].start == "One")
    }

    /// A list's items share one group, each with its own number as
    /// markdown.js sets them, and the run ends with it.
    @Test func lists() {
        let reading = HandoffDocument.reading(
            markdown: "- a\n- b\n- c\n\n1. one\n2. two",
            facts: Self.facts())
        let items = reading.blocks.filter { $0.kind == .item }
        #expect(items.map(\.text) == ["- a", "- b", "- c", "1. one", "2. two"])
        #expect(items.map(\.group) == [1, 1, 1, 2, 2])
        #expect(items.map(\.item) == [1, 2, 3, 4, 5])
    }

    /// A table is one block, its rows together, as markdown.js gives a
    /// page's: the file writes blocks a blank line apart. None hinted.
    @Test func tables() {
        let reading = HandoffDocument.reading(
            markdown: "Text.\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n\nMore.",
            facts: Self.facts())
        #expect(reading.blocks.map(\.kind) == [.paragraph, .table, .paragraph])
        #expect(reading.blocks[1].text == "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |")
        #expect(reading.blocks[1].hint == nil)
        // And it comes to the file as one table.
        let made = Handoff.compose(reading, kind: .document).body
        #expect(made.contains("| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |"))
    }

    /// Cut to fit: whole parts while they fit, a part from its heading of
    /// the first two levels to the next, and the headings of those left
    /// out named; a heading inside code is no part's.
    @Test func fittedAtParts() {
        let sheet = { (name: String) in "## \(name)\n\n| A | B |\n| --- | --- |\n" + String(repeating: "| 1 | 2 |\n", count: 20) }
        let markdown = ["# Budget", sheet("Income"), sheet("Costs"), "```\n## not a sheet\n```", sheet("Summary")]
            .joined(separator: "\n\n")
        let whole = HandoffDocument.fitted(markdown, room: markdown.count)
        #expect(whole.markdown == markdown && whole.unread.isEmpty && !whole.truncated)
        let room = "# Budget".count + sheet("Income").count + 40
        let fitted = HandoffDocument.fitted(markdown, room: room)
        #expect(fitted.truncated)
        #expect(fitted.markdown.hasSuffix("| 1 | 2 |"))
        #expect(!fitted.markdown.contains("Costs"))
        #expect(fitted.unread == ["Costs", "Summary"])
        #expect(HandoffDocument.sheets(in: markdown) == 3)
    }

    /// A part too big for the room is cut at a row's end, its head kept,
    /// and a code block cut through is closed again.
    @Test func fittedInsideAPart() {
        let table = "| A | B |\n| --- | --- |\n" + String(repeating: "| 10 | 20 |\n", count: 100)
        let cut = HandoffDocument.fitted(table, room: 200)
        #expect(cut.truncated && cut.unread.isEmpty)
        #expect(cut.markdown.hasPrefix("| A | B |\n| --- | --- |\n| 10 | 20 |"))
        #expect(cut.markdown.hasSuffix("| 10 | 20 |") && cut.markdown.count <= 200)
        let code = "```json\n" + String(repeating: "  \"key\": 1,\n", count: 100) + "```"
        let closed = HandoffDocument.fitted(code, room: 120).markdown
        #expect(closed.hasPrefix("```json\n") && closed.hasSuffix("\n```"))
        let line = String(repeating: "word ", count: 100)
        // One long line, with no other place to cut, is cut where the room ends.
        #expect((40...50).contains(HandoffDocument.fitted(line, room: 50).markdown.count))
    }

    /// A workbook cut short says so, and names the sheets left out under
    /// "From the file", where the file's own words go.
    @Test func cutWorkbook() {
        var facts = FileFacts(format: .excel, name: "ledger.xlsx", bytes: 90_000)
        facts.sheets = 3
        facts.unread = ["Costs", "Summary"]
        let reading = HandoffDocument.reading(markdown: "## Income\n\n| A |\n| --- |\n| 1 |", facts: facts, truncated: true)
        let made = Handoff.document(title: facts.name, url: nil, composed: Handoff.compose(reading, kind: .spreadsheet),
                                    reading: reading, file: facts)
        #expect(made.contains("- Not in this file: the rest of the file, past what one file holds. The sheets left out are named under \"From the file\".\n"))
        #expect(made.contains("From the file:\n- The sheets not in this file: \"Costs\", \"Summary\"\n"))
        #expect(made.contains("[The file goes on past here. What is not in this file is said at its top.]"))
        #expect(made.hasPrefix("# ledger.xlsx\n\nFile: ledger.xlsx\n\nAbout this file, written by eGlu and not by the file:\n"))
    }

    /// One page read from a picture is said as one.
    @Test func onePictureRead() {
        var facts = FileFacts(format: .pdf, name: "scan.pdf", bytes: 90_000)
        facts.pages = 1
        facts.readFromPictures = [1]
        #expect(facts.counts == "1 page, 1 read from a picture of it")
        let reading = HandoffDocument.reading(markdown: "Words.", facts: facts)
        let made = Handoff.document(title: facts.name, url: nil, composed: Handoff.compose(reading, kind: .document),
                                    reading: reading, file: facts)
        #expect(made.contains("- Read from a picture of the page, on this device: page 1. Its words may be wrong in places.\n"))
    }

    /// What an Office file declares of itself, from its docProps.
    @Test func declared() throws {
        let app = "<Properties><Pages>12</Pages><Slides>0</Slides></Properties>"
        let core = "<cp:coreProperties><dc:title>Q3 &amp; Q4</dc:title><dc:creator>Ada Wren</dc:creator>"
            + "<dcterms:created xsi:type=\"dcterms:W3CDTF\">2026-10-02T09:00:00Z</dcterms:created></cp:coreProperties>"
        let made = ExtensionPreparationTests.zip([("docProps/app.xml", Data(app.utf8)), ("docProps/core.xml", Data(core.utf8))])
        let said = HandoffDocument.declared(in: made)
        #expect(said.pages == 12)
        #expect(said.slides == nil)
        #expect(said.title == "Q3 & Q4")
        #expect(said.author == "Ada Wren")
        #expect(said.created == "2026-10-02")
        #expect(HandoffDocument.declared(in: Data("not a zip".utf8)).title == nil)
    }

    /// A fenced block of code stays one block however it is written.
    @Test func code() {
        let reading = HandoffDocument.reading(
            markdown: "Text.\n\n```\nlet a = 1\n# not a heading\n```\n\nMore.",
            facts: Self.facts())
        #expect(reading.blocks.map(\.kind) == [.paragraph, .code, .paragraph])
        #expect(reading.blocks[1].text.contains("# not a heading"))
    }

    /// Words without Markdown: a link's address is no part of what a
    /// block says, and its first link's address is kept.
    @Test func plain() {
        let reading = HandoffDocument.reading(
            markdown: "See [the harbour plan](https://example.org/plan) and **bold** words.",
            facts: Self.facts())
        let block = reading.blocks[0]
        #expect(block.links == 1)
        #expect(block.link == "https://example.org/plan")
        #expect(block.plain == "See the harbour plan and bold words.".count)
        #expect(block.start == "See the harbour plan and bold words.")
    }

    /// Facts counted as markdown.js counts them: all the text, and the
    /// blocks that are prose of 200 or more.
    @Test func facts() {
        let prose = String(repeating: "word ", count: 60).trimmingCharacters(in: .whitespaces)
        let reading = HandoffDocument.reading(
            markdown: "# Title\n\n\(prose)\n\n- short",
            facts: Self.facts())
        #expect(reading.facts.characters == reading.blocks.reduce(0) { $0 + $1.characters })
        #expect(reading.facts.long == 1)
        #expect(reading.facts.written == prose.count)
        #expect(reading.facts.titled == "Title")
    }

    /// Where the markdown has no heading, the file's own title names it.
    @Test func untitled() {
        var facts = Self.facts()
        facts.title = "From the file itself"
        let reading = HandoffDocument.reading(markdown: "Only words.", facts: facts)
        #expect(reading.facts.titled == "From the file itself")
    }

    /// The document kept beside each fixture: `<name>.source.md` is the
    /// Markdown the engines gave, `<name>.file.json` what is known of the
    /// file (FileFacts) and where it came from, and `<name>.md` the file
    /// the handoff writes, as a page's `reading.json` and `md` are kept.
    @Test("Each kind of file comes to the file kept for it", arguments: [
        "report", "deck", "budget", "scan", "data", "files", "photo", "voice",
    ])
    func document(_ name: String) throws {
        let kept = try Self.file(name)
        let markdown = try String(contentsOf: HandoffComposeTests.root
            .appendingPathComponent("Tests/handoff/\(name).source.md"), encoding: .utf8)
        let reading = HandoffDocument.reading(markdown: markdown, facts: kept.facts)
        let made = Handoff.document(title: kept.facts.name, url: kept.url,
                                    composed: Handoff.compose(reading, kind: kept.facts.format.kind),
                                    reading: reading, file: kept.facts, read: HandoffComposeTests.moment)
        try HandoffComposeTests.hold(made, against: name)
    }

    /// A picture's facts carry its size, when it was taken, camera and
    /// lens — and never a place: where a picture was taken is never read,
    /// so nothing in what is kept of a file can carry it.
    @Test func noPlace() throws {
        var facts = FileFacts(format: .picture, name: "photo.jpg", bytes: 100)
        facts.width = 4_032
        facts.height = 3_024
        facts.taken = "2026-10-02"
        facts.camera = "Apple iPhone 17 Pro"
        facts.lens = "iPhone 17 Pro back camera"
        facts.described = true
        let written = try JSONEncoder().encode(facts)
        let object = try #require(JSONSerialization.jsonObject(with: written) as? [String: Any])
        for banned in ["place", "location", "gps", "GPS", "latitude", "longitude", "altitude"] {
            #expect(object[banned] == nil, "FileFacts carries \(banned)")
        }
    }

    /// A picture's camera is said without its date, and its lens after,
    /// each on one line however the picture wrote it.
    @Test func cameraWithoutDate() {
        var facts = FileFacts(format: .picture, name: "shot.jpg", bytes: 100)
        facts.camera = "Canon EOS R6"
        facts.lens = "RF24-105mm\nF4 L IS USM"
        #expect(facts.counts == "taken with Canon EOS R6, lens RF24-105mm F4 L IS USM")
        facts.taken = "2026-10-02"
        #expect(facts.counts == "taken 2026-10-02 with Canon EOS R6, lens RF24-105mm F4 L IS USM")
        facts.camera = nil
        facts.lens = nil
        #expect(facts.counts == "taken 2026-10-02")
    }

    /// JSON is written sorted and spaced in a ```json block, raw where
    /// it does not parse.
    @Test func jsonFormatted() {
        let made = HandoffDocument.json(Data(#"{"b":[2,3],"a":1}"#.utf8))
        #expect(made.hasPrefix("```json\n{\n"))
        #expect(made.contains("\"a\" : 1"))
        // Sorted: a's line comes before b's.
        #expect(made.range(of: "\"a\"")!.lowerBound < made.range(of: "\"b\"")!.lowerBound)
        let raw = HandoffDocument.json(Data("not json".utf8))
        #expect(raw == "```json\nnot json\n```")
    }

    /// The archive's files in order, each name's data taken back out, and
    /// folders, links and __MACOSX/ not among them; a protected archive
    /// and a ZIP64's own record both told.
    @Test func archiveWalked() throws {
        let made = Self.zip([
            ("report.txt", Array("words".utf8), false, false),
            ("folder/", [], false, false),
            ("__MACOSX/report.txt", Array("x".utf8), false, false),
            ("linked", Array("t".utf8), true, false),
            ("hidden.txt", Array("w".utf8), false, true),
        ])
        let items = ZipFile.contents(of: made)
        #expect(items.map(\.name) == ["report.txt", "folder/", "__MACOSX/report.txt", "linked", "hidden.txt"])
        #expect(items[1].isFolder && items[3].isLink && items[4].encrypted)
        #expect(!ZipFile.isZip64(made))
        // The exact name's own file, not the __MACOSX stub of it.
        #expect(ZipFile.file(in: made, matching: { $0 == "report.txt" }).map { String(decoding: $0, as: UTF8.self) } == "words")
        // And a walk of items like it, without the protected one inside.
        let open = items.filter { !$0.encrypted }
        let (read, skipped) = HandoffArchive.walk(open) { name in
            name.hasSuffix(".txt") || name.hasSuffix(".csv")
        }
        #expect(read == ["report.txt"])
        #expect(skipped == [])
        // The limits: 20 files and 50 MB unpacked in all.
        var many = (0..<22).map { ZipFile.Item(name: "f\($0).txt", size: 10, isFolder: false, isLink: false, encrypted: false) }
        many.append(ZipFile.Item(name: "big.txt", size: HandoffArchive.sizeLimit + 1, isFolder: false, isLink: false, encrypted: false))
        let walked = HandoffArchive.walk(many) { _ in true }
        #expect(walked.read.count == 20)
        #expect(walked.skipped == ["f20.txt (past the first 20 files)", "f21.txt (past the first 20 files)",
                                 "big.txt (too large)"])
        let sizes = (0..<3).map { ZipFile.Item(name: "s\($0).txt", size: 30_000_000, isFolder: false, isLink: false, encrypted: false) }
        let sized = HandoffArchive.walk(sizes) { _ in true }
        #expect(sized.read == ["s0.txt"])
        #expect(sized.skipped == ["s1.txt (too large)", "s2.txt (too large)"])
    }

    /// An archive inside the archive is named and not opened, whatever
    /// room is left: its files would have limits of their own.
    @Test func nestedArchiveNotOpened() {
        let items = [ZipFile.Item(name: "inner.zip", size: 10, isFolder: false, isLink: false, encrypted: false),
                     ZipFile.Item(name: "notes.txt", size: 10, isFolder: false, isLink: false, encrypted: false)]
        let walked = HandoffArchive.walk(items) { _ in true }
        #expect(walked.read == ["notes.txt"])
        #expect(walked.skipped == ["inner.zip (an archive inside this one, not opened)"])
    }

    /// eGlu opens a ZIP with files and no password; one protected, or
    /// written the ZIP64 way, it does not.
    @Test func archivesOpened() {
        let open = Self.zip([("a.txt", Array("a".utf8), false, false)])
        #expect(HandoffArchive.opens(open))
        #expect(!HandoffArchive.opens(Self.zip([("a.txt", Array("a".utf8), false, true)])))
        #expect(!HandoffArchive.opens(Data("not a zip".utf8)))
        // ZIP64's locator, 20 bytes before the end record, which this reader can't follow.
        var bytes = [UInt8](open)
        let end = bytes.count - 22
        bytes.insert(contentsOf: [0x50, 0x4B, 0x06, 0x07] + [UInt8](repeating: 0, count: 16), at: end)
        #expect(ZipFile.isZip64(Data(bytes)))
        #expect(!HandoffArchive.opens(Data(bytes)))
    }

    /// A PDF read from an archive says what a PDF on its own says of its
    /// pages, by its name.
    @Test func archivesFilesSaid() {
        var facts = FileFacts(format: .zip, name: "papers.zip", bytes: 9_000)
        var scan = FileFacts(format: .pdf, name: "scan.pdf", bytes: 4_000)
        scan.readFromPictures = [2, 3]
        scan.notRead = [301, 302]
        facts.within = [scan, FileFacts(format: .text, name: "notes.txt")]
        facts.entries = ["scan.pdf", "notes.txt"]
        let reading = HandoffDocument.reading(markdown: "## scan.pdf\n\nWords.\n\n## notes.txt\n\nMore.", facts: facts)
        let made = Handoff.document(title: facts.name, url: nil, composed: Handoff.compose(reading, kind: .archive),
                                    reading: reading, file: facts)
        #expect(made.contains("- In scan.pdf: not in this file: pages 301 to 302.\n"))
        #expect(made.contains("- In scan.pdf: read from pictures of the pages, on this device: pages 2 and 3. Their words may be wrong in places.\n"))
        #expect(!made.contains("In notes.txt"))
        // Kept with the facts, as every field is.
        let coded = try? JSONDecoder().decode(FileFacts.self, from: JSONEncoder().encode(facts))
        #expect(coded?.within == facts.within)
    }

    /// A small archive in ZipFile's own format: stored entries only, a
    /// file's name and bytes, its link or password mark where it has one.
    private static func zip(_ files: [(name: String, bytes: [UInt8], link: Bool, encrypted: Bool)]) -> Data {
        var out: [UInt8] = [], central: [UInt8] = []
        for (name, bytes, link, encrypted) in files {
            let nameBytes = [UInt8](name.utf8)
            let flags: UInt16 = encrypted ? 1 : 0
            let attributes: UInt32 = link ? 0xA1FF_0000 : 0
            let offset = out.count
            // Local file header: stored (method 0), sizes as they are.
            out += [0x50, 0x4B, 0x03, 0x04, 20, 0] + u16(flags) + [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            out += u32(UInt32(bytes.count)) + u32(UInt32(bytes.count)) + u16(UInt16(nameBytes.count)) + [0, 0]
            out += nameBytes + bytes
            central += [0x50, 0x4B, 0x01, 0x02, 20, 0, 20, 0] + u16(flags) + [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            central += u32(UInt32(bytes.count)) + u32(UInt32(bytes.count)) + u16(UInt16(nameBytes.count))
            central += [0, 0, 0, 0, 0, 0, 0, 0] + u32(attributes) + u32(UInt32(offset))
            central += nameBytes
        }
        let start = out.count
        out += central
        out += [0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0] + u16(UInt16(files.count)) + u16(UInt16(files.count))
        out += u32(UInt32(central.count)) + u32(UInt32(start)) + [0, 0]
        return Data(out)
    }

    private static func u16(_ n: UInt16) -> [UInt8] { [UInt8(n & 0xFF), UInt8(n >> 8)] }
    private static func u32(_ n: UInt32) -> [UInt8] { [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8(n >> 24)] }

    /// What the fixture's `.file.json` keeps: the file's facts, and the
    /// address it came from where it has one (nil for a file on the device).
    private static func file(_ name: String) throws -> (facts: FileFacts, url: URL?) {
        struct Kept: Decodable {
            var url: URL?
        }
        let data = try Data(contentsOf: HandoffComposeTests.root
            .appendingPathComponent("Tests/handoff/\(name).file.json"))
        let facts = try JSONDecoder().decode(FileFacts.self, from: data)
        let kept = try JSONDecoder().decode(Kept.self, from: data)
        return (facts, kept.url)
    }
}
