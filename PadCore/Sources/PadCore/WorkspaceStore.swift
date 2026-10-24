import Foundation

/// The workspace on disk as both apps' Session keep it: read once at launch,
/// written half a second after the last change, and never replaced by a
/// fresh one when what was there couldn't be read.
///
/// The writes go one at a time and in the order asked: on a concurrent
/// queue an older copy could finish last and be what stays.
@MainActor
public final class WorkspaceStore {
    /// What the workspace is at launch, or after a retry that worked.
    public struct Opened: Equatable, Sendable {
        public var workspace: Workspace
        /// Why the file on disk can't be used; nil when it can.
        public var problem: WorkspaceFile.Failure?
        /// A new workspace was written for a first launch.
        public var created: Bool
    }

    /// The folder of the workspace's file and of the history beside it.
    public let folder: URL
    /// The pages' snapshots, which outlive the workspace's file when it goes.
    public let snapshots: URL
    public var file: URL { WorkspaceStore.file(in: folder) }

    /// A first launch's workspace whose first write failed: retrying writes
    /// it, rather than reading a file that was never there.
    public private(set) var creating = false
    /// The write waiting its half second, if there is one.
    private var pending: DispatchWorkItem?
    private let writes: DispatchQueue
    private let delay: DispatchTimeInterval
    /// Told after each write from save, saveNow and saveAndWait, on the main
    /// actor: the error, or nil once one succeeds.
    private let written: @MainActor @Sendable ((any Error)?) -> Void

    public init(folder: URL, snapshots: URL, delay: DispatchTimeInterval = .milliseconds(500),
                written: @escaping @MainActor @Sendable ((any Error)?) -> Void = { _ in }) {
        self.folder = folder
        self.snapshots = snapshots
        self.delay = delay
        self.written = written
        writes = DispatchQueue(label: "Safience.workspace", qos: .utility)
    }

    public nonisolated static func file(in folder: URL) -> URL {
        folder.appendingPathComponent("workspace.json")
    }

    private static let history = "history.sqlite"

    /// The workspace at launch. A missing file beside history, snapshots or
    /// a backup is a workspace to recover, not a new install: nothing is
    /// written over it.
    public func open() -> Opened {
        switch WorkspaceFile.load(file) {
        case .loaded(let saved):
            return Opened(workspace: saved, problem: nil, created: false)
        case .failed(let problem):
            return Opened(workspace: .starting(), problem: problem, created: false)
        case .missing:
            let fresh = Workspace.starting()
            if holdsRecords {
                return Opened(workspace: fresh, problem: .unreadable, created: false)
            }
            creating = true
            do {
                try WorkspaceFile.write(fresh, to: file)
                creating = false
                return Opened(workspace: fresh, problem: nil, created: true)
            } catch {
                return Opened(workspace: fresh, problem: .unreadable, created: false)
            }
        }
    }

    private var holdsRecords: Bool {
        let files = FileManager.default
        let retainedSnapshots = (try? files.contentsOfDirectory(atPath: snapshots.path))?.isEmpty == false
        return files.fileExists(atPath: folder.appendingPathComponent(WorkspaceStore.history).path) || retainedSnapshots ||
            files.fileExists(atPath: WorkspaceFile.backup(for: file).path)
    }

    /// After a failed read, the file read again, or a first launch's
    /// workspace, `current`, written again. Never a new identity: nil
    /// while the file still can't be read, the write's error while a first
    /// launch's still can't be written.
    public func retry(_ current: Workspace) throws -> Opened? {
        if creating {
            try WorkspaceFile.write(current, to: file)
            creating = false
            return Opened(workspace: current, problem: nil, created: true)
        }
        guard case .loaded(let saved) = WorkspaceFile.load(file) else { return nil }
        return Opened(workspace: saved, problem: nil, created: false)
    }

    /// A backup in place of the file, with the file, the history and its
    /// sidecars and the snapshots kept aside first, before older space IDs
    /// can be pruned from them.
    public func restore(from backup: URL) throws -> Workspace {
        let retained = [WorkspaceStore.history, WorkspaceStore.history + "-wal", WorkspaceStore.history + "-shm"]
            .map { folder.appendingPathComponent($0) } + [snapshots]
        let workspace = try WorkspaceFile.restore(from: backup, to: file, preserving: retained)
        creating = false
        return workspace
    }

    /// Whether a write is waiting its half second.
    public var isSaving: Bool { pending != nil }

    /// `workspace` written half a second from now, unless another save comes first.
    public func save(_ workspace: Workspace) {
        pending?.cancel()
        let file = file
        let written = written
        let work = DispatchWorkItem { WorkspaceStore.write(workspace, to: file, written: written) }
        pending = work
        writes.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// `workspace` written now, in place of any write still waiting, after
    /// those already begun; `finished` hears of it on the writes' queue.
    public func saveNow(_ workspace: Workspace, finished: (@Sendable () -> Void)? = nil) {
        pending?.cancel()
        pending = nil
        let file = file
        let written = written
        writes.async {
            WorkspaceStore.write(workspace, to: file, written: written)
            finished?()
        }
    }

    /// As saveNow, and back only once it is written: for an app quitting.
    public func saveAndWait(_ workspace: Workspace) {
        pending?.cancel()
        pending = nil
        let file = file
        let written = written
        writes.sync { WorkspaceStore.write(workspace, to: file, written: written) }
    }

    /// One write, on the writes' queue, and what came of it told on the main actor.
    private nonisolated static func write(_ workspace: Workspace, to file: URL,
                                          written: @escaping @MainActor @Sendable ((any Error)?) -> Void) {
        let failure: (any Error)?
        do {
            try WorkspaceFile.write(workspace, to: file)
            failure = nil
        } catch {
            failure = error
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { written(failure) }
        }
    }
}
