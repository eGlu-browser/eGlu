#if canImport(SQLite3)
import Foundation
import SQLite3
import Testing
@testable import PadCore

@MainActor
struct HistoryFaultTests {
    private func fixture() throws -> (URL, HistoryStore, OpaquePointer) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-fault-\(UUID().uuidString).sqlite")
        let store = try HistoryStore(url: file)
        var connection: OpaquePointer?
        guard sqlite3_open(file.path, &connection) == SQLITE_OK, let connection else { throw HistoryStoreError.sqlite("fixture open") }
        return (file, store, connection)
    }
    private func sql(_ text: String, in connection: OpaquePointer) throws {
        guard sqlite3_exec(connection, text, nil, nil, nil) == SQLITE_OK else {
            throw HistoryStoreError.sqlite(String(cString: sqlite3_errmsg(connection)))
        }
    }
    private func visit(space: UUID) -> HistoryVisit {
        HistoryVisit(space: space, url: URL(string: "https://example.com/retained")!, title: "Retained", time: Date(), device: "fixture", kind: .link)
    }

    @Test func failedOpenLeavesExistingBytesIntact() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-unavailable-\(UUID().uuidString).sqlite")
        let bytes = Data("synthetic damaged database".utf8)
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: (any Error).self) { try HistoryStore(url: file) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func aReadFailureThrowsInsteadOfReturningAnEmptyHistory() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        try sql("ALTER TABLE visits RENAME TO retained_visits", in: connection)
        do {
            _ = try await store.entries(space: space)
            Issue.record("A missing table was presented as a successful query")
        } catch {}
        try sql("ALTER TABLE retained_visits RENAME TO visits", in: connection)
        let kept = try await store.entries(space: space)
        #expect(kept.count == 1)
    }

    @Test func failedClearRollsBackVisitsTombstonesAndRevisionBeforeRetry() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        let before = await store.revision
        try sql("CREATE TRIGGER deny_delete BEFORE DELETE ON visits BEGIN SELECT RAISE(ABORT, 'synthetic write failure'); END", in: connection)
        let removal = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(1))
        do {
            try await store.remove(removal, syncAccount: "account-A")
            Issue.record("A failed delete was acknowledged")
        } catch {}
        let kept = try await store.entries(space: space)
        #expect(kept.count == 1)
        #expect(await store.allRemovals().isEmpty)
        #expect(await store.revision == before)
        #expect(try await store.pendingClearings(for: "account-A").isEmpty)
        try sql("DROP TRIGGER deny_delete", in: connection)
        try await store.remove(removal, syncAccount: "account-A")
        #expect(try await store.entries(space: space).isEmpty)
        #expect(await store.allRemovals().map(\.id) == [removal.id])
        #expect(await store.revision == before + 1)
        #expect(try await store.pendingClearings(for: "account-A").map(\.id) == [removal.id])
        #expect(try await store.pendingClearings(for: "account-B").isEmpty)
        try await store.clearingSynced(removal.id)
        #expect(try await store.pendingClearings(for: "account-A").isEmpty)
    }

    @Test func aLaterLocalClearDoesNotLoseAnEarlierAccountBoundIntent() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        let first = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(1))
        try await store.remove(first, syncAccount: "account-A")
        let local = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(2))
        try await store.remove(local)
        #expect(try await store.pendingClearings(for: "account-A").map(\.id) == [first.id])
        #expect(try await store.pendingClearings(for: "account-B").isEmpty)
    }

    @Test func lockedDatabaseDoesNotAcknowledgeClearAndCanRetryTheSameRequest() async throws {
        let (file, store, connection) = try fixture()
        defer { sqlite3_close(connection); try? FileManager.default.removeItem(at: file) }
        let space = UUID()
        try await store.record(visit(space: space))
        let before = await store.revision
        let removal = HistoryRemoval(space: space, scope: .all, made: Date().addingTimeInterval(1))
        try sql("BEGIN IMMEDIATE", in: connection)
        do {
            try await store.remove(removal)
            Issue.record("A locked database was acknowledged as cleared")
        } catch {}
        #expect(await store.revision == before)
        #expect(await store.allRemovals().isEmpty)
        try sql("ROLLBACK", in: connection)
        #expect(try await store.entries(space: space).count == 1)
        try await store.remove(removal)
        #expect(try await store.entries(space: space).isEmpty)
    }
}
#endif
