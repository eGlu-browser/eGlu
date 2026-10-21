import AppKit
import PadCore
import SwiftUI

/// A window as SwiftUI keeps it between launches: an identity of its own,
/// so ⌘N always makes another, and the space it showed last.
struct WindowSeed: Codable, Hashable {
    var id = UUID()
    var space: UUID?
}

/// A window: the space's colour as its ground, the sidebar down its left,
/// the page as a card beside it, and the command bar over both when asked for.
struct BrowserView: View {
    /// What SwiftUI keeps of the window, to bring it back as it was at the next launch.
    @Binding var seed: WindowSeed?
    @StateObject private var model: WindowModel
    @ObservedObject private var session = Session.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    /// The sidebar's width as a drag on its edge began.
    @State private var widthAtStart: CGFloat?
    /// The width the page's card shares with an extension's side panel.
    @State private var cardsWidth: CGFloat = 0

    init(seed: Binding<WindowSeed?>) {
        _seed = seed
        _model = StateObject(wrappedValue: WindowModel(space: seed.wrappedValue?.space))
    }

    var body: some View {
        let colour = session.workspace.space(model.spaceID)?.color ?? .blue
        ZStack(alignment: .topLeading) {
            SpaceWash(color: colour)
            // The page's card stays one view whichever way the tabs are, so
            // its page isn't handed from one card to another as they change.
            let side = model.tabsInSidebar && model.sidebarShown
            HStack(spacing: 0) {
                if side {
                    Sidebar(model: model)
                        .frame(width: model.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    edge
                }
                VStack(spacing: Metrics.gap) {
                    // The tabs along the top (Settings › General › Tabs): one row over the page.
                    if !model.tabsInSidebar {
                        TopTabBar(model: model)
                            .frame(height: Metrics.control)
                            .transition(.opacity)
                    }
                    // An extension's side panel beside the page's card (ExtensionSidePanel.swift).
                    HStack(spacing: Metrics.gap) {
                        PageCard(model: model)
                        ExtensionSidePanelView(model: model, room: cardsWidth)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardsWidth = $0 }
                    // The panel follows the tab on screen; another space puts it away.
                    .onChange(of: model.tabID) { _, _ in ExtensionSidePanels.shared.tabChanged(in: model) }
                    .onChange(of: model.spaceID) { _, _ in ExtensionSidePanels.shared.close(in: model) }
                }
                .padding(.vertical, Metrics.gap)
                .padding(.trailing, Metrics.gap)
                .padding(.leading, side ? 0 : Metrics.gap)
            }
            if model.tabsInSidebar, !model.sidebarShown {
                peek
            }
            if let purpose = model.commandBar {
                commandBar(purpose)
            }
        }
        .ignoresSafeArea()
        .background(WindowReader(model: model))
        .frame(minWidth: 640, minHeight: 420)
        .focusedSceneObject(model)
        .onAppear {
            session.openWindow = { space in openWindow(value: WindowSeed(space: space)) }
            session.openSettings = { openSettings() }
            model.appear()
        }
        .onDisappear { model.disappear() }

        .onChange(of: model.spaceID) { _, space in seed = WindowSeed(id: seed?.id ?? UUID(), space: space) }
    }

    /// The sidebar's edge, beside the card: dragged, it makes the sidebar wider or narrower.
    private var edge: some View {
        Color.clear
            .frame(width: Metrics.gap)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = widthAtStart ?? model.sidebarWidth
                        widthAtStart = start
                        let width = start + drag.translation.width
                        model.sidebarWidth = min(max(width, WindowModel.widths.lowerBound), WindowModel.widths.upperBound)
                    }
                    .onEnded { _ in widthAtStart = nil }
            )
    }

    /// The hidden sidebar: a strip along the window's left edge that brings
    /// it out over the page, as a pane of glass, until the pointer has left
    /// the strip and the pane together for a moment.
    private var peek: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: Metrics.gap + 2)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            if model.peeking {
                let shape = RoundedRectangle(cornerRadius: Metrics.pane, style: .continuous)
                // As wide inside as the sidebar it stands for, with a gap of its own on the page's side.
                Sidebar(model: model, floating: true)
                    .frame(width: model.sidebarWidth + Metrics.gap)
                    .clipShape(shape)
                    .glassEffect(.regular, in: shape)
                    .padding(Metrics.gap)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .onHover { model.peek($0) }
    }

    private func commandBar(_ purpose: CommandBarPurpose) -> some View {
        GeometryReader { box in
            ZStack(alignment: .top) {
                // A click anywhere else puts the bar away.
                Color.black.opacity(0.14)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.commandBar = nil
                        model.focusPage()
                    }
                let top = max(box.size.height * 0.16, 48)
                // The rows have what is left under the field, down to a margin at the window's foot.
                CommandBar(model: model, purpose: purpose, room: max(box.size.height - top - 56 - 24, 120))
                    .id(purpose)
                    .frame(width: min(660, box.size.width - 48))
                    .padding(.top, top)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}

// MARK: The page's card

/// The page, as a card with round corners standing on the window's ground;
/// the space's start where the tab has gone nowhere yet, and what went
/// wrong where the page couldn't load.
private struct PageCard: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.card, style: .continuous)
        ZStack(alignment: .topTrailing) {
            shape
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
                .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
            if let page = model.page {
                PageSurface(page: page)
                    .clipShape(shape)
                if let failure = model.failure {
                    FailureView(message: failure, url: model.url) { model.reload() }
                        .clipShape(shape)
                }
            } else {
                StartView(model: model)
                    .clipShape(shape)
            }
            if model.finding {
                FindBar(model: model)
                    .padding(Metrics.gap)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // An extension's popup, in a pane as Handoff's, at the corner nearest its button (ExtensionPopup.swift).
        .overlay(alignment: .top) {
            ExtensionPopupPane(model: model)
        }
        // A handoff being made ready stands at the page's corner and holds nothing up (HandoffPanel).
        .overlay(alignment: .bottomTrailing) {
            if let job = model.handoff {
                HandoffPanel(model: model, job: job)
                    .padding(16)
                    .transition(.offset(y: 16).combined(with: .opacity))
            }
        }
        .animation(.bar, value: model.finding)
        .animation(.bar, value: model.handoff == nil)
    }
}

