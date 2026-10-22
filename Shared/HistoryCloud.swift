import CloudKit
import Foundation
import PadCore

/// History in the user's own iCloud, when Settings › iCloud › History is on
/// (Preferences.historySync), as well as Sync with iCloud: a zone of its own,
/// History, in the same CloudKit database and through the same engine as the
/// spaces (Sync.swift), whose records it builds from the history store and
/// takes into it, never from or into sync.json (HistorySync.swift in PadCore
/// has the records and the rules).
///
/// This device sends only its own visits: a record for each space and day,
/// in pieces, its visits compressed in the record's encrypted values, sent
/// again at most once a minute while the day goes on, and only visits ten
/// seconds old, so that a sign-in page found a moment late (a password field
/// that turns up after the page loads) never leaves. It deletes its own
/// records when it lets go of those days, and all of them when History's
/// switch is turned off; other devices keep what they took. A clearing goes
/// as a record of its own, which removes what it covers on every device and
/// keeps covering what comes in late.
@MainActor
final class HistoryCloud {
    static let shared = HistoryCloud()

    let zone = CKRecordZone.ID(zoneName: HistoryCloudZone.name)

    /// What is kept between launches, in the history store (HistoryStore.syncValue).
    private struct State: Codable {
        /// The records this device has saved, by name, to delete later.
        var mine: Set<String> = []
        /// Each record's CloudKit version, so a save changes iCloud's rather than conflicting with it.
        var fields: [String: Data] = [:]
        /// This device's days with visits iCloud hasn't had yet.
        var dirty: Set<HistoryDayOfSpace> = []
        /// Records for a space this device doesn't know yet, kept until its space record comes.
        var waiting: [String: Data] = [:]
        /// Visits made before this are never sent: made under another
        /// iCloud account, which this device left.
        var uploadAfter: Date?
        /// Everything the zone holds is still to be fetched (backfill): asked
        /// for, and not done yet, or cut short.
        var needsBackfill = false
        /// Clearings made with both switches on before sync was ready (at
        /// launch, while it joins), or of a space not in iCloud yet: sent
        /// once they can be (started, spacesChanged).
        var unsent: Set<UUID>?
        /// This device's records to delete from iCloud, kept while there was
        /// no engine to take them (History turned off while sync started).
        var deleting: Set<String>?
        /// The iCloud account all this is of (signedIn), by its user record.
        var account: String?
    }

    private static let stateName = "cloud"
    /// How long after a visit is recorded here before it is sent: long
    /// enough for a page to show a password field.
    static let settle: TimeInterval = 10
    /// Visits recorded on this device in the last `settle` seconds, by when
    /// (the wall clock, not the visit's time, which the sync clock may set
    /// ahead). In memory: a visit from before a relaunch is older than that.
    private var fresh: [UUID: Date] = [:]

    /// A visit just recorded here (HistoryRecorder.visit).
    func recorded(_ visit: UUID) {
        fresh[visit] = Date()
    }

    /// The visits too new to send.
    private func freshVisits(now: Date = Date()) -> Set<UUID> {
        fresh = fresh.filter { now.timeIntervalSince($0.value) < Self.settle }
        return Set(fresh.keys)
    }

    /// When this launch began. A visit recorded just before the last quit
    /// isn't in `fresh`, which starts empty: none of this device's goes in
    /// the first `settle` seconds.
    private let launched = Date()

    /// Whether a visit is too new to send, as a test made once for a read.
    private func tooNew(now: Date = Date()) -> (UUID) -> Bool {
        let new = freshVisits(now: now)
        if now.timeIntervalSince(launched) < Self.settle { return { _ in true } }
        return { new.contains($0) }
    }

    /// Whether a visit may have gone to iCloud already: recorded longer ago than `settle`.
    func mayHaveSent(_ visit: UUID) -> Bool {
        !freshVisits().contains(visit)
    }
    private var state = State()
    private var loading: Task<Void, Never>?
    /// Goes up when History is turned off, the account changes or the zone
    /// goes: work begun before it lets go of what it was doing.
    private var epoch = 0
    private var flushing: Task<Void, Never>?
    private var lastFlush = Date.distantPast
    private var backfilling = false
    private var saving: Task<Void, Never>?

    private var recorder: HistoryRecorder {
        HistoryRecorder.shared
    }

