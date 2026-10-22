import AppKit
import PadCore
import SwiftUI

/// What the command bar offers as an address is typed: the space's tabs and
/// pinned tabs, the other spaces and their tabs, the space's tabs on other
/// devices (Sync), the browser's commands, the space's bookmarks, and the
/// search engine's suggestions (Autocomplete in PadCore), each row saying
/// which it is. The iPad's Suggestions: where Apple Intelligence is on, its
/// on-device model adds what the words mean once typing pauses, the space's
/// history among what it reads (Intelligence.swift). ↑ and ↓ choose a row
/// and Return takes it; with none chosen, Return sends what was typed.
///
/// Opened for a new tab (⌘T), the field starts empty with everything listed
/// under headings, each command with its keys: the cheat sheet, in the bar.
@MainActor
final class Suggestions: ObservableObject {
    @Published private(set) var rows: [Suggestion] = []
    /// The row ↑ and ↓ have chosen; nil for the text as typed.
    @Published private(set) var selection: Int?
    /// The rows are everything there is, nothing typed yet: they show under headings.
    @Published private(set) var listing = false
    /// What the field held as typing began: the page's address, not a query.
    private var start = ""
    private var query = ""
    private var wide = false
    private var local: [Suggestion] = []
    /// The engine's words, and the text they answered.
    private var answer: (query: String, words: [String]) = ("", [])
    private var asking: Task<Void, Never>?
    /// The space's history for the text, and the text and the space it answered.
    private var remembered: (query: String, space: UUID?, pages: [HistoryPage]) = ("", nil, [])
    private var recalling: Task<Void, Never>?
    /// The engine was asked for this text: the model's searches stay out.
    private var asksEngine = false
    /// Apple Intelligence's model, made when words are first typed that it may be asked about.
    private lazy var mind = IntelligenceStatus.model()
    /// Whether the model can answer, asked once for a turn at the field.
    private var mindReady: Bool?
    /// What the model found the words mean, its searches, and the text it answered.
    private var thought: (query: String, meant: [Suggestion], searches: [Suggestion]) = ("", [], [])
    private var thinking: Task<Void, Never>?
    private var index: (made: Autocomplete.Index, space: UUID, tab: UUID?, spaces: [Space])?

    var selected: Suggestion? {
        selection.flatMap { rows.indices.contains($0) ? rows[$0] : nil }
    }

    /// Typing starts: in a field holding the page's address, or, for a new
    /// tab, in an empty one over everything there is to choose.
    func begin(in window: WindowModel, purpose: CommandBarPurpose) -> String {
        end()
        wide = purpose == .newTab
        start = wide ? "" : window.url.map { Destination.editable($0, engine: Session.shared.preferences.engine) } ?? ""
        query = start
        if wide {
            local = index(for: window).everything
            listing = true
            show()
        }
        return start
    }

    func typed(_ text: String, in window: WindowModel) {
        guard text != query else { return }
        query = text
        selection = nil
        let nothing = text.trimmingCharacters(in: .whitespaces).isEmpty
        if listing != (wide && nothing) { listing = wide && nothing }
        guard wide || (text != start && !nothing) else {
            asking?.cancel()
            recalling?.cancel()
            thinking?.cancel()
            thought = ("", [], [])
            answer = ("", [])
            remembered = ("", nil, [])
            local = []
            if !rows.isEmpty { rows = [] }
            return
        }
        let offered = index(for: window)
        local = offered.local(query: text, wide: wide)
        if nothing {
            asking?.cancel()
            recalling?.cancel()
            thinking?.cancel()
            answer = ("", [])
            remembered = ("", nil, [])
            thought = ("", [], [])
        } else {
            ask(text)
            recall(text, in: window.spaceID)
            think(text, about: offered)
        }
        show()
    }

    func end() {
        asking?.cancel()
        asking = nil
        recalling?.cancel()
        recalling = nil
        remembered = ("", nil, [])
        thinking?.cancel()
        thinking = nil
        thought = ("", [], [])
        mindReady = nil
        index = nil
        wide = false
        if listing { listing = false }
        start = ""
        query = ""
        local = []
        answer = ("", [])
        selection = nil
        if !rows.isEmpty { rows = [] }
    }

    /// ↓ from the field goes to the first row, ↑ from the first row back to the field.
    func move(_ by: Int) {
        guard !rows.isEmpty else { return }
        guard let index = selection else {
            if by > 0 { selection = 0 }
            return
        }
        let next = index + by
        selection = next < 0 ? nil : min(next, rows.count - 1)
    }

