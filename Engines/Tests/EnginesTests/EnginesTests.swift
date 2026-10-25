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

    func testEveryDialectIsTaken() async throws {
        XCTAssertEqual(Dialect.allCases.count, 5)
        for dialect in Dialect.allCases {
            let grammar = try Grammar(settings: GrammarSettings(dialect: dialect))
            _ = try await grammar.lint("A sentence.")
        }
        let american = try Grammar(settings: GrammarSettings(dialect: .american))
        let indian = try Grammar(settings: GrammarSettings(dialect: .indian))
        let lakh = "It cost one lakh rupees."
        let flagged = try await american.lint(lakh)
        XCTAssertFalse(flagged.isEmpty)
        let taken = try await indian.lint(lakh)
        XCTAssertEqual(taken, [])
    }

    func testValuesRoundTripThroughCodable() throws {
        let settings = GrammarSettings(dialect: .indian, rules: ["SpellCheck": false], words: ["eGlu"])
        XCTAssertEqual(
            try JSONDecoder().decode(GrammarSettings.self, from: JSONEncoder().encode(settings)),
            settings)
        let lint = GrammarLint(
            start: 0, end: 3, rule: "SpellCheck", kind: "Spelling", message: "m",
            priority: 63, suggestions: [.replace("the"), .insert("s"), .remove], context: "00")
        XCTAssertEqual(
            try JSONDecoder().decode(GrammarLint.self, from: JSONEncoder().encode(lint)), lint)
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

    /// Every call of one Grammar runs on one thread, its own, whichever
    /// task makes it: Harper's per-thread models are loaded once.
    func testCallsRunOnTheGrammarsOwnThread() async throws {
        let grammar = try Grammar()
        try await grammar.warmUp()
        let first = await grammar.threadID()
        var seen: Set<UInt32> = [first]
        try await withThrowingTaskGroup(of: UInt32.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    _ = try await grammar.lint("I has a apple.")
                    return await grammar.threadID()
                }
            }
            for try await id in group { seen.insert(id) }
        }
        XCTAssertEqual(seen, [first])
        let other = try Grammar()
        let otherID = await other.threadID()
        XCTAssertNotEqual(otherID, first)
    }

    /// A Grammar let go of, used or never used, frees its linter (on its
    /// thread, or here when it never had one) without crashing.
    func testGrammarsComeAndGo() async throws {
        for index in 0..<4 {
            let grammar = try Grammar()
            if index.isMultiple(of: 2) {
                _ = try await grammar.lint("teh")
            }
        }
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

    func testPagesAndFormatsRoundTripThroughCodable() throws {
        let pages = try Documents.pdfPages(fixture("text.pdf"))
        XCTAssertEqual(
            try JSONDecoder().decode(PDFPages.self, from: JSONEncoder().encode(pages)), pages)
        XCTAssertEqual(
            try JSONDecoder().decode([DocumentFormat].self, from: Data(#"["excel"]"#.utf8)), [.excel])
    }

    func testDetect() throws {
        XCTAssertEqual(try Documents.detect(fixture("hello.docx")), .docx)
        XCTAssertNil(try Documents.detect(Data([0x11, 0x22, 0x33, 0x44])))
    }

    /// Every fixture through the Swift API, by the format it is detected as
    /// and by that format given: a `DocumentFormat` whose name the engine
    /// doesn't take fails here, not on a person's file.
    func testEachFixtureByItsFormat() throws {
        let fixtures: [(file: String, format: DocumentFormat, words: String)] = [
            ("hello.docx", .docx, "Quarterly Report"),
            ("talk.pptx", .pptx, "Launch Plan"),
            ("sheets.xlsx", .excel, "Seoul"),
            ("text.pdf", .pdf, "Hello"),
        ]
        for (file, format, words) in fixtures {
            let data = try fixture(file)
            XCTAssertEqual(try Documents.detect(data), format, file)
            let detected = try Documents.markdown(data)
            XCTAssertEqual(detected.format, format, file)
            XCTAssertTrue(detected.markdown.contains(words), "\(file): \(detected.markdown)")
            let given = try Documents.markdown(data, format: format)
            XCTAssertEqual(given.format, format, file)
            XCTAssertTrue(given.markdown.contains(words), "\(file) as \(format): \(given.markdown)")
        }
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

extension Grammar {
    /// The Mach thread the actor's code runs on.
    func threadID() -> UInt32 {
        pthread_mach_thread_np(pthread_self())
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