    /// History goes to iCloud and comes from it: both switches on, and the spaces joined.
    var isOn: Bool {
        Sync.shared.isSyncing && Session.shared.preferences.historySync
    }

    private var device: String {
        Sync.shared.deviceID
    }

    /// The first visit a record may hold: after an account change, and within the days iCloud keeps.
    private func earliest(now: Date = Date()) -> Date {
        max(state.uploadAfter ?? .distantPast, now.addingTimeInterval(-HistoryCloudDay.kept))
    }

    // MARK: What happens here

    /// A visit recorded on this device (HistoryRecorder.visit), or one whose
    /// page was named, described or taken back since: its day is sent again.
    func visited(space: UUID, time: Date) {
        // With both switches on, the day is kept to send while sync starts
        // (at launch, while it joins), and goes once it has (started).
        guard isOn || isWanted else { return }
        Task {
            await ready()
            state.dirty.insert(HistoryDayOfSpace(space: space, day: HistoryCloudDay.key(for: time)))
            saveSoon()
            guard isOn else { return }
            flushSoon()
        }
    }

    /// History cleared here (HistoryRecorder.clear): the clearing goes to the
    /// other devices, and this device's records of the days it took visits
    /// from (`days`, HistoryStore.remove) are sent again without them.
    func cleared(_ removal: HistoryRemoval, days: Set<HistoryDayOfSpace>) {
        guard isOn || isWanted else { return }
        Task {
            await ready()
            state.dirty.formUnion(days)
            send(removal)
            saveSoon()
            guard isOn else { return }
            // Everything cleared: the clearings before it, which it holds for, go.
            if case .all = removal.scope { await dropGoneRemovals() }
            flushSoon()
        }
    }

    /// Both switches on, whether or not sync is running yet.
    private var isWanted: Bool {
        Session.shared.preferences.iCloudSync && Session.shared.preferences.historySync
    }

    /// A clearing made here, to the zone; kept to send later while sync
    /// isn't ready, or its space isn't in iCloud yet.
    private func send(_ removal: HistoryRemoval) {
        guard isOn, removal.space == nil || removal.space.flatMap(cloudID(of:)) != nil else {
            state.unsent = (state.unsent ?? []).union([removal.id])
            return
        }
        let name = HistoryCloudRecord.removal(removal.id).name
        state.mine.insert(name)
        state.unsent?.remove(removal.id)
        Sync.shared.queueHistory(save: [name], delete: [])
    }

    /// The clearings kept to send, sent if they can be now; those the store
    /// no longer keeps (held by a later clearing, or old) are let go.
    private func sendUnsent() async {
        guard isOn, let unsent = state.unsent, !unsent.isEmpty,
              let removals = await recorder.read({ await $0.allRemovals() }) else { return }
        state.unsent = unsent.intersection(removals.map(\.id))
        for removal in removals where unsent.contains(removal.id) { send(removal) }
        saveSoon()
    }

    /// One visit taken back after it may have gone (HistoryRecorder.forget):
    /// a clearing of that visit alone, so the devices that took it let it
    /// go too. Its day goes again as well, without it (visited).
    func withdrawn(_ removal: HistoryRemoval) {
        guard isOn || isWanted else { return }
        Task {
            await ready()
            send(removal)
            saveSoon()
        }
    }

    /// Visits before `cutoff` let go of here (Settings' retention), or past
    /// what iCloud keeps: this device's records of those days go too.
    func pruned(before cutoff: Date?) {
        guard isOn else { return }
        Task {
            await ready()
            guard isOn else { return }
            await dropRecords(before: cutoff)
        }
    }

    /// This device's day records before `cutoff`, or older than iCloud
    /// keeps, deleted; and its clearings that are no longer needed.
    private func dropRecords(before cutoff: Date?) async {
        let last = HistoryCloudDay.key(for: max(cutoff ?? .distantPast, earliest()))
        let old = state.mine.filter { name in
            if case .day(_, _, let day, _) = HistoryCloudRecord(name: name) { return day < last }
            return false
        }
        if !old.isEmpty {
            state.mine.subtract(old)
            Sync.shared.queueHistory(save: [], delete: Array(old))
            saveSoon()
        }
        await dropGoneRemovals()
    }

