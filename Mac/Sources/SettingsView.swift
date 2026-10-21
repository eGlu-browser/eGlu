import AppKit
import PadCore
import SwiftUI

/// Safience › Settings (⌘,): General, iCloud, Spaces, Pinned Tabs, and Ads
/// and Trackers, along the toolbar as a Mac app's settings are.
///
/// Every pane is the same width, so the window keeps its width and only its
/// height changes from one to the next, and every pane is a grouped form,
/// so its sections, rows and notes sit in the same places. What is dragged
/// into another order (the spaces, the pinned tabs) is a list inside its
/// section: a form's rows can't be dragged. The window opens on the pane it
/// was last on.
struct MacSettings: View {
    @AppStorage("settingsPane") private var pane = SettingsPane.general

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralSettings().settingsPane(height: 560)
            }
            Tab("iCloud", systemImage: "icloud", value: .iCloud) {
                CloudSettings().settingsPane(height: 250)
            }
            Tab("Spaces", systemImage: "square.stack", value: .spaces) {
                SpaceSettings().settingsPane(height: 600)
            }
            Tab("Pinned Tabs", systemImage: "pin", value: .pinned) {
                PinnedTabSettings().settingsPane(height: 520)
            }
            Tab("Ads and Trackers", systemImage: "shield", value: .blocking) {
                BlockingSettings().settingsPane(height: 520)
            }
        }
    }
}

enum SettingsPane: String {
    case general, iCloud, spaces, pinned, blocking
}

private extension View {
    /// One width for every pane; each its own height.
    func settingsPane(height: CGFloat) -> some View {
        formStyle(.grouped)
            .frame(width: SettingsMetrics.width, height: height)
    }
}

private enum SettingsMetrics {
    static let width: CGFloat = 600
    /// A row of a list inside a section, as high as the form's own rows.
    static let row: CGFloat = 34
}

// MARK: General

private struct GeneralSettings: View {
    @ObservedObject private var session = Session.shared
    @State private var isDefault = DefaultBrowser.isDefault

    var body: some View {
        Form {
            Section {
                // Nil is the Mac's own way: in a sidebar.
                Picker("Tabs", selection: Binding(get: { session.preferences.tabsPlacement ?? .sidebar },
                                                  set: { session.preferences.tabsPlacement = $0 })) {
                    Text("In a Sidebar").tag(Preferences.TabsPlacement.sidebar)
                    Text("Along the Top").tag(Preferences.TabsPlacement.top)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            } header: {
                Text("Window")
            }
            Section {
                Picker("Search engine", selection: $session.preferences.engine) {
                    ForEach(Destination.engines, id: \.id) { engine in
                        Text(engine.name).tag(engine.id)
                    }
                }
                Toggle("Suggestions as you type", isOn: $session.preferences.searchSuggestions)
            } header: {
                Text("Search")
            } footer: {
                Note("Your search engine hears what you type into the command bar, with no cookies and nothing that says who you are. A search shows its words in the address.")
            }
            if session.hasIntelligence {
                Section {
                    Toggle("Hand off the page to another app", isOn: $session.preferences.handoff)
                } header: {
                    Text("Handoff")
                } footer: {
                    Note("The page as text, with its address, goes to the app you pick in the share menu, an assistant such as Claude or ChatGPT, where you ask your question. Apple Intelligence tells on this Mac whether it is an article, a landing page or a web app. Nothing goes anywhere before you pick an app.")
                }
            }
            Section {
                LabeledContent("Default browser") {
                    if isDefault {
                        Label("Safience", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Make Default…") {
                            DefaultBrowser.ask()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isDefault = DefaultBrowser.isDefault }
                        }
                    }
                }
            } footer: {
                Note(isDefault ? "Links you open in other apps open here." : "Links you open in other apps open in your default browser.")
            }
        }
        .onAppear { isDefault = DefaultBrowser.isDefault }
    }
}

// MARK: iCloud

