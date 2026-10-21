import CloudKit
import Compression
import Foundation
import PadCore
import SwiftUI
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
/// PadCore has the records and the rules). The Mac app (Mac/) shares this
/// file and syncs the same records, and, between Macs, the list of Chrome
/// extensions from the Chrome Web Store and the spaces they are on in,
/// end-to-end encrypted with Advanced Data Protection; each Mac downloads
/// them itself. Sign-ins, cookies and what sites or extensions store never
/// leave the device.
///
/// What this device knows of iCloud is kept as a mirror: the workspace's
/// synced spaces are built from it when something comes in, and a change
/// here is compared with it to find the records to send.
@MainActor
final class Sync: ObservableObject, CKSyncEngineDelegate {
    static let shared = Sync()

    /// Something Settings should say: iCloud full, or nobody signed in.
    @Published private(set) var problem: String?
    /// Other devices' open tabs, recent ones only: the tab overview and the
    /// address bar list them to pick up from.
    @Published private(set) var elsewhere: [SyncDeviceTabs] = []
    /// Other Macs' Chrome extensions that aren't on this one, to offer.
    @Published private(set) var extensionOffers: [SyncExtension] = []

    private var engine: CKSyncEngine?
    private var stored = Stored()
    private var running = false
    /// Taking up what came in: what that changes here isn't sent back.
    private var applying = false
    /// Following another Mac's change to its extensions: what that changes
    /// here isn't sent back either (Extensions.follow).
    private var following = false
    /// Other Macs' switches for a space that hasn't arrived here yet,
    /// tried again as spaces come.
    private var waitingSwitches: (on: [SyncPlan.ExtensionInSpace], off: [SyncPlan.ExtensionInSpace]) = ([], [])
    private var saving: DispatchWorkItem?
    private var tabsSoon: DispatchWorkItem?
    private var active: NSObjectProtocol?
    /// The engine a join is under way for: the sign-in the engine reports
    /// during its first fetch asks for a join while the first one runs.
    private var joiningEngine: ObjectIdentifier?

    private let zone = CKRecordZone.ID(zoneName: SyncZone.name)

    /// The app coming to the front, and what this device is called on the
    /// other devices' lists of its tabs: on the iPad and iPhone, and on the Mac.
    #if os(macOS)
    private static let becameActive = NSApplication.didBecomeActiveNotification
    private static let deviceName = "Mac"
    private static func registerForPushes() { NSApplication.shared.registerForRemoteNotifications() }
    #else
    private static let becameActive = UIApplication.didBecomeActiveNotification
    private static var deviceName: String { UIDevice.current.model }
    private static func registerForPushes() { UIApplication.shared.registerForRemoteNotifications() }
    #endif

    /// The app's container: "iCloud." and its bundle identifier, so a build
    /// under another team's identifier has a container of its own.
    static var containerID: String {
        "iCloud." + (Bundle.main.bundleIdentifier ?? "net.taehee.safience")
    }

    private init() {
        stored = Stored.read() ?? Stored()
    }

    /// Spaces made while sync is on get their iCloud id at once; not while
    /// joining, when a space's name is what joins it to iCloud's.
    var assigns: Bool {
        running && stored.joined
    }

    // MARK: On and off

