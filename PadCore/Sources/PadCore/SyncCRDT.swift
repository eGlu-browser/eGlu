import Foundation

// Last edit wins, field by field.
//
// The workspace's records (spaces, bookmarks and folders, pinned tabs, the
// Mac's extensions and the spaces they are on in) are a state-based CRDT:
// each record is a map of last-writer-wins registers, one per field, and one
// more for whether the record is deleted (Shapiro, Preguiça, Baquero and
// Zawirski, "Conflict-free Replicated Data Types", 2011: the LWW-register
// and the LWW-element-set). Two versions of a record merge by taking each
// register from whichever side wrote it later. That merge is commutative,
// associative and idempotent, so every device that has seen the same edits,
// in whatever order and however many times, holds the same records.
//
// "Later" is a hybrid logical clock's (Kulkarni, Demirbas et al., "Logical
// Physical Clocks", 2014): the wall clock in milliseconds, never behind the
// latest stamp the device has seen, then a count, then the device. An edit
// made after seeing another is always stamped later than it, however wrong
// either device's clock is; edits made apart are ordered by their clocks.
//
// A deleted record stays in iCloud as a tombstone, its fields as they were
// and its register saying deleted, so a deletion and an edit made apart are
// ordered like any two edits; tombstones go for good after 30 days. A
// removed space only hides its bookmarks and pinned tabs: an edit inside it
// made after the removal brings the space back with all of them.
//
// Only the records' use changed: CloudKit's record types and fields are as
// they were, with one string field more, `stamps`, holding SyncStamps.

/// When an edit was made, by a device's hybrid logical clock (SyncClock).
public struct SyncStamp: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Milliseconds since 1970.
    public var time: Int64
    /// Edits within one millisecond, or while the wall clock is behind the
    /// latest stamp seen, in the order they were made.
    public var count: Int32
    /// The device that made it, so two devices' edits never tie.
    public var device: String

    public init(time: Int64, count: Int32 = 0, device: String) {
        self.time = time
        self.count = count
        self.device = device
    }

    public static func < (a: SyncStamp, b: SyncStamp) -> Bool {
        (a.time, a.count, a.device) < (b.time, b.count, b.device)
    }

    public var date: Date {
        Date(timeIntervalSince1970: Double(time) / 1000)
    }

    /// "time.count.device", as records keep it.
    public var description: String {
        "\(time).\(count).\(device)"
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let time = Int64(parts[0]), let count = Int32(parts[1]) else { return nil }
        self.init(time: time, count: count, device: String(parts[2]))
    }
}

extension SyncStamp: Codable {
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let stamp = SyncStamp(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a stamp: \(text)"))
        }
        self = stamp
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A device's hybrid logical clock: stamps its edits, and is moved on by
/// the stamps it sees, so its next edit is later than anything it has seen.
public struct SyncClock: Codable, Equatable, Sendable {
    public let device: String
    public private(set) var time: Int64 = 0
    public private(set) var count: Int32 = 0

    public init(device: String) {
        self.device = device
    }

    /// The stamp of an edit made now.
    public mutating func tick(now: Date = Date()) -> SyncStamp {
        let wall = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        if wall > time {
            time = wall
            count = 0
        } else {
            count += 1
        }
        return SyncStamp(time: time, count: count, device: device)
    }

    /// Another edit seen (from iCloud, or another device's history).
    public mutating func see(_ stamp: SyncStamp) {
        if (stamp.time, stamp.count) > (time, count) {
            time = stamp.time
            count = stamp.count
        }
    }

    /// A time for something kept only as a date (a visit, a clearing):
    /// later than anything seen and than the time before it by at least a
    /// millisecond, so a visit after a clearing is never at its very time,
    /// which a date, with no count, couldn't tell apart.
    public mutating func tickMillis(now: Date = Date()) -> Date {
        let wall = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
        time = max(wall, time + 1)
        count = 0
        return Date(timeIntervalSince1970: Double(time) / 1000)
    }

    /// A time seen, with no stamp of its own (a visit's, a clearing's).
    public mutating func see(_ date: Date) {
        see(SyncStamp(time: Int64((date.timeIntervalSince1970 * 1000).rounded(.down)), count: 0, device: ""))
    }
}

/// A record's registers' stamps: one per field, and whether it is deleted.
public struct SyncStamps: Codable, Equatable, Sendable {
    /// When each field was last set; a field with none was never stamped
    /// (a record from before stamps), and loses to any that was.
    public var fields: [String: SyncStamp]
    public var deleted: Bool
    /// When `deleted` was last set either way: every edit sets it false.
    public var life: SyncStamp?

