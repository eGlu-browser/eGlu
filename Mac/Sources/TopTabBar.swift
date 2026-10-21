import AppKit
import PadCore
import SwiftUI

/// The tabs along the top, for whoever chose them there over the sidebar
/// (Settings › General › Tabs): one row on the window's ground, level with
/// the window's own buttons. Back, forward and reload; the space's pinned
/// tabs as small tiles; its other tabs, sharing what room there is, the one
/// on screen raised in glass and standing for the address, as Safari's
/// compact tabs do (a click on it opens the command bar on its address);
/// then New Tab, the spaces with Clear and Space Settings, and the page's
/// own commands.
struct TopTabBar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var session = Session.shared

    /// A tab is never narrower than its name needs to read, nor wider than
    /// a long one needs; past that, the row scrolls.
    static let narrowest: CGFloat = 120
    static let widest: CGFloat = 240
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
                let each = min(max(box.size.width / CGFloat(max(others.count, 1)) - 4, Self.narrowest), Self.widest)
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(others) { tab in
                                TopTab(model: model, tab: tab, width: each)
                                    .id(tab.id)
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
            PlainIcon("plus", help: "New Tab (⌘T)") { model.commandBar = .newTab }
            SpaceBar(model: model, inRow: true)
                .fixedSize()
            // Extensions (ExtensionBar.swift): those pinned, then the puzzle button.
            PinnedExtensions(model: model)
            PageActionsButton(model: model)
            ExtensionsButton(model: model)
        }
        // The row's ground moves the window, as a title bar does; what is on it are only buttons.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

/// A tab in the row: its site's icon and its name, a close button while the
/// pointer is on it. The one on screen is raised in glass and is the
/// address: a click on it opens the command bar on where it is (⌘L).
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
            Text(selected ? (host ?? tab.label) : tab.label)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
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

    /// The tab on screen says where it is, as an address does: its site,
    /// or the words of a search with the chosen engine.
    private var host: String? {
        if let words = model.searchWords { return words }
        guard let host = model.url?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A pinned tab in the row: its icon on a small tile of glass. The one on
/// screen takes on its icon, as the sidebar's tile does (PinnedTile): its
/// glass tinted with the icon's ground, the icon's mark alone on a soft
/// plate of that ground.
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
            model.select(tab.id)
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
            .glassEffect(selected ? .regular.tint(ground?.opacity(0.4) ?? Color.primary.opacity(0.12)) : .regular, in: shape)
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
