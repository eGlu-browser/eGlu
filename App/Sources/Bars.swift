import PadCore
import SwiftUI
import UIKit

/// Everything a bar, the start page or the empty space can ask
/// a window to do.
enum BarAction {
    case select(UUID)
    case close(UUID)
    /// Several at once: Close Other Tabs, Close All Tabs.
    case closeTabs([UUID])
    case arrangeTabs(Workspace.Arrangement)
    case command(Command)
    case switchSpace(UUID)
    case spaceInNewWindow(UUID)
    case spaceSettings(UUID)
    case removeSpace(UUID)
    case moveTab(UUID, UUID)
    /// A tab dragged before another in the sidebar (SideTabs).
    case placeTab(UUID, before: UUID)
    case tabInNewWindow(UUID)
    case pin(UUID)
    case unpin(UUID)
    case backToPinned(UUID)
    case editAddress
    case cancelAddress
    case go(String)
    /// A row the address bar offered (Suggestions).
    case suggestion(Suggestion)
    case open(URL)
    case openInNewTab(URL)
    case back
    case forward
    case reload
    case stop
    case toggleBookmark
    case removeBookmark(UUID)
    /// A folder, named, inside another (nil: at the top level).
    case newFolder(String, in: UUID?)
    case renameBookmark(UUID, String)
    /// Into a folder, or nil for the top level.
    case moveBookmark(UUID, into: UUID?)
    case importBookmarks
    case dismissBanner
    /// A tab beside the one on screen; a new one; apart again; sides swapped.
    case splitWith(UUID)
    case splitWithNewTab
    case separate(UUID)
    case swapSides(UUID)
    /// The space's tabs as a grid, from the phone bar.
    case showTabs
    /// The iPhone's desktop view, in or out (DesktopPad).
    case desktopView
}

/// The row along the top, as the Mac's (TopTabs), as Safari's compact
/// layout: back, forward and reload, the pinned tabs as tiles and the other
/// tabs sharing the row, the one on screen the address; a tap on it types a
/// new one.
///
/// Only the tab on screen is in Liquid Glass; every other tab is flat, so
/// the eye finds it at once.
struct TopBar: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        TopTabs(session: session, window: window, act: act)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { LoadingLine(window: window) }
            .ignoresSafeArea(.keyboard)
    }
}

// MARK: Bookmarks

/// The space's bookmarks in a bar under the others, for tabs along the top
/// when the button beside New Tab turns it on (Preferences.bookmarksBar), as
/// the Mac's: each its icon and name; a folder, a menu of what it holds.
struct BookmarksStrip: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    static let height: CGFloat = 40

    var body: some View {
        let bookmarks = session.workspace.space(window.spaceID)?.bookmarks ?? []
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                if bookmarks.isEmpty {
                    Text("No bookmarks in this space yet. Star a page to keep it here.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 10)
                }
                ForEach(bookmarks) { item in
                    StripBookmark(item: item, act: act)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        }
        .scrollIndicators(.never)
        .feathered(.horizontal)
        .ignoresSafeArea(.keyboard)
    }
}

/// A bookmark in the bar: its icon and its name, as narrow as they let it be.
private struct StripBookmark: View {
    let item: Bookmark
    let act: (BarAction) -> Void

    var body: some View {
        if item.isFolder {
            Menu {
                StripFolder(items: item.children ?? [], act: act)
            } label: {
                label
            }
            .hoverEffect(.highlight)
        } else if let url = item.url {
            Button {
                HistoryRecorder.shared.expect(.bookmark, url)
                act(.open(url))
            } label: { label }
                .buttonStyle(PressScale())
                .hoverEffect(.highlight)
                .contextMenu {
                    Button("Open in New Tab", systemImage: "plus.square.on.square") { act(.openInNewTab(url)) }
                    Button("Copy Address", systemImage: "doc.on.doc") { UIPasteboard.general.url = Tracking.clean(url) }
                }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if item.isFolder {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            } else {
                SiteIconView(url: item.url, size: 16)
            }
            Text(item.label)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .frame(maxWidth: 170, alignment: .leading)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .contentShape(Capsule())
        .contentShape(.hoverEffect, Capsule())
    }
}

/// What a folder in the bar holds, as a menu: its bookmarks, its folders as menus of their own.
private struct StripFolder: View {
    let items: [Bookmark]
    let act: (BarAction) -> Void