    /// This device's clearings in iCloud that the store no longer keeps:
    /// past 400 days, when nothing they cleared can still be anywhere to come
    /// back (iCloud keeps no day longer), or held by a clearing of
    /// everything made after them (HistoryRemoval.subsumes).
    private func dropGoneRemovals() async {
        guard let removals = await recorder.read({ await $0.allRemovals() }) else { return }
        let oldest = Date().addingTimeInterval(-HistoryCloudDay.kept)
        let kept = Set(removals.filter { $0.made >= oldest }.map(\.id))
        let gone = state.mine.filter { name in
            if case .removal(let id) = HistoryCloudRecord(name: name) { return !kept.contains(id) }
            return false
        }
        guard !gone.isEmpty else { return }
        state.mine.subtract(gone)
        Sync.shared.queueHistory(save: [], delete: Array(gone))
        saveSoon()
    }

    // MARK: On and off

    /// The engine started (Sync.begin), or History's switch turned on: the
    /// zone made if it isn't there, this device's days sent, records
    /// waiting for a space looked at again, and, after a join or the switch
    /// (or a fetch of it that didn't finish), everything the zone holds
    /// fetched from its start.
    func started(backfill: Bool) {
        guard isOn else { return }
        Task {
            await ready()
            guard isOn else { return }
            Sync.shared.saveHistoryZone()
            // The prune at launch came before sync started, when it couldn't
            // reach iCloud; and the next is a day away.
            await dropRecords(before: Session.shared.preferences.historyRetention.cutoff(now: Date()))
            if backfill {
                state.needsBackfill = true
                await markAllDays()
            }
            flushSoon(now: true)
            await drainWaiting()
            await sendUnsent()
            if state.needsBackfill { await self.backfill() }
        }
    }

    /// History's switch turned off: nothing more sent or taken, and this
    /// device's records deleted from iCloud. Other devices keep the visits
    /// they took; only a clearing removes them.
    func switchedOff() {
        epoch += 1
        flushing?.cancel()
        flushing = nil
        Task {
            await ready()
            // Its clearings too: the other devices keep what they took of
            // them, and iCloud keeps nothing of this device's history.
            let mine = state.mine
            if !Sync.shared.queueHistory(save: [], delete: Array(mine)) {
                state.deleting = (state.deleting ?? []).union(mine)
            }
            state.mine.subtract(mine)
            state.dirty = []
            state.waiting = [:]
            state.unsent = nil
            state.needsBackfill = false
            saveSoon()
        }
    }

    /// The sync engine made (Sync.begin): deletions kept for it, queued,
    /// whether History is on or not.
    func engineStarted() {
        Task {
            await ready()
            guard let deleting = state.deleting, !deleting.isEmpty,
                  Sync.shared.queueHistory(save: [], delete: Array(deleting)) else { return }
            state.deleting = nil
            saveSoon()
        }
    }

    /// Another iCloud account, or none: what this device knew of the last
    /// one's zone goes, and its visits so far stay on it, never sent to the next.
    func accountChanged() {
        epoch += 1
        flushing?.cancel()
        flushing = nil
        Task {
            await ready()
            // By the sync clock, which this device's visits are dated by, and
            // which may be ahead of the wall clock: none from before goes.
            state = State(uploadAfter: Date())
            saveSoon()
        }
    }

    /// The iCloud account sync starts with (Sync.begin). Another than the
    /// one this was of, as when the account changed while sync was off and
    /// no engine saw it, is an account change (accountChanged), before
    /// anything is sent to it.
    func signedIn(as account: String?) async {
        guard let account else { return }
        await ready()
        if let known = state.account, known != account {
            epoch += 1
            flushing?.cancel()
            flushing = nil
            state = State(uploadAfter: Date())
        }
        state.account = account
        saveSoon()
    }

    /// The zone was deleted in iCloud: made again, with this device's days.
    func zoneDeleted() {
        epoch += 1
        flushing?.cancel()
        flushing = nil
        Task {
            await ready()
            state.fields = [:]
            state.mine = []
            saveSoon()
            started(backfill: true)
        }
    }

    /// The spaces changed (Sync applied what came in, or joined): records
    /// waiting for a space may have one now, and days waiting for a space's
    /// iCloud id may go.
    func spacesChanged() {
        guard isOn else { return }
        Task {
            await ready()
            guard isOn else { return }
            await drainWaiting()
            // A clearing of a space that wasn't in iCloud yet.
            await sendUnsent()
            if !state.dirty.isEmpty { flushSoon() }
        }
    }

