import AppKit
import Combine
import PadCore
import UniformTypeIdentifiers
import WebKit

/// Chrome extensions, run by WebKit's own extension engine
/// (`WKWebExtension`), the one Safari uses (Docs/ExtensionsDesign.md).
///
/// Each space has an extension controller of its own, on the space's
/// website store, so an extension turned on in two spaces is two of it:
/// its storage, its sign-ins and what it was allowed are each space's. An
/// extension's files are kept once, for every space.
///
/// Google's sign-in stays out of every extension's reach (ExtensionPolicy):
/// each context denies its hosts and the `cookies` permission, whatever the
/// extension asked for.
@MainActor
final class Extensions: NSObject, ObservableObject {
    static let shared = Extensions()

    /// What is installed, and where it is on.
    @Published private(set) var installed: [Installed] = []
    /// What the checks after install found, by space and extension.
    @Published private(set) var verdicts: [UUID: [String: ExtensionVerdict]] = [:]

    struct Installed: Codable, Equatable, Identifiable {
        enum Source: String, Codable {
            /// From the Chrome Web Store, with Google's signature.
            case store
            /// A CRX the person chose, signed by its developer.
            case file
            /// A ZIP the person chose: no signature, so a random id of its own.
            case unsigned
        }

        enum SiteAccess: String, Codable {
            /// Every site it asked for.
            case allSites
            /// The page it was clicked on, each time.
            case onClick
        }

        var id: String
        var name: String
        var version: String
        var source: Source
        var siteAccess: SiteAccess
        /// The spaces it is on in.
        var spaces: [UUID]
    }

    private var controllers: [UUID: WKWebExtensionController] = [:]
    private var contexts: [UUID: [String: WKWebExtensionContext]] = [:]
    private var evidence: [UUID: [String: ExtensionEvidence]] = [:]
    /// What each extension asked for that nothing here answers: what its
    /// errors are read against.
    private var lacking: [String: Set<String>] = [:]
    /// Each loaded context's errors watch, removed when it unloads.
    private var watches: [UUID: [String: NSObjectProtocol]] = [:]
    let tabs = ExtensionTabs()

    /// The scheme of extensions' own pages, as Chrome's.
    static let scheme = "chrome-extension"

    private override init() {
        super.init()
        // Before any context takes a base address in it: WebKit refuses one
        // in a scheme it wasn't told of, with an exception, not an error
        // (WKWebExtensionContext's setBaseURL:), and AppKit, catching it,
        // leaves Swift's tasks broken behind it.
        WKWebExtension.MatchPattern.registerCustomURLScheme(Self.scheme)
    }

    static var folder: URL {
        Session.folder.appendingPathComponent("Extensions", isDirectory: true)
    }

    private static var listFile: URL {
        folder.appendingPathComponent("installed.json")
    }

    /// The verified package of a version, kept as it came.
    static func package(_ id: String, _ version: String) -> URL {
        folder.appendingPathComponent(id, isDirectory: true).appendingPathComponent("\(version).zip")
    }

    /// The folder WebKit loads a version from: its package unpacked, with
    /// the shim put in (ExtensionPreparation).
    static func prepared(_ id: String, _ version: String) -> URL {
        folder.appendingPathComponent(id, isDirectory: true).appendingPathComponent(version, isDirectory: true)
    }

    /// Makes the prepared folder from the package, unless it is there and
    /// was made from this package with this shim. Off the main thread: a large extension
    /// takes a moment. Into a folder of its own first, so a folder that is
    /// there is always a whole one; and one at a time, so a load in another
    /// space, which may be reading it, finds it made rather than replaced.
    /// Only a folder made with another shim is replaced, and nothing loads
    /// one of those.
    nonisolated static func prepare(_ package: URL, into folder: URL) throws {
        try preparing.withLock { try prepareNow(package, into: folder) }
    }

    private nonisolated static let preparing = NSLock()

