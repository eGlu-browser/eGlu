import AppKit
import ApplicationServices
import Engines
import PadCore

/// Checking what is typed in other apps' fields (Docs/Tasks/03): the
/// orchestrator between the Accessibility reads (`FrontField`,
/// `FieldGeometry`), the linter (`WritingChecker`), the underlines and the
/// panel. All of it on the main actor; the Accessibility calls it makes
/// are quick reads.
///
/// Nothing typed is logged or kept: the field's text lives only in this
/// object and is sent nowhere (Decided 11).
@MainActor
final class ElsewhereChecker {
    static let shared = ElsewhereChecker()

    private var started = false
    private var field: AXUIElement?
    /// The field's text as last read, and the caret inside it.
    private var text = ""
    private var caret = 0
    /// The lints of the last run, in the field's UTF-16 offsets.
    private var lints: [GrammarLint] = []
    private var caretSettle = CaretSettle()
    /// What the panel is showing: the lint's index and its word.
    private var shown: (index: Int, word: String)?
    /// The apps list's additions: fields seen since launch.
    private(set) var seenApps: Set<String> = []

    /// The clock all the settles read, seconds since start.
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var tickTimer: Timer?
    private var lintWork: DispatchWorkItem?
    private var redrawWork: DispatchWorkItem?
    /// Bumped on every text change so a late lint answer is dropped.
    private var generation = 0

    private var preferences: Preferences { Session.shared.preferences }

    private init() {}

