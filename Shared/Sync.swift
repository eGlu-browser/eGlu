import CloudKit
import Foundation
import PadCore
import SwiftUI
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Spaces, bookmarks, pinned tabs and open tabs in the user's own iCloud,
/// when Settings turns it on.
///
/// CloudKit's private database, through CKSyncEngine, as Apple has apps sync
/// their data: one record per space, per bookmark and folder, per pinned
/// tab, and one per device and space for its open tabs (SyncModel.swift in
/// PadCore has the records and the rules). Both apps compile this file
/// (Shared/), so the Mac syncs the same records, and, between Macs, the list
/// of Chrome extensions from the Chrome Web Store and the spaces they are on
/// in, in encrypted fields (end to end with Advanced Data Protection); each
/// Mac downloads them itself. Sign-ins, cookies and what sites or extensions
/// store never leave the device.
///
/// What this device knows of iCloud is kept as a mirror: the workspace's
/// synced spaces are built from it when something comes in, and a change
/// here is compared with it to find the records to send. The last edit wins,
/// field by field (SyncCRDT.swift in PadCore): each edit is stamped by this
/// device's clock, a record from iCloud is merged with this device's
/// version, and a deleted record stays a tombstone for 30 days.
@MainActor
final class Sync: ObservableObject, CKSyncEngineDelegate {
    static let shared = Sync()
    /// What went wrong where nothing is shown for it, for Console.
    nonisolated static let log = Logger(subsystem: "net.taehee.safience", category: "Sync")

    /// Something Settings should say: iCloud full, or nobody signed in.
    @Published private(set) var problem: String?
    /// The problem said while iCloud is full, which a save that goes through takes away.
    private static var storageFull: String { String(localized: "Your iCloud storage is full, so eGlu can't sync. Free up space in iCloud to sync again.") }
    @Published private(set) var status = SyncStatus()
    private var fetchIssue = false
    private var fetchedMainZone = false
    private var sendIssue = false
    private var sentAnyChanges = false

    /// Other Macs' Chrome extensions that aren't on this one, to offer.
    @Published private(set) var extensionOffers: [SyncExtension] = []
    private static let writes = DispatchQueue(label: "eGlu.sync-state", qos: .utility)

