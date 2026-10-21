import AppKit
import PadCore
import SwiftUI
import UniformTypeIdentifiers

/// Arc's sidebar: the window's buttons and the page's back, forward and
/// reload at the top; the address under them; the space's pinned tabs as
/// tiles; its other tabs as rows, the newest last; and the spaces along the
/// foot, with the space's own tools. It lies on the window's ground, the
/// space's colour, with what holds something in Liquid Glass. Hidden (⌘S),
/// it slides out over the page when the pointer reaches the window's left
/// edge, as a pane of glass of its own.
struct Sidebar: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var session = Session.shared
    /// Out over the page, the sidebar being hidden.
    var floating = false
    /// What the list's glass draws past its tiles and rows: its rim and its light.
    private static let bleed: CGFloat = 4

    var body: some View {
        let space = session.workspace.space(model.spaceID)
        // One gap between the groups and round the sidebar's edges; on the
        // side by the page, the gap is the page's own (BrowserView.edge).
        VStack(spacing: Metrics.gap) {
            TopRow(model: model)
                .frame(height: Metrics.control)
            HStack(spacing: 2) {
                AddressPill(model: model)
                    .padding(.trailing, Metrics.gap - 2)
                PageActionsButton(model: model)
            }
            if let space {
                ZStack(alignment: .top) {
                    VStack(spacing: Metrics.gap) {
                        // The pinned tiles stay put while the tabs under them scroll, as Arc keeps them.
                        PinnedGrid(model: model, space: space)
                        ScrollViewReader { reader in
                            ScrollView {
                                TabList(model: model, space: space)
                                    // Glass draws a little past its shape: room for it, inside the scroll view.
                                    .padding(Self.bleed)
                            }
                            .scrollIndicators(.never)
                            // As much wider than its column as it is padded inside, so what it shows stays put.
                            .padding(-Self.bleed)
                            .feathered(.vertical)
                            // The tab on screen is always in view, however it came to be on screen.
                            .onChange(of: model.tabID) { _, tab in
                                withAnimation(.bar) { tab.map { reader.scrollTo($0) } }
                            }
                        }
                    }
                    // The space's tabs come in from the side they are on, as in Arc.
                    .id(space.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity))
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(.bar, value: space.id)
            } else {
                Spacer()
            }
            SpaceBar(model: model)
        }
        .padding([.top, .bottom, .leading], Metrics.gap)
        .padding(.trailing, floating ? Metrics.gap : 0)
    }
}

// MARK: The top row

/// The window's close, minimise and zoom buttons, then the sidebar's own
/// button, and back, forward and reload, plain, as Arc's are.
private struct TopRow: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        HStack(spacing: 0) {
            // The window's own buttons, centred in a cell as high as the row: the
            // first as far from the row's start as from its top.
            WindowButtons()
                .frame(width: WindowButtons.width, height: WindowButtons.side)
                .padding(.leading, (Metrics.control - WindowButtons.side) / 2)
            Spacer(minLength: Metrics.gap)
            HStack(spacing: 2) {
                PlainIcon("sidebar.left", help: model.sidebarShown ? "Hide Sidebar (⌘S)" : "Keep Sidebar Open (⌘S)") {
                    model.toggleSidebar()
                }
                PlainIcon("chevron.left", help: "Back (⌘[)", enabled: model.canGoBack) { model.back() }
                PlainIcon("chevron.right", help: "Forward (⌘])", enabled: model.canGoForward) { model.forward() }
                if model.loading {
                    PlainIcon("xmark", help: "Stop (⌘.)") { model.stop() }
                } else {
                    PlainIcon("arrow.clockwise", help: "Reload (⌘R)", enabled: model.tabID != nil) { model.reload() }
                }
            }
        }
        // The row's ground moves the window, as a title bar does; the buttons on it are only buttons.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

// MARK: The address