    var body: some View {
        if items.isEmpty {
            Text("Empty")
        }
        ForEach(items) { item in
            if item.isFolder {
                Menu(item.label, systemImage: "folder") { StripFolder(items: item.children ?? [], act: act) }
            } else if let url = item.url {
                Button(item.label) { act(.open(url)) }
            }
        }
    }
}

// MARK: The space

/// The space's own button, filled with its colour, so a window says which
/// space it is in at a glance; its menu goes to the others.
struct SpaceButton: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        let color = space?.color ?? .blue
        Menu {
            Section {
                ForEach(session.workspace.spaces) { other in
                    Button {
                        act(.switchSpace(other.id))
                    } label: {
                        if other.id == window.spaceID {
                            Label(other.name, systemImage: "checkmark")
                        } else {
                            Label(other.name, systemImage: other.symbol)
                        }
                    }
                }
            }
            Section {
                Button("New Space…", systemImage: "plus") { act(.command(.newSpace)) }
                Button("Space Settings…", systemImage: "slider.horizontal.3") { act(.spaceSettings(window.spaceID)) }
                // An iPhone has one window: nowhere to open another.
                if UIApplication.shared.supportsMultipleScenes {
                    Button("Open in New Window", systemImage: "macwindow.badge.plus") { act(.spaceInNewWindow(window.spaceID)) }
                }
                if session.workspace.spaces.count > 1 {
                    Button("Remove Space…", systemImage: "trash", role: .destructive) { act(.removeSpace(window.spaceID)) }
                }
            }
        } label: {
            // On the phone bar, among icons for a thumb: a little larger, and
            // a long name gives way before the icons do.
            let thumb = scale == .thumb
            HStack(spacing: thumb ? 6 : 5) {
                Image(systemName: space?.symbol ?? "square.grid.2x2")
                    .font(.system(size: thumb ? 14 : 12, weight: .semibold))
                let name = Text(space?.name ?? "")
                    .font(.system(size: thumb ? 15 : 13, weight: .semibold))
                    .lineLimit(1)
                if thumb { name.frame(maxWidth: 100) } else { name }
                Image(systemName: "chevron.down")
                    .font(.system(size: thumb ? 9 : 8, weight: .bold))
                    .opacity(0.75)
                    // The chevron's weight sits low; up a point, it lines up with the text.
                    .offset(y: 0.5)
            }
            .foregroundStyle(color.ink)
            .padding(.horizontal, thumb ? 14 : 12)
            .frame(height: thumb ? 36 : Metrics.control)
            .liquidGlass(tint: color.color, in: Capsule(), otherwise: color.color)
            .frame(height: thumb ? 44 : Metrics.target)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, Capsule().inset(by: Metrics.ring))
            .animation(.bar, value: color)
        }
        .accessibilityLabel("Space: \(space?.name ?? "")")
    }
}

// MARK: Tabs

/// Where things sit in a tab and in the address field, so that what the tab
/// says and the address being typed start at the same place, and one fades
/// into the other without moving: a 28-point slot for the icon or the close
/// button, 2 points in, and the words 4 points after it.
enum TabFace {
    static let lead: CGFloat = 2
    static let slot: CGFloat = 28
    static let gap: CGFloat = 4
}

/// The page's own commands on the phone's page menu (…). The three that
/// act on the page as it is, finding in it, sharing it and handing it off,
/// sit side by side in one row, as the system sets cut, copy and paste: a
/// control group in a menu is that row. They come first, which in this menu
/// is nearest the button and so at its foot, under the thumb. Copy Link is
/// next to them, and copies the address as Share sends it, without the tags
/// that follow whoever opens it (Tracking.clean).
struct PageItems: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        if window.url != nil {
            ControlGroup {
                Button("Find", systemImage: "text.magnifyingglass") { act(.command(.find)) }
                Button("Share", systemImage: "square.and.arrow.up") { act(.command(.share)) }
                if window.canHandoff {
                    Button("Handoff", systemImage: Command.handoff.symbol) { act(.command(.handoff)) }
                }
            }
            Button("Copy Link", systemImage: "doc.on.doc") {
                if let url = window.url { UIPasteboard.general.url = Tracking.clean(url) }
            }
            Button(window.bookmarked ? "Remove Bookmark" : "Bookmark This Page",
                   systemImage: window.bookmarked ? "star.slash" : "star") { act(.toggleBookmark) }
        }
        if let blocking = window.blocking {
            Button(blocking ? "Allow Ads on This Site" : "Block Ads on This Site",
                   systemImage: blocking ? "shield.slash" : "shield") { act(.command(.contentBlocking)) }
        }
    }
}

