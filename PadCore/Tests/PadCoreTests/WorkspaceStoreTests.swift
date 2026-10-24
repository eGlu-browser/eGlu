import Foundation
import Testing
@testable import PadCore

@MainActor
struct WorkspaceStoreTests {
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func store(in folder: URL, delay: DispatchTimeInterval = .milliseconds(500)) -> WorkspaceStore {
        WorkspaceStore(folder: folder.appendingPathComponent("Safience", isDirectory: true),
                       snapshots: folder.appendingPathComponent("Snapshots", isDirectory: true), delay: delay)
    }

    @Test func aFirstLaunchWritesANewWorkspace() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = store(in: folder)
        let opened = store.open()
        #expect(opened.created)
        #expect(opened.problem == nil)
        #expect(WorkspaceFile.load(store.file) == .loaded(opened.workspace))
    }

    @Test func aSavedWorkspaceIsReadBack() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var workspace = Workspace.starting()
        workspace.addSpace(named: "Client")
        let store = store(in: folder)
        try WorkspaceFile.write(workspace, to: store.file)
        #expect(store.open() == .init(workspace: workspace, problem: nil, created: false))
    }

    @Test(arguments: ["Safience/history.sqlite", "Snapshots/tab", "Safience/workspace.last-good.json"])
    func aMissingFileBesideRecordsIsRecoveryNotANewInstall(_ record: String) throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let kept = folder.appendingPathComponent(record)
        try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kept".utf8).write(to: kept)
        let store = store(in: folder)
        let opened = store.open()
        #expect(opened.problem == .unreadable)
        #expect(!opened.created)
        #expect(!FileManager.default.fileExists(atPath: store.file.path), "nothing written over what may come back")
        #expect(try store.retry(opened.workspace) == nil, "a retry reads; it never makes a new identity")
    }

    @Test func anEmptySnapshotsFolderIsANewInstall() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = store(in: folder)
        try FileManager.default.createDirectory(at: store.snapshots, withIntermediateDirectories: true)
        #expect(store.open().created)
    }

    @Test func aDamagedFileIsLeftAloneAndRetryReadsItAgain() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = store(in: folder)
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: store.file)
        let opened = store.open()
        #expect(opened.problem == .invalid)
        #expect(try store.retry(opened.workspace) == nil)
        let mended = Workspace.starting()
        try FileManager.default.removeItem(at: store.file)
        try WorkspaceFile.write(mended, to: store.file)
        #expect(try store.retry(opened.workspace) == .init(workspace: mended, problem: nil, created: false))
    }

    @Test func aFailedFirstWriteIsWrittenOnRetry() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = store(in: folder)
        // A folder that can't be written to: the first write can't happen.
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.folder.path)
        let opened = store.open()
        #expect(opened.problem == .unreadable)
        #expect(store.creating)
        #expect(throws: (any Error).self) { try store.retry(opened.workspace) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.folder.path)
        #expect(try store.retry(opened.workspace) == .init(workspace: opened.workspace, problem: nil, created: true))
        #expect(!store.creating)
        #expect(WorkspaceFile.load(store.file) == .loaded(opened.workspace))
    }

    @Test func restoringKeepsTheHistoryAndSnapshotsAside() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = store(in: folder)
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.snapshots, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: store.folder.appendingPathComponent("history.sqlite"))
        try Data("wal".utf8).write(to: store.folder.appendingPathComponent("history.sqlite-wal"))
        let backup = Workspace.starting()
        let candidate = folder.appendingPathComponent("candidate.json")
        try JSONEncoder().encode(backup).write(to: candidate)
        #expect(try store.restore(from: candidate) == backup)
        #expect(WorkspaceFile.load(store.file) == .loaded(backup))
        let aside = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
            .filter { $0.hasPrefix("workspace-recovery-") }
        #expect(aside.count == 1)
        let kept = try FileManager.default.contentsOfDirectory(atPath: store.folder.appendingPathComponent(aside[0]).path)
        #expect(Set(kept) == ["history.sqlite", "history.sqlite-wal", "Snapshots"])
    }

    @Test func savesWaitAndOnlyTheLastIsWritten() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = store(in: folder, delay: .milliseconds(50))
        let first = store.open().workspace
        var second = first
        second.addSpace(named: "Second")
        var third = second
        third.addSpace(named: "Third")
        store.save(second)
        store.save(third)
        #expect(store.isSaving)
        #expect(WorkspaceFile.load(store.file) == .loaded(first), "nothing written before its half second")
        try await Task.sleep(for: .milliseconds(300))
        #expect(WorkspaceFile.load(store.file) == .loaded(third))
    }

    @Test func eachWriteSaysWhetherItFailed() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let told = Told()
        let store = WorkspaceStore(folder: folder.appendingPathComponent("Safience", isDirectory: true),
                                   snapshots: folder.appendingPathComponent("Snapshots", isDirectory: true)) { told.failures.append($0 != nil) }
        let workspace = store.open().workspace
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.folder.path)
        await withCheckedContinuation { done in store.saveNow(workspace) { done.resume() } }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.folder.path)
        store.saveAndWait(workspace)
        try await Task.sleep(for: .milliseconds(50))
        #expect(told.failures == [true, false])
    }

    @Test func savingNowTakesThePlaceOfTheWaitingWrite() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = store(in: folder, delay: .seconds(60))
        var next = store.open().workspace
        next.addSpace(named: "Next")
        store.save(next)
        store.saveAndWait(next)
        #expect(!store.isSaving)
        #expect(WorkspaceFile.load(store.file) == .loaded(next))
        var later = next
        later.addSpace(named: "Later")
        store.save(later)
        await withCheckedContinuation { done in store.saveNow(later) { done.resume() } }
        #expect(!store.isSaving)
        #expect(WorkspaceFile.load(store.file) == .loaded(later))
    }
}

struct PreferencesChangesTests {
    @Test func eachChangeIsNamed() {
        let old = Preferences()
        #expect(old.changes(from: old).isEmpty)
        var new = old
        new.historyRetention = old.historyRetention == .month ? .week : .month
        new.historySync.toggle()
        new.iCloudSync.toggle()
        new.handoff.toggle()
        #expect(new.changes(from: old) == [.historyRetention, .historySync, .iCloudSync, .handoff])
        var filters = old
        filters.filterLists["easylist"] = false
        #expect(filters.changes(from: old) == .contentBlocking)
        var blocking = old
        blocking.blocksContent.toggle()
        #expect(blocking.changes(from: old) == .contentBlocking)
        var limits = old
        limits.limits = LiveLimits(heavy: old.limits.heavy + 1)
        #expect(limits.changes(from: old) == .limits)
        var other = old
        other.bookmarksBar.toggle()
        #expect(other.changes(from: old).isEmpty, "the pages hear of it; nothing else answers to it")
    }

    @Test func storedPreferencesComeBack() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        #expect(Preferences.stored(in: defaults, key: "preferences") == Preferences())
        var preferences = Preferences()
        preferences.handoff = true
        preferences.engine = "duckduckgo"
        preferences.store(in: defaults, key: "preferences")
        #expect(Preferences.stored(in: defaults, key: "preferences") == preferences)
    }
}

@MainActor
private final class Told {
    var failures: [Bool] = []
}