/// The page's site, in glass: a click opens the command bar on its address
/// (⌘L), as Arc's does, and the link at its end, while the pointer is on
/// it, copies the address. A line along its foot while the page loads.
private struct AddressPill: View {
    @ObservedObject var model: WindowModel
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous)
        HStack(spacing: 0) {
            Button {
                model.commandBar = .here
            } label: {
                // The icon in the column the tabs' icons are in, the words where theirs start.
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(label)
                        .font(.system(size: 13, weight: model.url == nil ? .regular : .medium))
                        .foregroundStyle(model.url == nil ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                }
                .padding(.leading, 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.url?.absoluteString ?? "Search or enter an address (⌘L)")
            .accessibilityLabel("Address")
            .accessibilityValue(model.url?.absoluteString ?? "")
            if hovering, model.url != nil {
                Button {
                    model.copyLink()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "link")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
                .help("Copy Link (⇧⌘C)")
                .accessibilityLabel("Copy Link")
                .transition(.opacity)
            }
        }
        .frame(height: Metrics.field)
        // Under the pointer the glass darkens a step, as a field you can click into does.
        .background(Highlight(hovering: hovering, shape: shape))
        .overlay(alignment: .bottomLeading) {
            if model.loading {
                GeometryReader { box in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: max(box.size.width * model.progress, 12), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .animation(.easeOut(duration: 0.2), value: model.progress)
                }
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .glassEffect(.regular, in: shape)
        .onHover { inside in withAnimation(.hover) { hovering = inside } }
    }

    private var icon: String {
        guard let url = model.url, model.searchWords == nil else { return "magnifyingglass" }
        if url.scheme == "https" { return model.secure ? "lock.fill" : "lock.open.fill" }
        return url.scheme == "http" ? "exclamationmark.triangle.fill" : "doc"
    }

    /// The site, as Arc shows it: its host without www. A search with the
    /// chosen engine says what was searched for, as Safari does.
    private var label: String {
        guard let url = model.url else { return "Search or enter address" }
        if let words = model.searchWords { return words }
        guard let host = url.host() else { return Destination.pretty(url) }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// The … beside the address: the page's own commands, as the iPhone's page
/// menu (…) has them (PageActions).
struct PageActionsButton: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        Button {
            model.pageActionsShown.toggle()
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(PlainIconStyle())
        .help("Share and More")
        .accessibilityLabel("More")
        .popover(isPresented: $model.pageActionsShown, arrowEdge: .bottom) {
            PageActions(model: model)
        }
    }
}

// MARK: Pinned tabs

/// A tab carried by a drag: within the sidebar to another place, onto the
/// tiles to pin it, or onto a space's button to move it there.
struct TabDrag: Codable, Transferable {
    let tab: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .safienceTab)
    }
}

extension UTType {
    static let safienceTab = UTType(exportedAs: "net.taehee.safience.tab")
}

/// The space's pinned tabs as tiles of glass, Arc's favourites: the site's
/// icon alone, its title when the pointer rests on it. Those this Mac hides
/// (Settings › Pinned Tabs) are left out.
private struct PinnedGrid: View {
    @ObservedObject var model: WindowModel
    let space: Space
    @ObservedObject private var session = Session.shared

    var body: some View {
        let pinned = space.tabs.filter { $0.isPinned && session.preferences.shows($0) }
        if !pinned.isEmpty {
            GlassEffectContainer(spacing: 2) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52, maximum: 120), spacing: Metrics.gap)], spacing: Metrics.gap) {
                    ForEach(pinned) { tab in
                        PinnedTile(model: model, tab: tab)
                    }
                }
            }
        }
    }
}

/// A pinned tab's tile: the site's icon on glass, all tiles one size. The
/// one on screen takes on its icon: its glass is tinted, lightly, with the
/// icon's own ground (IconTint); the icon is drawn without that ground, its
/// mark alone; and under the mark a soft plate of the ground fades out into
/// the tint. What the site draws stands on its own colour, with no square
/// of the icon's left to show. In a window that isn't in front the system
/// greys tinted glass, and the icon comes back whole on it, where its mark
/// alone could go unseen.
private struct PinnedTile: View {
    @ObservedObject var model: WindowModel
    let tab: TabRecord
    @ObservedObject private var icons = SiteIcons.shared
    @Environment(\.controlActiveState) private var activeState
    @State private var hovering = false
    @State private var targeted = false
    /// Where the pointer is over the tile, and the tile's size, for the plate to lean toward it.
    @State private var pointer: CGPoint?
    @State private var size = CGSize.zero

    /// How strongly the tile on screen is tinted, as chosen from a sheet of looks (K3).
    private static let tint = 0.4