    public init(fields: [String: SyncStamp] = [:], deleted: Bool = false, life: SyncStamp? = nil) {
        self.fields = fields
        self.deleted = deleted
        self.life = life
    }

    enum CodingKeys: String, CodingKey {
        case fields = "f", deleted = "d", life = "l"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fields = try c.decodeIfPresent([String: SyncStamp].self, forKey: .fields) ?? [:]
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        life = try c.decodeIfPresent(SyncStamp.self, forKey: .life)
    }

    /// The latest edit of the record.
    public var latest: SyncStamp? {
        (Array(fields.values) + [life].compactMap { $0 }).max()
    }

    /// Every stamp in it, for a clock to see.
    public var all: [SyncStamp] {
        Array(fields.values) + [life].compactMap { $0 }
    }

    /// As CloudKit's `stamps` field keeps them.
    public var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public init(text: String) {
        self = (try? JSONDecoder().decode(SyncStamps.self, from: Data(text.utf8))) ?? SyncStamps()
    }
}

extension SyncRecord {
    /// Two versions of one record as one: each field from whichever side
    /// stamped it later, deleted or not from whichever said so later. A tie
    /// (the same edit, or two records from before stamps) goes to the
    /// greater value, deleted over not, so the merge is the same both ways.
    public static func merged(_ a: SyncRecord, _ b: SyncRecord) -> SyncRecord {
        var out = a
        for key in a.kind.fields {
            let (stampA, stampB) = (a.stamps.fields[key], b.stamps.fields[key])
            let takeB: Bool
            switch (stampA, stampB) {
            case let (x?, y?) where x != y: takeB = y > x
            case (nil, _?): takeB = true
            case (_?, nil): takeB = false
            default: takeB = order(b.fields[key]) > order(a.fields[key])
            }
            if takeB {
                out.fields[key] = b.fields[key]
                out.stamps.fields[key] = stampB
            }
        }
        let lifeB: Bool
        switch (a.stamps.life, b.stamps.life) {
        case let (x?, y?) where x != y: lifeB = y > x
        case (nil, _?): lifeB = true
        case (_?, nil): lifeB = false
        default: lifeB = b.stamps.deleted && !a.stamps.deleted
        }
        if lifeB {
            out.stamps.deleted = b.stamps.deleted
            out.stamps.life = b.stamps.life
        }
        return out
    }

    /// A total order on a field's values, for ties only.
    private static func order(_ field: SyncField?) -> String {
        switch field {
        case nil: return ""
        case .string(let value)?: return "s" + value
        case .double(let value)?: return "n" + String(format: "%.17g", value)
        case .date(let value)?: return "t" + String(format: "%.17g", value.timeIntervalSince1970)
        }
    }
}

// MARK: The mirror as a CRDT

extension SyncMirror {
    /// A record as this device knows it, shown or not, with its stamps.
    public func entry(named name: String) -> SyncRecord? {
        guard var record = record(named: name) ?? buried[name] else { return nil }
        record.stamps = stamps[name] ?? SyncStamps()
        return record
    }

    /// Every record this device knows, shown or buried, but other devices' open tabs.
    public var entryNames: Set<String> {
        Set(spaces.keys).union(bookmarks.keys).union(pinned.keys).union(extensions.keys)
            .union(extensionUses.keys).union(buried.keys)
    }

    /// Puts a record in as its stamps say: among the shown records, or the
    /// buried (deleted, or one this build can't read). A removed space may
    /// show again after (settleSpaces).
    public mutating func put(_ record: SyncRecord) {
        guard record.kind != .deviceTabs else {
            take(record)
            return
        }
        remove(record.name)
        buried[record.name] = nil
        stamps[record.name] = record.stamps
        var plain = record
        plain.stamps = SyncStamps()
        if record.stamps.deleted || !take(plain) {
            buried[record.name] = plain
        }
    }

    /// A record from iCloud merged with this device's version of it. True
    /// when this device's version had something later, to send back.
    @discardableResult
    public mutating func merge(_ incoming: SyncRecord) -> Bool {
        guard incoming.kind != .deviceTabs else {
            take(incoming)
            return false
        }
        guard let local = entry(named: incoming.name) else {
            put(incoming)
            return false
        }
        let merged = SyncRecord.merged(local, incoming)
        put(merged)
        return merged != incoming
    }

    /// A record let go of entirely: its tombstone gone from iCloud, or never wanted.
    public mutating func forget(_ name: String) {
        remove(name)
        buried[name] = nil
        stamps[name] = nil
    }

    /// Whether a shown or buried record is deleted.
    public func isDeleted(_ name: String) -> Bool {
        stamps[name]?.deleted == true
    }

