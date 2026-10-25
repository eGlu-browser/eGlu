import PadCore
import UIKit
import WebKit

/// Every tab's page: live, or frozen to a picture.
///
/// A live page keeps its WebKit content process. A frozen one keeps a
/// picture of how it looked and what WebKit needs to load it back where it
/// was, and nothing else: opening it shows the picture while the page loads
/// again underneath. Which tabs stay live is the Freezer's choice
/// (Memory.swift in PadCore): the tabs on screen, one heavy tab, a couple of
/// light ones, and under memory pressure only the tabs on screen.
@MainActor
final class Pages {
    private(set) var live: [UUID: Page] = [:]
    private final class KeptImage {
        let token: PageSnapshotFiles.Token
        let image: UIImage
        init(_ image: UIImage, token: PageSnapshotFiles.Token) {
            self.image = image
            self.token = token
        }
    }
    /// Frozen tabs' pictures, each the whole screen's: for the moment a
    /// page loads again under its picture. Each is tens of megabytes, so
    /// only the last few are held; the rest are on disk (Snapshots), read
    /// when wanted, and the system empties this when memory runs short.
    private let pictures: NSCache<NSUUID, KeptImage> = {
        let cache = NSCache<NSUUID, KeptImage>()
        cache.countLimit = 3
        return cache
    }()
    /// Small pictures of tabs taken as they left the screen, for the tab
    /// overview; the system empties it when memory runs short.
    private let previews: NSCache<NSUUID, KeptImage> = {
        let cache = NSCache<NSUUID, KeptImage>()
        cache.countLimit = 24
        return cache
    }()
    /// How wide the tab overview's pictures are, in points: a card in two
    /// columns on a large iPhone.
    static let previewWidth: CGFloat = 200
    private struct KeptState {
        let space: UUID
        let url: URL?
        let value: Any
    }
    private var states: [UUID: KeptState] = [:]
    private var addresses: [UUID: URL] = [:]
    /// Tabs being frozen right now, so they aren't frozen twice.
    private var freezing: Set<UUID> = []
    private var pressure: DispatchSourceMemoryPressure?

    /// The tab's page, made and loaded when it was frozen or never opened.
    /// `thawed` says it was, so the window can show the picture meanwhile.
    func page(for tab: TabRecord, in space: UUID) -> (page: Page, thawed: Bool) {
        if let page = live[tab.id], page.space == space { return (page, false) }
        if live[tab.id] != nil { moved(tab.id) }
        let page = Page(tab: tab.id, space: space)
        live[tab.id] = page
        addresses[tab.id] = tab.url
        let token = Snapshots.token(for: tab.id, in: space)
        // Consume disk state even when the in-memory copy is available.
        let disk = Snapshots.takeState(url: tab.url, using: token)
        let kept = states.removeValue(forKey: tab.id)
        let state: Any? = kept.flatMap { $0.space == space && $0.url == tab.url ? $0.value : nil } ?? disk
        // A tab that had a page before (a new tab has no name yet) comes
        // back as it was: no new visit in its history.
        if state != nil || !tab.title.isEmpty { page.restoring() }
        if let state {
            page.view.interactionState = state
        }
        // No state, or one WebKit couldn't use: the tab's address.
        if page.view.url == nil, let url = tab.url {
            page.load(url)
        }
        return (page, true)
    }

    /// A page WebKit made for a tab, opened by another page.
    func adopt(tab: UUID, space: UUID, configuration: WKWebViewConfiguration) -> Page {
        close(tab)
        let page = Page(tab: tab, space: space, configuration: configuration)
        live[tab] = page
        return page
    }

    /// The frozen tab's picture, to show at once while its page loads again
    /// under it: the one still held, or the one on disk. One read from disk
    /// isn't kept: it is shown once, until the page has loaded.
    func picture(for tab: UUID) -> UIImage? {
        guard let (token, url) = snapshot(for: tab) else { return nil }
        return image(in: pictures, for: token) ?? Snapshots.picture(url: url, using: token)
    }

