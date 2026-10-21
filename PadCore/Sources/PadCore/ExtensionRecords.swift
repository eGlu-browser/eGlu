import Foundation

/// What Safience keeps on the Mac about the problems an extension ran into
/// (Docs/ExtensionsDesign.md, section 4, "In use"): which API, of what
/// kind, where in the extension, how often, when first and last; and the
/// versions around it. Never the error's own words, arguments, page text
/// or addresses, which can hold an address or an account name. At most
/// 200 an extension, for 30 days. Nothing of it leaves the Mac unless the
/// person sends a report themselves (Report a Problem).
public struct ExtensionRecords: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Hashable, Sendable {
        public var id: String
        public var version: String
        public var safience: String
        public var macOS: String
        /// The shim's stamp, as the prepared folder has it.
        public var shim: String
        /// Where in the extension: "worker", "popup", "content script", "page".
        public var place: String
        public var api: String
        public var kind: String
        public var count: Int
        public var first: Date
        public var last: Date

        public init(id: String, version: String, safience: String, macOS: String, shim: String, place: String,
                    api: String, kind: String, count: Int = 1, first: Date, last: Date) {
            self.id = id
            self.version = version
            self.safience = safience
            self.macOS = macOS
            self.shim = shim
            self.place = place
            self.api = api
            self.kind = kind
            self.count = count
            self.first = first
            self.last = last
        }

        /// The same problem again: one record, counted.
        func isSame(as other: Record) -> Bool {
            id == other.id && version == other.version && safience == other.safience && macOS == other.macOS
                && shim == other.shim && place == other.place && api == other.api && kind == other.kind
        }
    }

    public static let most = 200
    public static let days = 30

    public private(set) var records: [Record] = []

    public init() {}

    /// A problem seen: counted on its record, or a new one; then the
    /// extension's oldest past 200 go, and everything past 30 days.
    public mutating func note(_ record: Record, now: Date = Date()) {
        if let index = records.firstIndex(where: { $0.isSame(as: record) }) {
            records[index].count += record.count
            records[index].last = max(records[index].last, record.last)
        } else {
            records.append(record)
        }
        prune(now: now)
    }

    public mutating func prune(now: Date = Date()) {
        let oldest = now.addingTimeInterval(-Double(Self.days) * 24 * 60 * 60)
        records.removeAll { $0.last < oldest }
        let ids = Set(records.map(\.id))
        for id in ids {
            let mine = records.filter { $0.id == id }
            guard mine.count > Self.most else { continue }
            let going = Set(mine.sorted { $0.last < $1.last }.prefix(mine.count - Self.most))
            records.removeAll { going.contains($0) }
        }
    }

    /// An extension's, newest first.
    public func of(_ id: String) -> [Record] {
        records.filter { $0.id == id }.sorted { $0.last > $1.last }
    }

    /// An extension gone from Safience: its records with it.
    public mutating func forget(_ id: String) {
        records.removeAll { $0.id == id }
    }

    /// Where an error happened, from the file it names inside the
    /// extension: its worker, its popup's scripts, its content scripts, or
    /// another of its pages.
    public static func place(of file: String, in manifest: ExtensionManifest) -> String {
        // "/bg.js", "./bg.js" and "bg.js" are one file.
        let clean = ExtensionPreparation.normalized
        let path = clean(file)
        if case .worker(let worker, _) = manifest.background, clean(worker) == path { return "worker" }
        if case .scripts(let scripts, _) = manifest.background, scripts.map(clean).contains(path) { return "worker" }
        if manifest.contentScripts.contains(where: { $0.scripts.map(clean).contains(path) }) { return "content script" }
        if let popup = manifest.popup.map(clean) {
            // Its folder's scripts, or beside it at the top, those named as it is.
            let folder = Self.folder(of: popup)
            let name = (popup as NSString).lastPathComponent.split(separator: ".").first.map(String.init) ?? popup
            if folder.isEmpty ? Self.folder(of: path).isEmpty && (path as NSString).lastPathComponent.hasPrefix(name) : Self.folder(of: path) == folder {
                return "popup"
            }
        }
        return "page"
    }

    static func folder(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }
}

/// The extensions Safience's developers tried by hand for a release, with
/// what they tried; the only place that says a feature works, since only
/// there were the features used. Shipped with the app, looked up on the
/// Mac, so what someone installed never leaves it.
public struct ExtensionTried: Sendable {
    public struct Entry: Equatable, Sendable {
        /// The Chrome Web Store id.
        public var id: String
        /// The versions it holds for, both ends included; nil for no end.
        public var from: ExtensionVersion?
        public var through: ExtensionVersion?
        public var works: Bool
        /// The Safience version it was tried on.
        public var release: String
        /// What was tried, in words: "blocking on 20 sites".
        public var what: String

        public init(id: String, from: ExtensionVersion?, through: ExtensionVersion?, works: Bool, release: String, what: String) {
            self.id = id
            self.from = from
            self.through = through
            self.works = works
            self.release = release
            self.what = what
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// The list this release ships: empty until an extension has been
    /// tried by hand on Safience; nothing is said to work before then.
    public static let shipped = ExtensionTried(entries: [])

    public func entry(for id: String, version: String) -> Entry? {
        guard let version = ExtensionVersion(version) else { return nil }
        return entries.first {
            $0.id == id && ($0.from.map { version >= $0 } ?? true) && ($0.through.map { version <= $0 } ?? true)
        }
    }
}
