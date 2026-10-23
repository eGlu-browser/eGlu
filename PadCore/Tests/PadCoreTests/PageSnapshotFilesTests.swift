import Foundation
import Testing
@testable import PadCore

struct PageSnapshotFilesTests {
    private let a = URL(string: "https://client-a.example/editor")!
    private let b = URL(string: "https://client-b.example/editor")!

    private func withFiles(_ run: (PageSnapshotFiles, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try run(PageSnapshotFiles(folder: folder), folder)
    }

    @Test("The same tab in another space cannot read the old space's state or picture")
    func spaceIsolation() throws {
        try withFiles { files, _ in
            let tab = UUID()
            let old = files.token(for: tab, in: UUID())
            let moved = files.token(for: tab, in: UUID())
            for kind in [PageSnapshotFiles.Kind.state, .picture] {
                files.save(Data("client A".utf8), kind: kind, url: a, using: old)
                #expect(files.data(kind: kind, url: a, using: moved) == nil)
                #expect(files.data(kind: kind, url: a, using: old) == Data("client A".utf8))
            }
        }
    }

    @Test("Thaw consumes the queued snapshot once and preserves its opaque back/forward bytes")
    func consumeState() throws {
        try withFiles { files, _ in
            let token = files.token(for: UUID(), in: UUID())
            let opaque = Data([0, 1, 2, 255, 0, 8])
            files.save(opaque, kind: .state, url: a, using: token)
            #expect(files.takeState(url: a, using: token) == opaque)
            #expect(files.takeState(url: a, using: token) == nil)
            #expect(files.data(kind: .state, url: b, using: token) == nil)
        }
    }

    @Test("A snapshot for an earlier address cannot replace the saved tab address")
    func navigationIdentity() throws {
        try withFiles { files, _ in
            let token = files.token(for: UUID(), in: UUID())
            files.save(Data("old navigation".utf8), kind: .state, url: a, using: token)
            #expect(files.takeState(url: b, using: token) == nil)
            #expect(files.takeState(url: a, using: token) == nil)
        }
    }

    @Test("Invalidation orders pending writes and rejects callbacks that finish after a move")
    func pendingWrites() throws {
        try withFiles { files, _ in
            let tab = UUID(), space = UUID()
            let old = files.token(for: tab, in: space)
            files.save(Data("queued state".utf8), kind: .state, url: a, using: old)
            files.save(Data("queued image".utf8), kind: .picture, url: a, using: old)
            files.invalidate(tab)
            files.save(Data("late callback".utf8), kind: .state, url: a, using: old)
            files.save(Data("late image".utf8), kind: .picture, url: a, using: old)
            let current = files.token(for: tab, in: space)
            #expect(!files.isCurrent(old))
            #expect(files.data(kind: .state, url: a, using: current) == nil)
            #expect(files.data(kind: .picture, url: a, using: current) == nil)
            files.save(Data("new navigation".utf8), kind: .state, url: b, using: current)
            #expect(files.takeState(url: b, using: current) == Data("new navigation".utf8))
        }
    }

    @Test("After thaw and later navigation, a new process cannot restore the consumed page")
    func relaunchAfterNavigation() throws {
        try withFiles { files, folder in
            let tab = UUID(), space = UUID()
            let token = files.token(for: tab, in: space)
            files.save(Data("frozen A".utf8), kind: .state, url: a, using: token)
            #expect(files.takeState(url: a, using: token) != nil)
            let relaunched = PageSnapshotFiles(folder: folder)
            let next = relaunched.token(for: tab, in: space)
            #expect(relaunched.takeState(url: b, using: next) == nil)
            #expect(relaunched.takeState(url: a, using: next) == nil)
        }
    }

    @Test("A frozen page's same-space back/forward snapshot survives relaunch unchanged")
    func frozenRelaunch() throws {
        try withFiles { files, folder in
            let tab = UUID(), space = UUID()
            let token = files.token(for: tab, in: space)
            let opaque = Data([255, 4, 0, 12, 9])
            files.save(opaque, kind: .state, url: a, using: token)
            #expect(files.data(kind: .state, url: a, using: token) == opaque)
            let relaunched = PageSnapshotFiles(folder: folder)
            let next = relaunched.token(for: tab, in: space)
            #expect(relaunched.takeState(url: a, using: next) == opaque)
        }
    }

    @Test("Pruning removes unscoped legacy files and closed tabs while retaining scoped state")
    func pruneLegacy() throws {
        try withFiles { files, folder in
            let tab = UUID(), gone = UUID(), space = UUID()
            let kept = files.token(for: tab, in: space)
            let removed = files.token(for: gone, in: space)
            files.save(Data([1]), kind: .state, url: a, using: kept)
            files.save(Data([2]), kind: .picture, url: a, using: removed)
            #expect(files.data(kind: .state, url: a, using: kept) == Data([1]))
            let legacy = folder.appendingPathComponent("\(tab.uuidString).state")
            try Data([3]).write(to: legacy)
            files.prune(keeping: [tab])
            #expect(files.data(kind: .state, url: a, using: kept) == Data([1]))
            #expect(files.data(kind: .picture, url: a, using: removed) == nil)
            #expect(!FileManager.default.fileExists(atPath: legacy.path))
        }
    }

}
