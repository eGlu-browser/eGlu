import AppKit
import PadCore
import SwiftUI

/// The tabs along the top, for whoever chose them there over the sidebar
/// (Settings › General › Tabs): one row on the window's ground, level with
/// the window's own buttons, as the iPad's row is (TopTabs). Back, forward,
/// reload and the bookmarks bar's button; the space's pinned tabs as small tiles; its other tabs,
/// sharing what room there is (TabWidths), the one on screen raised in
/// glass, wider, and the address, as Safari's compact tabs are: where the
/// page is, a click on it opening the command bar on its address, and its …
/// and ✕ under the pointer. Then New Tab, the spaces and Space Settings, each plain button 2 points from the
/// next and the spaces' glass a gap from both.
struct TopTabBar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var session = Session.shared

    /// What a tab's glass draws past its shape.
    private static let rim: CGFloat = 3

    var body: some View {
        let space = session.workspace.space(model.spaceID)
        let pinned = space?.tabs.filter { $0.isPinned && session.preferences.shows($0) } ?? []
        let others = space?.tabs.filter { !$0.isPinned } ?? []
        HStack(spacing: Metrics.gap) {
            WindowButtons()
                .frame(width: WindowButtons.width, height: WindowButtons.side)
                .padding(.leading, (Metrics.control - WindowButtons.side) / 2)
            HStack(spacing: 2) {
                PlainIcon("chevron.left", help: "Back (⌘[)", enabled: model.canGoBack) { model.back() }
                PlainIcon("chevron.right", help: "Forward (⌘])", enabled: model.canGoForward) { model.forward() }
                if model.loading {
                    PlainIcon("xmark", help: "Stop (⌘.)") { model.stop() }
                } else {
                    PlainIcon("arrow.clockwise", help: "Reload (⌘R)", enabled: model.tabID != nil) { model.reload() }
                }
                let barShown = session.preferences.bookmarksBar
                PlainIcon(barShown ? "star.square.on.square.fill" : "star.square.on.square",
                          help: barShown ? "Hide Bookmarks Bar (⇧⌘B)" : "Show Bookmarks Bar (⇧⌘B)") {
                    withAnimation(.bar) { session.preferences.bookmarksBar.toggle() }
                }
            }
            // The pinned tabs stay put while the others scroll beside them.
            if !pinned.isEmpty {
                HStack(spacing: 4) {
                    ForEach(pinned) { tab in
                        TopPinnedTab(model: model, tab: tab)
                    }
                }
                .animation(.bar, value: pinned.map(\.id))
                if !others.isEmpty {
                    Rectangle()
                        .fill(Palette.faint)
                        .frame(width: 1, height: 16)
                }
            }
            GeometryReader { box in
                let widths = TabWidths.widths(count: others.count, room: box.size.width, gap: 4,
                                              address: others.contains { $0.id == model.tabID })
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(space.map(TabList.items(of:)) ?? [], id: \.first?.id) { item in
                                // A split's two side by side on a ground of their own, as one place in the row.
                                HStack(spacing: 0) {
                                    ForEach(item) { tab in
                                        TopTab(model: model, tab: tab, width: tab.id == model.tabID ? widths.current : widths.each)
                                            .id(tab.id)
                                    }
                                }
                                .background {
                                    if item.count == 2 {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.wash)
                                    }
                                }
                            }
                        }
                        // Room for the glass's rim inside the scroll view, all round.
                        .padding(Self.rim)
                        .animation(.bar, value: others.map(\.id))
                    }
                    .scrollIndicators(.never)
                    .padding(-Self.rim)
                    .feathered(.horizontal)
                    // The tab on screen is always in view, however it came to be on screen.
                    .onAppear {
                        DispatchQueue.main.async { model.tabID.map { reader.scrollTo($0, anchor: .center) } }
                    }
                    .onChange(of: model.tabID) { _, tab in
                        withAnimation(.bar) { tab.map { reader.scrollTo($0) } }
                    }
                }
            }
            .frame(height: Metrics.control)
            HStack(spacing: 2) {
                PlainIcon("plus", help: "New Tab (⌘T)") { model.commandBar = .newTab }
                SpaceBar(model: model, inRow: true)
                    .fixedSize()
                // Extensions (ExtensionBar.swift): the puzzle button and its list.
                ExtensionsButton(model: model)
            }
        }
        // The row's ground moves the window, as a title bar does; what is on it are only buttons.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