    /// What Return does with nothing chosen, said at the field's end.
    func sendLabel(for text: String) -> String? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty, typed != start else { return nil }
        let engine = Session.shared.preferences.engine
        // What isn't a search is an address.
        if let url = Destination.url(for: typed, engine: engine), url != Destination.search(typed, engine: engine) {
            return "Open \(Destination.pretty(url))"
        }
        return "Search \(Autocomplete.engineName(engine))"
    }

    private func show() {
        // The engine's words for a few letters fewer stay while they still
        // fit, so the rows don't empty and fill again with every letter.
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let words = answer.query == query ? answer.words : answer.words.filter { $0.lowercased().hasPrefix(typed) }
        var engine = Autocomplete.engine(words, query: query, engine: Autocomplete.engineName(Session.shared.preferences.engine))
        // The model's answer to a few letters fewer stays too, while the
        // words run on from them, until it answers again.
        let current = thought.query == query || (!thought.query.isEmpty && query.hasPrefix(thought.query))
        let meant = current ? thought.meant.filter { row in !local.contains { $0.id == row.id } } : []
        // Its searches only where the engine isn't asked.
        if current, !asksEngine {
            engine = thought.query == query ? thought.searches
                : thought.searches.filter { $0.phrase.lowercased().hasPrefix(typed) }
        }
        // History's answer to a few letters fewer stays too, the rows the letters still fit.
        let recalled = remembered.query == query
        let history = remembered.space == index?.space && (recalled || (!remembered.query.isEmpty && query.hasPrefix(remembered.query)))
            ? Autocomplete.history(remembered.pages, query: query, shown: local, tabs: index?.made.tabs ?? [:], stale: !recalled) : []
        // The row ↑ and ↓ chose stays chosen as rows come in around it.
        let chosen = selected?.id
        rows = Autocomplete.rows(local: local, history: history, meant: meant, engine: engine, wide: wide)
        if let chosen { selection = rows.firstIndex { $0.id == chosen } }
    }

    /// The space's history for `text` (HistoryRecorder.search), as it comes.
    /// The store looks inside words and in descriptions, which the letters
    /// alone don't: its rows are its own (Autocomplete.history).
    private func recall(_ text: String, in space: UUID) {
        recalling?.cancel()
        recalling = Task { [weak self] in
            let pages = await HistoryRecorder.shared.search(space: space, text: text, limit: 12)
            guard !Task.isCancelled, let self, self.query == text, self.index?.space == space else { return }
            remembered = (text, space, pages)
            show()
        }
    }

    /// The engine's suggestions for `text`, when Settings has them on and
    /// the engine offers them. Never for an address (suggestionsURL).
    private func ask(_ text: String) {
        asking?.cancel()
        let preferences = Session.shared.preferences
        guard preferences.searchSuggestions,
              let url = Autocomplete.suggestionsURL(for: text, engine: preferences.engine)
        else {
            asksEngine = false
            answer = ("", [])
            return
        }
        asksEngine = true
        asking = Task { [weak self] in
            // A moment first, so a word typed quickly asks once, not once a letter.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let reply = try? await Suggestions.session.data(from: url),
                  (reply.1 as? HTTPURLResponse)?.statusCode == 200,
                  !Task.isCancelled, let self, self.query == text
            else { return }
            answer = (text, Autocomplete.parse(reply.0))
            show()
        }
    }

    /// What Apple Intelligence's model makes of `text`, once typing pauses,
    /// where Settings has it on, the Mac has Apple Intelligence, and it isn't
    /// in Low Power Mode or hot: the iPad's Suggestions.think.
    private func think(_ text: String, about offered: Autocomplete.Index) {
        thinking?.cancel()
        let process = ProcessInfo.processInfo
        let spares = process.isLowPowerModeEnabled || process.thermalState == .serious || process.thermalState == .critical
        guard Session.shared.preferences.intelligence, Session.shared.hasIntelligence, Autocomplete.asksModel(text), !spares,
              let mind
        else {
            thought = ("", [], [])
            return
        }
        let ready = mindReady ?? mind.ready
        if mind.isKnown { mindReady = ready }
        guard ready else {
            thought = ("", [], [])
            return
        }
        mind.prewarm()
        let wantsSearches = !asksEngine
        let space = index?.space
        thinking = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let visited = if let space { await HistoryRecorder.shared.recall(space: space, text: text) } else { [HistoryPage]() }
            guard !Task.isCancelled,
                  let question = Autocomplete.intentQuestion(query: text, candidates: offered.candidates,
                                                             history: visited.map(Autocomplete.candidate(for:))),
                  let reply = await mind.answer(question, searches: wantsSearches),
                  !Task.isCancelled, let self, self.query == text
            else { return }
            let searches = Autocomplete.intentSearches(reply, to: question)
            let picked = Autocomplete.intentPicks(reply, to: question, shown: self.rows.filter { !$0.byMeaning })
            thought = (text, [], searches)
            show()
            guard !picked.isEmpty else { return }
            await withTaskGroup(of: (Int, Autocomplete.IntentGrade?).self) { group in
                for (place, candidate) in picked.enumerated() {
                    let about = Autocomplete.gradeQuestion(query: question.query, about: candidate)
                    group.addTask { (place, await mind.grade(about)) }
                }
                var fits: Set<Int> = []
                for await (place, grade) in group {
                    guard !Task.isCancelled, self.query == text else {
                        group.cancelAll()
                        return
                    }
                    guard grade?.keeps == true else { continue }
                    fits.insert(place)
                    let meant = picked.indices.filter(fits.contains).map {
                        Autocomplete.meantRow(for: picked[$0], query: question.query)
                    }
                    self.thought = (text, meant, searches)
                    self.show()
                }
            }
        }
    }

    /// No cookies and nothing kept: the engine hears the words, and nothing
    /// about who typed them.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    private func index(for window: WindowModel) -> Autocomplete.Index {
        let spaces = Session.shared.workspace.spaces
        if let kept = index, kept.space == window.spaceID, kept.tab == window.tabID, kept.spaces == spaces {
            return kept.made
        }
        let made = Autocomplete.Index(candidates(for: window))
        index = (made, window.spaceID, window.tabID, spaces)
        return made
    }

    /// Everything there is to find from this window, in the order it is
    /// listed with nothing typed: the space's tabs, the last seen first; the
    /// other spaces' tabs, and those spaces; the commands; and the space's bookmarks.
    private func candidates(for window: WindowModel) -> [Autocomplete.Candidate] {
        let workspace = Session.shared.workspace
        let here = workspace.space(window.spaceID)
        let others = workspace.spaces.filter { $0.id != window.spaceID }
        var list: [Autocomplete.Candidate] = []
        for tab in (here?.tabs ?? []).sorted(by: { $0.shown > $1.shown }) where tab.id != window.tabID {
            guard let url = tab.url ?? tab.pinned else { continue }
            list.append(Autocomplete.Candidate(
                id: "tab-\(tab.id)", source: tab.isPinned ? .pinnedTab : .tab, action: .tab(tab.id),
                title: tab.label, url: url, shown: tab.shown
            ))
        }
        for space in others {
            for tab in space.tabs.sorted(by: { $0.shown > $1.shown }) {
                guard let url = tab.url ?? tab.pinned else { continue }
                list.append(Autocomplete.Candidate(
                    id: "tab-\(tab.id)", source: .tabIn(space.name), action: .tab(tab.id), title: tab.label, url: url,
                    shown: tab.shown
                ))
            }
        }
        for space in others {
            list.append(Autocomplete.Candidate(
                id: "space-\(space.id)", source: .space, action: .space(space.id), title: space.name,
                keywords: ["space", "switch space"],
                detail: "\(space.tabs.count) \(space.tabs.count == 1 ? "tab" : "tabs")", symbol: space.symbol
            ))
        }
        for command in WindowModel.commands where command != .newTab && (command != .handoff || window.canHandoff) {
            list.append(Autocomplete.Candidate(
                id: "command-\(command.rawValue)", source: .command, action: .command(command), title: command.title,
                keywords: command.keywords, detail: WindowModel.keys(for: command) ?? "", symbol: command.symbol
            ))
        }
        for bookmark in here?.bookmarks.flatMap(\.links) ?? [] {
            guard let url = bookmark.url else { continue }
            list.append(Autocomplete.Candidate(
                id: "bookmark-\(bookmark.id)", source: .bookmark, action: .open(url), title: bookmark.label, url: url
            ))
        }
        return list
    }
}

