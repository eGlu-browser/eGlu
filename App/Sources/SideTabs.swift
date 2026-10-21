import PadCore
import SwiftUI
import UIKit

/// The tabs down the window's side (Settings › Tabs › In a Sidebar), as the
/// Mac keeps them and as Arc does: back and forward and the page's menu;
/// the address, a click on which types a new one in the command bar; the
/// space's pinned tabs as tiles; New Tab and the other tabs as rows, a
/// split's two on a shared ground; and the space at the foot, its menu
/// going to the others. While it shows, the row along the top and the
/// address bar go. Put away (its button, or Show or Hide Tab Bar), the
/// address bar comes back with the button at its start, to bring it back.
///
/// Like the bars, it sits on the window's ground, which takes the colour
/// along the top of the page (Browser.applySiteColor).
struct SideTabs: View {
    @ObservedObject var session: Session
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    static let width: CGFloat = 272

    var body: some View {
        let space = session.workspace.space(window.spaceID)
        // Without the pinned tabs this device hides (Settings › Pinned Tabs).
        let row = TabRow(tabs: (space?.tabs ?? []).filter(session.preferences.shows), splits: space?.splits ?? [],
                         current: window.tabID, compact: false, addressRequired: false, width: 0)
        let others = session.workspace.spaces.filter { $0.id != window.spaceID }
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                SideButton(symbol: "sidebar.left", label: "Hide Sidebar") { act(.command(.tabBar)) }
                Spacer(minLength: 0)
                HistoryButtons(window: window, act: act)
                PageMenu(window: window, act: act)
            }
            AddressCapsule(window: window, editable: false, act: act)
                .overlay(alignment: .bottom) {
                    LoadingLine(window: window)
                        .padding(.horizontal, 16)
                }
            // The pinned tiles stay put while the tabs under them scroll, as the Mac's do.
            if !row.pinned.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(row.pinned) { tab in
                        SidePinnedTab(window: window, tab: tab, row: row, others: others, act: act)
                    }
                }
                .animation(.bar, value: row.pinned.map(\.id))
            }
            ScrollView {
                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        SideNewTab { act(.command(.newTab)) }
                        ForEach(row.items) { item in
                            VStack(spacing: 2) {
                                ForEach(item.tabs) { tab in
                                    SideTab(window: window, tab: tab, row: row, others: others, act: act)
                                }
                            }
                            // A split's two on a ground of their own, as the row has them.
                            .padding(item.tabs.count > 1 ? 2 : 0)
                            .background {
                                if item.tabs.count > 1 {
                                    RoundedRectangle(cornerRadius: SideTab.corner + 2, style: .continuous)
                                        .fill(Palette.shade)
                                }
                            }
                        }
                    }
                }
                .animation(.bar, value: row.others.map(\.id))
            }
            .scrollIndicators(.never)
            .feathered(.vertical)
            HStack(spacing: 0) {
                SpaceButton(session: session, window: window, act: act)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea(.keyboard)
    }
}

/// A button on the sidebar's top row: its symbol alone, highlighted under
/// the pointer, 40 points that answer.
private struct SideButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
        .accessibilityLabel(label)
    }
}

/// The page's own commands, as the tab on screen's menu has them in the
/// row along the top: Find, Share and Handoff, the link, the bookmark, the
/// site's switches; then everything else.
private struct PageMenu: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    var body: some View {
        Menu {
            PageItems(window: window, act: act)
            Section { AppItems(act: act) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: Metrics.control, height: Metrics.control)
                .liquidGlass(in: Circle(), otherwise: .clear)
                .frame(width: Metrics.target, height: Metrics.target)
                .contentShape(Rectangle())
                .contentShape(.hoverEffect, Circle().inset(by: Metrics.ring))
        }
        .hoverEffect(.highlight)
        .accessibilityLabel("Page Menu")
    }
}

/// A pinned tab: its icon on a tile. The one on screen is raised in glass;
/// the others sit on a quiet ground.
private struct SidePinnedTab: View {
    @ObservedObject var window: WindowModel
    let tab: TabRecord
    let row: TabRow
    let others: [Space]
    let act: (BarAction) -> Void

