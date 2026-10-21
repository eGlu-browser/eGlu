import AppKit
import PadCore
import SwiftUI
import WebKit

/// Where extensions show in a window (Docs/ExtensionsDesign.md, section 2,
/// "Where extensions show"): the puzzle button, with this space's
/// extensions in its list, in the order the person drags them to; on the
/// sidebar's address row, or at the end of the tabs along the top.
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

/// The puzzle button's list: this space's extensions, each pressed to use
/// it, with its switch and what else it offers, dragged into the order the
/// person wants; then the store and the other ways to add one.
struct ExtensionsList: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var extensions = Extensions.shared
    /// Other Macs' extensions, offered here (iCloud).
    @ObservedObject private var sync = Sync.shared
    /// The row being dragged to another place.
    @State private var dragging: String?

    var body: some View {
        let offers = extensions.offers(from: sync)
        VStack(alignment: .leading, spacing: 0) {
            if extensions.installed.isEmpty && offers.isEmpty {
                Text("No extensions yet")
                    .font(.headline)
                    .padding([.horizontal, .top], 14)
                Text("Add one from the Chrome Web Store: its page has an Add to Safience button.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
            } else {
                let rows = VStack(alignment: .leading, spacing: 2) {
                    // Whose switches these are: the window's space.
                    if !extensions.installed.isEmpty, let space = Session.shared.workspace.space(model.spaceID) {
                        SectionTitle("In \(space.name)")
                    }
                    ForEach(extensions.installed) { item in
                        ExtensionRow(model: model, item: item)
                            .onDrag {
                                dragging = item.id
                                return NSItemProvider(object: item.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: Reorder(target: item.id, dragging: $dragging))
                            .accessibilityAction(named: "Move Up") { extensions.move(item.id, by: -1) }
                            .accessibilityAction(named: "Move Down") { extensions.move(item.id, by: 1) }
                    }
                    // Other Macs' that aren't on this one (iCloud).
                    if !offers.isEmpty {
                        SectionTitle("On Your Other Macs")
                            .padding(.top, extensions.installed.isEmpty ? 0 : 6)
                        ForEach(offers, id: \.storeID) { offer in
                            OfferRow(model: model, offer: offer)
                        }
                    }
                }
                .padding(8)
                // Its whole height for a few; scrolled past that.
                if extensions.installed.count + offers.count <= 5 {
                    rows.fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView { rows }.frame(height: 420)
                }
            }
            Divider()
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

/// A row moved as another is dragged over it, as a list on the Mac moves.
private struct Reorder: DropDelegate {
    let target: String
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.bar) { Extensions.shared.move(dragging, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// A section's name over its rows, on the rows' leading line.
private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 2)
    }
}

/// Tells the row its button is held down, so the whole row darkens on the
/// press itself, not on its release.
private struct PressReporting: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, now in pressed = now }
    }
}

/// An extension's row, read as a Mac menu's items are: flat until the
/// pointer is on it, then washed, and darker the moment it is pressed. One
/// that can't be used here (off in this space, or incompatible) is dimmed
/// and stays flat, its switch the thing to reach for.
private struct ExtensionRow: View {
    @ObservedObject var model: WindowModel
    let item: Extensions.Installed
    @ObservedObject private var extensions = Extensions.shared
    #if DEBUG
    /// Drawn hovered for a picture of it (-extensionRowHover YES).
    @State private var hovering = UserDefaults.standard.bool(forKey: "extensionRowHover")
    #else
    @State private var hovering = false
    #endif
    @State private var pressed = false

