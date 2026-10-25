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
        "report", "deck", "budget", "scan",
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