    /// Where the pointer is, or where a debug build was told to put it (`-hoverPinned 0.8,0.3`).
    private var shownPointer: CGPoint? {
        #if DEBUG
        if let spot = PointerGlow.debugSpot, model.tabID == tab.id, size.width > 0 {
            return CGPoint(x: spot.x * size.width, y: spot.y * size.height)
        }
        #endif
        return pointer
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous)
        let selected = model.tabID == tab.id
        let url = tab.url ?? tab.pinned
        let colour = model.space?.color ?? .blue
        let ground = selected ? PinnedIcon.ground(for: url, colour: colour) : nil
        let open = selected && activeState != .inactive
        Button {
            model.select(tab.id)
        } label: {
            ZStack {
                PointerGlow(pointer: shownPointer)
                PinnedIcon(url: url, open: open, colour: colour, size: Metrics.tileIcon,
                           lean: Plate.lean(toward: shownPointer, in: size, reach: CGSize(width: 13, height: 9)))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.tile)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .background(Highlight(hovering: hovering && !selected, shape: shape))
            // The plate's softened edge stays inside the tile.
            .clipShape(shape)
            .contentShape(shape)
            // A square icon with no one colour round its edge lights the glass in the label colour, faintly.
            .glassEffect(selected ? .regular.tint(ground?.opacity(Self.tint) ?? Color.primary.opacity(0.12)) : .regular,
                         in: shape)
            .overlay {
                if targeted { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
            }
        }
        // A press gives a little, inside the tile's own room: the glass's own press grew the
        // tile, and the list cut it off at its top.
        .buttonStyle(TilePress())
        .animation(.bar, value: open)
        .animation(.bar, value: colour)
        .onHover { hovering = $0 }
        .onContinuousHover { phase in
            withAnimation(.spring(duration: 0.45, bounce: 0)) {
                if case .active(let point) = phase { pointer = point } else { pointer = nil }
            }
        }
        .help(tab.label)
        .draggable(TabDrag(tab: tab.id)) {
            SiteIconView(url: url, size: Metrics.tileIcon)
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

/// The densest of the open tile's tint: a soft plate of the icon's ground
/// under its mark (K3, from a sheet of looks: 26 points, corners of 8,
/// softened by 6). While the pointer is on the tile it leans well toward
/// it, out from under the mark, and spreads a little, so the colour can be
/// seen to follow; at rest it drifts by a point or so, slowly, as light
/// through glass would. It holds still where Reduce Motion is on, and
/// leans without spreading.
struct Plate: View {
    let ground: Color
    /// Toward the pointer; nil while it is elsewhere.
    let toward: CGSize?
    /// Its side, corner and softening: the sidebar's tile's, or smaller in the row along the top.
    var side: CGFloat = 26
    var corner: CGFloat = 8
    var blur: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || toward != nil)) { context in
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(ground)
                .frame(width: side, height: side)
                .blur(radius: blur)
                .scaleEffect(toward == nil || reduceMotion ? 1 : 1.25)
                .offset(toward ?? drift(at: context.date))
        }
    }

    /// Where the plate leans: toward the pointer, three fifths of the way
    /// from the tile's middle, as far as `reach` either way; nil while the
    /// pointer is elsewhere.
    static func lean(toward pointer: CGPoint?, in size: CGSize, reach: CGSize) -> CGSize? {
        guard let pointer, size.width > 0 else { return nil }
        let x = (pointer.x - size.width / 2) * 0.6
        let y = (pointer.y - size.height / 2) * 0.6
        return CGSize(width: min(max(x, -reach.width), reach.width), height: min(max(y, -reach.height), reach.height))
    }

    /// A slow loop of about a point and a half across and one down, its
    /// two periods apart so it never quite repeats.
    private func drift(at date: Date) -> CGSize {
        guard !reduceMotion else { return .zero }
        let t = date.timeIntervalSinceReferenceDate
        return CGSize(width: cos(t * 2 * .pi / 7) * 1.5, height: sin(t * 2 * .pi / 5) * 1)
    }
}