    /// Removed spaces brought back where an edit inside them (a bookmark or
    /// pinned tab stamped later, deleting one included) came after the
    /// removal, as the last edit wins, with all they hold. The space's own
    /// register says so from then, stamped with that edit's stamp, and the
    /// space is sent: kept in its record, so that edit's tombstone can go
    /// after its 30 days without hiding the space again, and merged like any
    /// edit, so devices that brought it back from different edits end the
    /// same. Run after every change. Returns the spaces brought back.
    @discardableResult
    public mutating func settleSpaces() -> [String] {
        let removed = Set(buried.filter { $0.value.kind == .space }.keys).union(spaces.keys.filter { isDeleted($0) })
        guard !removed.isEmpty else { return [] }
        var inside: [String: SyncStamp] = [:]
        // An edit's stamp: not a field the device only found (SyncKind.foundFields).
        func note(_ name: String, _ kind: SyncKind, in space: String?) {
            guard let space, removed.contains(space), let marks = stamps[name],
                  let stamp = (marks.fields.filter { !kind.foundFields.contains($0.key) }.map(\.value) + [marks.life].compactMap { $0 }).max()
            else { return }
            if inside[space].map({ stamp > $0 }) ?? true { inside[space] = stamp }
        }
        for bookmark in bookmarks.values { note(bookmark.id, .bookmark, in: bookmark.space) }
        for pin in pinned.values { note(pin.id, .pinned, in: pin.space) }
        for (name, record) in buried where record.kind == .bookmark || record.kind == .pinned {
            note(name, record.kind, in: record.fields["space"]?.string)
        }
        var back: [String] = []
        for name in removed.sorted() {
            guard var record = entry(named: name), record.stamps.deleted, let gone = record.stamps.life else { continue }
            if let latest = inside[name], latest > gone {
                record.stamps.deleted = false
                record.stamps.life = latest
                back.append(name)
            }
            // Shown or buried as its stamps say.
            put(record)
        }
        return back
    }

    /// Everything a space holds, shown, hidden or deleted: its bookmarks,
    /// pinned tabs and extensions' uses; not devices' open tabs.
    public func contents(of space: String) -> [String] {
        bookmarks.values.filter { $0.space == space }.map(\.id) + pinned.values.filter { $0.space == space }.map(\.id)
            + extensionUses.values.filter { $0.space == space }.map(\.id)
            + buried.filter { $0.value.kind != .space && $0.value.kind != .deviceTabs && $0.value.fields["space"]?.string == space }.map(\.key)
    }

    /// The removed spaces that are still removed.
    public var removedSpaces: Set<String> {
        Set(buried.filter { $0.value.kind == .space && isDeleted($0.key) }.keys)
    }
}

extension SyncPlan {
    /// How long a deleted record stays in iCloud as a tombstone.
    public static let tombstoneLife: TimeInterval = 30 * 24 * 60 * 60

    /// This device's own edits, `new` being the records as they are now and
    /// `old` as they were: every field that changed is stamped, a record
    /// gone is buried with deleted set, one new or back has every field
    /// stamped. What a removed space held stays as it was, hidden with it,
    /// and so do records this device doesn't show (another device's
    /// bookmarks in a space not here). Returns the records to send.
    public static func stamp(_ new: SyncMirror, over old: SyncMirror, clock: inout SyncClock,
                             now: Date = Date()) -> (mirror: SyncMirror, changed: [String]) {
        var out = new
        out.stamps = old.stamps
        out.buried = old.buried
        var changed: [String] = []
        let spaces = Set(new.spaces.keys)
        let names = Set(old.spaces.keys).union(new.spaces.keys)
            .union(old.bookmarks.keys).union(new.bookmarks.keys)
            .union(old.pinned.keys).union(new.pinned.keys)
            .union(old.extensions.keys).union(new.extensions.keys)
            .union(old.extensionUses.keys).union(new.extensionUses.keys)
        for name in names.sorted() {
            switch (old.record(named: name), new.record(named: name)) {
            case (nil, let record?):
                // New here, or back from being deleted.
                let stamp = clock.tick(now: now)
                var marks = old.stamps[name] ?? SyncStamps()
                for key in record.kind.fields { marks.fields[key] = stamp }
                marks.deleted = false
                marks.life = stamp
                out.stamps[name] = marks
                out.buried[name] = nil
                changed.append(name)
            case let (before?, after?):
                let edited = after.kind.fields.filter { before.fields[$0] != after.fields[$0] }
                guard !edited.isEmpty else { continue }
                let stamp = clock.tick(now: now)
                var marks = old.stamps[name] ?? SyncStamps()
                for key in edited { marks.fields[key] = stamp }
                // An edit is also the record's being there, later than a
                // deletion made apart from it; a field the device only found
                // (a pinned page's title) is not.
                if !Set(edited).isSubset(of: after.kind.foundFields) {
                    marks.deleted = false
                    marks.life = stamp
                }
                out.stamps[name] = marks
                changed.append(name)
            case (let before?, nil):
                // In a space that is gone here: hidden with it, not deleted.
                if before.kind != .space, let space = before.fields["space"]?.string, !spaces.contains(space) {
                    out.put(old.entry(named: name) ?? before)
                    continue
                }
                let stamp = clock.tick(now: now)
                var marks = old.stamps[name] ?? SyncStamps()
                marks.deleted = true
                marks.life = stamp
                var gone = before
                gone.stamps = marks
                out.put(gone)
                changed.append(name)
            case (nil, nil):
                continue
            }
        }
        return (out, changed)
    }