/// The way to everything else, at the end of the tab on screen's menu, as
/// at the end of the phone's page menu.
struct AppItems: View {
    let act: (BarAction) -> Void

    var body: some View {
        Button(Command.everything.title, systemImage: "command") { act(.command(.everything)) }
        Button("History", systemImage: Command.history.symbol) { act(.command(.history)) }
        Button("Settings", systemImage: "gearshape") { act(.command(.settings)) }
    }
}

// MARK: The address

/// The address as it reads when nobody is typing; a tap types a new one.
private struct AddressSummary: View {
    @ObservedObject var window: WindowModel
    /// What the page is called rather than where it is, as Settings › The
    /// tab you are on shows has it; never on a sign-in page (showsAddress).
    var titled = false
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            // A page's title carries no warning, as the iPad's tab doesn't:
            // the address does, and every sign-in page shows its address.
            SecurityIcon(window: window, warns: !(titled && !window.title.isEmpty))
                .frame(width: TabFace.slot, height: scale.control)
                .padding(.leading, scale.lead)
            Group {
                if let words = window.searchWords {
                    // A search with the chosen engine says what was searched for, as Safari does.
                    Text(words)
                        .foregroundStyle(Palette.ink)
                } else if titled, window.url != nil, !window.title.isEmpty {
                    Text(window.title)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.ink)
                } else {
                    AddressLine(url: window.url)
                }
            }
            .font(.system(size: scale.text))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, TabFace.gap)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { act(.editAddress) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.url.map { "Address, \(Destination.pretty($0))" } ?? "Address")
        .accessibilityHint("Type a new address or a search")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { act(.editAddress) }
    }
}

/// A tab's address as AddressCapsule shows the one on screen, for a tab that
/// isn't: its site's icon and its name or its address, in the same capsule
/// (PhoneBar's sideways drag).
struct NeighbourAddress: View {
    let tab: TabRecord
    let titled: Bool
    @Environment(\.barScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if tab.url != nil {
                    SiteIconView(url: tab.url, size: scale.icon)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: scale.icon * 0.75, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: scale.icon, height: scale.icon)
                }
            }
            .frame(width: TabFace.slot, height: scale.control)
            .padding(.leading, scale.lead)
            Group {
                if titled, tab.url != nil, !tab.title.isEmpty {
                    Text(tab.title)
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.ink)
                } else {
                    AddressLine(url: tab.url)
                }
            }
            .font(.system(size: scale.text))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, TabFace.gap)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: scale.control)
        .liquidGlass(reacting: false, in: Capsule(), otherwise: Palette.wash)
        .frame(height: scale.target)
    }
}

/// The site's icon, or a warning when the page or something on it came
/// over a connection anyone on the way can read.
private struct SecurityIcon: View {
    @ObservedObject var window: WindowModel
    var warns = true
    @Environment(\.barScale) private var scale

    var body: some View {
        if warns && window.insecure {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: scale.icon * 0.75))
                .foregroundStyle(Palette.unsafe)
                .frame(width: scale.icon, height: scale.icon)
                .accessibilityLabel("Not secure")
        } else if window.url != nil, window.searchWords == nil {
            SiteIconView(url: window.url, size: scale.icon)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: scale.icon * 0.75, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: scale.icon, height: scale.icon)
        }
    }
}

/// "accounts." muted, "google.com" in bold, "/v3/signin" muted: the part of
/// the host that says who you are talking to stands out.
struct AddressLine: View {
    let url: URL?
    /// The host alone, as a tab says where it is.
    var hostOnly = false

    var body: some View {
        text
    }

    private var text: Text {
        guard let url, let host = url.host() else {
            return Text(AddressEditor.placeholder).foregroundStyle(Palette.muted)
        }
        let bare = host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let full = Destination.pretty(url)
        let pretty = hostOnly && full.hasPrefix(bare) ? bare : full
        let name = Destination.registrable(bare)
        guard pretty.hasPrefix(bare), bare.hasSuffix(name) else {
            return Text(pretty).foregroundStyle(Palette.ink)
        }
        let sub = String(bare.dropLast(name.count))
        let rest = String(pretty.dropFirst(bare.count))
        return Text(sub).foregroundStyle(Palette.muted)
            + Text(name).foregroundStyle(Palette.ink).fontWeight(.semibold)
            + Text(rest).foregroundStyle(Palette.muted)
    }
}