/// A pinned tab's icon, in the sidebar's tile and the row's, the same in
/// every space and every look of the screen (IconTint.Look), and every icon
/// as large to the eye as the others: each is cut to what it draws first
/// (IconTint.trimmed), so the clear space a site leaves round it counts for
/// nothing.
///
/// At rest: an icon that fills its own square fills the square; a badge (a
/// disc of one colour round what it holds) is as it is, a little larger
/// where it is round, as large to the eye as a square (`badgeSide`); any
/// other shape on clear stands on a square of black or white, inside it at
/// its optical size (`symbolFrame`). On screen, in a window in front: the
/// icon's colour is the tile's, in a soft plate leaning to the pointer, and
/// the icon is what stands on it, at the size it has at rest: an own icon's
/// or a badge's mark without its ground (a badge of one colour, itself in
/// white or black); a shape alone, in its own colours on its square's
/// colour, or, all one colour, in the words' colour on the space's. A
/// window behind greys tinted glass, so its tile shows the icon at rest.
struct PinnedIcon: View {
    let url: URL?
    /// On screen, in a window in front.
    let open: Bool
    let colour: SpaceColor
    /// A square icon's side.
    let size: CGFloat
    let lean: CGSize?
    var plate = (side: CGFloat(26), corner: CGFloat(8), blur: CGFloat(6))
    @ObservedObject private var icons = SiteIcons.shared
    @Environment(\.colorScheme) private var scheme

    /// The tile's colour on screen: the icon's ground, a shape's square, or
    /// for a shape of one colour the space's; a letter's until the icon
    /// comes; nil for an icon whose edge is no one colour.
    static func ground(for url: URL?, colour: SpaceColor) -> Color? {
        switch IconTint.look(for: url) {
        case .own(let ground)?: return ground.map { Color(nsColor: $0) }
        case .badge(let badge, _, _)?: return Color(nsColor: badge)
        case .shape(let square, let oneColour)?: return oneColour ? colour.color : Color(nsColor: square)
        case nil: return IconTint.color(for: url)
        }
    }

    /// Where a shape is drawn in a square of `square` points: as large to the
    /// eye as a round one 72% of the square across, its width and height
    /// multiplying to that one's, so a tall, narrow logo (Figma's) is not
    /// lost beside a round one (GitHub's); and never more than 82% of the
    /// square either way, so it never meets the square's edge.
    static func symbolFrame(of picture: NSImage, square: CGFloat) -> CGSize {
        let aspect = picture.size.width / max(picture.size.height, 1)
        let height = square * 0.72 / aspect.squareRoot()
        let width = height * aspect
        let fit = min(1, square * 0.82 / max(width, height))
        return CGSize(width: (width * fit).rounded(), height: (height * fit).rounded())
    }

    /// A badge's side beside squares of `square` points: as large as theirs
    /// to the eye, so larger the less of its box it covers (a disc, about
    /// 0.79 of it, by a tenth), and never by more than an eighth.
    static func badgeSide(fill: Double, square: CGFloat) -> CGFloat {
        (square * min(max((0.95 / max(fill, 0.01)).squareRoot(), 1), 1.125)).rounded()
    }