    private nonisolated static func prepareNow(_ package: URL, into folder: URL) throws {
        var shim = Scripts.extensionShim
        #if DEBUG
        // To see what WebKit does without it (`-extensionsWithoutShim YES`).
        if UserDefaults.standard.bool(forKey: "extensionsWithoutShim") { shim = "" }
        #endif
        // The package's size and time, taken before it is read: one put in
        // its place, of the same version, is told apart.
        let kept = try package.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let stamp = [ExtensionPreparation.stamp(for: shim), String(kept.fileSize ?? 0),
                     String(kept.contentModificationDate?.timeIntervalSince1970 ?? 0)].joined(separator: " ")
        let stampFile = folder.appendingPathComponent(ExtensionPreparation.stampFile)
        if (try? String(contentsOf: stampFile, encoding: .utf8)) == stamp { return }
        let archive = try Data(contentsOf: package)
        let files = FileManager.default
        let making = folder.deletingLastPathComponent()
            .appendingPathComponent(".\(folder.lastPathComponent).\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: making, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: making) }
        // Every name was checked to stay inside the folder before the
        // first is written, and only plain files are made: no link in a
        // package can lead a later file elsewhere.
        try ExtensionPreparation.prepare(archive, shim: shim, stamp: stamp) { path, data in
            let file = making.appendingPathComponent(path)
            try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
        try files.moveItem(at: making, to: folder)
    }

    // MARK: Starting

    /// At launch: what is installed, loaded where it is on, one after
    /// another, as starting them all at once leaves some workers unstarted.
    func start() {
        #if DEBUG
        // To tell the extensions' part of a launch from the rest (`-noExtensions YES`).
        if UserDefaults.standard.bool(forKey: "noExtensions") { return }
        #endif
        if let data = try? Data(contentsOf: Self.listFile),
           let list = try? JSONDecoder().decode([Installed].self, from: data) {
            installed = list
        }
        tabs.start()
        // Loaded once the app has finished launching, and the turn after: a
        // load holds the main thread long enough to hold up the first frame,
        // as Search found (its Extensions.swift, start(for:)).
        launched = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.loadAll() } }
        }
    }

    private var launched: NSObjectProtocol?

    private func loadAll() {
        if let launched { NotificationCenter.default.removeObserver(launched) }
        launched = nil
        #if DEBUG
        checkFromTheCommandLine()
        #endif
        Task {
            for item in installed {
                for space in item.spaces where Session.shared.workspace.space(space) != nil {
                    await load(item, in: space)
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }
    }

    private func saveList() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(installed) { try? data.write(to: Self.listFile, options: .atomic) }
    }

    /// The space's controller, made the first time a page in the space is.
    /// Every page gets it before its view exists, as WebKit needs, whether
    /// or not anything is on in the space yet.
    func controller(for space: UUID) -> WKWebExtensionController {
        if let controller = controllers[space] { return controller }
        let configuration = WKWebExtensionController.Configuration(identifier: space)
        configuration.defaultWebsiteDataStore = Stores.store(for: space)
        let controller = WKWebExtensionController(configuration: configuration)
        controller.delegate = self
        controllers[space] = controller
        return controller
    }

    func space(of controller: WKWebExtensionController?) -> UUID? {
        controllers.first { $0.value === controller }?.key
    }

    func context(_ id: String, in space: UUID) -> WKWebExtensionContext? {
        contexts[space]?[id]
    }

    /// The extensions on in a space, in the order they were installed.
    func on(in space: UUID) -> [Installed] {
        installed.filter { $0.spaces.contains(space) && contexts[space]?[$0.id] != nil }
    }

    /// Whether a URL is one of the extensions' own pages.
    func isExtensionPage(_ url: URL?) -> Bool {
        guard let url, url.scheme == Self.scheme, let host = url.host() else { return false }
        return installed.contains { $0.id == host }
    }

    // MARK: Loading

    private func load(_ item: Installed, in space: UUID) async {
        guard contexts[space]?[item.id] == nil else { return }
        var seen = ExtensionEvidence()
        do {
            let (file, folder) = (Self.package(item.id, item.version), Self.prepared(item.id, item.version))
            try await Task.detached(priority: .userInitiated) { try Self.prepare(file, into: folder) }.value
            let package = try await WKWebExtension(resourceBaseURL: folder)
            // Turned off, removed, updated, or its space gone, while the
            // package was read: not loaded after all.
            guard installed.first(where: { $0.id == item.id }) == item,
                  Session.shared.workspace.space(space) != nil, contexts[space]?[item.id] == nil
            else { return }
            let context = WKWebExtensionContext(for: package)
            context.uniqueIdentifier = item.id
            // chrome-extension://, as Chrome's own addresses are: an
            // extension that checks where its pages are finds them there.
            context.baseURL = URL(string: "\(Self.scheme)://\(item.id)/")!
            context.isInspectable = true
            context.inspectionName = item.name
            allow(context, package, access: item.siteAccess)
            watch(context, item, in: space)
            try controller(for: space).load(context)
            contexts[space, default: [:]][item.id] = context
            seen = firstLook(at: context, package, archive: Self.package(item.id, item.version), id: item.id)
        } catch {
            seen.start = .failed
            unwatch(item.id, in: space)
            NSLog("Safience: extension \(item.id) didn't load in a space: \(error.localizedDescription)")
            #if DEBUG
            Self.note("load failed: \(error)")
            #endif
        }
        record(seen, item.id, in: space)
        if seen.start == .checking, let context = contexts[space]?[item.id] {
            startBackground(of: context, item, in: space)
        }
    }

    private func unload(_ id: String, in space: UUID) {
        unwatch(id, in: space)
        guard let context = contexts[space]?.removeValue(forKey: id) else { return }
        try? controllers[space]?.unload(context)
        evidence[space]?[id] = nil
        verdicts[space]?[id] = nil
    }

    /// What the extension may do: what it asked for, less what no extension
    /// gets; its sites when the person chose all of them; never Google's
    /// sign-in.
    private func allow(_ context: WKWebExtensionContext, _ package: WKWebExtension, access: Installed.SiteAccess) {
        for permission in package.requestedPermissions where !ExtensionPolicy.deniedPermissions.contains(permission.rawValue) {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for name in ExtensionPolicy.deniedPermissions {
            context.setPermissionStatus(.deniedExplicitly, for: WKWebExtension.Permission(rawValue: name))
        }
        if access == .allSites {
            for pattern in package.allRequestedMatchPatterns {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
        }
        for site in ExtensionPolicy.deniedSites {
            if let pattern = try? WKWebExtension.MatchPattern(string: site) {
                context.setPermissionStatus(.deniedExplicitly, for: pattern)
            }
        }
    }

    // MARK: Checking (Docs/ExtensionsDesign.md, section 4)

    /// What can be told before the background has started: what WebKit
    /// dropped from what it asked for, and what its code reaches for that
    /// nothing here answers.
    private func firstLook(at context: WKWebExtensionContext, _ package: WKWebExtension, archive file: URL, id: String) -> ExtensionEvidence {
        var seen = ExtensionEvidence()
        seen.start = package.hasBackgroundContent ? .checking : .started
        guard let archive = try? Data(contentsOf: file),
              let manifestData = ZipFile.file(in: archive, matching: { $0 == "manifest.json" }),
              let manifest = try? ExtensionManifest(json: manifestData)
        else { return seen }
        let kept = Set((package.requestedPermissions.union(package.optionalPermissions)).map(\.rawValue))
        let dropped = manifest.dropped(kept: kept)
        seen.cookiesKeptBack = manifest.permissions.contains("cookies")
        // A permission's name is its namespace's: one WebKit dropped is a
        // namespace this Mac doesn't have.
        let missing = Set(dropped.filter { $0 != "cookies" } + (manifest.usesChromeSignIn ? ["identity.getAuthToken"] : []))
        lacking[id] = missing
        var notes: [String] = []
        for file in manifest.files where file.hasSuffix(".js") {
            guard let source = ZipFile.file(in: archive, matching: { $0 == file }) else { continue }
            let uses = ExtensionScan.uses(in: String(decoding: source, as: UTF8.self), file: file, of: missing)
            for use in uses where !use.tested && !notes.contains(use.path) { notes.append(use.path) }
        }
        seen.mayNotWork = notes
        return seen
    }

    /// Starts the background, and gives it five seconds. WebKit doesn't
    /// always answer when a worker throws as it starts; its errors say so
    /// instead (code 6), and are watched apart from this.
    private func startBackground(of context: WKWebExtensionContext, _ item: Installed, in space: UUID) {
        var answered = false
        context.loadBackgroundContent { [weak self] error in
            MainActor.assumeIsolated {
                answered = true
                self?.update(item.id, in: space) { $0.start = error == nil ? .started : .failed }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard !answered else { return }
            self?.update(item.id, in: space) { if $0.start == .checking { $0.start = .timedOut } }
        }
    }

    private func watch(_ context: WKWebExtensionContext, _ item: Installed, in space: UUID) {
        let id = item.id
        watches[space, default: [:]][id] = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification, object: context, queue: .main
        ) { [weak self, weak context] _ in
            MainActor.assumeIsolated {
                guard let self, let context else { return }
                self.errorsChanged(context, id, in: space)
            }
        }
    }

    private func unwatch(_ id: String, in space: UUID) {
        if let token = watches[space]?.removeValue(forKey: id) { NotificationCenter.default.removeObserver(token) }
    }

    private func errorsChanged(_ context: WKWebExtensionContext, _ id: String, in space: UUID) {
        let missing = lacking[id] ?? []
        update(id, in: space) { seen in
            for error in context.errors {
                let nsError = error as NSError
                if nsError.domain == WKWebExtensionContext.errorDomain,
                   nsError.code == WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue {
                    seen.start = .failed
                }
                if let problem = ExtensionError.problem(in: nsError.localizedDescription, missing: missing) {
                    seen.problems.insert(problem)
                }
            }
        }
    }

    private func update(_ id: String, in space: UUID, _ change: (inout ExtensionEvidence) -> Void) {
        guard var seen = evidence[space]?[id] else { return }
        change(&seen)
        record(seen, id, in: space)
    }

    private func record(_ seen: ExtensionEvidence, _ id: String, in space: UUID) {
        evidence[space, default: [:]][id] = seen
        verdicts[space, default: [:]][id] = ExtensionVerdict(seen)
    }

    // MARK: Installing

    enum Refused: LocalizedError {
        case download(Int)
        case nothing
        case notAPackage
        case noManifest
        case badVersion
        case notChecked(String)

        var errorDescription: String? {
            switch self {
            case .download(let code): return "The Chrome Web Store answered \(code)."
            case .nothing: return "The Chrome Web Store has nothing for that extension. It may have been taken down."
            case .notAPackage: return "That isn't a Chrome extension."
            case .noManifest: return "The extension has no manifest.json."
            case .badVersion: return "The extension's version isn't one Chrome would take."
            case .notChecked(let reason): return reason
            }
        }
    }

    /// The extension a Chrome Web Store page is about, fetched from the store,
    /// checked, and offered to the person.
    func add(fromStorePage url: URL, in window: WindowModel?) {
        guard let id = ExtensionStore.id(ofPage: url) else { return }
        Task {
            do {
                let crx = try await download(id)
                let archive = try CRXFile.archive(of: crx, id: id, fromStore: true)
                try await offer(archive, id: id, source: .store, in: window)
            } catch {
                tell(error, in: window)
            }
        }
    }

    /// A CRX or ZIP the person chose: Install from File.
    func addFromFile(in window: WindowModel?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "crx") ?? .data, .zip]
        panel.message = "Choose a Chrome extension: a .crx file, or a .zip with its manifest.json."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try Data(contentsOf: url)
                if CRXFile.isCRX(data) {
                    let header = try CRXFile.header(of: data)
                    guard let id = header.declaredID else { throw CRXFile.Refusal.noDeveloperKey }
                    try await offer(try CRXFile.archive(of: data, id: id, fromStore: false), id: id, source: .file, in: window)
                } else if ZipFile.isArchive(data) {
                    // No key to make an id from: a random one, which can't
                    // be any store extension's.
                    let id = ExtensionID.letters((0..<16).map { _ in UInt8.random(in: 0...255) })
                    try await offer(data, id: id, source: .unsigned, in: window)
                } else {
                    throw Refused.notAPackage
                }
            } catch {
                tell(error, in: window)
            }
        }
    }

    private func download(_ id: String) async throws -> Data {
        var request = URLRequest(url: ExtensionStore.packageURL(for: id))
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else { throw Refused.download(http.statusCode) }
            guard let final = http.url, ExtensionStore.isPackageHost(final) || final.host() == "clients2.google.com" else {
                throw Refused.notAPackage
            }
        }
        guard !data.isEmpty else { throw Refused.nothing }
        return data
    }

    /// The install sheet: what it is, what it asks for, where it goes and
    /// what it may read; then the files kept and the extension loaded.
    private func offer(_ archive: Data, id: String, source: Installed.Source, in window: WindowModel?, asking: Bool = true) async throws {
        guard let manifestData = ZipFile.file(in: archive, matching: { $0 == "manifest.json" }) else { throw Refused.noManifest }
        let manifest = try ExtensionManifest(json: manifestData)
        // Both name files: only what Chrome itself takes, 32 letters and a
        // version of numbers and dots, so neither can lead out of the folder.
        guard ExtensionID.isValid(id) else { throw Refused.notAPackage }
        guard let version = ExtensionVersion(manifest.version)?.description else { throw Refused.badVersion }
        let name = manifest.name.hasPrefix("__MSG_") ? id : manifest.name
        let space = window?.spaceID ?? Session.shared.workspace.spaces[0].id
        guard asking else {
            try keep(archive, id: id, name: name, version: version, source: source, access: .allSites, spaces: [space])
            return
        }
        let alert = NSAlert()
        alert.messageText = "Add \u{201C}\(name)\u{201D}?"
        var lines: [String] = []
        if !manifest.permissions.isEmpty { lines.append("It asks for: " + manifest.permissions.joined(separator: ", ") + ".") }
        if !manifest.hostPermissions.isEmpty || !manifest.contentScripts.isEmpty {
            lines.append("It can read and change the sites it is allowed, and send what it reads anywhere.")
        }
        if manifest.permissions.contains("cookies") { lines.append("It won't get your cookies: they are kept from Google's sign-in.") }
        lines.append(source == .store ? "From the Chrome Web Store, signed by Google." : source == .file ? "From a file, signed by its developer." : "From a file, not signed by anyone.")
        alert.informativeText = lines.joined(separator: "\n\n")
        let access = NSPopUpButton(frame: NSRect(x: 0, y: 28, width: 280, height: 26))
        access.addItems(withTitles: ["On All Sites It Asks For", "When I Click It"])
        let scope = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        scope.addItems(withTitles: ["In This Space", "In All Spaces"])
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54))
        accessory.addSubview(access)
        accessory.addSubview(scope)
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let answer = await present(alert, in: window)
        guard answer == .alertFirstButtonReturn else { return }
        try keep(archive, id: id, name: name, version: version, source: source,
                 access: access.indexOfSelectedItem == 1 ? .onClick : .allSites,
                 spaces: scope.indexOfSelectedItem == 1 ? Session.shared.workspace.spaces.map(\.id) : [space])
    }

    /// The files kept, the extension listed and loaded where it goes.
    private func keep(_ archive: Data, id: String, name: String, version: String, source: Installed.Source,
                      access: Installed.SiteAccess, spaces: [UUID]) throws {
        let file = Self.package(id, version)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try archive.write(to: file, options: .atomic)
        let item = Installed(id: id, name: name, version: version, source: source, siteAccess: access, spaces: spaces)
        // A newer version of one already here: the same id, so the same
        // developer's key. An unsigned one has a random id of its own and
        // never takes another's place.
        if let old = installed.firstIndex(where: { $0.id == id }) {
            for space in installed[old].spaces { unload(id, in: space) }
            installed[old] = item
            // The old version's package and folder, now nothing loads them;
            // not a folder being made (its name starts with a dot), which
            // goes when it is done or fails.
            let kept = [file.lastPathComponent, version]
            let here = file.deletingLastPathComponent()
            for name in (try? FileManager.default.contentsOfDirectory(atPath: here.path)) ?? []
            where !kept.contains(name) && !name.hasPrefix(".") {
                try? FileManager.default.removeItem(at: here.appendingPathComponent(name))
            }
        } else {
            installed.append(item)
        }
        saveList()
        Task { for space in spaces { await load(item, in: space) } }
    }

    /// A question as a sheet on the window. Never as a modal run of its
    /// own: that spins a run loop inside a task, which Swift's main-actor
    /// checks don't survive. With no window to put it on, the answer is no.
    private func present(_ alert: NSAlert, in window: WindowModel?) async -> NSApplication.ModalResponse {
        guard let host = window?.window ?? NSApp.keyWindow ?? Session.shared.frontWindow?.window else {
            return .alertSecondButtonReturn
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: host) { continuation.resume(returning: $0) }
        }
    }

    private func tell(_ error: Error, in window: WindowModel?) {
        let reason = (error as? CRXFile.Refusal)?.reason ?? error.localizedDescription
        guard let host = window?.window ?? NSApp.keyWindow ?? Session.shared.frontWindow?.window else {
            NSLog("Safience: an extension couldn't be added: \(reason)")
            return
        }
        let alert = NSAlert()
        alert.messageText = "The extension couldn't be added."
        alert.informativeText = reason
        alert.beginSheetModal(for: host)
    }

    // MARK: Turning off, removing

    func turn(_ id: String, on: Bool, in space: UUID) {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        if on {
            guard !installed[index].spaces.contains(space) else { return }
            installed[index].spaces.append(space)
            saveList()
            let item = installed[index]
            Task { await load(item, in: space) }
        } else {
            installed[index].spaces.removeAll { $0 == space }
            saveList()
            unload(id, in: space)
        }
    }

    /// Gone from every space, its data with it, then its files. Every
    /// space's: one it was turned off in kept its data, for when it is
    /// turned on again.
    func remove(_ id: String) {
        guard installed.contains(where: { $0.id == id }) else { return }
        for space in Session.shared.workspace.spaces.map(\.id) { unload(id, in: space) }
        installed.removeAll { $0.id == id }
        saveList()
        let types = WKWebExtensionController.allExtensionDataTypes
        let controllers = Session.shared.workspace.spaces.map { controller(for: $0.id) }
        Task {
            for controller in controllers {
                let records = await controller.dataRecords(ofTypes: types).filter { $0.uniqueIdentifier == id }
                if !records.isEmpty { await controller.removeData(ofTypes: types, from: records) }
            }
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id, isDirectory: true))
        }
    }

    /// The configuration an extension's own page needs, in a space where
    /// the extension is loaded.
    func configuration(for url: URL, in space: UUID) -> WKWebViewConfiguration? {
        guard isExtensionPage(url), let id = url.host() else { return nil }
        return contexts[space]?[id]?.webViewConfiguration
    }

    /// A space going: its extensions unload and their data goes, and its
    /// controller is let go before its website store is erased, which
    /// WebKit won't do while anything holds the store.
    func removeSpace(_ space: UUID) {
        for id in Array((contexts[space] ?? [:]).keys) { unload(id, in: space) }
        watches[space] = nil
        for index in installed.indices { installed[index].spaces.removeAll { $0 == space } }
        saveList()
        controllers[space] = nil
        contexts[space] = nil
        verdicts[space] = nil
        evidence[space] = nil
    }

    // MARK: The shim's answers

    /// The name the shim sends its native messages to.
    static let shimApplication = "safience"

    /// What the shim asked, answered as it reads answers: {value} or
    /// {error}. An answer that will touch a site's data, as Search's
    /// browsingData does, checks ExtensionPolicy.mayTouchData first; none
    /// here does yet.
    private func answer(_ api: String, _ args: [Any], from id: String, in space: UUID) -> [String: Any] {
        switch api {
        case "report":
            // An error nobody caught: [kind, its words, file, line]. Only
            // the API it names is kept, as for WebKit's own errors.
            let problem = args.count > 1 ? (args[1] as? String).flatMap { ExtensionError.problem(in: $0, missing: lacking[id] ?? []) } : nil
            #if DEBUG
            Self.note("shim report: \(problem?.api ?? "no API named")")
            #endif
            if let problem { update(id, in: space) { $0.problems.insert(problem) } }
            return ["value": NSNull()]
        default:
            return ["error": "Safience doesn't answer \(api)."]
        }
    }

    // MARK: Running one

    /// What a click on the extension's button does: its popup, or its own
    /// handler; never a grant of the page on a hands-off one.
    func run(_ id: String, in window: WindowModel) {
        guard let context = contexts[window.spaceID]?[id] else { return }
        let tab = window.tabID.map { tabs.tab($0, in: window.spaceID) }
        context.performAction(for: tab)
    }
}

