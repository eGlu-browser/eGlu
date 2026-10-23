import Foundation
import XCTest
@testable import PadCore

final class LegacyDataMigrationTests: XCTestCase {
    private let bundle = "test.safience.migration"
    private let workspace = "Application Support/Safience"
    private let website = "WebKit/WebsiteDataStore"

    private func temporaryLibrary() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SafienceMigrationTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func source(_ library: URL, _ path: String) -> URL {
        library.appendingPathComponent("Containers/\(bundle)/Data/Library/\(path)")
    }

    private func outside(_ library: URL, _ path: String) -> URL {
        library.appendingPathComponent(path)
    }

    private func put(_ value: String, at file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: file)
    }

    private func read(_ file: URL) throws -> String {
        String(decoding: try Data(contentsOf: file), as: UTF8.self)
    }

    private func journal(_ library: URL) -> URL {
        outside(library, "Application Support/Safience Migration/\(bundle).json")
    }

    private func checkpoint(_ library: URL) throws -> Set<String> {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: journal(library))) as? [String: [String]]
        return Set(json?["completed"] ?? [])
    }

    func testCopiesLegacyDataAndLeavesEverySourceIntact() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let inputs = [workspace + "/workspace.json": "workspace", workspace + "/history.sqlite-wal": "wal",
                      website + "/StoreA/IndexedDB/data": "site data", "WebKit/ContentRuleLists/rules": "rules"]
        for (path, value) in inputs { try put(value, at: source(library, path)) }
        let result = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(result.completed, [workspace, website, "WebKit/ContentRuleLists"])
        XCTAssertTrue(result.preservedExisting.isEmpty)
        for (path, value) in inputs {
            let destination = path.hasPrefix("WebKit/") ? path.replacingOccurrences(of: "WebKit/", with: "WebKit/\(bundle)/") : path
            XCTAssertEqual(try read(outside(library, destination)), value)
            XCTAssertEqual(try read(source(library, path)), value)
        }
        XCTAssertEqual(try checkpoint(library), result.completed)
    }

    func testOutsideWorkspaceRemainsAuthoritativeWithoutBackupOrMerge() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        try put("legacy", at: source(library, workspace + "/workspace.json"))
        try put("legacy history", at: source(library, workspace + "/history.sqlite"))
        try put("current", at: outside(library, workspace + "/workspace.json"))
        try put("current wal", at: outside(library, workspace + "/history.sqlite-wal"))
        let result = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertTrue(result.preservedExisting.contains(workspace))
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "current")
        XCTAssertEqual(try read(outside(library, workspace + "/history.sqlite-wal")), "current wal")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(library, workspace + "/history.sqlite").path))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: outside(library, "Application Support").path)
        XCTAssertEqual(Set(siblings), ["Safience", "Safience Migration"], "relaunch must not make repeated whole-workspace backups")
        XCTAssertEqual(try read(source(library, workspace + "/workspace.json")), "legacy")
    }

    func testExistingWebKitStoresArePreservedAsUnitsAndMissingStoresAreCopied() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let destination = "WebKit/\(bundle)/WebsiteDataStore"
        try put("legacy db", at: source(library, website + "/A/Cookies.sqlite"))
        try put("legacy wal", at: source(library, website + "/A/Cookies.sqlite-wal"))
        try put("missing db", at: source(library, website + "/B/Cookies.sqlite"))
        try put("missing wal", at: source(library, website + "/B/Cookies.sqlite-wal"))
        try put("current db", at: outside(library, destination + "/A/Cookies.sqlite"))
        let result = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertTrue(result.preservedExisting.contains(website))
        XCTAssertEqual(try read(outside(library, destination + "/A/Cookies.sqlite")), "current db")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(library, destination + "/A/Cookies.sqlite-wal").path), "an existing store must not receive legacy SQLite sidecars")
        XCTAssertEqual(try read(outside(library, destination + "/B/Cookies.sqlite")), "missing db")
        XCTAssertEqual(try read(outside(library, destination + "/B/Cookies.sqlite-wal")), "missing wal")
    }

    func testStagedCopyResumesAndOnlyCopiesMissingFiles() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let kept = source(library, workspace + "/already-copied")
        try put("complete", at: kept)
        try put("remaining", at: source(library, workspace + "/remaining"))
        let staged = outside(library, "Application Support/.Safience.safience-migration")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: kept, to: staged.appendingPathComponent("already-copied"))
        let progress = MigrationProgressRecorder()
        _ = try LegacyDataMigration.run(library: library, bundle: bundle) { progress.record($0) }
        XCTAssertEqual(progress.lastCopied(in: workspace), 1, "a completed staged file is reused instead of copying the directory again")
        XCTAssertEqual(try read(outside(library, workspace + "/already-copied")), "complete")
        XCTAssertEqual(try read(outside(library, workspace + "/remaining")), "remaining")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testPreviousMovingDirectoryIsAdoptedWithoutRecopyingCompletedFiles() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let kept = source(library, website + "/A/already-copied")
        try put("complete", at: kept)
        try put("remaining", at: source(library, website + "/A/remaining"))
        let moving = outside(library, "WebKit/\(bundle)/WebsiteDataStore.moving/A")
        try FileManager.default.createDirectory(at: moving, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: kept, to: moving.appendingPathComponent("already-copied"))
        let progress = MigrationProgressRecorder()
        _ = try LegacyDataMigration.run(library: library, bundle: bundle) { progress.record($0) }
        XCTAssertEqual(progress.lastCopied(in: website), 1)
        XCTAssertEqual(try read(outside(library, "WebKit/\(bundle)/WebsiteDataStore/A/already-copied")), "complete")
        XCTAssertEqual(try read(outside(library, "WebKit/\(bundle)/WebsiteDataStore/A/remaining")), "remaining")
        XCTAssertFalse(FileManager.default.fileExists(atPath: moving.deletingLastPathComponent().path))
    }

    func testFailureLeavesNoPartialPublishedDirectoryAndRetryResumes() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        try put("legacy", at: source(library, workspace + "/nested/file"))
        let blocker = outside(library, "Application Support/.Safience.safience-migration/nested")
        try put("blocking file", at: blocker)
        XCTAssertThrowsError(try LegacyDataMigration.run(library: library, bundle: bundle))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(library, workspace).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal(library).path))
        XCTAssertEqual(try read(source(library, workspace + "/nested/file")), "legacy")
        try FileManager.default.removeItem(at: blocker)
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(try read(outside(library, workspace + "/nested/file")), "legacy")
    }

    func testEachCompletedDirectoryIsCheckpointedBeforeALaterFailure() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        try put("workspace", at: source(library, workspace + "/workspace.json"))
        try put("site", at: source(library, website + "/A/data"))
        let blocker = outside(library, "WebKit/\(bundle)/.WebsiteDataStore.safience-migration")
        try put("blocked", at: blocker)
        XCTAssertThrowsError(try LegacyDataMigration.run(library: library, bundle: bundle))
        XCTAssertEqual(try checkpoint(library), [workspace])
        try put("current edit", at: outside(library, workspace + "/workspace.json"))
        try FileManager.default.removeItem(at: blocker)
        let result = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(result.completed, [workspace, website, "WebKit/ContentRuleLists"])
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "current edit")
        XCTAssertEqual(try read(outside(library, "WebKit/\(bundle)/WebsiteDataStore/A/data")), "site")
    }

    func testJournalFailureAfterPublicationDoesNotReplacePublishedDataOnRetry() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        try put("legacy", at: source(library, workspace + "/workspace.json"))
        let blocker = outside(library, "Application Support/Safience Migration")
        try put("journal blocker", at: blocker)
        XCTAssertThrowsError(try LegacyDataMigration.run(library: library, bundle: bundle))
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "legacy")
        try put("new current edit", at: outside(library, workspace + "/workspace.json"))
        try FileManager.default.removeItem(at: blocker)
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "new current edit")
        XCTAssertEqual(try read(source(library, workspace + "/workspace.json")), "legacy")
    }

    func testCompletedJournalSkipsFutureLegacyChangesAndRepeatedRuns() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        try put("legacy", at: source(library, workspace + "/workspace.json"))
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        try put("later legacy change", at: source(library, workspace + "/workspace.json"))
        let progress = MigrationProgressRecorder()
        for _ in 0..<3 {
            _ = try LegacyDataMigration.run(library: library, bundle: bundle) { progress.record($0) }
        }
        XCTAssertEqual(progress.count, 0)
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "legacy")
    }
    func testMatchingSizeAndTimestampCannotHideAnInterruptedCopy() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let from = source(library, workspace + "/workspace.json")
        let staged = outside(library, "Application Support/.Safience.safience-migration/workspace.json")
        try put("valid-data", at: from)
        try put("wrong-data", at: staged)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        for file in [from, staged] {
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        }
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "valid-data")
        XCTAssertEqual(try read(from), "valid-data")
    }
}

private final class MigrationProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LegacyDataMigration.Progress] = []

    func record(_ value: LegacyDataMigration.Progress) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return values.count
    }

    func lastCopied(in item: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return values.last { $0.item == item }?.copiedFiles
    }


}
