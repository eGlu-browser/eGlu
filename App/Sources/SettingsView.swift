import GameController
import PadCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings (⌃⌥,). Short, because most of what this app does is meant to
/// stay out of sight; the switches here are for checking and adjusting the
/// bridges on a real iPad.
///
/// A section has words under it only for what a person has to know to act:
/// a step to take somewhere else, what a choice does to their data, where
/// what they type is sent, whose work a list is, or that something failed.
/// What a control's own label says is not said again under it.
struct SettingsView: View {
    @ObservedObject var session: Session
    /// The space of the window Settings opened from, which imports go into.
    let spaceID: UUID
    /// The part to open at, when the address bar sent one (SettingsAnchor).
    var anchor: SettingsAnchor?
    /// Which layouts' parts to have (Device.settingsLayouts): a phone-width
    /// window's (one bar at the bottom, Desktop View), an iPad's (the tabs'
    /// place, the trackpad, shortcuts), or, on the iPhone Duo, both.
    var phoneLayout = Device.phone
    var padLayout = !Device.phone
    let done: () -> Void
    /// A keyboard with keys is attached: a phone's Settings then have the
    /// keyboard's parts too (its shortcuts work, Browser.phoneKeys).
    @State private var keyboard = GCKeyboard.coalesced != nil
    @State private var importing = false
    @State private var imported: (title: String, message: String)?
    @State private var clearingHistory = false
    /// The part the address bar sent Settings to, for a moment after it opens there.
    @State private var lit: SettingsAnchor?
    /// Apple Intelligence on this device, as Settings opens (Intelligence.swift).
    private let intelligence = IntelligenceStatus.current

    /// Where what is typed goes, and that Apple Intelligence stays on the device where it is there.
    private var searchFooter: String {
        var text = "What you type goes to your search engine for suggestions, without cookies. Complete addresses are excluded, but text typed before an address is recognized may be sent. Turn this off to keep address-bar typing on your device."
        if intelligence == .ready { text += " Apple Intelligence works on this \(Device.name) and sends nothing anywhere." }
        return text
    }