#if DEBUG
// MARK: Checking from the command line

extension Extensions {
    /// A line in the check's steps file, beside its report.
    static func note(_ line: String) {
        guard let out = UserDefaults.standard.string(forKey: "extensionReport") else { return }
        let text = ((try? String(contentsOfFile: out + ".steps", encoding: .utf8)) ?? "") + line + "\n"
        try? text.write(toFile: out + ".steps", atomically: true, encoding: .utf8)
    }

    /// For checking an extension without a window's sheet:
    /// `Safience --args -installExtension x.zip -extensionPages https://a/,https://b/ -extensionSpaces 2 -extensionReport out.txt`
    /// makes as many spaces as asked, installs the extension in every one,
    /// opens each page in each space, and after 15 seconds writes what was
    /// seen: each extension's verdict and errors, and each page's title.
    fileprivate func checkFromTheCommandLine() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "installExtension") else { return }
        let note = Extensions.note
        note("hook")
        Task {
            note("task")
            try? await Task.sleep(for: .seconds(3))
            let session = Session.shared
            let wanted = max(1, defaults.integer(forKey: "extensionSpaces"))
            while session.workspace.spaces.count < wanted {
                session.change { _ = $0.addSpace(named: "Test \($0.spaces.count + 1)") }
            }
            let spaces = session.workspace.spaces.prefix(wanted).map(\.id)
            note("installing in \(spaces.count)")
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let (archive, id, source): (Data, String, Installed.Source)
                if CRXFile.isCRX(data) {
                    let declared = try CRXFile.header(of: data).declaredID ?? ""
                    (archive, id, source) = (try CRXFile.archive(of: data, id: declared, fromStore: false), declared, .file)
                } else {
                    (archive, id, source) = (data, ExtensionID.letters([UInt8](repeating: 7, count: 16)), .unsigned)
                }
                guard let manifestData = ZipFile.file(in: archive, matching: { $0 == "manifest.json" }),
                      let manifest = try? ExtensionManifest(json: manifestData),
                      let version = ExtensionVersion(manifest.version)?.description
                else { throw Refused.noManifest }
                try keep(archive, id: id, name: manifest.name, version: version, source: source, access: .allSites, spaces: spaces)
            } catch {
                note("refused: \(error)")
            }
            note("installed")
            try? await Task.sleep(for: .seconds(4))
            var opened: [(space: UUID, tab: UUID)] = []
            let pages = (defaults.string(forKey: "extensionPages") ?? "").split(separator: ",").compactMap { URL(string: String($0)) }
            for space in spaces {
                for url in pages {
                    guard let tab = session.change({ $0.openTab(url, in: space) }), let record = session.workspace.tab(tab) else { continue }
                    _ = session.pages.page(for: record, in: space)
                    opened.append((space, tab))
                }
            }
            note("pages opened")
            try? await Task.sleep(for: .seconds(11))
            note("reporting")
            guard let out = defaults.string(forKey: "extensionReport") else { return }
            var lines: [String] = []
            for (number, space) in spaces.enumerated() {
                for item in installed where item.spaces.contains(space) {
                    let context = contexts[space]?[item.id]
                    lines.append("space \(number + 1) extension \(item.name) loaded=\(context?.isLoaded ?? false)")
                    if let verdict = verdicts[space]?[item.id] {
                        lines.append("space \(number + 1) verdict \(verdict.title)")
                        lines += verdict.lines.map { "space \(number + 1) line \($0)" }
                    }
                    lines += (context?.errors ?? []).map { "space \(number + 1) error \(($0 as NSError).code) \($0.localizedDescription)" }
                    lines.append("space \(number + 1) cookies \(context?.permissionStatus(for: .cookies).rawValue ?? 99)")
                    let stamp = Self.prepared(item.id, item.version).appendingPathComponent(ExtensionPreparation.stampFile)
                    lines.append("space \(number + 1) prepared \((try? String(contentsOf: stamp, encoding: .utf8)) ?? "-")")
                }
                for page in opened where page.space == space {
                    let view = session.pages.live[page.tab]?.view
                    lines.append("space \(number + 1) page \(view?.url?.host() ?? "-"): \(view?.title ?? "-")")
                }
            }
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
    }
}
#endif