    var body: some View {
        let selected = tab.id == window.tabID
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let url = tab.url ?? tab.pinned
        SiteIconView(url: url, size: 20)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if selected {
                    Color.clear.liquidGlass(reacting: false, in: shape, otherwise: Palette.card)
                } else {
                    shape.fill(Palette.wash)
                }
            }
            .contentShape(shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight)
            .onTapGesture { act(.select(tab.id)) }
            .contextMenu { TabMenuItems(window: window, tab: tab, row: row, others: others, act: act) }
            .draggable(TabDrop(id: tab.id)) { SiteIconView(url: url, size: 24) }
            .dropDestination(for: TabDrop.self) { drops, _ in
                guard let drop = drops.first, drop.id != tab.id else { return false }
                act(.placeTab(drop.id, before: tab.id))
                return true
            }
            .animation(.bar, value: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.title.isEmpty ? "Pinned Tab" : tab.title)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// New Tab, at the head of the tabs, as the Mac's sidebar has it.
private struct SideNewTab: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text("New Tab")
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 10)
            .frame(height: Metrics.target)
            .contentShape(Rectangle())
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: SideTab.corner, style: .continuous))
        }
        .buttonStyle(PressScale())
        .hoverEffect(.highlight)
    }
}

/// A tab in the list: its icon and its name, and a close button on the one
/// on screen and under the pointer. The one on screen is raised in glass.
private struct SideTab: View {
    @ObservedObject var window: WindowModel
    let tab: TabRecord
    let row: TabRow
    let others: [Space]
    let act: (BarAction) -> Void
    @State private var hovering = false

    static let corner: CGFloat = 12

    var body: some View {
        let selected = tab.id == window.tabID
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        HStack(spacing: 10) {
            SiteIconView(url: tab.url, size: 16)
                .frame(width: 20)
            Text(tab.title.isEmpty ? (tab.url?.host() ?? "New Tab") : tab.title)
                .font(.system(size: 14, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Palette.ink : Palette.ink.opacity(0.85))
                .lineLimit(1)
            Spacer(minLength: 0)
            if selected || hovering {
                Button {
                    act(.close(tab.id))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .contentShape(.hoverEffect, Circle())
                }
                .buttonStyle(PressScale())
                .hoverEffect(.highlight)
                .accessibilityLabel("Close Tab")
                .transition(.opacity)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: Metrics.target)
        .background {
            if selected {
                Color.clear.liquidGlass(reacting: false, in: shape, otherwise: Palette.card)
            }
        }
        .contentShape(shape)
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.highlight)
        .onHover { inside in withAnimation(.bar) { hovering = inside } }
        .onTapGesture { act(.select(tab.id)) }
        .contextMenu { TabMenuItems(window: window, tab: tab, row: row, others: others, act: act) }
        .draggable(TabDrop(id: tab.id)) {
            HStack(spacing: 8) {
                SiteIconView(url: tab.url, size: 16)
                Text(tab.title).font(.system(size: 14)).lineLimit(1)
            }
            .padding(10)
        }
        .dropDestination(for: TabDrop.self) { drops, _ in
            guard let drop = drops.first, drop.id != tab.id else { return false }
            act(.placeTab(drop.id, before: tab.id))
            return true
        }
        .animation(.bar, value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A tab dragged to another place in the sidebar.
struct TabDrop: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

/// A tab's menu in the sidebar: the row along the top's (TabStripView), in SwiftUI.
private struct TabMenuItems: View {
    @ObservedObject var window: WindowModel
    let tab: TabRecord
    let row: TabRow
    let others: [Space]
    let act: (BarAction) -> Void

    var body: some View {
        let selected = tab.id == window.tabID
        let paired = row.paired.contains(tab.id)
        if selected {
            Section { PageItems(window: window, act: act) }
        }
        Section {
            if tab.isPinned {
                Button("Back to Pinned Page", systemImage: "arrow.uturn.backward") { act(.backToPinned(tab.id)) }
                Button("Unpin Tab", systemImage: "pin.slash") { act(.unpin(tab.id)) }
            } else {
                Button("Pin Tab", systemImage: "pin") { act(.pin(tab.id)) }
                    .disabled(tab.url == nil)
                if paired {
                    Button("Separate Tabs", systemImage: "rectangle") { act(.separate(tab.id)) }
                    Button("Swap Sides", systemImage: "arrow.left.arrow.right") { act(.swapSides(tab.id)) }
                } else if selected {
                    Button("Split with New Tab", systemImage: "rectangle.split.2x1") { act(.splitWithNewTab) }
                } else if row.current.map({ !$0.isPinned }) == true {
                    Button("Open in Split View", systemImage: "rectangle.split.2x1") { act(.splitWith(tab.id)) }
                }
            }
        }
        Section {
            Button("Close Tab", systemImage: "xmark") { act(.close(tab.id)) }
            if UIApplication.shared.supportsMultipleScenes {
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { act(.tabInNewWindow(tab.id)) }
            }
            if !others.isEmpty {
                Menu("Move to Space", systemImage: "arrow.right.square") {
                    ForEach(others) { space in
                        Button(space.name, systemImage: space.symbol) { act(.moveTab(tab.id, space.id)) }
                    }
                }
            }
        }
        if selected {
            Section { AppItems(act: act) }
        }
    }
}