    var body: some View {
        let look = IconTint.look(for: url)
        let trimmed = IconTint.trimmed(for: url)
        if open, let ground = Self.ground(for: url, colour: colour), let look, let trimmed {
            Group {
                if case .shape(_, true) = look {
                    // A firmer plate under a shape of one colour, for its ink to stand out on the space's colour.
                    Plate(ground: ground, toward: lean, side: plate.side + 4, corner: plate.corner + 1, blur: plate.blur - 1)
                } else {
                    Plate(ground: ground, toward: lean, side: plate.side, corner: plate.corner, blur: plate.blur)
                }
            }
            .transition(.opacity)
            Group {
                switch look {
                case .shape(_, true):
                    let frame = Self.symbolFrame(of: trimmed, square: size)
                    ink.mask { picture(trimmed) }
                        .frame(width: frame.width, height: frame.height)
                case .shape:
                    let frame = Self.symbolFrame(of: trimmed, square: size)
                    picture(trimmed).frame(width: frame.width, height: frame.height)
                case .own:
                    picture(IconTint.mark(for: url) ?? trimmed).frame(width: size, height: size)
                case .badge(let badge, let solid, let fill):
                    let side = Self.badgeSide(fill: fill, square: size)
                    if solid {
                        IconTint.ink(on: badge).mask { picture(trimmed) }
                            .frame(width: side, height: side)
                    } else {
                        picture(IconTint.mark(for: url) ?? trimmed).frame(width: side, height: side)
                    }
                }
            }
            .transition(.opacity)
        } else if case .badge(_, _, let fill)? = look, let trimmed {
            // As it is: the badge is its own ground, and needs no square.
            let side = Self.badgeSide(fill: fill, square: size)
            picture(trimmed)
                .frame(width: side, height: side)
                .transition(.opacity)
        } else if let look, let trimmed {
            let corner = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            Group {
                switch look {
                case .shape(let square, _):
                    let frame = Self.symbolFrame(of: trimmed, square: size)
                    ZStack {
                        corner.fill(Color(nsColor: square))
                        picture(trimmed).frame(width: frame.width, height: frame.height)
                    }
                    .frame(width: size, height: size)
                case .own, .badge:
                    picture(trimmed)
                        .frame(width: size, height: size)
                        .clipShape(corner)
                }
            }
            // A hairline keeps a white or black square from running into the glass.
            .overlay { corner.strokeBorder(Palette.outline, lineWidth: 0.5) }
            .transition(.opacity)
        } else {
            // No icon yet: its letter, on its colour.
            SiteIconView(url: url, size: size)
                .transition(.opacity)
        }
    }

    /// A picture whole, in its own colours, as large as its frame lets it be.
    private func picture(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }

    /// A shape of one colour on the space's: white, or dark where white
    /// would stand out too little, on yellow, and on gray in the light,
    /// where the tile is lighter than the colour itself (3 to 1 at the
    /// least, as WCAG asks of what isn't text).
    private var ink: Color {
        colour == .gray && scheme == .light ? Color.black.opacity(0.85) : colour.ink
    }
}

/// A soft light under the pointer while it is on a pinned tile, following
/// it as light on glass would: on every tile, whether or not its icon has a
/// ground for a plate.
struct PointerGlow: View {
    let pointer: CGPoint?
    var radius: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { box in
            if let pointer {
                RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.2 : 0.7), Color.white.opacity(0)],
                               center: UnitPoint(x: pointer.x / max(box.size.width, 1), y: pointer.y / max(box.size.height, 1)),
                               startRadius: 0, endRadius: radius)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    #if DEBUG
    /// Where a debug build puts the pointer on the open tile, in the tile's
    /// own fractions, for a picture of it: `-hoverPinned 0.8,0.3`.
    static let debugSpot: CGPoint? = {
        let parts = (UserDefaults.standard.string(forKey: "hoverPinned") ?? "").split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }()
    #endif
}

// MARK: The space's own tabs

/// New Tab, then the space's tabs that aren't pinned.
private struct TabList: View {
    @ObservedObject var model: WindowModel
    let space: Space

    var body: some View {
        VStack(spacing: 2) {
            NewTabRow(model: model, unpinned: space.tabs.filter { !$0.isPinned }.map(\.id))
            ForEach(space.tabs.filter { !$0.isPinned }) { tab in
                TabRow(model: model, tab: tab)
                    .id(tab.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }
            // The rest of the list takes a tab dropped below the last.
            TailDrop(model: model)
        }
    }
}

private struct NewTabRow: View {
    @ObservedObject var model: WindowModel
    /// The space's tabs under it, first to last.
    let unpinned: [UUID]
    @State private var targeted = false

