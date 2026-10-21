import PadCore
import SwiftUI

/// The space's history (Show All History: ⌘Y on a Mac, ⌃⌥Y on an iPad):
/// the pages gone to in it, by day, newest first, each page once a day;
/// or, with words typed, the pages they find, most wanted first. A page is
/// opened from here, or let go of, alone or with its day; Clear History
/// lets go of a stretch of time.
struct HistoryView: View {
    let spaceID: UUID
    /// A page chosen: in the tab on screen, or in a new one.
    let open: (URL, _ newTab: Bool) -> Void
    let done: () -> Void
    @ObservedObject private var recorder = HistoryRecorder.shared
    @State private var entries: [HistoryEntry] = []
    @State private var days: [HistoryDay] = []
    @State private var found: [HistoryPage] = []
    /// The words `found` answers, so "No Results" waits for the store.
    @State private var searched: String?
    /// What Apple Intelligence made of the words sent with Return
    /// (Intelligence.historyQuery): searched for in their place while they stay.
    @State private var understood: (text: String, query: HistoryQuery)?
    @State private var understanding = false
    @State private var text = ""
    /// Whether the store has been asked yet, so an empty list isn't called empty before it is.
    @State private var loaded = false
    /// Whether older visits may be left to show, as the list reaches its end.
    @State private var more = true
    /// Older visits being asked for (loadOlder): let go of when the list is loaded again, or changed.
    @State private var paging: Task<Void, Never>?
    @State private var clearing = false
    /// The day whose Clear was pressed, asked about before it goes.
    @State private var dayAsked: HistoryDay?

    /// Visits asked for at a time.
    private static let batch = 300

