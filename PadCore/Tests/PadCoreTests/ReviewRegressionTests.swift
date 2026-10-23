import Foundation
import Testing
@testable import PadCore

struct ReviewRegressionTests {
    @Test func filteredSearchUsesTheMatchingVisitsDate() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try HistoryStore(url: folder.appendingPathComponent("history.sqlite"))
        let space = UUID()
        let url = try #require(URL(string: "https://example.com/article"))
        let today = Date(timeIntervalSince1970: 1_792_500_000)
        let yesterday = today.addingTimeInterval(-86_400)
        try await store.record(HistoryVisit(space: space, url: url, title: "Article", time: yesterday, device: "phone", kind: .link), now: today)
        try await store.merge([HistoryVisit(space: space, url: url, title: "Article", time: today, device: "mac", kind: .link)], now: today)
        let local = try await store.search(space: space, query: HistoryQuery(words: "article"), scope: HistoryScope(device: "phone"))
        #expect(local.first?.last == yesterday)
        let dated = try await store.search(space: space, query: HistoryQuery(words: "article", to: yesterday))
        #expect(dated.first?.last == yesterday)
        let all = try await store.search(space: space, query: HistoryQuery(words: "article"))
        #expect(all.first?.last == today)
    }

    @Test(arguments: [
        ("https://youtube.com./watch?v=abc&si=tracking", "https://youtube.com./watch?v=abc"),
        ("https://x.com./user/status/1?s=20&t=token", "https://x.com./user/status/1"),
        ("https://notyoutube.com./watch?si=keep", "https://notyoutube.com./watch?si=keep"),
    ])
    func cleanLinksWithFullyQualifiedHosts(_ pair: (String, String)) throws {
        let url = try #require(URL(string: pair.0))
        #expect(Tracking.clean(url).absoluteString == pair.1)
    }
}
