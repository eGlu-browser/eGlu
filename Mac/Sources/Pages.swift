import AppKit
import PadCore
import WebKit

/// Every tab's page: live, or let go until it is opened again.
///
/// A live page keeps its WebKit content process. One let go keeps only what
/// WebKit needs to load it back where it was (its back and forward list and
/// where it was scrolled to), in memory and in Caches (Snapshots); opening
/// the tab loads it again from there. A Mac has room for more live pages
/// than an iPad, so the Freezer (Memory.swift in PadCore) is given more.
@MainActor
final class Pages {
    private(set) var live: [UUID: Page] = [:]
    private var states: [UUID: Any] = [:]
    private var pressure: DispatchSourceMemoryPressure?

    /// What stays live off screen on a Mac: a few heavy web apps, and the
    /// light pages last looked at.
    static let limits = LiveLimits(heavy: 3, lightOffScreen: 12)

    /// The tab's page, made and loaded when it was let go or never opened.
    func page(for tab: TabRecord, in space: UUID) -> Page {
        if let page = live[tab.id] { return page }
        let page = Page(tab: tab.id, space: space)
        live[tab.id] = page
        let state: Any? = states.removeValue(forKey: tab.id) ?? Snapshots.state(for: tab.id)
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
        return page
    }

    /// A page WebKit made for a tab, opened by another page.
    func adopt(tab: UUID, space: UUID, configuration: WKWebViewConfiguration) -> Page {
        live[tab]?.tearDown()
        let page = Page(tab: tab, space: space, configuration: configuration)
        live[tab] = page
        return page
    }

    func isLive(_ tab: UUID) -> Bool {
        live[tab] != nil
    }

    /// A tab closed for good: its page and everything kept for it.
    func close(_ tab: UUID) {
        live.removeValue(forKey: tab)?.tearDown()
        states[tab] = nil
        Snapshots.remove(tab)
    }

    /// Takes a tab's page down when the tab moves to another space, whose
    /// store is not the one the page was signed in with.
    func moved(_ tab: UUID) {
        live.removeValue(forKey: tab)?.tearDown()
        states[tab] = nil
    }

    /// A pinned tab put back: its page goes, and it loads at its pinned address when next opened.
    func unload(_ tab: UUID) {
        live.removeValue(forKey: tab)?.tearDown()
        states[tab] = nil
        Snapshots.remove(tab)
    }

    /// Lets go of what the Freezer says should go now.
    func enforce(pressure: Bool = false) {
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
        for tab in Freezer.plan(loads, limits: Self.limits, pressure: pressure) {
            guard let page = live[tab] else { continue }
            release(page)
        }
    }

    private func release(_ page: Page) {
        if let state = page.view.interactionState {
            states[page.tab] = state
            // Never a sign-in page's on disk: it can hold an email address.
            if !page.isSignIn { Snapshots.save(state: state, for: page.tab) }
        }
        live[page.tab] = nil
        page.tearDown()
    }

    /// Memory pressure, from the system: every tab off screen that can go, goes.
    func watchMemory() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.enforce(pressure: true) }
        }
        source.resume()
        pressure = source
    }
}