    #if os(iOS)
    private static let clearPlacement = ToolbarItemPlacement.topBarLeading
    #else
    private static let clearPlacement = ToolbarItemPlacement.destructiveAction
    #endif

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("History")
                .searchable(text: $text, prompt: Self.searchPrompt)
                .onSubmit(of: .search) { Task { await understand() } }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: done)
                    }
                    // Apart from Done, at the other end on iPad, so neither is pressed for the other.
                    ToolbarItem(placement: Self.clearPlacement) {
                        Button("Clear…") { clearing = true }
                            .disabled(loaded && entries.isEmpty)
                    }
                }
        }
        // Reloaded as words are typed (a moment after the last), and as history changes.
        .task(id: Reload(text: text, revision: recorder.revision, understood: understood?.text)) { await load() }
        .sheet(isPresented: $clearing) {
            ClearHistoryView(spaceID: spaceID) { clearing = false }
        }
        .confirmationDialog(dayAsked.map { "Clear the history of \(Self.name(of: $0.start))?" } ?? "",
                            isPresented: Binding(get: { dayAsked != nil }, set: { if !$0 { dayAsked = nil } }),
                            titleVisibility: .visible, presenting: dayAsked) { day in
            Button("Clear \(Self.name(of: day.start))", role: .destructive) { clear(day) }
        }
        .environment(\.spaceColor, Session.shared.workspace.space(spaceID)?.color ?? .gray)
    }

    @ViewBuilder
    private var list: some View {
        let searching = !text.trimmingCharacters(in: .whitespaces).isEmpty
        List {
            if searching {
                Section {
                    ForEach(found) { page in
                        row(page, time: page.last, day: true)
                    }
                } header: {
                    if understanding {
                        Label("Asking Apple Intelligence…", systemImage: "sparkles")
                    } else if let understood, understood.text == text.trimmingCharacters(in: .whitespaces) {
                        Label(Self.describe(understood.query), systemImage: "sparkles")
                    }
                }
            } else {
                ForEach(days) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            row(entry.page, time: entry.time, day: false)
                                .onAppear { if entry.id == days.last?.entries.last?.id { showOlder() } }
                        }
                    } header: {
                        HStack {
                            Text(Self.name(of: day.start))
                            Spacer()
                            Button("Clear") { dayAsked = day }
                                .buttonStyle(.borderless)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .overlay {
            if searching, searched == text.trimmingCharacters(in: .whitespaces), found.isEmpty {
                ContentUnavailableView.search(text: text)
            } else if loaded, !searching, days.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock",
                                       description: Text("Pages you go to in this space show here."))
            }
        }
    }

    private func row(_ page: HistoryPage, time: Date, day: Bool) -> some View {
        Button {
            open(page.url, false)
            done()
        } label: {
            HistoryRow(page: page, time: time, showsDay: day)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in New Tab", systemImage: "plus.square.on.square") {
                open(page.url, true)
                done()
            }
            Button("Copy Link", systemImage: "doc.on.doc") { copy(page.url) }
            Divider()
            Button("Delete from History", systemImage: "trash", role: .destructive) { delete(page) }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(page) }
        }
    }

    // MARK: Loading

    private struct Reload: Equatable {
        var text: String
        var revision: Int
        var understood: String?
    }

    /// Apple Intelligence, where it is on: Return asks it what the words mean.
    private static var asksIntelligence: Bool {
        Session.shared.preferences.intelligence && Session.shared.hasIntelligence
    }

    private static var searchPrompt: String {
        asksIntelligence ? "Search History, or Describe and Press Return" : "Search History"
    }

    /// The words sent, as Apple Intelligence reads them: the words to look
    /// for, and the days, which a phrase like "last Friday" names.
    private func understand() async {
        let words = text.trimmingCharacters(in: .whitespaces)
        guard Self.asksIntelligence, !words.isEmpty, understood?.text != words, let mind = IntelligenceStatus.model() else { return }
        understanding = true
        defer { understanding = false }
        guard let query = await mind.historyQuery(words, now: Date()),
              text.trimmingCharacters(in: .whitespaces) == words else { return }
        understood = (words, query)
    }

    /// What Apple Intelligence searched for: its words, and its days.
    static func describe(_ query: HistoryQuery) -> String {
        var parts: [String] = []
        if !query.words.isEmpty { parts.append("“\(query.words)”") }
        if let from = query.from, let to = query.to {
            let calendar = Calendar.current
            parts.append(calendar.isDate(from, inSameDayAs: to) ? name(of: from)
                         : "\(from.formatted(.dateTime.month(.abbreviated).day())) to \(to.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return parts.isEmpty ? "Everything" : parts.joined(separator: ", ")
    }

    private func load() async {
        stopPaging()
        let words = text.trimmingCharacters(in: .whitespaces)
        if words.isEmpty {
            found = []
            searched = nil
        } else {
            // A moment after the last key, so each one doesn't ask the store.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            // What Apple Intelligence made of these words, if it was asked; else the words as typed.
            let query = understood?.text == words ? understood?.query : nil
            let pages = if let query { await recorder.search(space: spaceID, query: query, limit: 100) }
                        else { await recorder.search(space: spaceID, text: words, limit: 100) }
            guard !Task.isCancelled else { return }
            found = pages
            searched = words
        }
        // The days as well while searching, so what was cleared meanwhile is
        // gone when the search is. As many as were showing, so a change
        // doesn't take the list back to its start.
        let wanted = max(entries.count, Self.batch)
        let fresh = await recorder.entries(space: spaceID, limit: wanted)
        guard !Task.isCancelled else { return }
        show(fresh)
        more = fresh.count == wanted
        loaded = true
    }

    private func showOlder() {
        guard more, paging == nil else { return }
        paging = Task {
            await loadOlder()
            paging = nil
        }
    }

    private func stopPaging() {
        paging?.cancel()
        paging = nil
    }

    /// The next older visits, as the list's last row comes on screen; more
    /// of them while they add no row, all being to pages the last day shows.
    private func loadOlder() async {
        while more, let last = entries.last {
            let rows = days.reduce(0) { $0 + $1.entries.count }
            let older = await recorder.entries(space: spaceID, before: last.time, limit: Self.batch)
            guard !Task.isCancelled else { return }
            show(entries + older)
            more = older.count == Self.batch
            if days.reduce(0, { $0 + $1.entries.count }) > rows { return }
        }
    }

    private func show(_ list: [HistoryEntry]) {
        entries = list
        days = History.days(list)
    }

    // MARK: Letting go

    /// Every visit to the page in this space, as Safari deletes a history item.
    private func delete(_ page: HistoryPage) {
        stopPaging()
        recorder.clear(space: spaceID, scope: .page(page.key))
        found.removeAll { $0.key == page.key }
        show(entries.filter { $0.page.key != page.key })
    }

    private func clear(_ day: HistoryDay) {
        stopPaging()
        // To the day's last moment, not the next one's first (HistoryRemoval takes both ends).
        let end = (Calendar.current.date(byAdding: .day, value: 1, to: day.start) ?? day.start).addingTimeInterval(-0.001)
        let to = min(end, Date())
        recorder.clear(space: spaceID, scope: .range(from: day.start, to: to))
        show(entries.filter { $0.time < day.start || $0.time > to })
    }

    private func copy(_ url: URL) {
        let clean = Tracking.clean(url)
        #if os(iOS)
        UIPasteboard.general.url = clean
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([clean as NSURL])
        #endif
    }

    /// "Today", "Yesterday", or the day's date, with its year only when it isn't this one.
    static func name(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}

/// A page in the History list: its icon, its name and its site, and when.
private struct HistoryRow: View {
    let page: HistoryPage
    let time: Date
    /// The day as well as the time: in search results, which aren't by day.
    let showsDay: Bool

    var body: some View {
        HStack(spacing: 10) {
            SiteIconView(url: page.url, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title.isEmpty ? site : page.title)
                    .lineLimit(1)
                Text(site)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(showsDay && !Calendar.current.isDateInToday(time) ? time.formatted(.dateTime.month(.abbreviated).day())
                                                                   : time.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var site: String {
        guard let host = page.url.host() else { return page.url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Clear History: a stretch of time back from now, in one space or in
/// every one. What a page stored (sign-ins, cookies) stays: that is the
/// space's own, and a space is cleared of it in its settings.
struct ClearHistoryView: View {
    let done: () -> Void
    @State private var span = HistorySpan.lastHour
    /// The space it clears; nil for every one.
    @State private var space: UUID?
    @ObservedObject private var session = Session.shared

    /// Opened from a window, on its space; from Settings on a Mac, which has none, on every space.
    init(spaceID: UUID?, done: @escaping () -> Void) {
        _space = State(initialValue: spaceID)
        self.done = done
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Clear", selection: $span) {
                        ForEach(HistorySpan.allCases, id: \.self) { span in
                            Text(span.label).tag(span)
                        }
                    }
                    .pickerStyle(.inline)
                    if session.workspace.spaces.count > 1 {
                        Picker("From", selection: $space) {
                            Text("Every Space").tag(UUID?.none)
                            ForEach(session.workspace.spaces) { space in
                                Text(space.name).tag(UUID?.some(space.id))
                            }
                        }
                    }
                } footer: {
                    Text("The pages gone to in that time go from history, and their closed tabs from Reopen Closed Tab. Sign-ins and what sites have stored stay.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Clear History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: done)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear History", role: .destructive) {
                        HistoryRecorder.shared.clear(space: space, scope: span.scope(now: Date()))
                        done()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 320)
        #endif
    }
}
