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

    /// A table's head row holds the row that draws it, then a block per
    /// row, none hinted.
    @Test func tables() {
        let reading = HandoffDocument.reading(
            markdown: "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |",
            facts: Self.facts())
        let rows = reading.blocks.filter { $0.kind == .table }
        #expect(rows.count == 3)
        #expect(rows[0].text == "| A | B |\n| --- | --- |")
        #expect(rows[1].text == "| 1 | 2 |")
        #expect(rows.allSatisfy { $0.hint == nil })
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
