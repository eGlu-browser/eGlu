import Foundation
import Testing
@testable import PadCore

struct WorkspaceRecoveryTests {
    private func temporaryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("workspace.json")
    }

    @Test func missingIsDistinctFromUnreadable() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(WorkspaceFile.load(file) == .missing)
        #expect(WorkspaceFile.load(file.deletingLastPathComponent()) == .failed(.unreadable))
    }

    @Test(arguments: ["broken", "{}", "{\"spaces\":[],\"closed\":[]}"])
    func damagedWorkspaceDoesNotInventSpaceIdentities(_ contents: String) throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let bytes = Data(contents.utf8)
        try bytes.write(to: file)
        #expect(WorkspaceFile.load(file) == .failed(.invalid))
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func legacyWorkspaceKeepsItsIdentities() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let workspace = Workspace.starting()
        try JSONEncoder().encode(workspace).write(to: file)
        #expect(WorkspaceFile.load(file) == .loaded(workspace))
    }

    @Test func futureFormatIsNotLoadedOrOverwritten() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let workspace = Workspace.starting()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        object["schemaVersion"] = 900
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: file)
        #expect(WorkspaceFile.load(file) == .failed(.unsupportedVersion(900)))
        #expect(throws: WorkspaceFile.Failure.unsupportedVersion(900)) {
            try WorkspaceFile.write(.starting(), to: file)
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func savesKeepThePreviousValidWorkspaceAsBackup() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = Workspace.starting()
        try WorkspaceFile.write(first, to: file)
        #expect(WorkspaceFile.read(WorkspaceFile.backup(for: file)) == first)
        var next = first
        next.addSpace(named: "Client")
        try WorkspaceFile.write(next, to: file)
        #expect(WorkspaceFile.read(file) == next)
        #expect(WorkspaceFile.read(WorkspaceFile.backup(for: file)) == first)
    }

    @Test func corruptionAfterLaunchCannotBeOverwrittenByAScheduledSave() throws {
        let file = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let original = Workspace.starting()
        try WorkspaceFile.write(original, to: file)
        let broken = Data("damaged source".utf8)
        try broken.write(to: file)
        #expect(throws: WorkspaceFile.Failure.invalid) { try WorkspaceFile.write(.starting(), to: file) }
        #expect(try Data(contentsOf: file) == broken)
        #expect(WorkspaceFile.read(WorkspaceFile.backup(for: file)) == original)
    }

    @Test func explicitRestorePreservesTheRejectedFileAndOriginalSpaceIDs() throws {
        let file = try temporaryFile()
        let folder = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = Workspace.starting()
        try WorkspaceFile.write(original, to: file)
        let broken = Data("damaged source".utf8)
        try broken.write(to: file)
        let restored = try WorkspaceFile.restore(from: WorkspaceFile.backup(for: file), to: file)
        #expect(restored == original)
        #expect(WorkspaceFile.read(file) == original)
        let preserved = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("workspace-recovery-") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: #require(preserved.first).appendingPathComponent("workspace.json")) == broken)
    }

    @Test func restoringAnOlderWorkspaceArchivesHistoryAndSnapshotBytesBeforeCleanup() throws {
        let file = try temporaryFile()
        let folder = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = Workspace.starting()
        try WorkspaceFile.write(old, to: file)
        var latest = old
        latest.addSpace(named: "Recent Client")
        try WorkspaceFile.write(latest, to: file)
        let history = folder.appendingPathComponent("history.sqlite")
        let wal = folder.appendingPathComponent("history.sqlite-wal")
        let snapshots = folder.appendingPathComponent("Snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let snapshot = snapshots.appendingPathComponent("recent-client.state")
        try Data("recent history".utf8).write(to: history)
        try Data("recent journal".utf8).write(to: wal)
        try Data("recent snapshot".utf8).write(to: snapshot)
        try WorkspaceFile.restore(from: WorkspaceFile.backup(for: file), to: file, preserving: [history, wal, snapshots])
        let recovered = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("workspace-recovery-") })
        #expect(WorkspaceFile.read(recovered.appendingPathComponent("workspace.json")) == latest)
        // Cleanup of active records must not remove the separate recovery copies.
        try FileManager.default.removeItem(at: history)
        try FileManager.default.removeItem(at: wal)
        try FileManager.default.removeItem(at: snapshots)
        #expect(try Data(contentsOf: recovered.appendingPathComponent("history.sqlite")) == Data("recent history".utf8))
        #expect(try Data(contentsOf: recovered.appendingPathComponent("history.sqlite-wal")) == Data("recent journal".utf8))
        #expect(try Data(contentsOf: recovered.appendingPathComponent("Snapshots/recent-client.state")) == Data("recent snapshot".utf8))
        #expect(WorkspaceFile.read(file) == old)
    }

    @Test func invalidRecoveryCandidateLeavesEveryFileUntouched() throws {
        let file = try temporaryFile()
        let folder = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace.starting()
        try WorkspaceFile.write(workspace, to: file)
        let candidate = folder.appendingPathComponent("invalid.json")
        try Data("invalid backup".utf8).write(to: candidate)
        let source = try Data(contentsOf: file)
        let backup = try Data(contentsOf: WorkspaceFile.backup(for: file))
        #expect(throws: WorkspaceFile.Failure.invalid) { try WorkspaceFile.restore(from: candidate, to: file) }
        #expect(try Data(contentsOf: file) == source)
        #expect(try Data(contentsOf: WorkspaceFile.backup(for: file)) == backup)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(!names.contains { $0.hasPrefix("workspace-recovery-") })
    }
}