extension Command {
    /// The command's own symbol, for its row in the command bar.
    var symbol: String {
        switch self {
        case .everything: return "command"
        case .newTab: return "plus"
        case .closeTab: return "xmark"
        case .reopenTab: return "arrow.uturn.backward"
        case .address: return "link"
        case .reload: return "arrow.clockwise"
        case .stop: return "xmark.circle"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .nextTab: return "arrow.down.square"
        case .previousTab: return "arrow.up.square"
        case .nextSpace: return "arrow.right.square"
        case .previousSpace: return "arrow.left.square"
        case .newSpace: return "plus.square.on.square"
        case .newWindow: return "macwindow.badge.plus"
        case .closeWindow: return "xmark.rectangle"
        case .tabBar: return "sidebar.left"
        case .diagnostics: return "waveform.path.ecg"
        case .settings: return "gearshape"
        case .focusPage: return "keyboard"
        case .pinTab: return "pin"
        case .splitTab: return "rectangle.split.2x1"
        case .bookmark: return "star"
        case .share: return "square.and.arrow.up"
        case .siteMode: return "desktopcomputer"
        case .spaceSettings: return "slider.horizontal.3"
        case .importBookmarks: return "square.and.arrow.down"
        case .contentBlocking: return "shield"
        case .linkMenu: return "contextualmenu.and.cursorarrow"
        case .find: return "text.magnifyingglass"
        case .handoff: return "arrowshape.turn.up.right"
        case .history: return "clock"
        }
    }

