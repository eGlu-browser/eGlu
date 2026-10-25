import XCTest
@testable import PadCore

/// History's records in iCloud: what they are called, which day a visit is
/// in, and how a day is cut into records CloudKit takes.
final class HistorySyncTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_500_000)

    func testRecordNamesGoBothWays() {
        let space = UUID()
        let day = HistoryCloudRecord.day(device: "D3F1-AA", space: space, day: "20261020", chunk: 2)
        XCTAssertEqual(day.name, "HistoryDay.D3F1-AA.\(space.uuidString).20261020.2")
        XCTAssertEqual(HistoryCloudRecord(name: day.name), day)
        let removal = HistoryCloudRecord.removal(UUID())
        XCTAssertEqual(HistoryCloudRecord(name: removal.name), removal)
        XCTAssertEqual(removal.type, "HistoryRemoval")
        for wrong in ["Space.x", "HistoryDay.d.\(space.uuidString).2026102.0", "HistoryDay..\(space.uuidString).20261020.0",
                      "HistoryDay.d.\(space.uuidString).20261340.0", "HistoryRemoval.nope"] {
            XCTAssertNil(HistoryCloudRecord(name: wrong), wrong)
        }
    }

    func testADayIsUTCsAndIsKept400Days() throws {
        XCTAssertEqual(HistoryCloudDay.key(for: now), "20261020")
        let range = try XCTUnwrap(HistoryCloudDay.range(of: "20261020"))
        XCTAssertTrue(range.from <= now && now <= range.to)
        XCTAssertEqual(range.to.timeIntervalSince(range.from), 86_400 - 0.001, accuracy: 0.0001)
        XCTAssertFalse(HistoryCloudDay.isExpired("20261020", now: now))
        XCTAssertTrue(HistoryCloudDay.isExpired(HistoryCloudDay.key(for: now.addingTimeInterval(-401 * 86_400)), now: now))
        XCTAssertNil(HistoryCloudDay.range(of: "20260230"))
    }

    func testADayIsCutIntoPiecesInTheOrderItWasVisited() {
        let space = UUID()
        let visits = (0..<50).map { n in
            HistoryVisit(space: space, url: URL(string: "https://example.com/\(n)")!, title: String(repeating: "t", count: 200),
                         time: now.addingTimeInterval(Double(-n)), device: "this", kind: .link)
        }
        let chunks = HistoryCloudPayload.chunks(visits, limit: 4_000)
        XCTAssertGreaterThan(chunks.count, 2)
        XCTAssertEqual(chunks.flatMap { $0 }.map(\.id), visits.sorted { $0.time < $1.time }.map(\.id), "oldest first, none lost")
        for chunk in chunks { XCTAssertLessThanOrEqual(HistoryCloudPayload.encode(chunk).count, 4_000) }
        XCTAssertEqual(HistoryCloudPayload.visits(from: HistoryCloudPayload.encode(visits))?.map(\.id), visits.map(\.id))
        XCTAssertEqual(HistoryCloudPayload.chunks([]).count, 0)
        let removal = HistoryRemoval(space: nil, scope: .range(from: now, to: now), made: now)
        XCTAssertEqual(HistoryCloudPayload.removal(from: HistoryCloudPayload.encode(removal)), removal)
    }

    #if canImport(SQLite3)
    func testTheStoreGivesADevicesDaysAndKeepsSyncState() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let store = try HistoryStore(url: file)
        let space = UUID()
        try await store.record(HistoryVisit(space: space, url: URL(string: "https://a.com")!, title: "A", time: now, device: "this", kind: .link))
        try await store.record(HistoryVisit(space: space, url: URL(string: "https://b.com")!, time: now.addingTimeInterval(-2 * 86_400),
                                            device: "this", kind: .link))
        try await store.record(HistoryVisit(space: space, url: URL(string: "https://c.com")!, time: now, device: "other", kind: .link))
        let days = try await store.days(device: "this")
        XCTAssertEqual(days, [HistoryDayOfSpace(space: space, day: "20261020"), HistoryDayOfSpace(space: space, day: "20261018")])
        let range = try XCTUnwrap(HistoryCloudDay.range(of: "20261020"))
        let today = try await store.visits(device: "this", space: space, from: range.from, to: range.to)
        XCTAssertEqual(today.map(\.title), ["A"], "this device's own, that day, with the page's name")
        let later = try await store.days(device: "this", since: now.addingTimeInterval(-86_400))
        XCTAssertEqual(later.count, 1)

        // The same visit again, from a record sent once the page had its name: the name comes.
        let unnamed = HistoryVisit(space: space, url: URL(string: "https://d.com")!, time: now, device: "other", kind: .link)
        try await store.merge([unnamed])
        var named = unnamed
        named.title = "D"
        named.summary = "About D"
        try await store.merge([named])
        let found = try await store.search(space: space, query: HistoryQuery(words: "about"))
        XCTAssertEqual(found.map(\.title), ["D"])

        try await store.setSyncValue(Data("x".utf8), for: "cloud")
        let kept = try await store.syncValue("cloud")
        XCTAssertEqual(kept, Data("x".utf8))
        try await store.setSyncValue(nil, for: "cloud")
        let gone = try await store.syncValue("cloud")
        XCTAssertNil(gone)
    }

    /// Every visit of this device's goes, whenever it was made (§2a): one
    /// recorded before sync was on, or named after it was made, included.
    func testADevicesVisitsGoWithTheNamesTheirPagesHaveNow() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let store = try HistoryStore(url: file)
        let space = UUID()
        let page = URL(string: "https://a.com/page")!
        try await store.record(HistoryVisit(space: space, url: page, time: now, device: "this", kind: .link))
        let time = try await store.update(space: space, url: page, title: "Named later", summary: "About it", device: "this")
        XCTAssertEqual(time, now, "the day of this device's visit, to send again")
        let range = try XCTUnwrap(HistoryCloudDay.range(of: "20261020"))
        let sent = try await store.visits(device: "this", space: space, from: range.from, to: range.to)
        XCTAssertEqual(sent.map(\.title), ["Named later"])
        XCTAssertEqual(sent.map(\.summary), ["About it"])
        let days = try await store.days(device: "this", since: now.addingTimeInterval(-86_400))
        XCTAssertEqual(days, [HistoryDayOfSpace(space: space, day: "20261020")])
    }
    #endif
}
