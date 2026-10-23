import Foundation

/// Disposable page state, isolated by space and tab. Every disk operation and
/// generation check uses one serial queue, including synchronous consumption.
/// The queue protects the only mutable property, `generations`.
public final class PageSnapshotFiles: @unchecked Sendable {
    public enum Kind: String, Sendable { case state, picture }

    public struct Token: Equatable, Sendable {
        public let space: UUID
        public let tab: UUID
        fileprivate let generation: UUID
    }

    private struct Record: Codable {
        let url: URL?
        let data: Data
    }

    private let folder: URL
    private let queue = DispatchQueue(label: "PageSnapshotFiles", qos: .utility)
    private var generations: [UUID: UUID] = [:]

    public init(folder: URL) { self.folder = folder }

    public func token(for tab: UUID, in space: UUID) -> Token {
        queue.sync {
            let generation = generations[tab] ?? UUID()
            generations[tab] = generation
            return Token(space: space, tab: tab, generation: generation)
        }
    }

    public func isCurrent(_ token: Token) -> Bool {
        queue.sync { current(token) }
    }

    /// A callback from before a move, close, or navigation cannot recreate data.
    public func save(_ data: Data, kind: Kind, url: URL?, using token: Token) {
        queue.async {
            guard self.current(token),
                  let encoded = try? PropertyListEncoder().encode(Record(url: url, data: data)) else { return }
            try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
            try? encoded.write(to: self.file(token, kind), options: .atomic)
        }
    }

    public func data(kind: Kind, url: URL?, using token: Token) -> Data? {
        queue.sync { read(kind: kind, url: url, using: token) }
    }

    /// A thawed page owns its back/forward state in WebKit. Consuming the disk
    /// copy prevents an earlier frozen navigation from winning after relaunch.
    /// Waiting on the same queue also consumes any write already submitted.
    public func takeState(url: URL?, using token: Token) -> Data? {
        queue.sync {
            guard current(token) else { return nil }
            let state = read(kind: .state, url: url, using: token)
            // Restoring is safe only once its stale disk copy is gone.
            do { try FileManager.default.removeItem(at: file(token, .state)) }
            catch { return nil }
            return state
        }
    }

    /// Completes after earlier writes and deletion; later old-token writes fail.
    public func invalidate(_ tab: UUID) {
        queue.sync {
            generations[tab] = UUID()
            for name in names() where tabID(in: name) == tab || name == "\(tab.uuidString).state"
                || name == "\(tab.uuidString).jpg" {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
    }

    /// Legacy tab-only files have no trustworthy space identity and are removed.
    public func prune(keeping tabs: Set<UUID>) {
        queue.async {
            for name in self.names() {
                if let tab = self.tabID(in: name), tabs.contains(tab) { continue }
                try? FileManager.default.removeItem(at: self.folder.appendingPathComponent(name))
            }
        }
    }

    private func current(_ token: Token) -> Bool {
        generations[token.tab] == token.generation
    }

    private func file(_ token: Token, _ kind: Kind) -> URL {
        folder.appendingPathComponent("\(token.space.uuidString).\(token.tab.uuidString).\(kind.rawValue)")
    }

    private func read(kind: Kind, url: URL?, using token: Token) -> Data? {
        guard current(token), let data = try? Data(contentsOf: file(token, kind)),
              let record = try? PropertyListDecoder().decode(Record.self, from: data),
              record.url == url else { return nil }
        return record.data
    }

    private func names() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func tabID(in name: String) -> UUID? {
        let parts = name.split(separator: ".")
        guard parts.count == 3, UUID(uuidString: String(parts[0])) != nil,
              Kind(rawValue: String(parts[2])) != nil else { return nil }
        return UUID(uuidString: String(parts[1]))
    }
}