    /// Records that waited for their space, clearings first.
    private func drainWaiting() async {
        guard !state.waiting.isEmpty else { return }
        let waiting = state.waiting
        state.waiting = [:]
        let names = waiting.keys.sorted { a, b in
            a.hasPrefix(HistoryCloudRecord.removalType) && !b.hasPrefix(HistoryCloudRecord.removalType)
        }
        for name in names {
            if let payload = waiting[name] { await take(name: name, payload: payload, fields: nil) }
        }
        saveSoon()
    }

    // MARK: Sending

    /// The app going to the background (Sync, on iPhone and iPad): the days
    /// waiting for the next send go now. Visits too new to send stay marked,
    /// and go in the next send, when the app runs again.
    func leaving() async {
        await ready()
        guard isOn, !state.dirty.isEmpty else { return }
        flushing?.cancel()
        flushing = nil
        await flush()
        if !state.dirty.isEmpty { flushSoon() }
    }

    /// A space removed here (HistoryRecorder): its records go from iCloud
    /// with it (flush), whether or not there are visits to send.
    func spaceRemoved() {
        guard isOn else { return }
        Task {
            await ready()
            guard isOn else { return }
            flushSoon()
        }
    }

    private func flushSoon(now: Bool = false) {
        guard flushing == nil else { return }
        let wait = now ? 0 : max(5, 60 - Date().timeIntervalSince(lastFlush))
        let started = epoch
        flushing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            await flush()
            guard epoch == started else { return }
            flushing = nil
            // Days marked while it ran, or with visits too new to send yet.
            if !state.dirty.isEmpty { flushSoon() }
        }
    }

    /// The days with new visits as the records to save, and the pieces a day
    /// no longer has, or a space gone, as records to delete. The records
    /// themselves are made as the engine sends them (record(for:)).
    private func flush() async {
        guard isOn else { return }
        let started = epoch
        lastFlush = Date()
        // Taken off the list before the store is asked, so a visit made
        // meanwhile marks its day again rather than being taken as sent.
        let days = state.dirty
        state.dirty = []
        var save: [String] = []
        var delete: [String] = []
        let me = device
        let first = earliest()
        for day in days {
            guard let range = HistoryCloudDay.range(of: day.day), range.to >= first else { continue }
            guard let cloud = cloudID(of: day.space) else {
                // Not in iCloud yet: kept for when it is. Gone: let go of.
                if Session.shared.workspace.space(day.space) != nil { state.dirty.insert(day) }
                continue
            }
            let visits = await recorder.read { try await $0.visits(device: me, space: day.space, from: range.from, to: range.to) } ?? []
            guard epoch == started, isOn else { return }
            // After the read: a visit recorded while it ran is in it, and new.
            let new = tooNew()
            let kept = visits.filter { $0.time > first }
            // Too new to send: the day goes again once they are not.
            if kept.contains(where: { new($0.id) }) { state.dirty.insert(day) }
            let count = HistoryCloudPayload.chunks(kept.filter { !new($0.id) }).count
            let names = (0..<count).map { HistoryCloudRecord.day(device: me, space: cloud, day: day.day, chunk: $0).name }
            let gone = state.mine.filter { name in
                guard case let .day(device, space, other, chunk) = HistoryCloudRecord(name: name) else { return false }
                return device == me && space == cloud && other == day.day && chunk >= count
            }
            save += names
            delete += gone
            state.mine.formUnion(names)
            state.mine.subtract(gone)
        }
        // A space removed here: its records go too.
        let spaces = Set(Session.shared.workspace.spaces.compactMap(\.cloudID))
        let orphaned = state.mine.filter { name in
            if case let .day(_, space, _, _) = HistoryCloudRecord(name: name) { return !spaces.contains(space) }
            return false
        }
        delete += orphaned
        state.mine.subtract(orphaned)
        Sync.shared.queueHistory(save: save, delete: delete)
        saveSoon()
    }

    /// Every day this device has visits on, and every day it has records
    /// of (a clearing may have emptied one, whose records then go), to send again.
    private func markAllDays() async {
        let me = device
        let first = earliest()
        let days = await recorder.read { try await $0.days(device: me, since: first) } ?? []
        state.dirty.formUnion(days)
        for name in state.mine {
            guard case let .day(device, cloud, day, _) = HistoryCloudRecord(name: name), device == me,
                  let space = localID(of: cloud) else { continue }
            state.dirty.insert(HistoryDayOfSpace(space: space, day: day))
        }
        saveSoon()
    }

    /// The record the engine is about to send, made from the store now; nil
    /// when it is no longer there to send (a piece the day lost, a clearing
    /// of a space that is gone, History turned off meanwhile).
    func record(for id: CKRecord.ID) async -> CKRecord? {
        await ready()
        guard isOn, id.zoneID == zone, let parsed = HistoryCloudRecord(name: id.recordName) else { return nil }
        let payload: Data
        switch parsed {
        case let .day(device, cloud, day, chunk):
            guard device == self.device, let space = localID(of: cloud), let range = HistoryCloudDay.range(of: day) else { return nil }
            let first = earliest()
            let visits = await recorder.read { try await $0.visits(device: device, space: space, from: range.from, to: range.to) } ?? []
            guard isOn else { return nil }
            // After the read, as in flush; a day with visits held back goes
            // again once they aren't, as this send may now leave them out.
            let new = tooNew()
            if visits.contains(where: { $0.time > first && new($0.id) }) {
                state.dirty.insert(HistoryDayOfSpace(space: space, day: day))
                saveSoon()
                flushSoon()
            }
            let chunks = HistoryCloudPayload.chunks(visits.filter { $0.time > first && !new($0.id) })
            guard chunks.indices.contains(chunk) else { return nil }
            let sent = chunks[chunk].map { visit in
                var visit = visit
                visit.space = cloud
                return visit
            }
            payload = HistoryCloudPayload.encode(sent)
        case .removal(let removalID):
            let removals = await recorder.read { await $0.allRemovals() } ?? []
            guard var removal = removals.first(where: { $0.id == removalID }) else { return nil }
            if let space = removal.space {
                guard let cloud = cloudID(of: space) else { return nil }
                removal.space = cloud
            }
            payload = HistoryCloudPayload.encode(removal)
        }
        guard let compressed = Deflate.deflate(payload) else { return nil }
        let record = state.fields[id.recordName].flatMap(Sync.record(fromSystemFields:)) ?? CKRecord(recordType: parsed.type, recordID: id)
        record.encryptedValues["payload"] = compressed
        return record
    }

    /// A record's CloudKit version: as sent, as iCloud has it after a conflict, or none.
    func keepFields(_ data: Data?, for name: String) {
        Task {
            await ready()
            state.fields[name] = data
            saveSoon()
        }
    }

    /// A record deleted, by this device or another.
    func deleted(_ id: CKRecord.ID) {
        Task {
            await ready()
            forgetRecord(id.recordName)
            saveSoon()
        }
    }

    private func forgetRecord(_ name: String) {
        state.fields[name] = nil
        state.mine.remove(name)
        state.waiting[name] = nil
    }

    // MARK: Taking

    /// Records from iCloud: clearings first, so that a day that came with
    /// them is taken after what it covers was cleared; then visits, other
    /// devices', into the store. A record deleted is not a clearing: what
    /// it held stays.
    func took(_ records: [CKRecord], deleted: [CKRecord.ID]) async {
        await ready()
        for id in deleted { forgetRecord(id.recordName) }
        guard isOn else {
            saveSoon()
            return
        }
        let removals = records.filter { $0.recordType == HistoryCloudRecord.removalType }
        for record in removals + records.filter({ $0.recordType != HistoryCloudRecord.removalType }) {
            guard let payload = record.encryptedValues["payload"] as? Data else { continue }
            await take(name: record.recordID.recordName, payload: payload, fields: Sync.systemFields(of: record))
        }
        saveSoon()
    }

    private func take(name: String, payload: Data, fields: Data?) async {
        if let fields { state.fields[name] = fields }
        guard let parsed = HistoryCloudRecord(name: name), let data = Deflate.inflate(payload) else { return }
        switch parsed {
        case let .day(device, cloud, day, _):
            // Older than any day record is kept: whoever wrote it, it goes.
            if HistoryCloudDay.isExpired(day, now: Date()) {
                state.mine.remove(name)
                Sync.shared.queueHistory(save: [], delete: [name])
                return
            }
            // This device's own, as it sent it.
            guard device != self.device else { return }
            guard let space = localID(of: cloud) else {
                state.waiting[name] = payload
                return
            }
            guard let visits = HistoryCloudPayload.visits(from: data) else { return }
            // Seen, so a clearing made here after is later than all of them.
            if let latest = visits.map(\.order).max() { Sync.shared.saw(latest) }
            // Not what this device's own Settings › History would have let go
            // already: another device may keep its history longer.
            let cutoff = Session.shared.preferences.historyRetention.cutoff(now: Date())
            let here = visits.compactMap { visit -> HistoryVisit? in
                if let cutoff, visit.time < cutoff { return nil }
                var visit = visit
                visit.space = space
                return visit
            }
            guard !here.isEmpty else { return }
            recorder.write { try await $0.merge(here) }
        case .removal:
            guard var removal = HistoryCloudPayload.removal(from: data) else { return }
            Sync.shared.saw(removal.made)
            if let cloud = removal.space {
                guard let space = localID(of: cloud) else {
                    state.waiting[name] = payload
                    return
                }
                removal.space = space
            }
            // Past 400 days nothing it cleared can still be anywhere: it goes, whoever made it.
            if removal.made < Date().addingTimeInterval(-HistoryCloudDay.kept) {
                state.mine.remove(name)
                Sync.shared.queueHistory(save: [], delete: [name])
                return
            }
            let taken = removal
            let me = device
            recorder.write { [weak self] store in
                // This device's days it took visits from, sent again without them.
                let days = try await store.remove(taken, daysOf: me)
                await MainActor.run { self?.cleared(days: days, by: taken) }
            }
            // Closed tabs are dated by the wall clock: measured against the clearing's.
            recorder.dropClosedTabs(space: taken.space, scope: taken.scope, madeAt: taken.wall ?? taken.made)
        }
    }

    /// What a clearing from another device took of this device's own: its
    /// days go again without it, and a clearing of everything lets the
    /// clearings before it go. Called from inside the recorder's write, so
    /// it waits on nothing of the recorder's: what reads the store
    /// (dropGoneRemovals) goes on after that write is done.
    private func cleared(days: Set<HistoryDayOfSpace>, by removal: HistoryRemoval) {
        guard isOn else { return }
        state.dirty.formUnion(days)
        saveSoon()
        if case .all = removal.scope { Task { await dropGoneRemovals() } }
        if !state.dirty.isEmpty { flushSoon() }
    }

    /// Everything the zone holds, from its start: when the switch turns on,
    /// or after a join, the engine's own fetches having gone past what
    /// came while it was off. Asked again at the next start until it is
    /// done; what it took twice the store takes once.
    private func backfill() async {
        guard !backfilling else { return }
        backfilling = true
        defer { backfilling = false }
        let started = epoch
        let database = CKContainer(identifier: Sync.containerID).privateCloudDatabase
        var token: CKServerChangeToken?
        do {
            while true {
                let changes = try await database.recordZoneChanges(inZoneWith: zone, since: token)
                var records: [CKRecord] = []
                for (_, result) in changes.modificationResultsByID {
                    if case .success(let modification) = result { records.append(modification.record) }
                }
                guard epoch == started else { return }
                await took(records, deleted: [])
                token = changes.changeToken
                guard changes.moreComing else { break }
            }
        } catch {
            // No zone yet, or offline: tried again at the next start.
            return
        }
        guard epoch == started else { return }
        state.needsBackfill = false
        saveSoon()
    }

    // MARK: Spaces

    private func cloudID(of space: UUID) -> UUID? {
        Session.shared.workspace.space(space)?.cloudID
    }

    private func localID(of cloud: UUID) -> UUID? {
        Session.shared.workspace.spaces.first { $0.cloudID == cloud }?.id
    }

    // MARK: Kept on the device

    /// The kept state, read once, before anything here reads or changes it.
    private func ready() async {
        if loading == nil {
            loading = Task { [weak self] in
                guard let self else { return }
                if let data = await recorder.read({ try await $0.syncValue(Self.stateName) }) ?? nil,
                   let kept = try? JSONDecoder().decode(State.self, from: data) {
                    state = kept
                }
            }
        }
        await loading?.value
    }

    private func saveSoon() {
        saving?.cancel()
        saving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let data = try? JSONEncoder().encode(state) else { return }
            recorder.write(changes: false) { try await $0.setSyncValue(data, for: Self.stateName) }
        }
    }
}
