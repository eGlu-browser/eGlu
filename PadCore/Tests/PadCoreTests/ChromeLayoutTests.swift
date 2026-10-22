import Testing
@testable import PadCore

/// Which of a window's bars show (Browser.refreshChrome).
struct ChromeLayoutTests {
    private func layout(compact: Bool = false, strip: Bool = false, placement: Preferences.TabsPlacement? = nil,
                        tabBar: Bool = true, bookmarksBar: Bool = false, required: Bool = false,
                        typing: Bool = false) -> ChromeLayout {
        ChromeLayout(compact: compact, strip: strip, placement: placement, tabBar: tabBar,
                     bookmarksBar: bookmarksBar, addressRequired: required, typing: typing)
    }

    @Test func `a phone has the bar at the bottom and nothing else`() {
        let phone = layout(compact: true, placement: .sidebar, bookmarksBar: true, required: true)
        #expect(phone.phoneBar == .twoRows)
        #expect(!phone.sidebar && !phone.topBar && !phone.addressBar && !phone.bookmarksBar)
    }

    @Test func `beside the strip the bar is one row, and typing it is the address alone`() {
        #expect(layout(compact: true, strip: true).phoneBar == .oneRow)
        #expect(layout(compact: true, strip: true, typing: true).phoneBar == .typing)
        #expect(layout(compact: true, typing: true).phoneBar == .typing)
    }

    @Test func `tabs along the top, with the bookmarks bar where Settings shows it`() {
        let wide = layout(bookmarksBar: true)
        #expect(wide.phoneBar == nil)
        #expect(wide.topBar && wide.bookmarksBar && !wide.sidebar && !wide.addressBar)
    }

    @Test func `the tab bar turned off still shows where an address must`() {
        #expect(!layout(tabBar: false).topBar)
        #expect(layout(tabBar: false, required: true).topBar)
    }

    @Test func `a sidebar has the address and bookmarks itself, and put away leaves the address bar`() {
        let shown = layout(placement: .sidebar, bookmarksBar: true, required: true)
        #expect(shown.sidebar && !shown.topBar && !shown.addressBar && !shown.bookmarksBar)
        let away = layout(placement: .sidebar, tabBar: false)
        #expect(!away.sidebar && away.addressBar && !away.topBar)
    }
}