/// A tab that has gone nowhere yet: the space's name, a field that is the
/// command bar's, and the space's bookmarks as tiles.
private struct StartView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var session = Session.shared

    var body: some View {
        let space = session.workspace.space(model.spaceID)
        let bookmarks = space?.bookmarks.flatMap(\.links).filter { $0.url != nil } ?? []
        VStack(spacing: 22) {
            Spacer(minLength: 40)
            if let space {
                Image(systemName: space.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(space.color.ink)
                    .frame(width: 60, height: 60)
                    .background(space.color.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(space.name)
                    .font(.system(size: 22, weight: .semibold))
            }
            Button {
                model.commandBar = model.tabID == nil ? .newTab : .here
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("Search or enter an address")
                    Spacer()
                    Text("⌘T").foregroundStyle(.tertiary)
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(width: 440, height: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            if !bookmarks.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 100), spacing: 14)], spacing: 16) {
                    ForEach(bookmarks.prefix(24)) { bookmark in
                        Button {
                            if let url = bookmark.url { model.open(url, newTab: false) }
                        } label: {
                            VStack(spacing: 7) {
                                SiteIconView(url: bookmark.url, size: 28)
                                    .frame(width: 56, height: 56)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Text(bookmark.label)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 88)
                        }
                        .buttonStyle(PressScale())
                        .help(bookmark.url?.absoluteString ?? "")
                    }
                }
                .frame(maxWidth: 560)
            }
            Spacer(minLength: 40)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Why the page didn't load, and a way to try again.
private struct FailureView: View {
    let message: String
    let url: URL?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Safience Can’t Open This Page")
                .font(.system(size: 17, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let url {
                Text(Destination.pretty(url))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 380)
            }
            Button("Try Again", action: retry)
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Find on the page: a field in glass at the card's top corner. Return and
/// ⌘G go to the next place, ⇧Return and ⇧⌘G to the one before, Escape ends it.
private struct FindBar: View {
    @ObservedObject var model: WindowModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Find on Page", text: $model.findText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 180)
                .focused($focused)
                .onSubmit { model.find(backwards: NSEvent.modifierFlags.contains(.shift)) }
                .onChange(of: model.findText) { _, _ in model.find() }
                .onExitCommand { model.endFinding() }
            if model.findMissed {
                Text("Not found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Button { model.find(backwards: true) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .help("Previous (⇧⌘G)")
            Button { model.find() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .help("Next (⌘G)")
            Button { model.endFinding() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Done")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .glassEffect(.regular, in: Capsule())
        .onAppear { focused = true }
        .onChange(of: model.findRequests) { _, _ in focused = true }
    }
}