    /// The same from disk, away from the main thread, for a card already
    /// moving under a finger (Browser.slide): a moment later, not a stall now.
    func readPicture(for tab: UUID, _ done: @escaping @MainActor @Sendable (UIImage?) -> Void) {
        guard let (token, url) = snapshot(for: tab) else { return done(nil) }
        Snapshots.picture(url: url, using: token, done)
    }

    /// The tab's page is back and its picture has gone from the screen.
    func forgetPicture(of tab: UUID) {
        pictures.removeObject(forKey: tab as NSUUID)
    }

    /// The tab as the tab overview shows it, `width` points wide: the page
    /// as it is now when it is on screen, the picture it was frozen with
    /// otherwise. Pictures on disk are read small and not kept, so a space
    /// with many tabs never holds them all at full size.
    func preview(for tab: UUID, width: CGFloat, _ done: @escaping @MainActor @Sendable (UIImage?) -> Void) {
        guard let (token, url) = snapshot(for: tab) else { return done(nil) }
        let finish: @MainActor @Sendable (UIImage?) -> Void = { image in
            done(Snapshots.isCurrent(token) ? image : nil)
        }
        let fallback = { [weak self] in
            guard let self, Snapshots.isCurrent(token) else { return finish(nil) }
            if let kept = self.image(in: self.previews, for: token) {
                finish(kept)
            } else if let held = self.image(in: self.pictures, for: token) {
                // A frozen tab's picture is the whole screen's; a card needs a
                // fraction of it, made small away from the main thread.
                let pixels = CGSize(width: width * 3, height: width * 3 * held.size.height / max(held.size.width, 1))
                held.prepareThumbnail(of: pixels) { small in
                    DispatchQueue.main.async { finish(small ?? held) }
                }
            } else {
                Snapshots.thumbnail(url: url, using: token, pixels: Int(width * 3 * 1.6), finish)
            }
        }
        guard let page = live[tab] else { return fallback() }
        page.preview(width: width) { image in
            if let image { finish(image) } else { fallback() }
        }
    }

    /// The tab as a sideways swipe on the phone bar brings it in, there at
    /// once: a live page as it last left the screen (a small picture, soft
    /// for the moment the slide lasts), a frozen one as it was frozen.
    func slidePicture(for tab: UUID) -> UIImage? {
        guard let (token, _) = snapshot(for: tab) else { return nil }
        if live[tab] != nil, let kept = image(in: previews, for: token) { return kept }
        return image(in: pictures, for: token) ?? image(in: previews, for: token)
    }

    /// A picture of the page as it leaves the screen, so the tab overview
    /// shows it as it was rather than as it was when last frozen.
    func keepPreview(of page: Page) {
        let tab = page.tab
        let token = Snapshots.token(for: tab, in: page.space)
        page.preview(width: Self.previewWidth) { [weak self] image in
            guard let self, self.live[tab] === page, Snapshots.isCurrent(token) else { return }
            if let image { self.previews.setObject(KeptImage(image, token: token), forKey: tab as NSUUID) }
        }
    }

    func isLive(_ tab: UUID) -> Bool {
        live[tab] != nil
    }

    /// Tabs whose page is not live: frozen, or never opened this run.
    var frozenCount: Int {
        Session.shared.workspace.spaces.reduce(0) { $0 + $1.tabs.count } - live.count
    }

    /// A tab closed for good: its page, its picture, everything.
    func close(_ tab: UUID) {
        live.removeValue(forKey: tab)?.tearDown()
        addresses[tab] = nil
        invalidate(tab)
    }

    private func invalidate(_ tab: UUID) {
        freezing.remove(tab)
        pictures.removeObject(forKey: tab as NSUUID)
        previews.removeObject(forKey: tab as NSUUID)
        states[tab] = nil
        Snapshots.remove(tab)
    }