    /// Of records deleted outright in iCloud (tombstones collected after
    /// their 30 days), those this device makes again, as the deletion, which
    /// carries no version, crossed a newer edit: saved in iCloud within 30
    /// days by iCloud's clock (`saved`, against `now` as iCloud's time is; a
    /// stamp can be ahead of any clock), or with an edit still to send
    /// (`unsent`: one that set the deleted register, not a field only found,
    /// SyncKind.foundFields), a deletion too. A space kept so keeps all it holds, deleted after it
    /// (SyncPlan.expired); so does a space with an edit inside it still to
    /// send, as an edit inside a removed space brings it back. A record in a
    /// space that stays is kept only if edited itself; in a space let go
    /// of, never. Returns every record to save again.
    public static func survivors(of deleted: [String], in mirror: SyncMirror, unsent: Set<String>,
                                 saved: (String) -> Date?, now: Date = Date()) -> Set<String> {
        let gone = Set(deleted)
        let recent = now.addingTimeInterval(-tombstoneLife)
        func alive(_ name: String) -> SyncRecord? {
            mirror.entry(named: name).flatMap { $0.stamps.deleted || $0.kind == .deviceTabs ? nil : $0 }
        }
        func edited(_ name: String) -> Bool {
            unsent.contains(name) || saved(name).map { $0 > recent } == true
        }
        func held(by space: String) -> [String] {
            mirror.names(in: space).dropFirst().filter { alive($0) != nil }
        }
        var spaces: [String: Bool] = [:]
        func keeps(space: String) -> Bool {
            if let known = spaces[space] { return known }
            // An edit inside it still to send, a deletion too, brings it back.
            let kept = alive(space) != nil && (edited(space) || mirror.contents(of: space).contains { unsent.contains($0) })
            spaces[space] = kept
            return kept
        }
        var out = Set<String>()
        for name in deleted {
            guard let record = alive(name) else {
                if mirror.isDeleted(name), edited(name) { out.insert(name) }
                continue
            }
            if record.kind == .space {
                if keeps(space: name) { out.insert(name); out.formUnion(held(by: name)) }
            } else if let space = record.fields["space"]?.string {
                if gone.contains(space) ? keeps(space: space) : alive(space) != nil && edited(name) { out.insert(name) }
            } else if edited(name) {
                out.insert(name)
            }
        }
        return out
    }

    /// Tombstones older than `tombstoneLife`, to delete from iCloud and
    /// forget. Old by `saved`, when iCloud last saved the tombstone, by its
    /// own clock, where known, and `now` as iCloud's time is, so no
    /// device's clock decides; else by the deletion's stamp. Never one
    /// `waiting` to be saved: iCloud hasn't got it as it is yet. What a
    /// removed space held goes only once the space is deleted for good
    /// (`gone`, and no longer here), so every device learns of the space's
    /// deletion first (SyncPlan.survivors). Another device's open tabs are
    /// its own to delete.
    public static func expired(in mirror: SyncMirror, now: Date = Date(), waiting: Set<String> = [], gone: Set<String> = [],
                               saved: (String) -> Date? = { _ in nil }) -> [String] {
        var names = Set<String>()
        for name in mirror.buried.keys where !waiting.contains(name) {
            guard let marks = mirror.stamps[name], marks.deleted, let life = marks.life,
                  now.timeIntervalSince(saved(name) ?? life.date) > tombstoneLife else { continue }
            names.insert(name)
        }
        for space in gone where mirror.entry(named: space) == nil {
            names.formUnion(mirror.contents(of: space).filter { !waiting.contains($0) })
        }
        return names.sorted()
    }
}