    /// Its title on a Mac, where the sidebar is what the iPad's tab bar is.
    var macTitle: String {
        self == .tabBar ? "Show or Hide Sidebar" : title
    }
}

// MARK: - The bar

/// Arc's command bar in Liquid Glass, over the middle of the window: a big
/// field, and under it the rows of what the words find. ⌘T opens it for a
/// new tab, ⌘L and a click on the address for the page on screen. Its glass
/// is the space's colour, as the sidebar's ground is, so it reads as the
/// browser's and not as more of the page it lies over.
struct CommandBar: View {
    @ObservedObject var model: WindowModel
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var suggestions: Suggestions
    let purpose: CommandBarPurpose
    /// The height the rows may take, under the field.
    var room: CGFloat = 440
    @State private var text = ""
    /// What the field held as it opened: the page's address, or nothing.
    @State private var started = ""

    init(model: WindowModel, purpose: CommandBarPurpose, room: CGFloat) {
        self.model = model
        suggestions = model.suggestions
        self.purpose = purpose
        self.room = room
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.pane, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: purpose == .newTab ? "plus.magnifyingglass" : "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                CommandField(text: $text, placeholder: "Search or enter an address", selectsAll: purpose == .here) { key in
                    switch key {
                    case .up: suggestions.move(-1)
                    case .down: suggestions.move(1)
                    case .cancel: close()
                    case .send: send()
                    }
                }
                if let label = suggestions.selected == nil ? suggestions.sendLabel(for: text) : nil {
                    HStack(spacing: 4) {
                        Text(label).lineLimit(1)
                        Image(systemName: "return")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            if !suggestions.rows.isEmpty {
                Divider().opacity(0.6)
                SuggestionRows(suggestions: suggestions, tint: model.space?.color.color ?? .accentColor) { row in
                    model.run(row, purpose: purpose)
                }
                .frame(maxHeight: min(440, room))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .clipShape(shape)
        // The space's colour in the glass, firmer in the dark, where the
        // colour is lighter; the glass's own blur keeps rows of words
        // legible over a busy page. A soft shadow lifts it off the page.
        .glassEffect(.regular.tint((model.space?.color.color ?? .accentColor).opacity(scheme == .dark ? 0.34 : 0.3)), in: shape)
        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.16), radius: 30, y: 14)
        .animation(.bar, value: suggestions.rows.isEmpty)
        .onAppear {
            started = suggestions.begin(in: model, purpose: purpose)
            text = started
        }
        .onDisappear { suggestions.end() }
        .onChange(of: text) { _, now in suggestions.typed(now, in: model) }
    }

    private func send() {
        if let row = suggestions.selected {
            model.run(row, purpose: purpose)
            return
        }
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return close() }
        model.commandBar = nil
        // The page's own address sent again is a reload, as in Safari.
        if purpose == .here, typed == started {
            model.reload()
        } else {
            model.go(typed, newTab: purpose == .newTab)
        }
    }

    private func close() {
        model.commandBar = nil
        model.focusPage()
    }
}

/// The rows themselves, scrolling. With everything listed and nothing typed
/// yet, each kind is under a heading.
struct SuggestionRows: View {
    @ObservedObject var suggestions: Suggestions
    let tint: Color
    let choose: (Suggestion) -> Void

    static func headings(_ rows: [Suggestion]) -> [Int: String] {
        var headings: [Int: String] = [:]
        var last: String?
        for (index, row) in rows.enumerated() {
            let kind = kind(row.source)
            if kind != last { headings[index] = kind }
            last = kind
        }
        return headings
    }