    var body: some View {
        let on = item.spaces.contains(model.spaceID)
        let warning = extensions.warning(item.id, in: model.spaceID)
        let incompatible = extensions.isIncompatible(item.id)
        // Read again whenever WebKit says an action changed (actionsChanged).
        let _ = extensions.actionsChanged
        let action = on ? extensions.action(for: item.id, in: model) : nil
        let usable = on && !incompatible && action?.isEnabled != false
        // One line for every control: the name's, or the middle of name and warning.
        HStack(alignment: .center, spacing: 8) {
            // The extension itself, pressed as its button in Chrome's
            // toolbar is: its popup, or what it does on a press.
            Button {
                model.extensionsShown = false
                extensions.run(item.id, in: model)
            } label: {
                HStack(spacing: 8) {
                    ExtensionIcon(item: item, action: action, space: model.spaceID)
                        .saturation(usable ? 1 : 0)
                        .opacity(usable ? 1 : 0.55)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(usable ? .primary : .secondary)
                            .lineLimit(1)
                        if incompatible {
                            // One word, not the long account: the triangle's help has it.
                            Text("Incompatible")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else if on, let warning {
                            // Nothing said while it works; a warning when it
                            // doesn't, the check's account in its help.
                            Text(warning.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .frame(minHeight: Metrics.control)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressReporting(pressed: $pressed))
            .disabled(!usable)
            .help(on ? warning.map { $0.lines.joined(separator: " ") } ?? (action?.label.isEmpty == false ? action!.label : "Use \(item.name)") : "")
            .accessibilityLabel(action?.label.isEmpty == false ? action!.label : item.name)
            .accessibilityValue(action?.badgeText ?? "")
            Menu {
                if on, !incompatible {
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
                // The person's word over the checks', until it updates.
                if extensions.saidLooksWrong(item.id) {
                    Button("Show Its Warnings Again") { extensions.setLooksWrong(item.id, false) }
                } else if extensions.isWarned(item.id) {
                    Button("This Looks Wrong") { extensions.setLooksWrong(item.id, true) }
                }
                Button("Report a Problem\u{2026}") { ExtensionReport.show(item.id, in: model) }
                Divider()
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
            .frame(width: Metrics.control, height: Metrics.control)
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
                    .frame(width: 26, height: Metrics.control)
            }
        }
        .padding(8)
        // The row's corners round its icon's (4) by the 8 between them.
        // In under the pointer quickly; down at once on the press, back up softly.
        .background {
            RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous)
                .fill(pressed ? Palette.press : hovering && usable ? Palette.hover : Color.clear)
                .animation(pressed ? nil : .hover, value: pressed)
                .animation(.hover, value: hovering)
        }
        .onHover { hovering = $0 }
    }
}

/// An extension's icon in its row: the one its button shows on this tab
/// if it set one, with its badge (a count, a word) at the corner.
private struct ExtensionIcon: View {
    let item: Extensions.Installed
    let action: WKWebExtension.Action?
    let space: UUID
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        Group {
            if let icon = action?.icon(for: CGSize(width: 20, height: 20)) ?? extensions.icon(of: item.id, in: space) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "puzzlepiece.extension").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
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
                    .offset(x: 5, y: 4)
                    .transition(.mark)
            }
        }
        .animation(.bar, value: action?.badgeText)
    }
}

/// Another Mac's extension that isn't on this one: its name, and Add,
/// which downloads it here and asks in this Mac's own sheet.
private struct OfferRow: View {
    @ObservedObject var model: WindowModel
    let offer: SyncExtension
    @ObservedObject private var extensions = Extensions.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .frame(height: Metrics.control)
            // Not here yet: dimmed, its Add the thing to press.
            Text(offer.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Menu {
                Button("Don\u{2019}t Offer on This Mac") { extensions.decline(offer.storeID) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: Metrics.control, height: Metrics.control)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More for \(offer.title)")
            Button("Add") {
                extensions.add(storeID: offer.storeID, in: model, access: offer.siteAccess == "onClick" ? .onClick : .allSites)
            }
            .controlSize(.small)
            .disabled(extensions.busy != nil)
            .accessibilityLabel("Add \(offer.title) to This Mac")
        }
        .padding(8)
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
