import AppKit
import PadCore
import SwiftUI
import WebKit

/// Where extensions show in a window (Docs/ExtensionsDesign.md, section 2,
/// "Where extensions show"): the puzzle button, with this space's
/// extensions in its list, and the buttons of those pinned, with their
/// badges; on the sidebar's address row, or at the end of the tabs along
/// the top.
struct ExtensionsButton: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        let unseen = extensions.unseen.contains { $0.hasPrefix(model.spaceID.uuidString) }
        Button {
            model.extensionsShown.toggle()
        } label: {
            Image(systemName: "puzzlepiece.extension")
                .overlay(alignment: .topTrailing) {
                    // Something new to read about one of them: in by scale,
                    // opacity and blur, not suddenly.
                    if unseen {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 3, y: -2)
                            .transition(.mark)
                    }
                }
                .animation(.bar, value: unseen)
        }
        .buttonStyle(PressedIconStyle())
        .help("Extensions")
        .accessibilityLabel("Extensions")
        .accessibilityValue(unseen ? "Something new to read" : "")
        .popover(isPresented: $model.extensionsShown, arrowEdge: .bottom) {
            ExtensionsList(model: model)
        }
        // Right after an install the list opens by itself, with the new one's
        // check; once, not again as the button is drawn anew.
        .onReceive(extensions.$justInstalled) { installed in
            // In the window in front that shows the space.
            guard let installed, installed.space == model.spaceID,
                  Session.shared.allWindows.first(where: { $0.spaceID == installed.space && $0.window?.isKeyWindow == true })
                    ?? Session.shared.allWindows.first(where: { $0.spaceID == installed.space }) === model else { return }
            model.extensionsShown = true
            DispatchQueue.main.async { extensions.tookJustInstalled() }
        }
    }
}

/// The pinned extensions' buttons: each its icon, its badge and its name
/// as help, pressed as Chrome's are (Extensions.run), only those on in the
/// window's space; as many as there is room for, the rest in the puzzle
/// button's list, as Chrome's toolbar keeps them.
struct PinnedExtensions: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        let pinned = extensions.on(in: model.spaceID).filter { $0.pinned == true && !extensions.isIncompatible($0.id) }
        if !pinned.isEmpty {
            FittingRow(spacing: 2) {
                ForEach(pinned) { item in
                    ExtensionActionButton(model: model, item: item)
                }
            }
            .frame(maxWidth: model.tabsInSidebar ? .infinity : nil, alignment: .leading)
        }
    }
}

/// A row of buttons that shows those it has room for, in order, and puts
/// the rest out of sight; at most half a row of tabs it shares a bar with,
/// as an HStack offers the less flexible half first.
struct FittingRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var width: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let next = width + (index == 0 ? 0 : spacing) + size.width
            if let room = proposal.width, next > room { break }
            width = next
        }
        return CGSize(width: width, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var full = false
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            full = full || x + size.width > bounds.maxX + 0.5
            // Out of sight, and of the pointer's way, past the room.
            let at = full ? CGPoint(x: -10_000, y: -10_000) : CGPoint(x: x, y: bounds.midY)
            subview.place(at: at, anchor: .leading, proposal: .unspecified)
            x += size.width + spacing
        }
    }
}

struct ExtensionActionButton: View {
    @ObservedObject var model: WindowModel
    let item: Extensions.Installed
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        // Read again whenever WebKit says an action changed (actionsChanged).
        let _ = extensions.actionsChanged
        let action = extensions.action(for: item.id, in: model)
        let icon = action?.icon(for: CGSize(width: 16, height: 16)) ?? extensions.icon(of: item.id, in: model.spaceID)
        Button {
            extensions.run(item.id, in: model)
        } label: {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge = action?.badgeText, !badge.isEmpty {
                    // Counts don't shift the badge as they change.
                    Text(badge.prefix(4))
                        .font(.system(size: 8, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12, minHeight: 11)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: 6, y: 5)
                        .transition(.mark)
                }
            }
            .animation(.bar, value: action?.badgeText)
        }
        .buttonStyle(PressedIconStyle())
        .disabled(action?.isEnabled == false)
        .help(action?.label.isEmpty == false ? action!.label : item.name)
        .accessibilityLabel(action?.label.isEmpty == false ? action!.label : item.name)
        .accessibilityValue(action?.badgeText ?? "")
    }
}