    private static func kind(_ source: Suggestion.Source) -> String {
        switch source {
        case .tab, .pinnedTab: return "Open Tabs"
        case .tabIn: return "Tabs in Other Spaces"
        case .space: return "Spaces"
        case .command: return "Commands"
        case .setting: return "Settings"
        case .device: return "On Other Devices"
        case .bookmark: return "Bookmarks"
        case .history: return "History"
        case .searched, .engine, .intelligence: return "Searches"
        }
    }

    var body: some View {
        let rows = suggestions.rows
        let listing = suggestions.listing
        let headings = listing ? Self.headings(rows) : [:]
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if let heading = headings[index] {
                            Text(heading)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, index == 0 ? 2 : 10)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                        SuggestionRow(row: row, selected: index == suggestions.selection, named: !listing, tint: tint)
                            .id(row.id)
                            .onTapGesture { choose(row) }
                    }
                }
                .padding(8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: suggestions.selection) { _, index in
                if let index, rows.indices.contains(index) { scroller.scrollTo(rows[index].id) }
            }
        }
    }
}

/// A row: the page's icon, or a space's or a command's own symbol; the
/// phrase, what was typed plain and what the row completes in bold; and at
/// the end where it came from, or a command's keys. The chosen row is filled
/// with the space's colour, as Arc's is with the theme's.
private struct SuggestionRow: View {
    let row: Suggestion
    let selected: Bool
    var named = true
    let tint: Color
    @State private var hovering = false

    private var keys: String? {
        guard case .command = row.action, !row.detail.isEmpty else { return nil }
        return row.detail
    }

    private var showsSource: Bool {
        if named { return true }
        switch row.source {
        case .tabIn, .device: return true
        default: return false
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                phrase
                    .font(.system(size: 13))
                    .lineLimit(1)
                if !row.detail.isEmpty, keys == nil {
                    Text(row.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let keys {
                Text(keys)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            } else if showsSource {
                // Found by Apple Intelligence from what the words mean, not by their letters.
                if row.byMeaning {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                        .accessibilityHidden(true)
                }
                Text(row.source.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: Metrics.rowCorner, style: .continuous)
                .fill(selected ? tint : Color.primary.opacity(hovering ? 0.07 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.byMeaning ? "\(row.phrase), \(row.source.label), found by Apple Intelligence"
                                          : "\(row.phrase), \(row.source.label)")
        .accessibilityValue(row.detail)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var icon: some View {
        switch row.source {
        case .tab, .pinnedTab, .tabIn, .device, .bookmark, .history:
            SiteIconView(url: row.url, size: 16)
        case .searched:
            symbol("clock.arrow.circlepath")
        case .space:
            symbol(row.symbol ?? "square.stack")
        case .command:
            symbol(row.symbol ?? "command")
        case .setting:
            symbol("gearshape")
        case .engine, .intelligence:
            symbol("magnifyingglass")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.secondary)
    }

    /// The typed letters plain, the rest of the phrase in bold: what the row
    /// adds to what was typed.
    private var phrase: Text {
        let letters = Array(row.phrase)
        let typed = row.typed
            .map { $0.clamped(to: 0..<letters.count) }
            .filter { !$0.isEmpty }
            .sorted { $0.lowerBound < $1.lowerBound }
        var parts: [Text] = []
        var at = 0
        for range in typed where range.lowerBound >= at {
            parts.append(part(letters[at..<range.lowerBound], typed: false))
            parts.append(part(letters[range], typed: true))
            at = range.upperBound
        }
        parts.append(part(letters[at...], typed: false))
        return parts.reduce(Text(verbatim: "")) { Text("\($0)\($1)") }
    }

    private func part(_ letters: ArraySlice<Character>, typed: Bool) -> Text {
        Text(verbatim: String(letters))
            .fontWeight(typed ? .regular : .semibold)
            .foregroundStyle(selected ? Color.white.opacity(typed ? 0.85 : 1) : Color.primary.opacity(typed ? 0.7 : 1))
    }
}

// MARK: - The field

/// The keys the command bar's field hands to the bar rather than to its text.
enum FieldKey {
    case up, down, cancel, send
}

/// The command bar's field: AppKit's, which says when ↑, ↓, Return and
/// Escape are pressed rather than moving in its text. Focused as it appears,
/// with the page's address in it selected whole, as in Safari.
struct CommandField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var selectsAll = false
    let key: (FieldKey) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        field.stringValue = text
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            if !selectsAll { field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0) }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandField

        init(_ parent: CommandField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.key(.up)
            case #selector(NSResponder.moveDown(_:)): parent.key(.down)
            case #selector(NSResponder.cancelOperation(_:)): parent.key(.cancel)
            case #selector(NSResponder.insertNewline(_:)): parent.key(.send)
            default: return false
            }
            return true
        }
    }
}