    var body: some View {
        NavigationStack {
            // The reader is how Settings opens at a part (anchor); every
            // section's header is a place it can go (SettingsHeader).
            ScrollViewReader { scroller in
            Form {
                DefaultBrowserSection()

                CloudSection(session: session)

                AppIconSection()

                if phoneLayout {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cursor speed")
                            HStack(spacing: 10) {
                                Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                                Slider(value: $session.preferences.cursorSpeed, in: DesktopView.cursorSpeeds)
                                    .accessibilityLabel("Cursor speed")
                                Image(systemName: "hare.fill").foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        SettingsHeader("Desktop View", .desktopView)
                    }
                    Section {
                        // Its choices as rows: a menu beside a label this long has no room on a phone.
                        Picker("The address bar shows", selection: $session.preferences.address) {
                            Text("The page's address").tag(AddressMode.always)
                            Text("The page's title").tag(AddressMode.automatic)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        SettingsHeader("The address bar shows", .addressBar)
                    } footer: {
                        Text("Sign-in pages always show their address.")
                    }
                }
                if padLayout {
                Section {
                    // The name's capitals and the pictures' top edge as far from the
                    // row's top as the name is from its left (17 points, measured).
                    HStack(alignment: .top) {
                        Text("Tabs")
                            .padding(.top, -1.5)
                        Spacer()
                        // Nil is the iPad's own way: along the top.
                        TabsLayoutPicker(selection: Binding {
                            session.preferences.tabsPlacement ?? .top
                        } set: {
                            session.preferences.tabsPlacement = $0
                        })
                        .padding(.top, 2)
                        .padding(.bottom, 6)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Tabs")
                    if session.preferences.tabsPlacement == .sidebar {
                        Toggle("Show the sidebar", isOn: $session.preferences.tabBar)
                    } else {
                        // Asked once: the phone layout's own part above already asks it.
                        if !phoneLayout {
                            Picker("The tab you are on shows", selection: $session.preferences.address) {
                                Text("Its address").tag(AddressMode.always)
                                Text("Its title").tag(AddressMode.automatic)
                            }
                        }
                        Toggle("Show the tab bar", isOn: $session.preferences.tabBar)
                    }
                } header: {
                    SettingsHeader("Window", .window)
                } footer: {
                    if session.preferences.tabsPlacement == .sidebar {
                        Text("With the sidebar hidden, ⌃⌥K lists every tab.")
                    } else {
                        Text("Sign-in pages always show their address. With the tab bar hidden, ⌃⌥K lists every tab.")
                    }
                }
                }

                Section {
                    NavigationLink {
                        SpaceList(session: session)
                    } label: {
                        HStack {
                            Text("Spaces")
                            Spacer()
                            Text("\(session.workspace.spaces.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    NavigationLink {
                        PinnedTabList(session: session)
                    } label: {
                        HStack {
                            Text("Pinned Tabs")
                            Spacer()
                            Text("\(session.workspace.spaces.reduce(0) { $0 + $1.pinnedCount })")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Button("Import Bookmarks into \(session.workspace.space(spaceID)?.name ?? "This Space")…") {
                        importing = true
                    }
                } header: {
                    SettingsHeader("Spaces and bookmarks", .spaces)
                } footer: {
                    Text("Import a bookmarks file exported from Chrome or Safari.")
                }

                Section {
                    Stepper(value: $session.preferences.limits.lightOffScreen, in: 0...6) {
                        Text("Light tabs kept open: \(session.preferences.limits.lightOffScreen)")
                    }
                } header: {
                    SettingsHeader("Memory", .memory)
                } footer: {
                    Text("Tabs past this number freeze and load again when you open them.")
                }

                if padLayout {
                Section {
                    Picker("Two-finger scroll", selection: $session.preferences.wheel) {
                        Text("As each site needs").tag(WheelMode?.none)
                        Text("Bridge when WebKit sends nothing").tag(WheelMode?.some(.auto))
                        Text("Always bridge").tag(WheelMode?.some(.always))
                        Text("Never bridge").tag(WheelMode?.some(.off))
                    }
                    Picker("Tab and arrow keys", selection: $session.preferences.keys) {
                        Text("As each site needs").tag(Override.site)
                        Text("Send to the page first").tag(Override.on)
                        Text("Leave to the system").tag(Override.off)
                    }
                    Toggle("Show pages' own cursors", isOn: $session.preferences.pageCursors)
                } header: {
                    SettingsHeader("Trackpad and keyboard", .trackpad)
                }
                } else if keyboard {
                Section {
                    Picker("Tab and arrow keys", selection: $session.preferences.keys) {
                        Text("As each site needs").tag(Override.site)
                        Text("Send to the page first").tag(Override.on)
                        Text("Leave to the system").tag(Override.off)
                    }
                } header: {
                    SettingsHeader("Keyboard", .trackpad)
                }
                }

                Section {
                    Picker("Search engine", selection: $session.preferences.engine) {
                        ForEach(Destination.engines, id: \.id) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
                    Toggle("Search engine suggestions", isOn: $session.preferences.searchSuggestions)
                    // Only where Apple Intelligence is there to suggest: not turned off, not still getting ready.
                    if intelligence == .ready {
                        Toggle("Suggest with Apple Intelligence", isOn: $session.preferences.intelligence)
                    }
                } header: {
                    SettingsHeader("Search", .search)
                } footer: {
                    Text(searchFooter)
                }

                Section {
                    Picker("Keep history for", selection: $session.preferences.historyRetention) {
                        ForEach(HistoryRetention.allCases, id: \.self) { retention in
                            Text(retention.label).tag(retention)
                        }
                    }
                    Button("Clear History…") { clearingHistory = true }
                } header: {
                    SettingsHeader("History", .history)
                } footer: {
                    Text("Each space keeps its own history. Pages older than this are deleted.")
                }
                .sheet(isPresented: $clearingHistory) {
                    ClearHistoryView(spaceID: spaceID) { clearingHistory = false }
                }

                BlockingSection(session: session)

                LinkMenuSection(session: session)

                // Nothing of Handoff without Apple Intelligence: not even its switch.
                if session.hasIntelligence {
                    HandoffSection(session: session)
                }

                if Device.diagnostics {
                    Section {
                        Toggle("Show diagnostics", isOn: $session.preferences.diagnostics)
                    } header: {
                        SettingsHeader("Diagnostics", .diagnostics)
                    }
                }

                if padLayout || keyboard {
                Section {
                    // By the menu each is in, as the command bar lists them.
                    ForEach(ShortcutGroup.allCases.flatMap(\.commands).filter { Device.offers($0, compact: !padLayout) }, id: \.self) { command in
                        HStack {
                            Text(command.title)
                            Spacer()
                            KeyCaps(keys: Shortcuts.chord(for: command)?.caps ?? [])
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(command.title)
                        .accessibilityValue(Shortcuts.chord(for: command)?.label ?? "")
                    }
                    HStack {
                        Text("A tab by its place, the last one")
                        Spacer()
                        Text("⌃⌥1 … ⌃⌥9").foregroundStyle(.secondary).monospaced()
                    }
                } header: {
                    SettingsHeader("Shortcuts", .shortcuts)
                }

                Section("Known limitations") {
                    Text(Device.phone
                         ? "iOS keeps its own shortcuts (⌘Tab, ⌘Space, the Globe key); no app can give those to a page."
                         : "iPadOS keeps its own shortcuts (⌘Tab, ⌘Space, the Globe key) and its three- and four-finger gestures; no app can give those to a page.")
                    Text("With VoiceOver on, ⌃⌥ is VoiceOver's own key; type a command's name in the address bar instead.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.html, .zip]) { result in
                guard case .success(let file) = result else { return }
                // Readable until the import has read it, which it does away from the main thread.
                let scoped = file.startAccessingSecurityScopedResource()
                session.importBookmarks(from: file, into: spaceID) { outcome in
                    if scoped { file.stopAccessingSecurityScopedResource() }
                    imported = outcome
                }
            }
            .alert(imported?.title ?? "", isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } })) {
                Button("OK") { imported = nil }
            } message: {
                Text(imported?.message ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
            .environment(\.settingsLit, lit)
            .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in keyboard = true }
            .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
                keyboard = GCKeyboard.coalesced != nil
            }
            // Sent to a part, the list goes to that section's first row, at
            // the top: its header, just above, would be under the title bar.
            // This much more kept clear there leaves the header in view. (A
            // list scrolls a row to its top, middle or bottom, nowhere between.)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: anchor == nil ? 0 : SettingsHeader.room)
                    .allowsHitTesting(false)
            }
            .task {
                guard let anchor else { return }
                // Once the list has its rows: before that there is nowhere to scroll to.
                try? await Task.sleep(for: .milliseconds(120))
                scroller.scrollTo(anchor, anchor: .top)
                lit = anchor
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.6)) { lit = nil }
            }
            }
        }
    }

}

extension EnvironmentValues {
    /// The part of Settings that was just gone to (SettingsView.lit).
    @Entry var settingsLit: SettingsAnchor?
}

/// A section's header in Settings, which is also a place the address bar
/// can send Settings to (SettingsAnchor): the list scrolls to it, and it
/// shows in the accent colour for a moment, so the eye finds the section
/// among the others on screen (the last ones can't be brought to the top).
struct SettingsHeader: View {
    let title: String
    let anchor: SettingsAnchor
    @Environment(\.settingsLit) private var lit

    /// A header's height with the gap over it, about: what the list keeps
    /// clear at its top when it is sent to a section (SettingsView).
    static let room: CGFloat = 44

    init(_ title: String, _ anchor: SettingsAnchor) {
        self.title = title
        self.anchor = anchor
    }

    var body: some View {
        Text(title)
            // Left as the list draws its headers but while it is lit.
            .foregroundStyle(lit == anchor ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.foreground))
            .id(anchor)
    }
}

/// Handoff (Handoff.swift): its switch. What goes beside the file is the
/// page's address and a line for the question, which is the person's to
/// ask in the app they pick (Handoff.prompt).
private struct HandoffSection: View {
    @ObservedObject var session: Session

    var body: some View {
        Section {
            Toggle("Hand off the page to another app", isOn: $session.preferences.handoff)
        } header: {
            SettingsHeader("Handoff", .handoff)
        } footer: {
            Text("The page goes as text to the app you pick, such as Claude or ChatGPT, for your question. Nothing leaves this \(Device.name) until you pick one.")
        }
    }
}

/// A link's menu, and the way to the sites that keep their own (OwnMenus).
private struct LinkMenuSection: View {
    @ObservedObject var session: Session

    var body: some View {
        let kept = OwnMenus.builtIn.filter { session.preferences.keepsOwnMenus(onHost: $0.host) }.count
            + session.preferences.addedOwnMenuSites.count
        Section {
            NavigationLink {
                OwnMenuSites(session: session)
            } label: {
                LabeledContent("Sites with their own menus") {
                    Text(kept.formatted(.number)).monospacedDigit()
                }
            }
        } header: {
            SettingsHeader("Link menu", .linkMenu)
        } footer: {
            Text("On web apps with their own menus, Safience's link menu stays out of the way.")
        }
    }
}

/// Settings › Link menu › Sites with their own menus: the built-in ones,
/// each with a switch, and one's own, added by host.
private struct OwnMenuSites: View {
    @ObservedObject var session: Session
    @State private var typed = ""

    var body: some View {
        List {
            Section {
                ForEach(session.preferences.addedOwnMenuSites, id: \.self) { host in
                    Text(host)
                }
                .onDelete { offsets in
                    let hosts = session.preferences.addedOwnMenuSites
                    for index in offsets where hosts.indices.contains(index) {
                        session.preferences.setKeepsOwnMenus(false, onHost: hosts[index])
                    }
                }
                HStack {
                    TextField("app.example.com", text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(OwnMenus.host(typed: typed) == nil)
                }
            } header: {
                Text("Your sites")
            } footer: {
                Text("A site covers every address under it: example.com covers app.example.com too.")
            }
            Section {
                ForEach(OwnMenus.builtIn, id: \.host) { site in
                    Toggle(isOn: keeps(site.host)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.name)
                            Text(site.host)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Built in")
            } footer: {
                Text("Turn one off for Safience's link menu on that site.")
            }
        }
        .navigationTitle("Sites with their own menus")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func keeps(_ host: String) -> Binding<Bool> {
        Binding(get: { session.preferences.keepsOwnMenus(onHost: host) },
                set: { session.preferences.setKeepsOwnMenus($0, onHost: host) })
    }

    private func add() {
        guard let host = OwnMenus.host(typed: typed) else { return }
        session.preferences.setKeepsOwnMenus(true, onHost: host)
        typed = ""
    }
}

/// Ads and trackers (ContentBlocker): on or off, the way to the filter lists,
/// and the sites it is off for.
private struct BlockingSection: View {
    @ObservedObject var session: Session
    @ObservedObject private var blocker = ContentBlocker.shared

    var body: some View {
        Section {
            Toggle("Block ads and trackers", isOn: $session.preferences.blocksContent)
            if session.preferences.blocksContent {
                NavigationLink {
                    FilterListsView(session: session)
                } label: {
                    LabeledContent("Filter lists") {
                        let on = session.preferences.filterLists(languages: ContentBlocker.languages, region: ContentBlocker.region).count
                        Text("\(on) on").monospacedDigit()
                    }
                }
                LabeledContent("Rules") {
                    if let shown = blocker.shown {
                        Text(shown.rules.formatted(.number)).monospacedDigit()
                    } else {
                        Text("Getting ready…")
                    }
                }
            }
            if session.preferences.blocksContent && !session.preferences.unblockedSites.isEmpty {
                let count = session.preferences.unblockedSites.count
                Button("Block on All Sites Again (\(count) allowed)") {
                    session.preferences.unblockedSites = []
                }
            }
        } header: {
            SettingsHeader("Ads and trackers", .blocking)
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "A site's menu can allow them on that site."
        if session.preferences.blocksContent, let dropped = blocker.shown?.dropped, dropped > 0 {
            text += " \(dropped) of WebKit's rule lists couldn't be made, so some ads still show."
        }
        return text
    }
}

/// Settings › Ads and trackers › Filter lists: every list there is, each
/// with a switch, what it takes away, whose it is (as its licence asks) and
/// the day the copy in use was made.
private struct FilterListsView: View {
    @ObservedObject var session: Session
    @ObservedObject private var blocker = ContentBlocker.shared

    var body: some View {
        List {
            Section {
                ForEach(ContentBlocking.lists) { list in
                    Toggle(isOn: uses(list)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.name)
                            Text(list.about)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(note(for: list))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                Text("EasyList, EasyPrivacy and YousList come with Safience; the others download when you turn them on.")
            }
        }
        .navigationTitle("Filter lists")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func uses(_ list: FilterList) -> Binding<Bool> {
        Binding(get: { session.preferences.uses(list, languages: ContentBlocker.languages, region: ContentBlocker.region) },
                set: { session.preferences.filterLists[list.id] = $0 })
    }

    /// Whose the list is, and how the copy in use stands.
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

/// The Home Screen icon: Safience, the app's own, or one of the alternates the
/// asset catalog compiles in (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in
/// project.yml), each the globe and pointer drawn in a style of its own. The system keeps the choice, so nothing here stores it; each
/// preview is that icon rendered in light and dark, so it matches the screen.
private struct AppIconSection: View {
    private struct Choice: Identifiable {
        /// The alternate's name, as the project lists it; nil is the app's own icon.
        let name: String?
        let title: String
        var id: String { title }
    }

    /// Each alternate is compiled under the name it is shown by. The system
    /// keeps a chosen icon by that name, so renaming one drops it for whoever
    /// had chosen it (as Diazo, Lilac, Oxide, Citrus and Midnight were dropped
    /// when they became Designer, Vista, Hardcover, Punk and Astro).
    private static let choices = [
        Choice(name: nil, title: "Safience"),
        Choice(name: "Designer", title: "Designer"),
        Choice(name: "Engineer", title: "Engineer"),
        Choice(name: "Signal", title: "Signal"),
        Choice(name: "Vista", title: "Vista"),
        Choice(name: "Hardcover", title: "Hardcover"),
        Choice(name: "Punk", title: "Punk"),
        Choice(name: "Astro", title: "Astro"),
    ]

    @State private var current = UIApplication.shared.alternateIconName
    @State private var failure: String?

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 16) {
                    ForEach(Self.choices) { choice in
                        let chosen = choice.name == current
                        Button { choose(choice) } label: {
                            VStack(spacing: 6) {
                                Image("IconPreview\(choice.name ?? "Safience")")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .padding(4)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2.5)
                                    }
                                Text(choice.title)
                                    .font(.caption)
                                    .foregroundStyle(chosen ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            } header: {
                SettingsHeader("App icon", .appIcon)
            } footer: {
                // Nothing under the icons but the system's refusal, when there is one.
                if let failure { Text(failure) }
            }
        }
    }

    private func choose(_ choice: Choice) {
        guard choice.name != current else { return }
        // The ring moves at the tap; the system's own notice comes after.
        let previous = current
        current = choice.name
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(choice.name)
                failure = nil
            } catch {
                // The system refused (it does while the app is not in front, or when it is busy): say so, put the ring back.
                current = previous
                failure = "The icon couldn't change: \(error.localizedDescription)"
            }
        }
    }
}