    var body: some View {
        Button {
            model.commandBar = .newTab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text("New Tab")
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: Metrics.row)
        }
        .buttonStyle(RowButtonStyle(corner: Metrics.rowCorner))
        .overlay(alignment: .bottom) { DropLine(shown: targeted) }
        .help("New Tab (⌘T)")
        .dropDestination(for: TabDrag.self) { items, _ in
            guard let item = items.first else { return false }
            // First of the tabs: before the first of the others.
            model.place(item.tab, pinned: false, before: unpinned.first { $0 != item.tab })
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// A tab's row: its site's icon and its title, a close button while the
/// pointer is on it. The tab on screen is raised in glass.
private struct TabRow: View {
    @ObservedObject var model: WindowModel
    let tab: TabRecord
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let selected = model.tabID == tab.id
        let shape = RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous)
        HStack(spacing: 8) {
            ZStack {
                if selected, model.loading, model.page != nil {
                    ProgressView().controlSize(.mini)
                } else {
                    SiteIconView(url: tab.url, size: 16)
                        .opacity(Session.shared.pages.isLive(tab.id) || selected ? 1 : 0.75)
                }
            }
            .frame(width: 16, height: 16)
            Text(tab.label)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if hovering {
                CloseButton { model.closeTab(tab.id) }
                    .transition(.opacity)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(height: Metrics.row)
        .background {
            if selected {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else {
                Highlight(hovering: hovering, shape: shape)
            }
        }
        .overlay(alignment: .top) { DropLine(shown: targeted) }
        .contentShape(shape)
        .onHover { inside in withAnimation(.hover) { hovering = inside } }
        .onTapGesture { model.select(tab.id) }
        .draggable(TabDrag(tab: tab.id)) {
            HStack(spacing: 6) {
                SiteIconView(url: tab.url, size: 16)
                Text(tab.label).font(.system(size: 13)).lineLimit(1)
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
        .help(tab.url?.absoluteString ?? tab.label)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A row's close button: its own highlight, a step stronger than the row's under it.
struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Highlight(hovering: hovering, shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? Color.primary : Color.secondary)
        .onHover { hovering = $0 }
        .help("Close Tab (⌘W)")
        .accessibilityLabel("Close Tab")
    }
}

/// Where a dragged tab will land, between two rows.
struct DropLine: View {
    let shown: Bool

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 6)
            .offset(y: -1)
            .opacity(shown ? 1 : 0)
    }
}

/// Below the last row: a tab dropped here goes to the end.
private struct TailDrop: View {
    @ObservedObject var model: WindowModel
    @State private var targeted = false

    var body: some View {
        Color.clear
            .frame(height: 60)
            .overlay(alignment: .top) { DropLine(shown: targeted) }
            .contentShape(Rectangle())
            .dropDestination(for: TabDrag.self) { items, _ in
                guard let item = items.first else { return false }
                model.place(item.tab, pinned: false, before: nil)
                return true
            } isTargeted: { targeted = $0 }
    }
}

/// A tab's menu, on its row or its tile.
struct TabMenu: View {
    @ObservedObject var model: WindowModel
    let tab: TabRecord

    var body: some View {
        let session = Session.shared
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { model.togglePin(tab.id) }
            .disabled(tab.url == nil && !tab.isPinned)
        if tab.isPinned, tab.url != tab.pinned {
            Button("Back to Pinned Page") { model.backToPinned(tab.id) }
        }
        Button("Duplicate Tab") { model.duplicate(tab.id) }
            .disabled(tab.url == nil)
        Button("Copy Link") { model.copyLink(tab.id) }
            .disabled(tab.url == nil)
        let others = session.workspace.spaces.filter { $0.id != model.spaceID }
        if !others.isEmpty {
            Menu("Move to Space") {
                ForEach(others) { space in
                    Button {
                        model.move(tab.id, to: space.id)
                    } label: {
                        Label(space.name, systemImage: space.symbol)
                    }
                }
            }
        }
        Divider()
        Button(tab.isPinned ? "Close and Unload" : "Close Tab") { model.closeTab(tab.id) }
    }
}

// MARK: The spaces

/// The sidebar's foot: the spaces in one piece of glass, each its icon,
/// the one on screen filled with its colour (a click goes there, a tab
/// dropped on one moves to it); then the space's own tools, plain:
/// downloads while there are any, Clear (every tab that isn't pinned
/// closes, as Arc's does), and Space Settings, where the spaces are put in
/// order, added, changed and removed.
struct SpaceBar: View {
    @ObservedObject var model: WindowModel
    /// In the row along the top: the tools straight after the spaces, no room between.
    var inRow = false
    @ObservedObject private var session = Session.shared
    @ObservedObject private var downloads = Downloads.shared
    /// Where each space's button is, for the one disc that marks the space on screen to go to.
    @Namespace private var places

    var body: some View {
        let clearable = model.space?.tabs.contains { !$0.isPinned } == true
        HStack(spacing: 2) {
            // As many as fit at their size, then smaller, then in a row that scrolls.
            ViewThatFits(in: .horizontal) {
                spaces(compact: false)
                spaces(compact: true)
                ScrollView(.horizontal) { spaces(compact: true, glass: false) }
                    .scrollIndicators(.never)
                    .padding(3)
                    .glassEffect(.regular, in: Capsule())
            }
            if inRow {
                Spacer().frame(width: Metrics.gap - 2)
            } else {
                Spacer(minLength: Metrics.gap)
            }
            if !downloads.items.isEmpty {
                DownloadsButton(model: model)
                    .transition(.opacity)
            }
            PlainIcon("trash", help: "Clear: Close Every Tab That Isn’t Pinned", enabled: clearable) {
                model.clearTabs()
            }
            Button {
                model.spacesPanel = model.spacesPanel == nil ? .list : nil
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(PlainIconStyle())
            .help("Space Settings")
            .accessibilityLabel("Space Settings")
            .popover(isPresented: Binding(get: { model.spacesPanel != nil }, set: { if !$0 { model.spacesPanel = nil } }),
                     arrowEdge: .top) {
                SpaceManager(model: model)
            }
        }
        .frame(height: Metrics.field)
        .animation(.bar, value: downloads.items.isEmpty)
    }

    /// The spaces' buttons, and under them one disc in the colour of the
    /// space on screen: going to another space (a click, a sideways sweep,
    /// ⌃1 to ⌃9) slides it there, its colour turning to that space's on the way.
    @ViewBuilder
    private func spaces(compact: Bool, glass: Bool = true) -> some View {
        let row = HStack(spacing: 2) {
            ForEach(session.workspace.spaces) { space in
                SpaceButton(model: model, space: space, compact: compact, places: places)
            }
        }
        .background {
            if let current = model.space {
                Circle()
                    .fill(current.color.color)
                    .matchedGeometryEffect(id: SpaceButton.place(current.id, compact: compact), in: places, isSource: false)
            }
        }
        if glass {
            row.padding(3).glassEffect(.regular, in: Capsule())
        } else {
            row
        }
    }
}

private struct SpaceButton: View {
    @ObservedObject var model: WindowModel
    let space: Space
    let compact: Bool
    let places: Namespace.ID
    @State private var targeted = false
    @State private var hovering = false

    /// A button's place, apart for each size the row may be drawn at.
    static func place(_ space: UUID, compact: Bool) -> String {
        "\(space.uuidString)\(compact ? "-compact" : "")"
    }

    var body: some View {
        let chosen = model.spaceID == space.id
        let side: CGFloat = compact ? 22 : 26
        Button {
            model.showSpace(space.id)
        } label: {
            Image(systemName: space.symbol)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .foregroundStyle(chosen ? space.color.ink : hovering ? Color.primary : Color.secondary)
                .frame(width: side, height: side)
                // The space on screen is marked by the row's one disc, under this button.
                .matchedGeometryEffect(id: Self.place(space.id, compact: compact), in: places, isSource: true)
                .background {
                    if !chosen { Highlight(hovering: hovering || targeted, shape: Circle()) }
                }
                .overlay {
                    if targeted { Circle().strokeBorder(space.color.color, lineWidth: 2) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(TilePress())
        .animation(.bar, value: chosen)
        .onHover { hovering = $0 }
        .dropDestination(for: TabDrag.self) { items, _ in
            guard let item = items.first, Session.shared.workspace.spaceID(of: item.tab) != space.id else { return false }
            model.move(item.tab, to: space.id)
            return true
        } isTargeted: { targeted = $0 }
        .help(space.name)
        .contextMenu {
            Button("Space Settings…") { model.spacesPanel = .edit(space.id) }
        }
        .accessibilityLabel(space.name)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

private struct DownloadsButton: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var downloads = Downloads.shared

    var body: some View {
        Button {
            model.downloadsShown.toggle()
        } label: {
            Image(systemName: "arrow.down")
                // How much of what is downloading has come, round the arrow.
                .overlay {
                    if downloads.active {
                        Circle()
                            .trim(from: 0, to: downloads.fraction)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 20, height: 20)
                    }
                }
        }
        .buttonStyle(PlainIconStyle())
        .help("Downloads")
        .accessibilityLabel("Downloads")
        .popover(isPresented: $model.downloadsShown, arrowEdge: .top) { DownloadList() }
    }
}