    private var canUseCloud: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["EGLU_ISOLATED_QA"] == "1" { return false }
        #endif
        #if os(macOS)
        return Session.canSync
        #else
        return true
        #endif
    }
    /// What clearing history does beyond this device: with both switches on,
    /// the clearing goes to the other devices, now or once sync can send it
    /// (HistoryCloud.cleared).
    var historyScopeDescription: String {
        guard Session.shared.preferences.iCloudSync, Session.shared.preferences.historySync else {
            return String(localized: "This clears history on this device only.")
        }
        return String(localized: "This also clears history on devices syncing history with this Apple Account. If sync is unavailable, the clearing waits on this device until sync resumes.")
    }

    func spaceRemovalDescription(_ space: Space) -> String {
        let scope: SpaceRemovalScope = space.cloudID == nil ? .deviceOnly : assigns ? .currentAccount : .iCloudUnchanged
        #if os(macOS)
        return SpaceRemovalCopy.message(tabs: space.tabs.count, device: "Mac", scope: scope, extensionData: true)
        #else
        return SpaceRemovalCopy.message(tabs: space.tabs.count, device: Device.name, scope: scope, extensionData: false)
        #endif
    }

    private var engine: CKSyncEngine?

    /// This device, as its records and its history's visits name it.
    var deviceID: String {
        stored.device
    }
    private var stored = Stored()
    private var running = false
    /// Taking up what came in: what that changes here isn't sent back.
    private var applying = false
    /// Following another Mac's change to its extensions: what that changes
    /// here isn't sent back either (Extensions.follow).
    private var following = false
    /// Other Macs' switches for a space that hasn't arrived here yet,
    /// tried again as spaces come; kept across launches.
    private var waitingSwitches: (on: [SyncPlan.ExtensionInSpace], off: [SyncPlan.ExtensionInSpace]) {
        get { (stored.waitingOn ?? [], stored.waitingOff ?? []) }
        set {
            stored.waitingOn = newValue.on.isEmpty ? nil : newValue.on
            stored.waitingOff = newValue.off.isEmpty ? nil : newValue.off
        }
    }
    private var saving: DispatchWorkItem?
    private var active: NSObjectProtocol?
    #if os(iOS)
    private var leaving: NSObjectProtocol?
    /// The time iOS gives the app to finish sending as it goes to the background.
    private var sendingTask = UIBackgroundTaskIdentifier.invalid
    #endif
    /// The engine a join is under way for: the sign-in the engine reports
    /// during its first fetch asks for a join while the first one runs.
    private var joiningEngine: ObjectIdentifier?
    /// The engine being made (begin): Retry Sync while it is doesn't make another.
    private var beginning = false

    private let zone = CKRecordZone.ID(zoneName: SyncZone.name)
    /// The record types this build knows: 2 since the Mac's extensions.
    private static let schema = 2

    /// The app coming to the front: on the iPad and iPhone, and on the Mac.
    #if os(macOS)
    private static let becameActive = NSApplication.didBecomeActiveNotification
    private static func registerForPushes() { NSApplication.shared.registerForRemoteNotifications() }
    #else
    private static let becameActive = UIApplication.didBecomeActiveNotification
    private static func registerForPushes() { UIApplication.shared.registerForRemoteNotifications() }
    #endif

    /// The app's container: "iCloud." and its bundle identifier, so a build
    /// under another team's identifier has a container of its own.
    static var containerID: String {
        "iCloud." + (Bundle.main.bundleIdentifier ?? "net.taehee.safience")
    }

    private init() {
        if let kept = Stored.read() {
            stored = kept
        } else {
            // Kept from the first launch, sync on or not: history names this
            // device's visits by it, and a new one each launch would leave
            // those from before behind when history sync is turned on.
            saveSoon()
        }
        status = SyncStatus(lastSuccessfulSync: stored.lastSuccessfulSync)
    }

    /// Spaces made while sync is on get their iCloud id at once; not while joining.
    var assigns: Bool {
        running && stored.joined
    }

    /// Running, and joined: what History's records need (HistoryCloud).
    var isSyncing: Bool {
        running && stored.joined && engine != nil
    }

    private var historyZone: CKRecordZone.ID {
        HistoryCloud.shared.zone
    }

    /// History's records to send and to delete (HistoryCloud), by name.
    /// False when there is no engine to take them yet (sync starting).
    @discardableResult
    func queueHistory(save: [String], delete: [String]) -> Bool {
        guard let engine else { return false }
        guard !(save.isEmpty && delete.isEmpty) else { return true }
        status.changed()
        let ids = { (name: String) in CKRecord.ID(recordName: name, zoneID: self.historyZone) }
        engine.state.add(pendingRecordZoneChanges: save.map { .saveRecord(ids($0)) } + delete.map { .deleteRecord(ids($0)) })
        return true
    }

    func saveHistoryZone() {
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: historyZone))])
    }

    // MARK: On and off

    /// At launch with sync on, or when Settings turns it on (`join`: this
    /// device's spaces join iCloud's again by identity).
    func start(join: Bool) {
        guard canUseCloud, Session.shared.canUseWorkspace, !running else { return }
        running = true
        status.start()
        if join { stored.joined = false }
        if stored.joined { settleLaunch() }
        active = NotificationCenter.default.addObserver(forName: Self.becameActive, object: nil,
                                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchSoon() }
        }
        #if os(iOS)
        leaving = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                         object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendBeforeSuspending() }
        }
        #endif
        Task { await begin() }
    }

    /// Settings turned it off: nothing more is sent or taken up, and what
    /// this device knew of iCloud is forgotten, so turning it on joins again.
    func stop() {
        guard running else { return }
        running = false
        status.stop()
        engine = nil
        following = false
        if let active { NotificationCenter.default.removeObserver(active) }
        active = nil
        #if os(iOS)
        if let leaving { NotificationCenter.default.removeObserver(leaving) }
        leaving = nil
        #endif
        let lastSync = stored.lastSuccessfulSync
        stored = Stored(device: stored.device, clock: stored.clock)
        stored.lastSuccessfulSync = lastSync
        extensionOffers = []
        problem = nil
        saveSoon()
    }

    private func begin() async {
        guard canUseCloud, running, !beginning else { return }
        beginning = true
        defer { beginning = false }
        status.start()
        let container = CKContainer(identifier: Self.containerID)
        let account = try? await container.accountStatus()
        guard running else { return }
        if account == .available {
            problem = nil
            // History's state is of one account: checked before anything of it is sent.
            let user = try? await container.userRecordID()
            guard running else { return }
            await HistoryCloud.shared.signedIn(as: user?.recordName)
            guard running else { return }
        } else {
            problem = String(localized: "Sign in to iCloud in Settings to sync.")
            status.wait(account == .noAccount || account == .restricted ? .account : .connection)
        }
        var state = stored.state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        // An older build skipped the record types it didn't know (the Mac's
        // extensions) and moved past them: fetched again from the start,
        // once, keeping what was waiting to be sent.
        var carried: [CKSyncEngine.PendingRecordZoneChange] = []
        if (stored.schema ?? 1) < Self.schema, let old = state {
            var past = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: old, delegate: self)
            past.automaticallySync = false
            carried = CKSyncEngine(past).state.pendingRecordZoneChanges
            state = nil
        }
        stored.schema = Self.schema
        let configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                       stateSerialization: state, delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        if !carried.isEmpty { engine.state.add(pendingRecordZoneChanges: carried) }
        // What was stamped while there was no engine (settleLaunch, changes while sync started).
        let waiting = (save: Array(stored.waitingSaves ?? []), delete: Array(stored.waitingDeletes ?? []))
        (stored.waitingSaves, stored.waitingDeletes) = (nil, nil)
        queue(waiting)
        // History's deletions kept while there was no engine, History on or off.
        HistoryCloud.shared.engineStarted()
        Self.registerForPushes()
        if stored.joined {
            queueChanges(of: Session.shared.workspace)
            collectTombstones()
            retireOpenTabs()
            HistoryCloud.shared.started(backfill: false)
            publishExtensions()
        } else {
            await joinWhenFetched(engine)
        }
    }

    /// What iCloud holds first, then this device's spaces join it.
    private func joinWhenFetched(_ engine: CKSyncEngine) async {
        let id = ObjectIdentifier(engine)
        guard joiningEngine != id else { return }
        joiningEngine = id
        defer { if joiningEngine == id { joiningEngine = nil } }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
        do {
            try await engine.fetchChanges()
        } catch {
            // Signed out, or offline: it joins when the account comes or on the next launch.
            guard self.engine === engine else { return }
            if (error as? CKError)?.code == .notAuthenticated { problem = String(localized: "Sign in to iCloud in Settings to sync.") }
            syncFailed(error)
            return
        }
        guard running, self.engine === engine, !stored.joined else { return }
        let remote = stored.mirror.adding(legacy: Self.legacySpaces())
        // A space deleted while this device was offline cannot rejoin under its old identity.
        applying = true
        let removals = Session.shared.change {
            SyncPlan.apply(SyncMirror(), to: &$0, deleted: remote.removedSpaces.union(stored.goneSpaces ?? []))
        }
        for space in removals.removedSpaces { Session.shared.removeSpace(space) }
        var joined = SyncMirror()
        Session.shared.change { joined = SyncPlan.join(&$0, remote: remote) }
        applying = false
        commit(joined)
        stored.joined = true
        #if os(macOS)
        // The other Macs' spaces for the extensions this one has, before its
        // own list is first sent.
        following = true
        let waiting = Extensions.shared.follow(removed: [], on: SyncPlan.joining(stored.mirror, local: Extensions.shared.syncList), off: [])
        following = false
        waitingSwitches.on += waiting.on
        #endif
        publishExtensions()
        saveSoon()
        // The spaces have their iCloud ids now: history after them, all the zone holds.
        HistoryCloud.shared.started(backfill: true)
    }

    /// On coming to the front. A device whose first join failed (offline at
    /// launch) joins now, rather than staying out of sync until the next launch.
    private func fetchSoon() {
        guard running, engine != nil else { return }
        if !stored.joined { joinSoon(); return }
        outsideCallback { sync in
            guard let engine = sync.engine else { return }
            do { try await engine.fetchChanges() }
            catch { if sync.engine === engine { sync.syncFailed(error) } }
        }
    }

    func retrySync() {
        guard canUseCloud, Session.shared.preferences.iCloudSync else { return }
        if !running { start(join: false); return }
        guard engine != nil else { Task { await begin() }; return }
        fetchSoon()
        outsideCallback { sync in
            guard let engine = sync.engine else { return }
            do { try await engine.sendChanges() }
            catch { if sync.engine === engine { sync.syncFailed(error) } }
        }
    }

    private var hasPendingSyncChanges: Bool {
        guard let engine else { return true }
        return !engine.state.pendingRecordZoneChanges.isEmpty || !engine.state.pendingDatabaseChanges.isEmpty
            || !(stored.waitingSaves ?? []).isEmpty || !(stored.waitingDeletes ?? []).isEmpty
            || HistoryCloud.shared.hasPendingChanges
    }

    func historyWorkChanged() {
        guard running else { return }
        if hasPendingSyncChanges { status.changed() }
        else { fetchSoon() }
    }

    private func syncFailed(_ error: Error) {
        let reason: SyncStatus.Waiting
        switch (error as? CKError)?.code {
        case .networkFailure, .networkUnavailable: reason = .connection
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .batchRequestFailed: reason = .service
        case .notAuthenticated: reason = .account
        default: reason = .error
        }
        status.wait(reason)
    }

    private func confirmSyncStatus() {
        guard status.lastSuccessfulSync != stored.lastSuccessfulSync else { return }
        stored.lastSuccessfulSync = status.lastSuccessfulSync
        saveSoon()
    }

    #if os(iOS)
    /// Going to the background: history waiting out its minute between sends
    /// goes now, and the engine sends what it has rather than when it next
    /// would, in the time iOS gives, as the app may not run again for a while.
    private func sendBeforeSuspending() {
        guard running, stored.joined, engine != nil, sendingTask == .invalid else { return }
        sendingTask = UIApplication.shared.beginBackgroundTask(withName: "Sync") { [weak self] in
            MainActor.assumeIsolated { self?.endSending() }
        }
        outsideCallback { sync in
            await HistoryCloud.shared.leaving()
            if let engine = sync.engine {
                do { try await engine.sendChanges() }
                catch { if sync.engine === engine { sync.syncFailed(error) } }
            }
            sync.endSending()
        }
    }

    private func endSending() {
        guard sendingTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(sendingTask)
        sendingTask = .invalid
    }
    #endif

    private func joinSoon() {
        outsideCallback { sync in
            guard let engine = sync.engine else { return }
            await sync.joinWhenFetched(engine)
        }
    }

    /// Work for the engine that one of its delegate callbacks asks for.
    /// CKSyncEngine stops the app (a fatal error) when a call made during a
    /// callback would call the delegate again, as fetchChanges does, and a
    /// Task started in a callback counts as the callback: it inherits the
    /// callback's context. A detached task inherits nothing, as the error
    /// itself advises.
    private func outsideCallback(_ work: @escaping @Sendable @MainActor (Sync) async -> Void) {
        Task.detached { [weak self] in
            guard let self else { return }
            await work(self)
        }
    }

    // MARK: Changes here

    /// At launch, before anything can change: the workspace and sync.json
    /// are each written a moment after a change, apart, so after a crash or
    /// a quit between the two, the one written later holds the latest
    /// synced edits. A workspace written later has edits not stamped yet:
    /// stamped as of when it was written, so an edit made since on another
    /// device stays later. Otherwise the mirror has them, and the workspace
    /// takes them from it; what it lacks is not a deletion.
    private func settleLaunch() {
        let modified = { (file: URL) in (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date }
        if let written = modified(Session.workspaceFile), written > modified(Stored.file) ?? .distantPast {
            commit(SyncPlan.records(of: Session.shared.workspace, keeping: stored.mirror), at: min(written, Date()))
        } else {
            applyMirror(deleted: [])
        }
    }

    /// After every change to the workspace (Session.change).
    func changed(from old: Workspace, to new: Workspace) {
        // Stamped now, engine or not (sync starting): sent once there is one.
        guard running, stored.joined, !applying else { return }
        if SyncPlan.hasSyncableChanges(from: old, to: new) { queueChanges(of: new) }
    }

    private func queueChanges(of workspace: Workspace, at now: Date = Date()) {
        commit(SyncPlan.records(of: workspace, keeping: stored.mirror), at: now)
    }

    /// This device's edits: the records as they are now, stamped by its
    /// clock over the mirror (SyncPlan.stamp), and sent. A deletion is a
    /// tombstone, sent like an edit.
    @discardableResult
    private func commit(_ next: SyncMirror, at now: Date = Date()) -> [String] {
        var clock = self.clock
        var (stamped, changed) = SyncPlan.stamp(next, over: stored.mirror, clock: &clock, now: now)
        let back = stamped.settleSpaces()
        // Edits proper, that set the deleted register (not a field only
        // found, SyncKind.foundFields).
        let lived = (changed + back).filter { stamped.stamps[$0]?.life != stored.mirror.stamps[$0]?.life }
        self.clock = clock
        stored.mirror = stamped
        noteEdits(lived)
        queue((changed + back, []))
        saveSoon()
        // A space brought back by this edit: the workspace follows, after
        // the change under way (this runs from Session.change).
        if !back.isEmpty, stored.joined {
            DispatchQueue.main.async { [weak self] in self?.applyMirror(deleted: []) }
        }
        return changed + back
    }

    /// This device's clock (SyncClock), kept with the mirror.
    private var clock: SyncClock {
        get { stored.clock ?? SyncClock(device: stored.device) }
        set { stored.clock = newValue }
    }

    /// A time for something made here that other devices order against
    /// what they made (a visit, a clearing): never behind what this device
    /// has seen, so a visit after a clearing it took is after that
    /// clearing, and a clearing covers every visit it has seen, whatever
    /// the clocks. A device whose clock runs ahead takes the others' along
    /// (Kulkarni et al.); held back, its clearings would cover visits made
    /// after them.
    func stampNow(now: Date = Date()) -> Date {
        var clock = self.clock
        let date = clock.tickMillis(now: now)
        self.clock = clock
        // Kept at once only while it runs ahead of the wall clock, the one
        // time losing it would set it back: sync.json holds the whole
        // mirror, too much to write for every page.
        if date.timeIntervalSince(now) > 1 { saveSoon() }
        return date
    }

    /// A time made on another device (a visit's, a clearing's), or kept in
    /// the history store, seen; kept at once while it is ahead of the wall
    /// clock, as in stampNow.
    func saw(_ date: Date) {
        var clock = self.clock
        clock.see(date)
        guard clock != self.clock else { return }
        self.clock = clock
        if date.timeIntervalSinceNow > 1 { saveSoon() }
    }

    private func see(_ stamps: SyncStamps) {
        var clock = self.clock
        for stamp in stamps.all { clock.see(stamp) }
        self.clock = clock
    }

    /// When tombstones were last looked over.
    private var collected = Date.distantPast
    /// When the last fetch ended, this launch.
    private var fetched = Date.distantPast

    /// Tombstones past their 30 days, and what a removed space held,
    /// deleted from iCloud for good (SyncPlan.expired); at most every few
    /// hours, after a fetch. Kept here until iCloud says they are gone
    /// (sentChanges), so one that comes back meanwhile, or a space an edit
    /// inside brings back, isn't deleted after all (keepCollecting).
    private func collectTombstones(now: Date = Date()) {
        guard running, stored.joined, now.timeIntervalSince(collected) > 6 * 60 * 60 else { return }
        collected = now
        // A space deleted for good stays noted until what it held is gone too, or it is back.
        stored.goneSpaces = stored.goneSpaces?.filter { stored.mirror.entry(named: $0) == nil && !stored.mirror.contents(of: $0).isEmpty }
        let collecting = stored.collecting ?? []
        let names = expired().filter { !collecting.contains($0) }
        guard !names.isEmpty else { return }
        stored.collecting = collecting.union(names)
        queue(([], names))
        saveSoon()
    }

    /// What is past its 30 days, by iCloud's clock: each tombstone's last
    /// save there, against the latest time iCloud has given (or this
    /// device's, if that is earlier). Not one still to be saved.
    private func expired() -> [String] {
        let now = min(Date(), (stored.serverTime ?? Date()).addingTimeInterval(24 * 60 * 60))
        return SyncPlan.expired(in: stored.mirror, now: now, waiting: unsent, gone: stored.goneSpaces ?? []) { [stored] name in
            stored.tombstonesSaved?[name]
        }
    }

    /// The records waiting to be saved in iCloud.
    private var unsent: Set<String> {
        Set((engine?.state.pendingRecordZoneChanges ?? []).compactMap { change -> String? in
            if case .saveRecord(let id) = change, id.zoneID == zone { return id.recordName }
            return nil
        })
    }

    /// A record as iCloud saved it: when, kept while what it saved is a
    /// tombstone. Tombstones expire by that (expired), never by a save from
    /// before the deletion, or one still to come.
    private func noteSaved(_ record: CKRecord) {
        noteServerTime(record.modificationDate)
        let name = record.recordID.recordName
        if let date = record.modificationDate, Self.syncRecord(record)?.stamps.deleted == true {
            stored.tombstonesSaved = (stored.tombstonesSaved ?? [:]).merging([name: date]) { _, new in new }
        } else {
            stored.tombstonesSaved?[name] = nil
        }
    }

    /// Edits proper (that set the deleted register: an edit here, or a
    /// space an edit inside brought back) noted with that stamp until
    /// iCloud has them (editsUnsent).
    private func noteEdits(_ names: [String]) {
        for name in names {
            guard let life = stored.mirror.stamps[name]?.life else { continue }
            stored.editsUnsent = (stored.editsUnsent ?? [:]).merging([name: life]) { _, new in new }
        }
    }

    /// A record let go of here: deleted from iCloud, for good.
    private func forget(_ name: String) {
        stored.mirror.forget(name)
        stored.collecting?.remove(name)
        stored.tombstonesSaved?[name] = nil
        stored.editsUnsent?[name] = nil
    }

    /// Tombstones whose deletion is on its way that no longer should go:
    /// edited after all, or in a space that is back. Their deletion is taken back.
    private func keepCollecting() {
        guard let collecting = stored.collecting, !collecting.isEmpty else { return }
        let back = collecting.subtracting(expired())
        guard !back.isEmpty else { return }
        engine?.state.remove(pendingRecordZoneChanges: back.map { .deleteRecord(recordID($0)) })
        stored.collecting = collecting.subtracting(back)
    }

    /// iCloud's time, as its records say it, never going back.
    private func noteServerTime(_ date: Date?) {
        guard let date, date > (stored.serverTime ?? .distantPast) else { return }
        stored.serverTime = date
    }

    /// A save of this device's just made: iCloud's time then was the time
    /// it gives the record, as a fetched record's isn't.
    private func noteSave(_ date: Date?) {
        guard let date else { return }
        noteServerTime(date)
        stored.lastSave = date
        stored.lastSaveNoted = Date()
    }

    /// iCloud's time now, as near as this device can tell: when it last
    /// saved something of this device's, and the time since by this
    /// device's clock, which may be set wrong but still counts seconds.
    private var serverNow: Date {
        guard let time = stored.lastSave, let noted = stored.lastSaveNoted else { return Date() }
        return time.addingTimeInterval(max(0, Date().timeIntervalSince(noted)))
    }

    private func queue(_ changes: (save: [String], delete: [String])) {
        guard !(changes.save.isEmpty && changes.delete.isEmpty) else { return }
        status.changed()
        for name in changes.delete { stored.systemFields[name] = nil }
        guard let engine else {
            // No engine yet (sync starting): kept with the mirror, so a quit
            // before it comes loses none; the last of a save and a deletion counts.
            var saves = (stored.waitingSaves ?? []).subtracting(changes.delete)
            var deletes = (stored.waitingDeletes ?? []).subtracting(changes.save)
            saves.formUnion(changes.save)
            deletes.formUnion(changes.delete)
            (stored.waitingSaves, stored.waitingDeletes) = (saves, deletes)
            return
        }
        engine.state.add(pendingRecordZoneChanges: changes.save.map { .saveRecord(recordID($0)) }
            + changes.delete.map { .deleteRecord(recordID($0)) })
    }

    // MARK: Open tabs

    /// Open tabs stay on their device: what this device, or one before it,
    /// sent of open tabs goes from iCloud, once. DeviceTabs stays a record
    /// type in the schema, unused, and what arrives of it is let be (took).
    private func retireOpenTabs() {
        let names = Array(stored.mirror.deviceTabs.keys)
        guard !names.isEmpty else { return }
        stored.mirror.deviceTabs = [:]
        queue(([], names))
        saveSoon()
    }

    // MARK: Chrome extensions (the Mac's)

    /// The Mac's list of extensions changed (Extensions.saveList).
    func extensionsChanged() {
        guard running, stored.joined, !applying, !following else { return }
        publishExtensions()
    }

    /// This Mac's own changes to its extensions since it last sent them
    /// (SyncPlan.publish): what only other Macs have is left alone.
    private func publishExtensions() {
        #if os(macOS)
        guard running, stored.joined else { return }
        let list = Extensions.shared.syncList
        guard list != stored.extensions else { return refreshOffers() }
        var next = stored.mirror
        _ = SyncPlan.publish(from: stored.extensions, to: list, in: &next)
        stored.extensions = list
        commit(next)
        refreshOffers()
        #endif
    }

    #if DEBUG && os(macOS)
    /// For checking the list's look from the command line (-extensionOfferTest).
    func offerForChecking(_ offers: [SyncExtension]) { extensionOffers = offers }
    #endif

    /// An extension just added on this Mac that the list has: on in the
    /// spaces it is on in on the other Macs too, as joining takes them up,
    /// besides those its sheet chose; so this Mac's choice turns nothing
    /// off on the others.
    func adopt(_ storeID: String) {
        #if os(macOS)
        guard running, stored.joined, engine != nil else { return }
        let on = SyncPlan.joining(stored.mirror, local: Extensions.shared.syncList).filter { $0.storeID == storeID }
        guard !on.isEmpty else { return }
        following = true
        let waiting = Extensions.shared.follow(removed: [], on: on, off: [])
        following = false
        waitingSwitches.on += waiting.on
        publishExtensions()
        #endif
    }

    private func refreshOffers() {
        #if os(macOS)
        extensionOffers = SyncPlan.offers(in: stored.mirror, local: Extensions.shared.syncList)
        #endif
    }

    // MARK: CKSyncEngine

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        switch event {
        case .willFetchChanges:
            fetchIssue = false
            fetchedMainZone = false
            status.beginWork()
        case .didFetchRecordZoneChanges(let result):
            if let error = result.error {
                fetchIssue = true
                syncFailed(error)
            } else if result.zoneID == zone {
                fetchedMainZone = true
            }
        case .willSendChanges:
            sendIssue = false
            sentAnyChanges = false
            status.beginWork()
        case .sentDatabaseChanges(let result):
            sentAnyChanges = sentAnyChanges || !result.savedZones.isEmpty || !result.deletedZoneIDs.isEmpty
            for failure in result.failedZoneSaves { sendIssue = true; syncFailed(failure.error) }
            for error in result.failedZoneDeletes.values { sendIssue = true; syncFailed(error) }
        case .didSendChanges:
            let confirm = status.sent(changed: sentAnyChanges, pending: hasPendingSyncChanges, failed: sendIssue)
            if confirm { fetchSoon() }
        case .stateUpdate(let update):
            do {
                stored.state = try JSONEncoder().encode(update.stateSerialization)
            } catch {
                // Without a state the engine fetches everything again next launch.
                stored.state = nil
                Self.log.error("Sync engine state not encoded: \(error.localizedDescription, privacy: .public)")
            }
            saveSoon()
        case .accountChange(let change):
            accountChanged(change)
        case .fetchedDatabaseChanges(let changes):
            // The zone deleted (iCloud's data for the app erased): start again.
            if changes.deletions.contains(where: { $0.zoneID == zone }) {
                stored = Stored(device: stored.device, clock: stored.clock)
                saveSoon()
                joinSoon()
            }
            if changes.deletions.contains(where: { $0.zoneID == historyZone }) { HistoryCloud.shared.zoneDeleted() }
        case .fetchedRecordZoneChanges(let changes):
            took(changes)
            // History's, into the history store (HistoryCloud), never the mirror.
            await HistoryCloud.shared.took(changes.modifications.map(\.record).filter { $0.recordID.zoneID == historyZone },
                                           deleted: changes.deletions.map(\.recordID).filter { $0.zoneID == historyZone })
        case .sentRecordZoneChanges(let sent):
            sentAnyChanges = sentAnyChanges || !sent.savedRecords.isEmpty || !sent.deletedRecordIDs.isEmpty
            for failure in sent.failedRecordSaves { sendIssue = true; syncFailed(failure.error) }
            for error in sent.failedRecordDeletes.values { sendIssue = true; syncFailed(error) }
            sentChanges(sent, engine: syncEngine)
        case .didFetchChanges:
            if !fetchIssue, fetchedMainZone { fetched = Date(); collectTombstones() }
            status.fetched(confirmed: fetchedMainZone, pending: hasPendingSyncChanges, failed: fetchIssue)
            confirmSyncStatus()
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        var pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        // A tombstone's collection goes only soon after a fetch, and while
        // it is still past its 30 days: a deletion, unlike a save, isn't
        // turned back by a newer version in iCloud, so a device back after
        // a while first learns what came back meanwhile. It waits, queued.
        if let collecting = stored.collecting, !collecting.isEmpty {
            let due = Date().timeIntervalSince(fetched) < 10 * 60 ? Set(expired()) : []
            pending.removeAll { change in
                guard case .deleteRecord(let id) = change, id.zoneID == zone else { return false }
                return collecting.contains(id.recordName) && !due.contains(id.recordName)
            }
        }
        guard !pending.isEmpty else { return nil }
        let history = historyZone
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
            // History's are made from the history store as they go.
            if id.zoneID == history {
                switch await HistoryCloud.shared.record(for: id) {
                case .failure:
                    // The store couldn't be read: kept, to go at the next send.
                    return nil
                case .success(nil):
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                    return nil
                case .success(let record?):
                    return record
                }
            }
            // Gone from the mirror since it was queued: nothing to send.
            guard let record = await self?.ckRecord(named: id.recordName) else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                return nil
            }
            return record
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            problem = nil
            // After a sign-out, this device's spaces join the account's again.
            if !stored.joined { joinSoon() } else { fetchSoon() }
        case .signOut:
            // Another person may sign in next: what this device knew of
            // the last one's iCloud goes; the workspace stays as it is.
            problem = String(localized: "Sign in to iCloud in Settings to sync.")
            stored = Stored(device: stored.device, clock: stored.clock)
            extensionOffers = []
            status = SyncStatus()
            status.wait(.account)
            saveSoon()
            HistoryCloud.shared.accountChanged()
        case .switchAccounts:
            stored = Stored(device: stored.device, clock: stored.clock)
            extensionOffers = []
            status = SyncStatus()
            status.start()
            saveSoon()
            HistoryCloud.shared.accountChanged()
            joinSoon()
        @unknown default:
            break
        }
    }

    /// Records from iCloud into the mirror, and the workspace from it: each
    /// merged with this device's version, field by field, the later edit
    /// winning (SyncMirror.merge); where this device's had something later,
    /// it is sent back. A record deleted outright in iCloud is a tombstone
    /// gone after its 30 days (collectTombstones): let go of here too.
    private func took(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        let before = stored.mirror
        var deletedSpaces = Set<String>()
        // Whether anything the workspace is made from came: a space, a
        // bookmark, a pinned tab, an extension.
        var touched = false
        let modifications = changes.modifications.filter { $0.record.recordID.zoneID == zone }
        var back: [String] = []
        for modification in modifications {
            let record = modification.record
            let name = record.recordID.recordName
            noteServerTime(record.modificationDate)
            // Another device's open tabs, from a build that still sent them: not kept (retireOpenTabs).
            guard let plain = Self.syncRecord(record), plain.kind != .deviceTabs else { continue }
            stored.systemFields[name] = Self.systemFields(of: record)
            noteSaved(record)
            see(plain.stamps)
            if plain.kind == .space { stored.goneSpaces?.remove(name) }
            if stored.mirror.merge(plain) { back.append(name) }
            touched = true
        }
        // But where this device has the record alive and edited since, the
        // deletion crossed that edit: made again (SyncPlan.survivors).
        let deletions = changes.deletions.filter { $0.recordID.zoneID == zone }
        let kept = SyncPlan.survivors(of: deletions.map(\.recordID.recordName), in: stored.mirror,
                                      unsent: Set((stored.editsUnsent ?? [:]).keys),
                                      saved: { [stored] in stored.systemFields[$0].flatMap(Self.record(fromSystemFields:))?.modificationDate },
                                      now: serverNow)
        for deletion in deletions {
            let name = deletion.recordID.recordName
            stored.systemFields[name] = nil
            // Open tabs, as retireOpenTabs deleted them: never here.
            guard deletion.recordType != SyncKind.deviceTabs.rawValue else { continue }
            touched = true
            guard !kept.contains(name) else { continue }
            if deletion.recordType == SyncKind.space.rawValue {
                if stored.mirror.spaces[name] != nil { deletedSpaces.insert(name) }
                stored.goneSpaces = (stored.goneSpaces ?? []).union([name])
            }
            forget(name)
        }
        // Made again: edits to send, so a later deletion of what a kept
        // space holds, in another fetch, keeps it too.
        noteEdits(Array(kept))
        back += kept
        // What a removed space held stays, hidden with it, until its
        // tombstone expires (SyncPlan.expired), extensions' uses too; an
        // edit inside it after the removal brings it back.
        let revived = stored.mirror.settleSpaces()
        noteEdits(revived)
        back += revived
        keepCollecting()
        queue((back, []))
        if stored.joined, touched { applyMirror(deleted: deletedSpaces) }
        followExtensions(from: before)
        saveSoon()
    }

    /// Another Mac's change to the list of extensions, followed here once
    /// the spaces are in place, after a fetch or a merge on a conflict; and
    /// what this Mac now has taken as sent, so a space removed in the same
    /// batch sends nothing back.
    private func followExtensions(from before: SyncMirror) {
        #if os(macOS)
        if stored.joined {
            var follow: (removed: [String], on: [SyncPlan.ExtensionInSpace], off: [SyncPlan.ExtensionInSpace]) = ([], [], [])
            if before.extensions != stored.mirror.extensions || before.extensionUses != stored.mirror.extensionUses
                || before.removedSpaces != stored.mirror.removedSpaces {
                follow = SyncPlan.follow(from: before, to: stored.mirror, local: Extensions.shared.syncList)
            }
            // Switches waiting for their space, as the mirror still has them:
            // a newer change may have turned one the other way meanwhile.
            let now = SyncPlan.extensionsOn(in: stored.mirror)
            let retry = (on: waitingSwitches.on.filter { now.contains($0) }, off: waitingSwitches.off.filter { !now.contains($0) })
            following = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let waiting = Extensions.shared.follow(removed: follow.removed, on: follow.on + retry.on, off: follow.off + retry.off)
                self.waitingSwitches = waiting
                self.following = false
                self.stored.extensions = Extensions.shared.syncList
                self.refreshOffers()
                self.saveSoon()
            }
        }
        #endif
    }

    /// The workspace's synced spaces as the mirror has them; spaces removed
    /// elsewhere (tombstones, or deleted outright) are removed here.
    private func applyMirror(deleted: Set<String>) {
        let session = Session.shared
        applying = true
        defer { applying = false }
        // Deleted for good too (goneSpaces): a workspace written before
        // such a deletion took its space away mustn't send it again.
        let removed = deleted.union(stored.mirror.removedSpaces).union(stored.goneSpaces ?? [])
        let applied = session.change { SyncPlan.apply(stored.mirror, to: &$0, deleted: removed) }
        // A remote unpin changes the dock, not this device's live pages.
        for space in applied.removedSpaces { session.removeSpace(space) }
        HistoryCloud.shared.spacesChanged()
        if applied.replacementSpace != nil {
            applying = false
            queueChanges(of: session.workspace)
        }
    }

    /// A record's CloudKit version, where its zone keeps them: the mirror's, or the history store's.
    private func keepFields(_ data: Data?, for id: CKRecord.ID) {
        if id.zoneID == historyZone {
            HistoryCloud.shared.keepFields(data, for: id.recordName)
        } else {
            stored.systemFields[id.recordName] = data
        }
    }

    private func sentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        let before = stored.mirror
        for record in sent.savedRecords {
            keepFields(Self.systemFields(of: record), for: record.recordID)
            if record.recordID.zoneID == zone {
                noteSaved(record)
                // The edit noted is in iCloud now (or a later one is).
                let name = record.recordID.recordName
                if let edit = stored.editsUnsent?[name], let life = Self.syncRecord(record)?.stamps.life, life >= edit {
                    stored.editsUnsent?[name] = nil
                }
            }
            noteSave(record.modificationDate)
        }
        var again: [CKSyncEngine.PendingRecordZoneChange] = []
        // Tombstones collected (collectTombstones): gone from iCloud, so from
        // here. One back since (edited, or a space an edit inside brought
        // back) whose deletion went before it could be taken back
        // (keepCollecting) is made again.
        let due = Set(expired())
        var forgot = false
        for id in sent.deletedRecordIDs where id.zoneID == zone {
            let name = id.recordName
            let collected = stored.collecting?.remove(name) != nil
            if due.contains(name) {
                // A space's deletion done: what it held goes next, after it.
                if stored.mirror.buried[name]?.kind == .space {
                    stored.goneSpaces = (stored.goneSpaces ?? []).union([name])
                    self.collected = .distantPast
                }
                forget(name)
                forgot = true
            } else if stored.mirror.entry(named: name) != nil {
                noteEdits([name])
                again.append(.saveRecord(id))
            } else if collected {
                forget(name)
            }
        }
        for id in sent.deletedRecordIDs where id.zoneID == historyZone {
            HistoryCloud.shared.deleted(id)
        }
        var merged = false
        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Changed in iCloud since this device last saw it: merged
                // with iCloud's version, field by field, and that sent.
                if let server = failure.error.serverRecord {
                    keepFields(Self.systemFields(of: server), for: id)
                    if id.zoneID == zone { noteSaved(server) }
                    // This device's own open tabs are its own: sent again as they are.
                    if id.zoneID == zone, let plain = Self.syncRecord(server), plain.kind != .deviceTabs {
                        see(plain.stamps)
                        stored.mirror.merge(plain)
                        merged = true
                    }
                }
                again.append(.saveRecord(id))
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                again.append(.saveRecord(id))
            case .unknownItem:
                // Deleted in iCloud meanwhile: made again from this device's
                // version where it holds a later edit than the deletion took
                // away; this device's own open tabs too. Not one that only a
                // field found changed (a pinned page's title): its deletion
                // stands.
                let name = id.recordName
                // Decided as an outright deletion is (SyncPlan.survivors): an
                // edit still to send, or one iCloud saved within 30 days.
                let saved = stored.systemFields[name].flatMap(Self.record(fromSystemFields:))?.modificationDate
                keepFields(nil, for: id)
                if id.zoneID == zone, stored.mirror.deviceTabs[name] == nil {
                    let kept = SyncPlan.survivors(of: [name], in: stored.mirror, unsent: Set((stored.editsUnsent ?? [:]).keys),
                                                  saved: { _ in saved }, now: serverNow)
                    // A space made again so, with all it holds, which the
                    // same collection may delete next: saved, as edits.
                    noteEdits(Array(kept))
                    again += kept.subtracting([name]).sorted().map { .saveRecord(recordID($0)) }
                    if !kept.contains(name) {
                        // A space so is deleted for good; the workspace follows after the batch.
                        if stored.mirror.entry(named: name)?.kind == .space {
                            stored.goneSpaces = (stored.goneSpaces ?? []).union([name])
                        }
                        forget(name)
                        forgot = true
                        continue
                    }
                }
                again.append(.saveRecord(id))
            case .quotaExceeded:
                problem = Self.storageFull
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
                 .batchRequestFailed, .notAuthenticated:
                // Passing, or another record's failure failing the batch: again later.
                again.append(.saveRecord(id))
            default:
                break
            }
        }
        if !sent.savedRecords.isEmpty, problem == Self.storageFull { problem = nil }
        if merged || forgot {
            let revived = stored.mirror.settleSpaces()
            noteEdits(revived)
            again += revived.map { .saveRecord(recordID($0)) }
            keepCollecting()
            if stored.joined { applyMirror(deleted: []) }
            followExtensions(from: before)
        }
        if !again.isEmpty { engine.state.add(pendingRecordZoneChanges: again) }
        saveSoon()
    }

    // MARK: Records

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zone)
    }

    /// The mirror's record as CloudKit's: on top of the version iCloud last
    /// sent, so the save changes that one rather than conflicting with it.
    private func ckRecord(named name: String) -> CKRecord? {
        // Shown or a tombstone: either goes, with its stamps.
        guard let plain = stored.mirror.entry(named: name) else { return nil }
        let record = stored.systemFields[name].flatMap(Self.record(fromSystemFields:))
            ?? CKRecord(recordType: plain.kind.rawValue, recordID: recordID(name))
        // An extension's fields encrypted end to end (SyncKind.isEncrypted).
        let values = Self.values(of: record, encrypted: plain.kind.isEncrypted)
        for key in plain.kind.fields {
            switch plain.fields[key] {
            case .string(let value): values.setObject(value as NSString, forKey: key)
            case .double(let value): values.setObject(NSNumber(value: value), forKey: key)
            case .date(let value): values.setObject(value as NSDate, forKey: key)
            case nil: values.setObject(nil, forKey: key)
            }
        }
        if plain.kind != .deviceTabs {
            values.setObject(plain.stamps.text as NSString, forKey: SyncRecord.stampsField)
        }
        return record
    }

    private static func syncRecord(_ record: CKRecord) -> SyncRecord? {
        guard let kind = SyncKind(rawValue: record.recordType) else { return nil }
        var fields: [String: SyncField] = [:]
        let values = Self.values(of: record, encrypted: kind.isEncrypted)
        for key in kind.fields {
            switch values.object(forKey: key) {
            case let value as String: fields[key] = .string(value)
            case let value as Date: fields[key] = .date(value)
            case let value as NSNumber: fields[key] = .double(value.doubleValue)
            default: break
            }
        }
        // None on a record from before stamps: every field loses to a stamped one.
        let stamps = (values.object(forKey: SyncRecord.stampsField) as? String).map(SyncStamps.init(text:)) ?? SyncStamps()
        return SyncRecord(kind: kind, name: record.recordID.recordName, fields: fields, stamps: stamps)
    }

    /// Where a kind's fields are kept: its encrypted values, or the record.
    private static func values(of record: CKRecord, encrypted: Bool) -> any CKRecordKeyValueSetting {
        if encrypted { return record.encryptedValues }
        return record
    }

    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Kept on the device

    private func saveSoon() {
        saving?.cancel()
        let snapshot = stored
        let file = Stored.file
        let work = DispatchWorkItem {
            // A failed save is retried by the next one; if none succeeds, the
            // next launch joins again from iCloud (Stored.read).
            do {
                let data = try JSONEncoder().encode(snapshot)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                Sync.log.error("sync.json not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
        saving = work
        Self.writes.asyncAfter(deadline: .now() + 1, execute: work)
    }
}