/// The puzzle button's list: this space's extensions, each with its switch,
/// what its checks found, a pin, and what else it offers; then the store
/// and the other ways to add one.
struct ExtensionsList: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if extensions.installed.isEmpty {
                Text("No extensions yet")
                    .font(.headline)
                    .padding([.horizontal, .top], 14)
                Text("Add one from the Chrome Web Store: its page has an Add to Safience button.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            } else {
                let rows = VStack(spacing: 2) {
                    ForEach(extensions.installed) { item in
                        ExtensionRow(model: model, item: item)
                    }
                }
                .padding(8)
                // Its whole height for a few; scrolled past that.
                if extensions.installed.count <= 5 {
                    rows.fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView { rows }.frame(height: 420)
                }
            }
            Divider().padding(.top, 8)
            HStack(spacing: 12) {
                Button("Chrome Web Store") {
                    model.open(URL(string: "https://chromewebstore.google.com/category/extensions")!, newTab: true)
                }
                Spacer()
                Menu("Add") {
                    Button("Install from File\u{2026}") { extensions.addFromFile(in: model) }
                    Button("Load Unpacked\u{2026}") { extensions.loadUnpacked(in: model) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.link)
            .padding(12)
        }
        .frame(width: 340)
        // Its own height, not the popover's guess.
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { extensions.seen(in: model.spaceID) }
    }
}

private struct ExtensionRow: View {
    @ObservedObject var model: WindowModel
    let item: Extensions.Installed
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        let on = item.spaces.contains(model.spaceID)
        let verdict = extensions.verdicts[model.spaceID]?[item.id]
        let incompatible = extensions.isIncompatible(item.id)
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let icon = extensions.icon(of: item.id, in: model.spaceID) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "puzzlepiece.extension").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            // Centred on the controls' line, as the name is.
            .frame(height: Metrics.control)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if incompatible {
                    // One word, not the long account: the triangle's help has it.
                    Text("Incompatible")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else if on, let verdict, verdict.status == .someFeaturesDontWork {
                    // Nothing said while it works; a warning when it doesn't,
                    // the check's account in its help.
                    Text(verdict.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            // On the controls' line when it is the name alone.
            .frame(minHeight: Metrics.control)
            .help(on && verdict?.status == .someFeaturesDontWork ? verdict.map { $0.lines.joined(separator: " ") } ?? "" : "")
            Spacer(minLength: 4)
            // None for one that can't run: there would be nothing to press.
            if !incompatible {
                Button {
                    extensions.setPinned(item.id, item.pinned != true)
                } label: {
                    // The one glyph turning into the other, not swapped.
                    Image(systemName: item.pinned == true ? "pin.fill" : "pin")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressedIconStyle())
                .help(item.pinned == true ? "Unpin" : "Pin to the Bar")
                .accessibilityLabel(item.pinned == true ? "Unpin \(item.name)" : "Pin \(item.name)")
                .disabled(!on)
            }
            Menu {
                if on, !incompatible {
                    Button("Use \u{201C}\(item.name)\u{201D}") { extensions.run(item.id, in: model) }
                    if extensions.context(item.id, in: model.spaceID)?.optionsPageURL != nil {
                        Button("Options") { extensions.openOptions(item.id, in: model) }
                    }
                    Picker("Site Access (All Spaces)", selection: Binding(get: { item.siteAccess }, set: { extensions.setSiteAccess(item.id, $0) })) {
                        Text("On All Sites It Asks For").tag(Extensions.Installed.SiteAccess.allSites)
                        Text("When I Click It").tag(Extensions.Installed.SiteAccess.onClick)
                    }
                    Divider()
                }
                if item.source == .unpacked {
                    Button("Reload") { extensions.reload(item.id) }
                }
                // Off, it still keeps its data here: this takes that too.
                Button("Remove from This Space") { extensions.remove(item.id, from: model.spaceID) }
                Button("Remove from Safience\u{2026}") { extensions.confirmRemoval(of: item.id, in: model) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: Metrics.control, height: Metrics.control)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More for \(item.name)")
            if incompatible {
                // In the switch's place: it can't be turned on here.
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 14))
                    .frame(width: 26, height: Metrics.control)
                    .help("Incompatible with Safience on this Mac. \(extensions.incompatibility(item.id))")
                    .accessibilityLabel("\(item.name) is incompatible")
            } else {
                Toggle("", isOn: Binding(get: { on }, set: { extensions.turn(item.id, on: $0, in: model.spaceID) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(on ? "Turn Off in This Space" : "Turn On in This Space")
                    .accessibilityLabel("\(item.name) in this space")
                    // On the name's line, as the pin and the menu are.
                    .frame(height: Metrics.control)
            }
        }
        .padding(8)
        // The row's corners round its icon's (4) by the 8 between them.
        .background(RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous).fill(Palette.wash.opacity(0.5)))
    }
}

extension AnyTransition {
    /// A small mark coming and going: from a quarter of its size, unseen
    /// and 4 points blurred.
    static var mark: AnyTransition {
        .scale(scale: 0.25).combined(with: .opacity).combined(with: .modifier(active: Blurred(radius: 4), identity: Blurred(radius: 0)))
    }
}

private struct Blurred: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

/// The bars' icon buttons, as PlainIconStyle draws them, pressed down a
/// little (0.96) as they are clicked.
struct PressedIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlainIconStyle().makeBody(configuration: configuration)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.hover, value: configuration.isPressed)
    }
}