private struct SignInBadge: View {
    var body: some View {
        Image(systemName: "key.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.muted)
            .frame(width: 24, height: 22)
            .background(Palette.wash, in: Capsule())
            .help("Sign-in page")
            .accessibilityLabel("Sign-in page")
            .transition(.opacity)
    }
}

/// The star: this page among the space's bookmarks, or not; a tap adds or
/// takes it away.
private struct BookmarkStar: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

    var body: some View {
        Button {
            act(.toggleBookmark)
        } label: {
            ZStack {
                if window.bookmarked {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Palette.ink)
                        .iconSwap()
                } else {
                    Image(systemName: "star")
                        .foregroundStyle(Palette.muted)
                        .iconSwap()
                }
            }
            .font(.system(size: scale.text, weight: .medium))
            // A star's centre of weight sits below its middle.
            .offset(y: -0.5)
            .frame(width: scale.button, height: scale.control)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous).inset(by: 3))
            .animation(.bar, value: window.bookmarked)
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel(window.bookmarked ? "Remove Bookmark" : "Bookmark This Page")
    }
}

private struct ReloadButton: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

    var body: some View {
        Button {
            act(window.loading ? .stop : .reload)
        } label: {
            ZStack {
                if window.loading {
                    Image(systemName: "xmark").iconSwap()
                } else {
                    Image(systemName: "arrow.clockwise").iconSwap()
                }
            }
            .font(.system(size: scale.text - 1, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: scale.button, height: scale.control)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous).inset(by: 3))
            .animation(.bar, value: window.loading)
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel(window.loading ? "Stop" : "Reload")
    }
}

/// The address being typed, in a phone's bar (an iPad's is typed in the
/// command bar, CommandBar). It opens with the address selected, so typing
/// replaces it, as Safari's does; Return goes, Cancel or a touch on the page
/// leaves it as it was. Its icon and its words sit where a tab's do
/// (TabFace), so the address's words fade into the field in place. It has
/// no glass of its own: it is drawn on the capsule's.
struct AddressEditor: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void
    @State private var text = ""
    @State private var focused = false
    @Environment(\.barScale) private var scale

    /// What an empty field says it takes: commands and settings too, now
    /// that it is the one place they are found.
    static let placeholder = "Address, search or command"

    var body: some View {
        HStack(spacing: 0) {
            SecurityIcon(window: window)
                .frame(width: TabFace.slot, height: scale.control)
                .padding(.leading, scale.lead)
            TypingField(text: $text, placeholder: Self.placeholder, fontSize: scale.text, focused: $focused,
                        selectsAll: true) { typed in act(.go(typed)) }
                .padding(.leading, TabFace.gap)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: scale.text + 1))
                        .foregroundStyle(Palette.faint)
                        .frame(width: scale.button, height: scale.control)
                        .contentShape(Rectangle())
                        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous).inset(by: 3))
                }
                .buttonStyle(PressScale())
                .hoverEffect(.highlight)
                .accessibilityLabel("Clear")
                .iconSwap()
            }
        }
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.bar, value: text.isEmpty)
        // Drawn before it is typed in, in the compact layout, so it starts
        // when typing does as well as when it appears.
        .onAppear { if window.editingAddress { begin() } }
        // Each turn at the field starts it over, one asked for while it is
        // already typed in included (WindowModel.addressTurn).
        .onChange(of: window.addressTurn) { _, _ in if window.editingAddress { begin() } }
        .onChange(of: text) { _, now in window.suggestions.typed(now, in: window) }
        .onChange(of: focused) { _, now in
            if !now && window.editingAddress { act(.cancelAddress) }
        }
    }

    /// The tab's address, all of it selected (TypingField.selectsAll), with
    /// the keys; or nothing, when everything is listed under the field.
    private func begin() {
        window.suggestions.begin(in: window)
        text = window.listsEverything ? "" : window.url.map { Destination.editable($0, engine: Session.shared.preferences.engine) } ?? ""
        focused = true
    }
}

/// Back and forward, in one piece of glass, as Safari has them.
struct HistoryButtons: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", "Back", enabled: window.canGoBack) { act(.back) }
            button("chevron.right", "Forward", enabled: window.canGoForward) { act(.forward) }
        }
        .background {
            Color.clear
                .liquidGlass(reacting: false, in: Capsule(), otherwise: .clear)
                .frame(height: Metrics.control)
        }
        .padding(.trailing, 4)
    }

    private func button(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Palette.ink : Palette.faint)
                // A chevron's point sits off its box; nudged toward the way it points.
                .offset(x: symbol == "chevron.left" ? -0.5 : 0.5)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// A round glass button on a bar: 32 points drawn, 40 that answer.
