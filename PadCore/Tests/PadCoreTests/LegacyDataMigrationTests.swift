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
    func testResumedStagingDropsObsoleteSidecarsAndFilesBeforePublication() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        try put("current database", at: source(library, workspace + "/history.sqlite"))
        try put("legitimate file", at: source(library, workspace + "/.report.copying"))
        let staged = outside(library, "Application Support/.Safience.safience-migration")
        for name in ["history.sqlite-wal", "history.sqlite-shm", "old/nested/file", ".history.sqlite.copying"] {
            try put("obsolete", at: staged.appendingPathComponent(name))
        }
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        let published = outside(library, workspace)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: published.path)), ["history.sqlite", ".report.copying"])
        XCTAssertEqual(try read(published.appendingPathComponent("history.sqlite")), "current database")
        XCTAssertEqual(try read(published.appendingPathComponent(".report.copying")), "legitimate file")
        XCTAssertEqual(try read(source(library, workspace + "/history.sqlite")), "current database")
    }

    func testMissingWebKitStoreReconcilesItsOwnResumedStaging() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let target = "WebKit/\(bundle)/WebsiteDataStore"
        try put("current A", at: outside(library, target + "/A/Cookies.sqlite"))
        try put("current B", at: source(library, website + "/B/Cookies.sqlite"))
        try put("obsolete WAL", at: outside(library, target + "/.B.safience-migration/Cookies.sqlite-wal"))
        try put("abandoned copy", at: outside(library, target + "/.B.safience-migration/.Cookies.sqlite.copying"))
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(try read(outside(library, target + "/A/Cookies.sqlite")), "current A")
        XCTAssertEqual(try read(outside(library, target + "/B/Cookies.sqlite")), "current B")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside(library, target + "/B").path), ["Cookies.sqlite"])
    }

    private func isPermissionFailure(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           [CocoaError.Code.fileReadNoPermission.rawValue, CocoaError.Code.fileWriteNoPermission.rawValue].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain,
           [Int(POSIXErrorCode.EACCES.rawValue), Int(POSIXErrorCode.EPERM.rawValue)].contains(error.code) { return true }
        return (error.userInfo[NSUnderlyingErrorKey] as? Error).map(isPermissionFailure) ?? false
    }

    func testAuthoritativeOutsideWorkspaceDoesNotRequireAnUnusedLegacyRead() throws {
        let library = try temporaryLibrary()
        let denied = source(library, "Application Support")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
            try? FileManager.default.removeItem(at: library)
        }
        try put("legacy workspace", at: source(library, workspace + "/workspace.json"))
        try put("current workspace", at: outside(library, workspace + "/workspace.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        let result = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertTrue(result.preservedExisting.contains(workspace))
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "current workspace")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        XCTAssertEqual(try read(source(library, workspace + "/workspace.json")), "legacy workspace")
    }

    func testDeniedSourceProbeDoesNotCheckpointMigrationAsMissing() throws {
        let library = try temporaryLibrary()
        let denied = source(library, "Application Support")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
            try? FileManager.default.removeItem(at: library)
        }
        try put("retained workspace", at: source(library, workspace + "/workspace.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        XCTAssertThrowsError(try LegacyDataMigration.run(library: library, bundle: bundle)) { error in
            XCTAssertTrue(self.isPermissionFailure(error), "Expected denied access, got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal(library).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(library, workspace).path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        XCTAssertEqual(try read(source(library, workspace + "/workspace.json")), "retained workspace")
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(try read(outside(library, workspace + "/workspace.json")), "retained workspace")
    }

    func testDeniedSubtreeLeavesStagingUnprunedAndUncheckpointedUntilRetry() throws {
        let library = try temporaryLibrary()
        let denied = source(library, workspace + "/protected")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
            try? FileManager.default.removeItem(at: library)
        }
        try put("retained source", at: denied.appendingPathComponent("file"))
        let old = outside(library, "Application Support/.Safience.safience-migration/history.sqlite-wal")
        try put("keep until enumeration succeeds", at: old)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        XCTAssertThrowsError(try LegacyDataMigration.run(library: library, bundle: bundle)) { error in
            XCTAssertTrue(self.isPermissionFailure(error), "Expected denied access, got \(error)")
        }
        XCTAssertEqual(try read(old), "keep until enumeration succeeds")
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal(library).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(library, workspace).path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        XCTAssertEqual(try read(outside(library, workspace + "/protected/file")), "retained source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(library, workspace + "/history.sqlite-wal").path))
    }

    func testSourceAndObsoleteStagedDirectoryLinksAreNeverTraversed() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let external = outside(library, "external")
        try put("external original", at: external.appendingPathComponent("keep"))
        try put("workspace", at: source(library, workspace + "/workspace.json"))
        let link = source(library, workspace + "/linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        let staged = outside(library, "Application Support/.Safience.safience-migration")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: staged.appendingPathComponent("obsolete-link"), withDestinationURL: external)
        _ = try LegacyDataMigration.run(library: library, bundle: bundle)
        let published = outside(library, workspace)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: published.appendingPathComponent("linked").path), external.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: published.appendingPathComponent("obsolete-link").path))
        XCTAssertEqual(try read(external.appendingPathComponent("keep")), "external original")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: external.path), ["keep"])
    }

    func testStagedDirectoryLinkCannotRedirectWritesIntoAnotherFolder() throws {
        let library = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let external = outside(library, "external")
        try put("external original", at: external.appendingPathComponent("keep"))
        try put("source file", at: source(library, workspace + "/nested/new-file"))
        let staged = outside(library, "Application Support/.Safience.safience-migration")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: staged.appendingPathComponent("nested"), withDestinationURL: external)
        XCTAssertThrowsError(try LegacyDataMigration.run(library: library, bundle: bundle))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: external.path), ["keep"])
        XCTAssertEqual(try read(external.appendingPathComponent("keep")), "external original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal(library).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside(library, workspace).path))
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