    /// At launch with sync on, or when Settings turns it on (`join`: this
    /// device's spaces join iCloud's again, by name).
    func start(join: Bool) {
        guard !running else { return }
        running = true
        if join { stored.joined = false }
        active = NotificationCenter.default.addObserver(forName: Self.becameActive, object: nil,
                                                        queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchSoon() }
        }
        Task { await begin() }
    }

    /// Settings turned it off: nothing more is sent or taken up, and what
    /// this device knew of iCloud is forgotten, so turning it on joins again.
    func stop() {
        guard running else { return }
        running = false
        engine = nil
        if let active { NotificationCenter.default.removeObserver(active) }
        active = nil
        stored = Stored(device: stored.device)
        elsewhere = []
        extensionOffers = []
        problem = nil
        saveSoon()
    }

    private func begin() async {
        let container = CKContainer(identifier: Self.containerID)
        let status = try? await container.accountStatus()
        guard running else { return }
        problem = status == .available ? nil : "Sign in to iCloud in Settings to sync."
        let state = stored.state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        let configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                       stateSerialization: state, delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        Self.registerForPushes()
        if stored.joined {
            // Changed while the app wasn't running, or before it was sent.
            queueChanges(of: Session.shared.workspace)
            publishTabsSoon()
            publishExtensions()
        } else {
            await joinWhenFetched(engine)
        }
        refreshElsewhere()
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
            if (error as? CKError)?.code == .notAuthenticated { problem = "Sign in to iCloud in Settings to sync." }
            return
        }
        guard running, self.engine === engine, !stored.joined else { return }
        let remote = stored.mirror.adding(legacy: Self.legacySpaces())
        applying = true
        var joined = SyncMirror()
        Session.shared.change { joined = SyncPlan.join(&$0, remote: remote) }
        applying = false
        let changes = SyncPlan.changes(from: stored.mirror, to: joined)
        stored.mirror = joined
        stored.joined = true
        queue(changes)
        publishTabs()
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
    }

    /// On coming to the front. A device whose first join failed (offline at
    /// launch) joins now, rather than staying out of sync until the next launch.
    private func fetchSoon() {
        guard running, engine != nil else { return }
        if !stored.joined { joinSoon(); return }
        outsideCallback { sync in try? await sync.engine?.fetchChanges() }
    }

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

    /// After every change to the workspace (Session.change).
    func changed(from old: Workspace, to new: Workspace) {
        guard running, stored.joined, !applying, engine != nil else { return }
        if Self.face(of: old) != Self.face(of: new) { queueChanges(of: new) }
        publishTabsSoon()
    }

    /// What of a workspace goes to iCloud, to tell cheaply whether a change
    /// touched it: most changes are a page's title or address.
    private struct Face: Equatable {
        var cloud: UUID?
        var name: String
        var symbol: String
        var color: SpaceColor
        var bookmarks: [Bookmark]
        var pins: [String]
    }

    private static func face(of workspace: Workspace) -> [Face] {
        workspace.spaces.map { space in
            Face(cloud: space.cloudID, name: space.name, symbol: space.symbol, color: space.color, bookmarks: space.bookmarks,
                 pins: space.tabs.filter(\.isPinned).map {
                     "\(($0.cloudID ?? $0.id).uuidString) \($0.pinned?.absoluteString ?? "") \($0.url == $0.pinned ? $0.title : "")"
                 })
        }
    }

    private func queueChanges(of workspace: Workspace) {
        let next = SyncPlan.records(of: workspace, keeping: stored.mirror)
        // Spaces removed here, remembered: a use of one that comes later is an orphan.
        remember(removed: Set(stored.mirror.spaces.keys).subtracting(next.spaces.keys))
        let changes = SyncPlan.changes(from: stored.mirror, to: next)
        stored.mirror = next
        queue(changes)
        saveSoon()
    }

    private func queue(_ changes: (save: [String], delete: [String])) {
        guard let engine, !(changes.save.isEmpty && changes.delete.isEmpty) else { return }
        for name in changes.delete { stored.systemFields[name] = nil }
        engine.state.add(pendingRecordZoneChanges: changes.save.map { .saveRecord(recordID($0)) }
            + changes.delete.map { .deleteRecord(recordID($0)) })
    }

    // MARK: This device's open tabs

    private func publishTabsSoon() {
        tabsSoon?.cancel()
        let soon = DispatchWorkItem { [weak self] in self?.publishTabs() }
        tabsSoon = soon
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: soon)
    }

    /// This device's open tabs, a record per synced space, sent when they
    /// changed, or a day after the last time, so other devices know it is
    /// still about.
    private func publishTabs() {
        guard running, stored.joined else { return }
        let now = Date()
        let mine = SyncPlan.deviceTabs(of: Session.shared.workspace, device: stored.device,
                                       deviceName: Self.deviceName, now: now)
        var save: [String] = []
        for record in mine {
            let known = stored.mirror.deviceTabs[record.id]
            if known?.tabs != record.tabs || known?.deviceName != record.deviceName
                || now.timeIntervalSince(known?.updated ?? .distantPast) > 24 * 60 * 60 {
                stored.mirror.deviceTabs[record.id] = record
                save.append(record.id)
            }
        }
        let ids = Set(mine.map(\.id))
        let gone = stored.mirror.deviceTabs.values.filter { $0.device == stored.device && !ids.contains($0.id) }.map(\.id)
        for name in gone { stored.mirror.deviceTabs[name] = nil }
        // Nothing new to send is nothing new to write: this runs after every burst of changes to the tabs.
        guard !save.isEmpty || !gone.isEmpty else { return }
        queue((save, gone))
        saveSoon()
    }

    private func refreshElsewhere() {
        let now = Date()
        elsewhere = stored.mirror.deviceTabs.values
            .filter { $0.device != stored.device && now.timeIntervalSince($0.updated) < SyncDeviceTabs.stale && !$0.tabs.isEmpty }
            .sorted { $0.updated > $1.updated }
    }

    // MARK: Chrome extensions (the Mac's)

    /// The Mac's list of extensions changed (Extensions.saveList).
    func extensionsChanged() {
        guard running, stored.joined, engine != nil, !applying, !following else { return }
        publishExtensions()
    }

    /// This Mac's own changes to its extensions since it last sent them
    /// (SyncPlan.publish): what only other Macs have is left alone.
    private func publishExtensions() {
        #if os(macOS)
        guard running, stored.joined else { return }
        let list = Extensions.shared.syncList
        guard list != stored.extensions else { return refreshOffers() }
        let changes = SyncPlan.publish(from: stored.extensions, to: list, in: &stored.mirror)
        stored.extensions = list
        queue(changes)
        refreshOffers()
        saveSoon()
        #endif
    }

    #if DEBUG && os(macOS)
    /// For checking the list's look from the command line (-extensionOfferTest).
    func offerForChecking(_ offers: [SyncExtension]) { extensionOffers = offers }
    #endif

    /// Spaces removed, here or elsewhere: the last 500 kept.
    private func remember(removed spaces: Set<String>) {
        guard !spaces.isEmpty else { return }
        let known = stored.removedSpaces ?? []
        stored.removedSpaces = Array((known + spaces.sorted().filter { !known.contains($0) }).suffix(500))
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
        case .stateUpdate(let update):
            stored.state = try? JSONEncoder().encode(update.stateSerialization)
            saveSoon()
        case .accountChange(let change):
            accountChanged(change)
        case .fetchedDatabaseChanges(let changes):
            // The zone deleted (iCloud's data for the app erased): start again.
            if changes.deletions.contains(where: { $0.zoneID == zone }) {
                stored = Stored(device: stored.device)
                saveSoon()
                joinSoon()
            }
        case .fetchedRecordZoneChanges(let changes):
            took(changes)
        case .sentRecordZoneChanges(let sent):
            sentChanges(sent, engine: syncEngine)
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] id in
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
            problem = "Sign in to iCloud in Settings to sync."
            stored = Stored(device: stored.device)
            elsewhere = []
            extensionOffers = []
            saveSoon()
        case .switchAccounts:
            stored = Stored(device: stored.device)
            elsewhere = []
            extensionOffers = []
            saveSoon()
            joinSoon()
        @unknown default:
            break
        }
    }

    /// Records from iCloud into the mirror, and the workspace from it. A
    /// record this device changed and has not sent yet keeps its change: only
    /// iCloud's version of it is taken, so the save goes on top of that one
    /// (as after a conflict, below) instead of the fetch putting the old
    /// value back in the workspace and the save then sending that.
    private func took(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        let before = stored.mirror
        var deletedSpaces = Set<String>()
        // Whether anything the workspace is made from came: a space, a
        // bookmark, a pinned tab. Another device's open tabs are no part of
        // it, and they come every few seconds while that device is used;
        // putting every space's bookmarks together again for each was work
        // for nothing.
        var touched = false
        let unsent = Set((engine?.state.pendingRecordZoneChanges ?? []).compactMap { change -> String? in
            if case .saveRecord(let id) = change { return id.recordName }
            return nil
        })
        for modification in changes.modifications {
            let record = modification.record
            let name = record.recordID.recordName
            if unsent.contains(name), stored.mirror.record(named: name) != nil {
                stored.systemFields[name] = Self.systemFields(of: record)
                continue
            }
            if let plain = Self.syncRecord(record), stored.mirror.take(plain) {
                stored.systemFields[name] = Self.systemFields(of: record)
                if plain.kind != .deviceTabs { touched = true }
            }
        }
        for deletion in changes.deletions {
            let name = deletion.recordID.recordName
            if deletion.recordType == SyncKind.space.rawValue { deletedSpaces.insert(name) }
            if deletion.recordType != SyncKind.deviceTabs.rawValue { touched = true }
            stored.mirror.remove(name)
            stored.systemFields[name] = nil
        }
        // A space removed elsewhere takes its extensions' uses with it, which
        // an app that doesn't know them (an older one, the desktop
        // extension) left behind; only once its deletion has come, and so
        // too a use that comes after it.
        remember(removed: deletedSpaces)
        let orphans = SyncPlan.uses(ofRemoved: Set(stored.removedSpaces ?? []), in: stored.mirror)
        for name in orphans { stored.mirror.remove(name) }
        queue(([], orphans))
        if stored.joined, touched { applyMirror(deleted: deletedSpaces) }
        #if os(macOS)
        // Another Mac's change to the list, followed here once the spaces
        // are in place; and what this Mac now has taken as sent, so a space
        // removed in the same batch sends nothing back.
        if stored.joined {
            var follow: (removed: [String], on: [SyncPlan.ExtensionInSpace], off: [SyncPlan.ExtensionInSpace]) = ([], [], [])
            if before.extensions != stored.mirror.extensions || before.extensionUses != stored.mirror.extensionUses {
                follow = SyncPlan.follow(from: before, to: stored.mirror, local: Extensions.shared.syncList)
            }
            let retry = waitingSwitches
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
        refreshElsewhere()
        saveSoon()
    }

    private func applyMirror(deleted: Set<String>) {
        let session = Session.shared
        applying = true
        defer { applying = false }
        let applied = session.change { SyncPlan.apply(stored.mirror, to: &$0, deleted: deleted) }
        for tab in applied.removedTabs { session.closeTab(tab) }
        for space in applied.removedSpaces {
            if session.workspace.spaces.count > 1 {
                session.removeSpace(space)
            } else {
                // The last space stays, no longer synced; it joins again as new.
                session.change { workspace in
                    if let s = workspace.spaces.firstIndex(where: { $0.id == space }) { workspace.spaces[s].cloudID = nil }
                }
            }
        }
    }

    private func sentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        for record in sent.savedRecords {
            stored.systemFields[record.recordID.recordName] = Self.systemFields(of: record)
        }
        var again: [CKSyncEngine.PendingRecordZoneChange] = []
        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Changed in iCloud since this device last saw it: saved
                // again on top of iCloud's version, which comes in too.
                if let server = failure.error.serverRecord { stored.systemFields[id.recordName] = Self.systemFields(of: server) }
                again.append(.saveRecord(id))
            case .zoneNotFound:
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
                again.append(.saveRecord(id))
            case .unknownItem:
                // Deleted in iCloud meanwhile: made again from this device's version.
                stored.systemFields[id.recordName] = nil
                again.append(.saveRecord(id))
            case .quotaExceeded:
                problem = "Your iCloud storage is full, so Safience can't sync. Free up space in iCloud to sync again."
            case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy,
                 .batchRequestFailed, .notAuthenticated:
                // Passing, or another record's failure failing the batch: again later.
                again.append(.saveRecord(id))
            default:
                break
            }
        }
        if !sent.savedRecords.isEmpty, problem?.hasPrefix("Your iCloud storage is full") == true { problem = nil }
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
        guard let plain = stored.mirror.record(named: name) else { return nil }
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
        return SyncRecord(kind: kind, name: record.recordID.recordName, fields: fields)
    }

    /// Where a kind's fields are kept: its encrypted values, or the record.
    private static func values(of record: CKRecord, encrypted: Bool) -> any CKRecordKeyValueSetting {
        if encrypted { return record.encryptedValues }
        return record
    }

    private static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Kept on the device

    /// The mirror, each record's CloudKit version, the engine's own state,
    /// and this device's id, in Application Support.
    private struct Stored: Codable {
        var mirror = SyncMirror()
        var systemFields: [String: Data] = [:]
        var state: Data?
        var device = UUID().uuidString
        /// This device's spaces have joined iCloud's.
        var joined = false
        /// The Mac's extensions as it last sent them (SyncPlan.publish);
        /// nil before the first time.
        var extensions: [SyncPlan.LocalExtension]?
        /// Spaces removed, whose extensions' uses go when they come.
        var removedSpaces: [String]?

        init(device: String = UUID().uuidString) {
            self.device = device
        }

        @MainActor static var file: URL {
            Session.folder.appendingPathComponent("sync.json")
        }

        @MainActor static func read() -> Stored? {
            (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        }
    }

    private func saveSoon() {
        saving?.cancel()
        let snapshot = stored
        let file = Stored.file
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        saving = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
    }

    // MARK: Before CloudKit

    /// What the key-value store kept before sync moved to CloudKit: read
    /// once, when this device first joins, and never written again.
    private static func legacySpaces() -> [CloudSpace] {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        return store.dictionaryRepresentation.keys.filter { $0.hasPrefix("space.") }.sorted().compactMap { key in
            store.data(forKey: key).flatMap(Deflate.inflate).flatMap { try? JSONDecoder().decode(CloudSpace.self, from: $0) }
        }
    }
}