struct BarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: Metrics.control, height: Metrics.control)
                .liquidGlass(in: Circle(), otherwise: .clear)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
                // The pointer's highlight takes the circle's shape, not the box's.
                .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// A hairline at the bottom of a bar that fills while the page loads.
struct LoadingLine: View {
    @ObservedObject var window: WindowModel
    @ObservedObject private var load: LoadProgress

    init(window: WindowModel) {
        self.window = window
        load = window.load
    }

    var body: some View {
        GeometryReader { box in
            Rectangle()
                .fill(Palette.faint)
                .frame(width: window.loading ? box.size.width * max(0.08, load.fraction) : 0, height: 2)
                .animation(.easeOut(duration: 0.2), value: load.fraction)
        }
        .frame(height: 2)
        .opacity(window.loading ? 1 : 0)
    }
}

/// The address bar while the sidebar is put away: the way back to it, back,
/// forward and reload, and the address.
struct AddressBar: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        HStack(spacing: 4) {
            // The sidebar put away: the way back to it.
            if session.preferences.tabsPlacement == .sidebar {
                BarButton(symbol: "sidebar.left", label: "Show Sidebar") { act(.command(.tabBar)) }
            }
            HistoryButtons(window: window, act: act)
            // Never typed in here: a click on it opens the command bar,
            // holding the address.
            AddressCapsule(window: window, editable: false, act: act)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.bar, value: window.editingAddress)
        .ignoresSafeArea(.keyboard)
    }
}

/// The address in one piece of glass: where the page is, its key badge on a
/// sign-in page, the star and reload; a tap types a new address, and the
/// address and the address being typed fade into each other on it, in place.
/// The address bar's, while the sidebar is put away, and the phone bar's.
struct AddressCapsule: View {
    @ObservedObject var window: WindowModel
    /// This capsule is the one typed in; otherwise another field is.
    let editable: Bool
    let act: (BarAction) -> Void
    @Environment(\.barScale) private var scale

    var body: some View {
        ZStack {
            if window.editingAddress && editable {
                AddressEditor(window: window, act: act)
                    .id(window.tabID)
                    .transition(.opacity)
            } else {
                HStack(spacing: 2) {
                    // On a phone, the bar's address follows the setting the iPad's tab does.
                    AddressSummary(window: window, titled: window.phone && !window.showsAddress, act: act)
                    if window.signIn { SignInBadge() }
                    if window.url != nil { BookmarkStar(window: window, act: act) }
                    ReloadButton(window: window, act: act)
                }
                .padding(.trailing, 2)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: scale.control)
        .liquidGlass(reacting: false, in: Capsule(), otherwise: Palette.wash)
        .frame(height: scale.target)
        .animation(.bar, value: window.editingAddress)
    }
}

/// A line under the address bar: Google refusing to sign in, a page that
/// ran out of memory again and again, a page that didn't load.
struct BannerBar: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        if let banner = window.banner {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: banner == .googleRefused ? "person.badge.key" : "exclamationmark.triangle")
                    .foregroundStyle(Palette.unsafe)
                Text(message(banner))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                switch banner {
                case .googleRefused:
                    Button("Go Back") { act(.back) }
                case .exhausted, .failed:
                    Button("Reload") { act(.reload) }
                }
                Button {
                    act(.dismissBanner)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .accessibilityLabel("Dismiss")
            }
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.wash)
        }
    }

    private func message(_ banner: Banner) -> String {
        switch banner {
        case .googleRefused:
            return SignIn.fallback
        case .exhausted:
            return "This page stopped because it ran out of memory, more than once. Close a heavy tab, then reload."
        case .failed(let reason):
            return reason
        }
    }
}

/// A space with no tab in this window.
struct EmptySpace: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        VStack(spacing: 14) {
            Image(systemName: space?.symbol ?? "square.grid.2x2")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(space?.color.color ?? Palette.faint)
            Text(space.map { "Nothing open in \($0.name)" } ?? "Nothing open")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.muted)
            HStack(spacing: 10) {
                Button("New Tab  \(Shortcuts.chord(for: .newTab)?.label ?? "")") { act(.command(.newTab)) }
                Button("\(Command.everything.title)  \(Shortcuts.chord(for: .everything)?.label ?? "")") {
                    act(.command(.everything))
                }
            }
            .buttonStyle(.bordered)
            .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
