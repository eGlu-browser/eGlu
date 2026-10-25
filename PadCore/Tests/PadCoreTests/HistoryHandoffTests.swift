import XCTest
@testable import PadCore

/// Handoffs in History: kept with a copy of their file, on this device only,
/// shown and filtered with the visits, and cleared with them.
final class HistoryHandoffTests: XCTestCase {
    private let space = UUID()
    private let now = Date(timeIntervalSince1970: 1_792_500_000)   // a Tuesday in October 2026

    private func url(_ text: String) throws -> URL {
        try XCTUnwrap(URL(string: text))
    }

    func testAHandoffIsKeptOnlyWhereAVisitWouldBe() throws {
        XCTAssertTrue(HistoryHandoff.keeps(try url("https://developer.apple.com/design/")))
        XCTAssertTrue(HistoryHandoff.keeps(nil), "a file on the device")
        XCTAssertTrue(HistoryHandoff.keeps(try url("file:///Users/me/report.pdf")), "a file's own address")
        XCTAssertFalse(HistoryHandoff.keeps(try url("https://accounts.google.com/signin")), "a sign-in page")
        XCTAssertFalse(HistoryHandoff.keeps(try url("https://example.com/report.pdf?token=abc")), "an address that signs whoever opens it in")
    }

    func testEachHandoffIsARowOfItsOwnBesideThePagesVisits() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let address = try url("https://figma.com/a")
        let page = HistoryPage(space: space, key: History.pageKey(address), url: address, title: "Figma", summary: "",
                               last: now, count: 1, frecency: 0)
        func handoff(_ minutesAgo: Double) -> HistoryEntry {
            HistoryEntry(handoff: HistoryHandoff(id: UUID(), space: space, title: "Figma", address: address,
                                                 time: now.addingTimeInterval(-minutesAgo * 60), file: URL(fileURLWithPath: "/a.md")))
        }
        let days = History.days([
            HistoryEntry(id: UUID(), time: now.addingTimeInterval(-60), kind: .link, page: page),
            handoff(2), handoff(3),
        ], calendar: calendar)
        XCTAssertEqual(days.first?.entries.map(\.kind), [.link, .handoff, .handoff], "the page once, and each handoff of it")
    }

    #if canImport(SQLite3)
    // MARK: The store

    private struct Kept {
        let store: HistoryStore
        let folder: URL
        let shelf: URL
    }

    /// A store with a folder for handoffs, and a shelf the handoffs' own files are written on first, as HandoffJob writes them.
    private func store() throws -> Kept {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)", isDirectory: true)
        let shelf = root.appendingPathComponent("Shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Handoffs", isDirectory: true)
        return Kept(store: try HistoryStore(url: root.appendingPathComponent("history.sqlite"), handoffs: folder), folder: folder, shelf: shelf)
    }

    private func file(_ name: String, _ text: String, on shelf: URL) throws -> URL {
        let file = shelf.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    private func visit(_ address: String, title: String, minutesAgo: Double, in space: UUID? = nil) throws -> HistoryVisit {
        HistoryVisit(space: space ?? self.space, url: try url(address), title: title, time: now.addingTimeInterval(-minutesAgo * 60),
                     device: "this", kind: .link)
    }

    @discardableResult
    private func handoff(_ title: String, address: String?, minutesAgo: Double, in space: UUID? = nil, into kept: Kept) async throws -> HistoryHandoff {
        let source = try file(title + ".md", "# " + title, on: kept.shelf)
        return try await kept.store.recordHandoff(space: space ?? self.space, title: title, address: try address.map(url),
                                                  time: now.addingTimeInterval(-minutesAgo * 60), copying: source)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func testAHandoffIsKeptWithACopyOfItsFileAndStaysOnTheDevice() async throws {
        let kept = try store()
        let source = try file("Pricing.md", "# Pricing\n\nSource: https://example.com/pricing", on: kept.shelf)
        let made = try await kept.store.recordHandoff(space: space, title: "Pricing", address: try url("https://example.com/pricing?utm_source=x"),
                                                      time: now, copying: source)
        XCTAssertEqual(made.file.lastPathComponent, "Pricing.md", "under the name it went with")
        XCTAssertEqual(made.file.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path,
                       kept.folder.standardizedFileURL.path, "in the folder for handoffs, in one of its own")
        XCTAssertEqual(try String(contentsOf: made.file, encoding: .utf8), "# Pricing\n\nSource: https://example.com/pricing")
        XCTAssertTrue(exists(source), "the shelf's file is the job's to remove")

        let entries = try await kept.store.entries(space: space)
        XCTAssertEqual(entries.map(\.kind), [.handoff])
        XCTAssertEqual(entries.first?.handoff?.title, "Pricing")
        XCTAssertEqual(entries.first?.handoff?.address?.absoluteString, "https://example.com/pricing", "without the tags, as a visit is kept")
        XCTAssertEqual(entries.first?.handoff?.prompt, Handoff.prompt(url: try url("https://example.com/pricing")))
        XCTAssertEqual(entries.first?.handoff?.file, made.file)

        // None of it is a visit: not for iCloud, the command bar, or a new tab's list.
        let sent = try await kept.store.visits(device: "this", since: .distantPast)
        XCTAssertTrue(sent.isEmpty, "nothing for other devices")
        let days = try await kept.store.days(device: "this")
        XCTAssertTrue(days.isEmpty, "no day record to send")
        let pages = try await kept.store.search(space: space, query: HistoryQuery(words: "pricing"))
        XCTAssertTrue(pages.isEmpty, "no page the command bar offers")
        let recent = try await kept.store.recent(space: space, device: "this", others: false)
        XCTAssertTrue(recent.isEmpty)

        let file = try await handoff("Notes", address: nil, minutesAgo: 1, into: kept)
        XCTAssertEqual(file.prompt, Handoff.prompt(file: "Notes"), "a file on the device goes with its name")
    }

    func testAHandoffThatCameAsAVisitIsLetGo() async throws {
        let kept = try store()
        var visit = try visit("https://example.com/", title: "Example", minutesAgo: 1)
        visit.kind = .handoff
        let merged = try await kept.store.merge([visit], now: now)
        XCTAssertTrue(merged.isEmpty)
        let entries = try await kept.store.entries(space: space)
        XCTAssertTrue(entries.isEmpty)
    }

    func testAStoreWithNoFolderKeepsNoHandoff() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(url: root.appendingPathComponent("history.sqlite"))
        let source = try file("A.md", "# A", on: root)
        do {
            try await store.recordHandoff(space: space, title: "A", address: nil, time: now, copying: source)
            XCTFail("kept with nowhere to keep its file")
        } catch HistoryStoreError.noHandoffFolder {}
    }

    func testTheFilterShowsHandoffsAlonePagesAloneOrBoth() async throws {
        let kept = try store()
        try await kept.store.record(try visit("https://figma.com/a", title: "Figma page", minutesAgo: 1), now: now)
        try await handoff("Figma handoff", address: "https://figma.com/a", minutesAgo: 2, into: kept)
        try await handoff("Report", address: nil, minutesAgo: 3, into: kept)
        var there = try visit("https://figma.com/c", title: "Figma there", minutesAgo: 4)
        there.device = "other"
        try await kept.store.merge([there], now: now)
        let calendar = Calendar(identifier: .gregorian)
        func titles(_ filter: HistoryFilter) async throws -> [String] {
            try await kept.store.entries(space: space, scope: filter.scope(device: "this", now: now, calendar: calendar)).map(\.page.title)
        }
        let all = try await titles(HistoryFilter())
        XCTAssertEqual(all, ["Figma page", "Figma handoff", "Report", "Figma there"], "newest first, both together")
        let handoffs = try await titles(HistoryFilter(show: .handoffs))
        XCTAssertEqual(handoffs, ["Figma handoff", "Report"])
        let pages = try await titles(HistoryFilter(show: .pages))
        XCTAssertEqual(pages, ["Figma page", "Figma there"])
        let here = try await titles(HistoryFilter(source: .thisDevice))
        XCTAssertEqual(here, ["Figma page", "Figma handoff", "Report"], "handoffs are this device's")
        let others = try await titles(HistoryFilter(source: .otherDevices))
        XCTAssertEqual(others, ["Figma there"], "and never another's")
        let yesterday = try await titles(HistoryFilter(period: .yesterday, show: .handoffs))
        XCTAssertTrue(yesterday.isEmpty)
        XCTAssertFalse(HistoryFilter(show: .handoffs).isEmpty)

        let limited = try await kept.store.entries(space: space, limit: 2)
        XCTAssertEqual(limited.map(\.page.title), ["Figma page", "Figma handoff"], "the newest of both, to the limit")
        let older = try await kept.store.entries(space: space, before: limited.last?.time, limit: 2)
        XCTAssertEqual(older.map(\.page.title), ["Report", "Figma there"], "and the next ones after them")

        // Searched by name and address, within the filter.
        let byName = try await kept.store.handoffs(space: space, query: HistoryQuery(words: "repo"))
        XCTAssertEqual(byName.map(\.title), ["Report"])
        let byAddress = try await kept.store.handoffs(space: space, query: HistoryQuery(words: "figma"))
        XCTAssertEqual(byAddress.map(\.title), ["Figma handoff"])
        let filtered = try await kept.store.handoffs(space: space, query: HistoryQuery(words: "figma"),
                                                    scope: HistoryFilter(show: .pages).scope(device: "this", now: now, calendar: calendar))
        XCTAssertTrue(filtered.isEmpty, "pages alone")
        let found = try await kept.store.search(space: space, query: HistoryQuery(words: "figma"),
                                                scope: HistoryFilter(show: .handoffs).scope(device: "this", now: now, calendar: calendar))
        XCTAssertTrue(found.isEmpty, "handoffs alone: no page found")
        let elsewhere = try await kept.store.handoffs(space: UUID(), query: HistoryQuery(words: "figma"))
        XCTAssertTrue(elsewhere.isEmpty, "another space's")
    }

    func testClearingAStretchOfTimeTakesItsHandoffsAndTheirFiles() async throws {
        let kept = try store()
        let other = UUID()
        let recent = try await handoff("Recent", address: "https://example.com/a", minutesAgo: 10, into: kept)
        let old = try await handoff("Old", address: nil, minutesAgo: 120, into: kept)
        let there = try await handoff("There", address: nil, minutesAgo: 10, in: other, into: kept)

        // A page's clearing says which visits, and leaves handoffs of the page.
        let page = HistoryRemoval(space: space, scope: .page(History.digest(ofKey: History.pageKey(try url("https://example.com/a")))), made: now)
        try await kept.store.remove(page, now: now)
        let afterPage = try await kept.store.entries(space: space)
        XCTAssertEqual(afterPage.map(\.page.title), ["Recent", "Old"])

        let hour = HistoryRemoval(space: space, scope: HistorySpan.lastHour.scope(now: now), made: now, wall: now)
        try await kept.store.remove(hour, now: now)
        let left = try await kept.store.entries(space: space)
        XCTAssertEqual(left.map(\.page.title), ["Old"], "the last hour's handoff goes")
        XCTAssertFalse(exists(recent.file.deletingLastPathComponent()), "with its file and its folder")
        XCTAssertTrue(exists(old.file))
        let elsewhere = try await kept.store.entries(space: other)
        XCTAssertEqual(elsewhere.map(\.page.title), ["There"], "another space's stays")

        let everything = HistoryRemoval(space: nil, scope: .all, made: now, wall: now)
        try await kept.store.remove(everything, now: now)
        let none = try await kept.store.entries(space: space)
        XCTAssertTrue(none.isEmpty)
        let noneThere = try await kept.store.entries(space: other)
        XCTAssertTrue(noneThere.isEmpty, "everything in every space")
        XCTAssertFalse(exists(old.file))
        XCTAssertFalse(exists(there.file))

        // Made after a clearing of everything that arrives late (from another device): it stays.
        let later = try await handoff("Later", address: nil, minutesAgo: 1, into: kept)
        let late = HistoryRemoval(space: nil, scope: .all, made: now.addingTimeInterval(-300), wall: now.addingTimeInterval(-300))
        try await kept.store.remove(late, now: now)
        let stays = try await kept.store.entries(space: space)
        XCTAssertEqual(stays.map(\.page.title), ["Later"])
        XCTAssertTrue(exists(later.file))
    }

    func testOneHandoffDeletedTakesItsFile() async throws {
        let kept = try store()
        let one = try await handoff("One", address: nil, minutesAgo: 2, into: kept)
        let two = try await handoff("Two", address: nil, minutesAgo: 1, into: kept)
        let before = await kept.store.revision
        try await kept.store.removeHandoff(one.id)
        let after = await kept.store.revision
        XCTAssertGreaterThan(after, before, "what shows history looks again")
        let left = try await kept.store.entries(space: space)
        XCTAssertEqual(left.map(\.page.title), ["Two"])
        XCTAssertFalse(exists(one.file.deletingLastPathComponent()))
        XCTAssertTrue(exists(two.file))
    }

    func testAtLaunchAFileWithNoHandoffGoesAndAHandoffWithNoFileToo() async throws {
        let kept = try store()
        let one = try await handoff("One", address: nil, minutesAgo: 2, into: kept)
        let two = try await handoff("Two", address: nil, minutesAgo: 1, into: kept)
        let files = FileManager.default
        // Left by a handoff whose row went while its file couldn't, and by something else.
        let stray = kept.folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: stray, withIntermediateDirectories: true)
        try Data("# Stray".utf8).write(to: stray.appendingPathComponent("Stray.md"))
        let loose = kept.folder.appendingPathComponent("Loose.md")
        try Data("# Loose".utf8).write(to: loose)
        try files.removeItem(at: two.file)

        try await kept.store.tidyHandoffs()
        XCTAssertFalse(exists(stray), "a file with no handoff goes")
        XCTAssertFalse(exists(loose))
        XCTAssertTrue(exists(one.file), "a handoff's own stays")
        let left = try await kept.store.entries(space: space)
        XCTAssertEqual(left.map(\.page.title), ["One"], "a handoff whose file is gone goes")

        // With no folder yet, there is nothing to tidy and nothing is lost.
        let fresh = try store()
        try await fresh.store.tidyHandoffs()
    }

    func testOldHandoffsGoAfterTheRetentionAndAGoneSpacesWithIt() async throws {
        let kept = try store()
        let old = try await handoff("Old", address: nil, minutesAgo: 60 * 24 * 40, into: kept)
        let new = try await handoff("New", address: nil, minutesAgo: 1, into: kept)
        let other = UUID()
        let gone = try await handoff("Gone space", address: nil, minutesAgo: 1, in: other, into: kept)
        try await kept.store.prune(keeping: .month, now: now)
        let left = try await kept.store.entries(space: space)
        XCTAssertEqual(left.map(\.page.title), ["New"], "older than a month goes")
        XCTAssertFalse(exists(old.file))

        try await kept.store.keepSpaces([space])
        let there = try await kept.store.entries(space: other)
        XCTAssertTrue(there.isEmpty, "a space gone takes its handoffs")
        XCTAssertFalse(exists(gone.file))
        XCTAssertTrue(exists(new.file))

        try await kept.store.removeSpace(space)
        XCTAssertFalse(exists(new.file))
    }
    #endif
}