/// The space's bookmarks in a row under the tabs, for whoever keeps the
/// tabs along the top and turned it on (Preferences.bookmarksBar): each its
/// icon and name; a folder, a menu of what it holds. A click opens one
/// here, a ⌘-click in a new tab.
struct BookmarksBar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var session = Session.shared

    var body: some View {
        let bookmarks = session.workspace.space(model.spaceID)?.bookmarks ?? []
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                if bookmarks.isEmpty {
                    Text("No bookmarks in this space yet. Bookmark a page with ⇧⌘D.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                }
                ForEach(bookmarks) { item in
                    BarBookmark(model: model, item: item)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .scrollIndicators(.never)
        .feathered(.horizontal)
    }
}

/// A bookmark in the bar: its icon and name, as narrow as they let it be.
private struct BarBookmark: View {
    @ObservedObject var model: WindowModel
    let item: Bookmark

    var body: some View {
        if item.isFolder {
            Menu {
                FolderMenu(model: model, items: item.children ?? [])
            } label: {
                label
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(RowButtonStyle(corner: 8))
            .fixedSize()
            .help(item.label)
        } else if let url = item.url {
            Button { model.open(bookmark: url) } label: { label }
                .buttonStyle(RowButtonStyle(corner: 8))
                .fixedSize()
                .help(Destination.pretty(url))
                .contextMenu {
                    Button("Open in New Tab") { model.open(url, newTab: true) }
                    Button("Copy Address") { WindowModel.copy(url) }
                }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            if item.isFolder {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                SiteIconView(url: item.url, size: 14)
            }
            Text(item.label)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 160, alignment: .leading)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
    }
}

/// What a folder in the bar holds, as a menu: its bookmarks, its folders as menus of their own.
private struct FolderMenu: View {
    @ObservedObject var model: WindowModel
    let items: [Bookmark]

    var body: some View {
        if items.isEmpty {
            Text("Empty")
        }
        ForEach(items) { item in
            if item.isFolder {
                Menu(item.label) { FolderMenu(model: model, items: item.children ?? []) }
            } else if let url = item.url {
                Button(item.label) { model.open(bookmark: url) }
            }
        }
    }
}

/// A tab in the row: its site's icon and its name, a close button while the
/// pointer is on it. The one on screen is raised in glass and is the
/// address: where it is, a click on it opening the command bar there (⌘L),
/// and under the pointer the page's … beside the ✕.
private struct TopTab: View {
    @ObservedObject var model: WindowModel
    let tab: TabRecord
    let width: CGFloat
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let selected = model.tabID == tab.id
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 7) {
            ZStack {
                if selected, model.loading, model.page != nil {
                    ProgressView().controlSize(.mini)
                } else {
                    SiteIconView(url: tab.url, size: 16)
                }
            }
            .frame(width: 16, height: 16)
            if selected {
                Group {
                    if let url = model.url {
                        addressText(url, engine: Session.shared.preferences.engine, quiet: .secondary)
                            .foregroundStyle(Color.primary)
                    } else {
                        Text("Search or enter address")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12.5))
                .lineLimit(1)
                // The end of the host is who you are talking to: it is the part kept.
                .truncationMode(.head)
            } else {
                Text(tab.label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            // Kept while its popover is open, which it stands under, and for Share… from the menu bar.
            if selected, hovering || model.pageActionsShown {
                PageActionsButton(model: model, inTab: true)
                    .transition(.opacity)
            }
            if hovering {
                CloseButton { model.closeTab(tab.id) }
                    .transition(.opacity)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(width: width, height: Metrics.control)
        .background {
            if selected {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else {
                Highlight(hovering: hovering, shape: shape)
            }
        }
        .overlay(alignment: .leading) {
            Capsule().fill(Color.accentColor).frame(width: 2, height: 18).offset(x: -3).opacity(targeted ? 1 : 0)
        }
        .contentShape(shape)
        .onHover { inside in withAnimation(.hover) { hovering = inside } }
        .onTapGesture {
            if selected { model.commandBar = .here } else { model.select(tab.id) }
        }
        .draggable(TabDrag(tab: tab.id)) {
            HStack(spacing: 6) {
                SiteIconView(url: tab.url, size: 16)
                Text(tab.label).font(.system(size: 12.5)).lineLimit(1)
            }
            .padding(8)
            .frame(width: 200, alignment: .leading)
        }
        .dropDestination(for: TabDrag.self) { items, _ in
            guard let item = items.first, item.tab != tab.id else { return false }
            model.place(item.tab, pinned: false, before: tab.id)
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu { TabMenu(model: model, tab: tab) }
        .help(selected ? "\(tab.url?.absoluteString ?? tab.label): click to type an address (⌘L)" : tab.url?.absoluteString ?? tab.label)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

}

/// A pinned tab in the row: its icon, shading under the pointer. The one on
/// screen is on a small tile of glass and takes on its icon, as the
/// sidebar's tile does (PinnedTile): its glass tinted with the icon's
/// ground, the icon's mark alone on a soft plate of that ground.
private struct TopPinnedTab: View {
    @ObservedObject var model: WindowModel
    let tab: TabRecord
    @ObservedObject private var icons = SiteIcons.shared
    @Environment(\.controlActiveState) private var activeState
    @State private var hovering = false
    @State private var targeted = false
    /// Where the pointer is over the tile, and the tile's size, as the sidebar's tile has them.
    @State private var pointer: CGPoint?
    @State private var size = CGSize.zero

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let selected = model.tabID == tab.id
        let url = tab.url ?? tab.pinned
        let colour = model.space?.color ?? .blue
        let ground = selected ? PinnedIcon.ground(for: url, colour: colour) : nil
        Button {
            // On screen, it stands for the address, as the tab on screen does.
            if selected { model.commandBar = .here } else { model.select(tab.id) }
        } label: {
            ZStack {
                PointerGlow(pointer: pointer, radius: 20)
                PinnedIcon(url: url, open: selected && activeState != .inactive, colour: colour, size: 16,
                           lean: Plate.lean(toward: pointer, in: size, reach: CGSize(width: 6, height: 4)),
                           plate: (side: 18, corner: 6, blur: 4))
            }
            .frame(width: Metrics.control + 4, height: Metrics.control)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .background(Highlight(hovering: hovering && !selected, shape: shape))
            .clipShape(shape)
            .contentShape(shape)
            // Glass only on the one on screen: the others are icons on the row, as its tabs are names.
            .background {
                if selected {
                    shape.fill(.clear)
                        .glassEffect(.regular.tint(ground?.opacity(0.4) ?? Color.primary.opacity(0.12)), in: shape)
                }
            }
            .overlay {
                if targeted { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
            }
        }
        .buttonStyle(TilePress())
        .animation(.bar, value: selected)
        .onHover { hovering = $0 }
        .onContinuousHover { phase in
            withAnimation(.spring(duration: 0.45, bounce: 0)) {
                if case .active(let point) = phase { pointer = point } else { pointer = nil }
            }
        }
        .help(tab.label)
        .draggable(TabDrag(tab: tab.id)) {
            SiteIconView(url: url, size: 16)
        }
        .dropDestination(for: TabDrag.self) { items, _ in
            guard let item = items.first, item.tab != tab.id else { return false }
            model.place(item.tab, pinned: true, before: tab.id)
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu { TabMenu(model: model, tab: tab) }
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