private extension SyncMirror {
    /// The key-value store's spaces that CloudKit hasn't got yet.
    func adding(legacy spaces: [CloudSpace]) -> SyncMirror {
        let old = SyncPlan.mirror(fromLegacy: spaces)
        var out = self
        for (id, space) in old.spaces where out.spaces[id] == nil {
            out.spaces[id] = space
            for bookmark in old.bookmarks.values where bookmark.space == id { out.bookmarks[bookmark.id] = bookmark }
        }
        return out
    }
}

/// zlib's deflate, as Apple's Compression has it: how the key-value store
/// kept each space, read back once (Sync.legacySpaces).
enum Deflate {
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 4 else { return nil }
        let size = data.prefix(4).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard size > 0, size < 8_000_000 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let body = data.dropFirst(4)
        let read = body.withUnsafeBytes { source -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(&buffer, size, base, body.count, nil, COMPRESSION_ZLIB)
        }
        return read == size ? Data(buffer) : nil
    }
}

#if canImport(UIKit)
/// Settings' iCloud section.
struct CloudSection: View {
    @ObservedObject var session: Session
    @ObservedObject var sync = Sync.shared

    var body: some View {
        Section {
            Toggle("Sync with iCloud", isOn: $session.preferences.iCloudSync)
            if session.preferences.iCloudSync, let problem = sync.problem {
                Label(problem, systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SettingsHeader("iCloud", .sync)
        } footer: {
            Text("Sign-ins and what sites store stay on each device. Turning it on joins spaces with the same name and keeps both sets of bookmarks; removing a space removes it everywhere.")
        }
    }
}
#endif