// MARK: What WebKit asks of the app

extension Extensions: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        guard let space = space(of: controller) else { return [] }
        return [tabs.window(for: space)]
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let space = space(of: controller), Session.shared.frontWindow?.spaceID == space,
              Session.shared.frontWindow?.window?.isKeyWindow == true
        else { return nil }
        return tabs.window(for: space)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let space = space(of: controller) else { return completionHandler(nil, nil) }
        let tab = tabs.open(configuration.url, in: space, active: configuration.shouldBeActive,
                            pinned: configuration.shouldBePinned, context: extensionContext)
        completionHandler(tab, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void) {
        guard let space = space(of: controller) else { return completionHandler(nil, nil) }
        // A space is one window to extensions: a new one shows the same space,
        // with its first address in a tab.
        for url in configuration.tabURLs.prefix(1) {
            _ = tabs.open(url, in: space, active: true, pinned: false, context: extensionContext)
        }
        if Session.shared.allWindows.contains(where: { $0.spaceID == space }) == false {
            Session.shared.openWindow?(space)
        }
        completionHandler(tabs.window(for: space), nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        guard let space = space(of: controller), let url = extensionContext.optionsPageURL else { return completionHandler(nil) }
        _ = tabs.open(url, in: space, active: true, pinned: false, context: extensionContext)
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let asked = permissions.filter { !ExtensionPolicy.deniedPermissions.contains($0.rawValue) }
        guard !asked.isEmpty else { return completionHandler([], nil) }
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(extensionContext.webExtension.displayName ?? "An extension")\u{201D} asks for more."
        alert.informativeText = asked.map(\.rawValue).sorted().joined(separator: ", ")
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        Task {
            let answer = await present(alert, in: Session.shared.frontWindow)
            completionHandler(answer == .alertFirstButtonReturn ? asked : [], nil)
        }
    }

    /// Chrome never asks site by site; a site the extension wants comes
    /// with its install, or with a click on its button.
    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        completionHandler([], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(extensionContext.webExtension.displayName ?? "An extension")\u{201D} asks to read and change more sites."
        alert.informativeText = matchPatterns.map(\.string).sorted().joined(separator: "\n")
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        Task {
            let answer = await present(alert, in: Session.shared.frontWindow)
            completionHandler(answer == .alertFirstButtonReturn ? matchPatterns : [], nil)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover,
              let view = Session.shared.frontWindow?.window?.contentView
        else { return completionHandler(nil) }
        // Under the window's top edge, at its end, until the buttons are in the bars.
        let anchor = NSRect(x: view.bounds.maxX - 40, y: view.bounds.maxY - 44, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        completionHandler(nil)
    }

    /// Safience's shim, through native messaging to "safience"
    /// (Scripts/extension-shim.js); nothing else gets an answer, as no
    /// desktop app talks to extensions through Safience yet.
    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?,
                                for extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void) {
        let id = extensionContext.uniqueIdentifier
        guard applicationIdentifier == Self.shimApplication, let call = message as? [String: Any], let api = call["api"] as? String,
              let space = space(of: controller), contexts[space]?[id] === extensionContext
        else {
            return replyHandler(nil, NSError(domain: "Safience", code: 1, userInfo: [NSLocalizedDescriptionKey: "Safience doesn't pass messages to other apps."]))
        }
        replyHandler(answer(api, call["args"] as? [Any] ?? [], from: id, in: space), nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort,
                                for extensionContext: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(NSError(domain: "Safience", code: 1, userInfo: [NSLocalizedDescriptionKey: "Safience doesn't pass messages to other apps."]))
    }
}