    /// Freezes what the Freezer says should be frozen now.
    func enforce(pressure: Bool = false) {
        // Short of memory, the pictures go first: they are on disk as well.
        if pressure { pictures.removeAllObjects() }
        let session = Session.shared
        let shown = session.shownTabs
        var loads: [TabLoad] = []
        for space in session.workspace.spaces {
            for tab in space.tabs {
                let page = live[tab.id]
                loads.append(TabLoad(
                    id: tab.id,
                    heavy: page?.isHeavy ?? Adapters.adapter(for: tab.url).isHeavy(tab.url),
                    onScreen: shown.contains(tab.id),
                    live: page != nil,
                    lastShown: tab.shown,
                    mustStay: page?.mustStay ?? false
                ))
            }
        }
        for tab in Freezer.plan(loads, limits: session.preferences.limits, pressure: pressure) {
            freeze(tab, force: pressure)
        }
    }

    /// Asks the page whether it holds anything typed, pictures it, then
    /// lets it go, looking again before each step: each takes a moment, and
    /// the tab may have come back on screen meanwhile.
    func freeze(_ tab: UUID, force: Bool = false) {
        guard let page = live[tab], !freezing.contains(tab) else { return }
        let token = Snapshots.token(for: tab, in: page.space)
        freezing.insert(tab)
        page.holdsTyping { [weak self] typed in
            guard let self, Snapshots.isCurrent(token) else { return }
            // For want of memory, a page goes even with something typed in it.
            guard force || typed == false, !page.mustStay, !Session.shared.shownTabs.contains(tab), self.live[tab] === page else {
                self.freezing.remove(tab)
                return
            }
            page.picture { [weak self] picture in
                guard let self, Snapshots.isCurrent(token) else { return }
                // The editor may have changed while WebKit made the picture.
                page.holdsTyping { [weak self] typed in
                    guard let self, Snapshots.isCurrent(token) else { return }
                    self.freezing.remove(tab)
                    guard force || typed == false, !page.mustStay, !Session.shared.shownTabs.contains(tab),
                          self.live[tab] === page else { return }
                    if let picture {
                        // For want of memory the picture isn't kept in memory either; it is on disk.
                        if !force { self.pictures.setObject(KeptImage(picture, token: token), forKey: tab as NSUUID) }
                        // Never persist a picture of a sign-in page.
                        if !page.isSignIn { Snapshots.save(picture, url: page.view.url, using: token) }
                    }
                    self.release(page, token: token)
                }
            }
        }
    }

    /// A page off screen whose process ended: frozen as it stands, with the
    /// picture it had, if any.
    func processEnded(_ page: Page) {
        guard live[page.tab] === page else { return }
        self.release(page, token: Snapshots.token(for: page.tab, in: page.space))
    }

    /// Takes a tab's page down when the tab moves to another space, whose
    /// store is not the one the page was signed in with.
    func moved(_ tab: UUID) {
        close(tab)
    }

    /// Invalidate old pictures and pending callbacks for every committed page,
    /// including same-address reloads, and address changes made by web apps.
    func navigationChanged(_ page: Page, committed: Bool = false) {
        guard live[page.tab] === page else { return }
        guard committed || addresses[page.tab] != page.view.url else { return }
        addresses[page.tab] = page.view.url
        invalidate(page.tab)
    }

    private func image(in cache: NSCache<NSUUID, KeptImage>, for token: PageSnapshotFiles.Token) -> UIImage? {
        guard let kept = cache.object(forKey: token.tab as NSUUID), kept.token == token else { return nil }
        return kept.image
    }

    private func snapshot(for tab: UUID) -> (PageSnapshotFiles.Token, URL?)? {
        let workspace = Session.shared.workspace
        guard let space = workspace.spaceID(of: tab), let record = workspace.tab(tab) else { return nil }
        return (Snapshots.token(for: tab, in: space), record.url)
    }

    private func release(_ page: Page, token: PageSnapshotFiles.Token) {
        guard live[page.tab] === page, Snapshots.isCurrent(token) else { return }
        if let state = page.view.interactionState {
            states[page.tab] = KeptState(space: page.space, url: page.view.url, value: state)
            if !page.isSignIn { Snapshots.save(state: state, url: page.view.url, using: token) }
        }
        live[page.tab] = nil
        page.tearDown()
    }

    /// Memory pressure, from the system: every tab that can freeze, does.
    func watchMemory() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.enforce(pressure: true) }
        }
        source.resume()
        pressure = source
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforce(pressure: true) }
        }
    }
}