/// Spaces, their bookmarks and pinned tabs, and each device's open tabs, in
/// the user's own iCloud (Sync.swift, the iPad's), with the iPhone and iPad
/// signed in to the same Apple Account.
private struct CloudSettings: View {
    @ObservedObject private var session = Session.shared
    @ObservedObject private var sync = Sync.shared

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: $session.preferences.iCloudSync)
                    .disabled(!Session.canSync)
                if !Session.canSync {
                    Label("This copy of Safience isn't signed for iCloud. A copy from the App Store, or one built with your team, syncs.",
                          systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.secondary)
                } else if session.preferences.iCloudSync, let problem = sync.problem {
                    Label(problem, systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Note("Your spaces, with their names, colours, icons, bookmarks and pinned tabs, show on your iPhone and iPad, and each device's open tabs show in the others' command bars. Sign-ins and what sites store stay on each device. Turning it on joins spaces with the same name and keeps both sets of bookmarks; removing a space removes it everywhere.")
            }
        }
    }
}

// MARK: Spaces

/// Every space, in the order ⌃1 to ⌃9 go to them, to drag into another
/// order, with + and − under them as a Mac's lists have; and the chosen
/// one's name, colour and icon in the section below.
private struct SpaceSettings: View {
    @ObservedObject private var session = Session.shared
    @State private var chosen: UUID?
    @State private var name = ""

