import XCTest
@testable import Engines

final class GrammarTests: XCTestCase {
    func testLintsHaveUTF16SpansAndSuggestions() async throws {
        let grammar = try Grammar()
        try await grammar.warmUp()
        let lints = try await grammar.lint("I has a apple.")
        XCTAssertTrue(lints.contains { $0.rule.contains("Agreement") })
        XCTAssertTrue(lints.contains { !$0.suggestions.isEmpty })
    }

    func testEmojiAndHangulSpansAreUTF16() async throws {
        let grammar = try Grammar()
        let text = "\u{1F600} teh"
        let lints = try await grammar.lint(text)
        // "teh" begins at UTF-16 offset 3 (surrogate pair + space).
        XCTAssertTrue(lints.contains { $0.start == 3 && $0.end == 6 }, "\(lints)")
    }

    func testOffRuleAndDictionaryWord() async throws {
        let grammar = try Grammar()
        let before = try await grammar.lint("Safience works.")
        XCTAssertTrue(before.contains { $0.rule == "SpellCheck" })
        try await grammar.configure(settings: GrammarSettings(words: ["Safience"]))
        let after = try await grammar.lint("Safience works.")
        XCTAssertFalse(after.contains { $0.rule == "SpellCheck" })

        let off = try Grammar(settings: GrammarSettings(rules: ["SpellCheck": false]))
        let lints = try await off.lint("I havv teh answer.")
        XCTAssertFalse(lints.contains { $0.rule == "SpellCheck" })
    }

    func testIgnoreContext() async throws {
        let grammar = try Grammar()
        let lints = try await grammar.lint("I has a apple.")
        guard let first = lints.first else { return XCTFail("no lints") }
        try await grammar.ignore(context: first.context)
        let after = try await grammar.lint("I has a apple.")
        XCTAssertFalse(after.contains { $0.context == first.context })
    }

    func testRules() throws {
        let rules = try Grammar.rules()
        XCTAssertGreaterThan(rules.count, 50)
        let spell = try XCTUnwrap(rules.first { $0.id == "SpellCheck" })
        XCTAssertFalse(spell.label.isEmpty)
        XCTAssertFalse(spell.description.isEmpty)
        XCTAssertFalse(spell.group.isEmpty)
    }

    func testTooLargeThrows() async throws {
        let grammar = try Grammar()
        let big = String(repeating: "a", count: 200_001)
        await XCTAssertThrowsErrorAsync(try await grammar.lint(big)) { error in
            XCTAssertEqual((error as? EngineError)?.kind, .tooLarge)
        }
    }
}

final class DocumentsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        // The same fixtures eglu-engines/tests/fixtures holds.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // EnginesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Engines
            .appending(path: "eglu-engines/tests/fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func testDetect() throws {
        XCTAssertEqual(try Documents.detect(fixture("hello.docx")), .docx)
        XCTAssertNil(try Documents.detect(Data([0x11, 0x22, 0x33, 0x44])))
    }

    func testDocxMarkdown() throws {
        let result = try Documents.markdown(fixture("hello.docx"))
        XCTAssertEqual(result.format, .docx)
        XCTAssertTrue(result.markdown.contains("Quarterly Report"))
        XCTAssertTrue(result.markdown.contains("Ada"))
    }

    func testPdfPages() throws {
        let pages = try Documents.pdfPages(fixture("text.pdf"))
        XCTAssertEqual(pages.pageCount, 1)
        XCTAssertEqual(pages.pages.count, 1)
        XCTAssertEqual(pages.pages[0].page, 0)
        XCTAssertFalse(pages.pages[0].needsOCR)
        XCTAssertTrue(pages.pages[0].markdown.contains("Hello"))
    }

    func testPicturePdfNeedsOCR() throws {
        let pages = try Documents.pdfPages(fixture("picture.pdf"))
        XCTAssertTrue(pages.pages[0].needsOCR)
    }

    func testGarbageIsAnErrorNotACrash() throws {
        XCTAssertThrowsError(try Documents.markdown(Data([0x11, 0x22, 0x33]))) { error in
            let kind = (error as? EngineError)?.kind
            XCTAssertTrue(kind == .unsupported || kind == .malformed, "\(String(describing: kind))")
        }
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error \(message)", file: file, line: line)
    } catch {
        handler(error)
    }
}