    /// Begin: watch the front app's field while the settings allow it.
    /// Idempotent; called once from Session's start.
    func start() {
        guard !started else { return }
        started = true
        AccessibilityAccess.shared.watch()
        let front = FrontField.shared
        front.configure { [weak self] in self?.preferences ?? Preferences() }
        front.onEvent = { [weak self] event in self?.hear(event) }
        front.onSeenApp = { [weak self] id in self?.seenApps.insert(id) }
        AcceptKey.shared.onAccept = { [weak self] in self?.acceptFirst() }
        front.start()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// A setting changed: checking may have to start or stop at once.
    /// Called from SessionPreferences' macOS half.
    func preferencesChanged() {
        if preferences.writing, preferences.writingOtherApps, !FrontField.shared.harperDesktopRunning {
            FrontField.shared.refreshFront()
        } else {
            drop()
        }
    }

    // MARK: - The field's events

    private func hear(_ event: FrontField.Event) {
        switch event {
        case .field(let element):
            fieldChanged(element)
        case .text(let text):
            textChanged(to: text)
        case .selection:
            selectionChanged()
        case .geometry:
            staleMarks()
        }
    }

    /// The 4 Hz beat while a field is watched: what notifications miss —
    /// a field that went without one, the app's move, a caret drifting —
    /// is caught here (Decided 2).
    private func tick() {
        FrontField.shared.refreshFront()
        guard field != nil else { return }
        if let event = caretSettle.tick(at: now) { hearSettle(event) }
        // Polls for apps that post no value notification.
        let text = FrontField.shared.readText() ?? ""
        if text != self.text { textChanged(to: text) }
        let caret = FrontField.shared.readCaret()
        if caret != self.caret {
            self.caret = caret ?? 0
            selectionChanged()
        }
    }

    private func fieldChanged(_ element: AXUIElement?) {
        field = element
        lints = []
        caretSettle = CaretSettle()
        shown = nil
        WritingPanel.shared.hide()
        Underlines.shared.clear()
        guard element != nil else {
            text = ""
            return
        }
        text = FrontField.shared.readText() ?? ""
        caret = FrontField.shared.readCaret() ?? 0
        scheduleLint()
    }

    private func textChanged(to text: String) {
        guard field != nil else { return }
        generation += 1
        self.text = text
        // Decided 10: the marks under a moving text are wrong at once.
        staleMarks()
        _ = caretSettle.moved(to: caret, at: now, textChanged: true).map(hearSettle)
        scheduleLint()
    }

    private func selectionChanged() {
        guard field != nil else { return }
        caret = FrontField.shared.readCaret() ?? 0
        if let event = caretSettle.moved(to: FrontField.shared.readCaret(),
                                        at: now, textChanged: false) {
            hearSettle(event)
        }
    }

    /// Underlines and panel vanish while anything moves; the marks return
    /// 150 ms after stillness, drawn from rectangles read again then.
    private func staleMarks() {
        Underlines.shared.clear()
        WritingPanel.shared.hide()
        shown = nil
        redrawWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.redraw() }
        redrawWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + CaretSettle.settle, execute: work)
    }

    // MARK: - Linting

    private func scheduleLint() {
        lintWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.lintNow() }
        lintWork = work
        // 300 ms of quiet first, so a run never splits a word being typed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func lintNow() {
        guard let field else { return }
        let text = self.text
        let region = WritingSpan.region(of: text, caret: caret)
        let piece = String(text[text.utf16Range(region)])
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            var found = await WritingChecker.shared.lint(piece)
            guard self.generation == generation, self.text == text else { return }
            for index in found.indices {
                found[index].start += region.lowerBound
                found[index].end += region.lowerBound
            }
            self.lints = found
            let ranges = found.map { $0.start..<$0.end }
            if let event = self.caretSettle.set(lints: ranges, at: self.now) {
                self.hearSettle(event)
            } else {
                self.caretRestCheck()
            }
            self.redraw(in: field)
        }
    }

    private func redraw() {
        guard let field else { return }
        redraw(in: field)
    }

    /// Read the lint rectangles again and put the underlines back.
    private func redraw(in element: AXUIElement) {
        let marks = lints.map { lint in
            Underlines.Marks(
                rects: FieldGeometry.rects(
                    for: NSRange(location: lint.start, length: lint.end - lint.start),
                    in: element),
                color: WritingColors.color(for: lint.kind))
        }.filter { !$0.rects.isEmpty }
        Underlines.shared.show(marks)
    }

    // MARK: - The panel

    private func hearSettle(_ event: CaretSettle.Event) {
        switch event {
        case .visit(let index):
            visit(lintAt: index)
        case .leave:
            WritingPanel.shared.hide()
            shown = nil
        }
    }

    /// The caret may already be inside a lint when its underlines arrive:
    /// visit it without a move.
    private func caretRestCheck() {
        guard let caret = FrontField.shared.readCaret() else { return }
        self.caret = caret
        if let index = lints.firstIndex(where: { $0.start <= caret && caret <= $0.end }) {
            visit(lintAt: index)
        }
    }

    private func visit(lintAt index: Int) {
        guard field != nil, lints.indices.contains(index), let field else { return }
        let lint = lints[index]
        let nsRange = NSRange(location: lint.start, length: lint.end - lint.start)
        guard nsRange.location + nsRange.length <= text.utf16.count else { return }
        let word = String(text[text.utf16Range(lint.start..<lint.end)])
        let rects = FieldGeometry.rects(for: nsRange, in: field)
        guard let anchor = rects.first else { return }
        let union = rects.reduce(anchor) { $0.union($1) }
        shown = (index, word)
        WritingPanel.shared.show(
            lint: lint, word: word, at: union,
            suggestions: lint.suggestions.prefix(5).map { Self.label(for: $0) },
            canAddToDictionary: lint.kind == "Spelling" || lint.kind == "Typo"
        ) { [weak self] action, suggestion in
            self?.act(action, on: lint, word: word, suggestion: suggestion)
        }
    }

    /// A suggestion's button text: the answer itself, "Remove" for a word
    /// to delete, `Insert "x"` for one to add.
    private static func label(for suggestion: Suggestion) -> String {
        switch suggestion {
        case .replace(let text): return text
        case .insert(let text): return String(localized: "Insert \"\(text)\"")
        case .remove: return String(localized: "Remove")
        }
    }

    /// ⌃⌥G: the panel's first suggestion, only while one is up.
    private func acceptFirst() {
        guard let shown, lints.indices.contains(shown.index),
              let field, let app = FrontField.shared.app else { return }
        let lint = lints[shown.index]
        guard !lint.suggestions.isEmpty else { return }
        apply(lint.suggestions[0], to: lint, word: shown.word, in: field, app: app)
    }

    /// A panel button, and for a suggestion which of them.
    private func act(_ action: PopupAction, on lint: GrammarLint,
                     word: String, suggestion: Int) {
        switch action {
        case .close:
            break
        case .ignoreLint:
            WritingChecker.shared.ignore(context: lint.context)
        case .addToDictionary:
            WritingChecker.shared.addWord(word)
        case .disableRule:
            Session.shared.preferences.writingRules[lint.rule] = false
        case .applySuggestion:
            if let field, let app = FrontField.shared.app,
               lint.suggestions.indices.contains(suggestion) {
                apply(lint.suggestions[suggestion], to: lint, word: word, in: field, app: app)
            }
        }
        // Whatever the action, the lint's text may differ now: lint again.
        scheduleLint()
    }

    /// Write the suggestion into the field through the app's own text
    /// setting or typing, so its Undo takes it back (FieldWriter).
    private func apply(_ suggestion: Suggestion, to lint: GrammarLint,
                       word: String, in field: AXUIElement, app: NSRunningApplication) {
        let replacement: String
        switch suggestion {
        case .replace(let text): replacement = text
        case .insert(let text): replacement = word + text
        case .remove: replacement = ""
        }
        _ = FieldWriter.replace(
            range: NSRange(location: lint.start, length: lint.end - lint.start),
            expected: word, with: replacement, in: field, app: app)
    }

    /// Checking stops: every mark gone, nothing read further.
    private func drop() {
        field = nil
        lints = []
        caretSettle = CaretSettle()
        shown = nil
        lintWork?.cancel()
        redrawWork?.cancel()
        WritingPanel.shared.hide()
        Underlines.shared.clear()
    }
}

private extension String {
    /// The substring at `range` in UTF-16 units.
    func utf16Range(_ range: Range<Int>) -> Range<String.Index> {
        let start = utf16.index(utf16.startIndex, offsetBy: range.lowerBound,
                                limitedBy: utf16.endIndex) ?? utf16.endIndex
        let end = utf16.index(utf16.startIndex, offsetBy: range.upperBound,
                              limitedBy: utf16.endIndex) ?? utf16.endIndex
        let lower = String.Index(start, within: self) ?? startIndex
        let upper = String.Index(end, within: self) ?? endIndex
        return lower..<upper
    }
}