    var body: some View {
        let spaces = session.workspace.spaces
        let space = chosen.flatMap { session.workspace.space($0) }
        Form {
            Section {
                List(selection: $chosen) {
                    ForEach(spaces) { space in
                        SpaceSettingsRow(space: space)
                            .tag(space.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .onMove { offsets, destination in
                        session.change { $0.moveSpaces(from: offsets, to: destination) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(spaces.count <= Self.rowsShown)
                .frame(height: CGFloat(min(spaces.count, Self.rowsShown)) * SettingsMetrics.row)
                AddRemove(canRemove: spaces.count > 1 && space != nil, add: add) {
                    if let chosen { remove(chosen) }
                }
            } header: {
                Text("Spaces")
            } footer: {
                Note("Drag a space to change its place. ⌃1 to ⌃9 go to the spaces in this order.")
            }
            if let space {
                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Colour") {
                        SpaceColours(space: space)
                    }
                    LabeledContent("Icon") {
                        SpaceSymbols(space: space)
                            .padding(.vertical, 4)
                    }
                } header: {
                    Text(space.name)
                }
            }
        }
        .onAppear {
            if chosen == nil { chosen = spaces.first?.id }
            name = space?.name ?? ""
        }
        .onChange(of: chosen) { _, id in name = id.flatMap { session.workspace.space($0)?.name } ?? "" }
        .onChange(of: name) { _, now in
            guard let chosen, session.workspace.space(chosen)?.name != now else { return }
            session.change { $0.renameSpace(chosen, to: now) }
        }
    }

    /// Past this many the list scrolls, so the chosen space's settings stay in view.
    private static let rowsShown = 6

    private func add() {
        let id = session.change { $0.addSpace(named: "Space \(session.workspace.spaces.count + 1)") }
        chosen = id
    }

    private func remove(_ id: UUID) {
        guard let space = session.workspace.space(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(space.name)?"
        alert.informativeText = "Its \(space.tabs.count) tabs close, and its sign-ins and bookmarks are erased from this Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove Space")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let finish = { (answer: NSApplication.ModalResponse) in
            guard answer == .alertFirstButtonReturn else { return }
            Session.shared.removeSpace(id)
            chosen = Session.shared.workspace.spaces.first?.id
        }
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }
}

/// A space in Settings' list: the handle, its icon on its colour, its name,
/// and how many tabs it has.
private struct SpaceSettingsRow: View {
    let space: Space

    var body: some View {
        HStack(spacing: 8) {
            DragHandle()
            Image(systemName: space.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(space.color.ink)
                .frame(width: 22, height: 22)
                .background(space.color.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(space.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(space.tabs.count == 1 ? "1 tab" : "\(space.tabs.count) tabs")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(height: SettingsMetrics.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Drag to change the order.")
    }
}

/// + and − at the foot of a list, as a Mac's lists have them.
private struct AddRemove: View {
    let canRemove: Bool
    let add: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: add) {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help("New Space")
            .accessibilityLabel("New Space")
            Divider().frame(height: 14)
            Button(action: remove) {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(!canRemove)
            .help("Remove Space…")
            .accessibilityLabel("Remove Space")
            Spacer()
        }
        .buttonStyle(.borderless)
    }
}

// MARK: Pinned Tabs

/// Each space's pinned tabs, in their order, to drag into another and to
/// show or hide in this Mac's sidebar. A hidden one stays pinned, in its
/// place and on your other devices: only this Mac's sidebar goes without
/// it (Preferences.hiddenPinnedTabs). The order is the space's, everywhere.
private struct PinnedTabSettings: View {
    @ObservedObject private var session = Session.shared

    var body: some View {
        let spaces = session.workspace.spaces.filter { $0.pinnedCount > 0 }
        Form {
            if spaces.isEmpty {
                Section {
                    Text("No pinned tabs yet.")
                        .foregroundStyle(.secondary)
                } footer: {
                    Note("Pin a tab from its menu, or with ⌘D, to keep it at the top of the sidebar.")
                }
            }
            ForEach(spaces) { space in
                Section {
                    let pinned = Array(space.tabs.prefix(space.pinnedCount))
                    List {
                        ForEach(pinned) { tab in
                            PinnedSettingsRow(tab: tab, shown: shown(tab.id))
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        }
                        .onMove { offsets, destination in
                            session.change { $0.movePinned(in: space.id, from: offsets, to: destination) }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(pinned.count) * SettingsMetrics.row)
                } header: {
                    Label(space.name, systemImage: space.symbol)
                } footer: {
                    if space.id == spaces.last?.id {
                        Note("Drag a tab to change its place; the order is the space's, everywhere it shows. A hidden tab stays pinned and keeps its place: only this Mac's sidebar leaves it out, and your iPhone and iPad choose for themselves.")
                    }
                }
            }
        }
    }

    private func shown(_ tab: UUID) -> Binding<Bool> {
        Binding(get: { !session.preferences.hiddenPinnedTabs.contains(tab) },
                set: { show in
                    if show {
                        session.preferences.hiddenPinnedTabs.remove(tab)
                    } else {
                        session.preferences.hiddenPinnedTabs.insert(tab)
                    }
                })
    }
}

/// A pinned tab in Settings' list: the handle, its icon and name, and
/// whether this Mac's sidebar shows it.
private struct PinnedSettingsRow: View {
    let tab: TabRecord
    let shown: Binding<Bool>

    var body: some View {
        HStack(spacing: 8) {
            DragHandle()
            SiteIconView(url: tab.pinned ?? tab.url, size: 18)
            Text(tab.label)
                .lineLimit(1)
                .foregroundStyle(shown.wrappedValue ? .primary : .secondary)
            Spacer(minLength: 8)
            Toggle("Show in Sidebar", isOn: shown)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .frame(height: SettingsMetrics.row)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Ads and Trackers

/// Blocking on or off, and each filter list with a switch, what it takes
/// away, whose it is (as its licence asks) and how its copy stands.
private struct BlockingSettings: View {
    @ObservedObject private var session = Session.shared
    @ObservedObject private var blocker = ContentBlocker.shared

    var body: some View {
        Form {
            Section {
                Toggle("Block ads and trackers", isOn: $session.preferences.blocksContent)
            } footer: {
                Note(blocker.summary)
            }
            Section("Filter Lists") {
                ForEach(ContentBlocking.lists) { list in
                    Toggle(isOn: uses(list)) {
                        Text(list.name)
                        Text(list.about)
                        Text(note(for: list))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!session.preferences.blocksContent)
        }
    }

    private func uses(_ list: FilterList) -> Binding<Bool> {
        Binding(get: { session.preferences.uses(list, languages: ContentBlocker.languages, region: ContentBlocker.region) },
                set: { session.preferences.filterLists[list.id] = $0 })
    }

    private func note(for list: FilterList) -> String {
        let credit = "By " + list.credit
        switch blocker.states[list.id] ?? .off {
        case .off:
            return credit
        case .waiting:
            return credit + " · Getting ready…"
        case .missing:
            return credit + " · Not downloaded yet. Safience tries again when it opens."
        case .ready(let made, let rules):
            let count = "\(rules.formatted(.number)) rules"
            guard let made else { return credit + " · " + count }
            return credit + " · " + made.formatted(date: .abbreviated, time: .omitted) + " · " + count
        }
    }
}

/// A section's note, under it: smaller and quieter than its rows, wrapping
/// as long as it needs.
private struct Note: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
