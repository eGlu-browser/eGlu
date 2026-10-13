import os
import PadCore
import SwiftUI
import UIKit

/// One handoff being made ready (Handoff.swift): the page read, its kind
/// told, the file written. How far it is is one value (Handoff.Stage),
/// which the browser acts on and the sheet shown meanwhile draws.
///
/// The file is written twice at the most. First as soon as the page has
/// been read, with its kind told by counting (Handoff.kind), which takes no
/// time to speak of: the share sheet can show from then on. Then again if
/// Apple Intelligence's model, asked meanwhile, says more: the kind as it
/// reads the page, a sentence on what the page is, and which of the parts
/// that were only started say the most. The model takes
/// seconds: they are spent on a sheet that says what Handoff does
/// (HandoffGuide), which goes on to the share sheet when the model has
/// answered. Whoever goes on sooner is choosing an app while it works, and
/// gets the file as it stands when the app is picked (HandoffFile).
///
/// Each of the two is one task, run in order on the main actor, with only
/// the writing itself away from it. The model is also given a time: a task
/// group would wait for the model to notice it was called off, which takes
/// it seconds, so the time is a task of its own that sets the stage and
/// leaves the model to wind down behind it.
@MainActor
@Observable
final class HandoffJob {
    private(set) var stage: Handoff.Stage = .reading
    /// The words that go beside the file: a question to start from, and the page's address.
    let prompt: String
    let file: URL

    /// This handoff's own folder, so that taking it away takes nothing of the next one's.
    private let folder: URL
    /// Whether the person had something selected on the page: it goes first, and the sheet says so.
    private(set) var selected = false
    @ObservationIgnored private var drafting: Task<Void, Never>?
    @ObservationIgnored private var organising: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    /// Whether an app has been given the file, after which it is not
    /// written again. Asked from the thread that writes and set from the
    /// one the share sheet prepares its items on, hence the lock; it is
    /// not held while the file is written, which swaps a whole file for a
    /// whole file, so an app that reads meanwhile gets one or the other.
    private let given = OSAllocatedUnfairLock(initialState: false)

    /// Where the files of handoffs are kept.
    private static let shelf = FileManager.default.temporaryDirectory.appendingPathComponent("Handoff", isDirectory: true)
    /// The folders of handoffs not yet over, by name: another window's may be at its share sheet when this one writes.
    private static var live: Set<String> = []
    /// How long the model is given. A page it has not read by then goes as counted.
    private static let patience: Duration = .seconds(8)
    /// A page with less text than this, in characters, is looked at as
    /// well as read, where the model looks at pictures: its words say too
    /// little, and a picture costs the model about as long again as the
    /// words do.
    private static let littleText = 1_500

    init(page: Page, url: URL, title: String, question: String, mind: PageMind?) {
        prompt = Handoff.prompt(question: question, url: url)
        folder = Self.shelf.appendingPathComponent(UUID().uuidString, isDirectory: true)
        file = folder.appendingPathComponent(Handoff.fileName(title: title, url: url))
        Self.live.insert(folder.lastPathComponent)
        drafting = Task { [weak page] in
            await self.draft(of: page, at: url, titled: title, mind: mind)
        }
    }

    /// Waits until there is a first file to give, or it is known there is none.
    func drafted() async {
        await drafting?.value
    }

    /// The handoff is over: its share sheet has closed, its guide was put
    /// away, or another handoff has taken its place. What is still under
    /// way is called off, and a file no app took is removed, once nothing
    /// is writing it any more.
    func finish(taken: Bool) {
        Self.live.remove(folder.lastPathComponent)
        organising?.cancel()
        deadline?.cancel()
        if !stage.isSettled { stage = .stopped }
        guard !taken else { return }
        let writers = [drafting, organising]
        let folder = folder
        Task {
            for writer in writers { await writer?.value }
            await Self.remove(folder)
        }
    }

    /// The file is being given to an app, on the thread its share is
    /// prepared on: from now on it stays as it is.
    nonisolated func give() {
        given.withLock { $0 = true }
    }

    // MARK: The two steps

    /// Reads the page and writes the first file, organised for the kind
    /// the count tells, then has the model asked.
    private func draft(of page: Page?, at url: URL, titled title: String, mind: PageMind?) async {
        let reading = await page?.markdown(limit: Handoff.limit)
        // Called off while the page was read: nothing is written.
        guard stage == .reading else { return }
        guard let reading else {
            stage = .wordsOnly
            return
        }
        selected = reading.hasSelection
        let counted = Handoff.kind(of: reading, url: url)
        let text = Handoff.document(title: title, url: url, composed: Handoff.compose(reading, kind: counted), reading: reading)
        let written = await Self.write(text, to: file, in: folder, emptying: Self.shelf, but: Self.live)
        guard stage == .reading else { return }
        guard written else {
            stage = .wordsOnly
            return
        }
        guard let mind else {
            stage = .ready(counted)
            return
        }
        stage = .organising(counted: counted)
        organising = Task { [weak page] in
            await self.organise(reading, counted: counted, with: mind, looking: page, at: url, titled: title)
        }
        deadline = Task {
            try? await Task.sleep(for: Self.patience)
            guard !Task.isCancelled, self.stage.isOrganising else { return }
            self.organising?.cancel()
            self.stage = .ready(counted)
        }
    }

    /// Asks the model what the page is and, where it is asked that too
    /// (Handoff.asksForPicks), which of the parts that would only be
    /// started say the most. If it says, the file is written again: for
    /// the kind as settled between the count and the model, with the
    /// parts it picked whole, and with its summary.
    private func organise(_ reading: PageReading, counted: PageKind, with mind: PageMind, looking page: Page?,
                          at url: URL, titled title: String) async {
        let candidates = Handoff.asksForPicks ? Handoff.candidates(in: reading, kind: counted) : []
        let briefs = (0...2).map { Handoff.brief(title: title, url: url, reading: reading, candidates: candidates, shortened: $0) }
        let question = PageQuestion(briefs: briefs, picks: !candidates.isEmpty)
        let answer = await mind.read(question, looks: reading.facts.characters < Self.littleText) { [weak page] in
            guard let page else { return nil }
            return await page.preview(width: 512 / max(1, page.view.traitCollection.displayScale))?.cgImage
        }
        // Called off or out of time while the model read: whichever it was has set the stage.
        guard !Task.isCancelled, stage.isOrganising else { return }
        deadline?.cancel()
        guard let answer else {
            stage = .ready(counted)
            return
        }
        let kind = Handoff.settled(counted: counted, answer: answer, facts: reading.facts)
        let composed = Handoff.compose(reading, kind: kind, promoted: Handoff.promoted(answer.picks, among: candidates))
        let text = Handoff.document(title: title, url: url, composed: composed, reading: reading, summary: answer.about)
        let written = await Self.rewrite(text, at: file, unless: given)
        // Asked again after the wait: it may have been called off while the file was written.
        guard stage.isOrganising else { return }
        stage = .ready(written ? kind : counted)
    }

    // MARK: Writing, away from the main thread

    /// The first file, in a folder of its own. The shelf is emptied before
    /// it of every handoff that is over: the file of the handoff before
    /// stays until now, since the app it went to may still have been
    /// reading it when the sheet closed. Those of handoffs still under
    /// way (`live`) stay: another window's share sheet may be open.
    @concurrent
    private static func write(_ text: String, to file: URL, in folder: URL, emptying shelf: URL, but live: Set<String>) async -> Bool {
        let files = FileManager.default
        for old in (try? files.contentsOfDirectory(at: shelf, includingPropertiesForKeys: nil)) ?? []
        where !live.contains(old.lastPathComponent) {
            try? files.removeItem(at: old)
        }
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The file again, unless an app has it by now.
    @concurrent
    private static func rewrite(_ text: String, at file: URL, unless given: OSAllocatedUnfairLock<Bool>) async -> Bool {
        guard !given.withLock({ $0 }) else { return false }
        return (try? Data(text.utf8).write(to: file, options: .atomic)) != nil
    }

    @concurrent
    private static func remove(_ folder: URL) async {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// The file of a handoff, for the share sheet. It is asked for when an app
/// is picked, which is how the job hears that the file is given
/// (HandoffJob.give): while the share sheet is open the model may still be
/// reading, and the file may still be written again; under the app that
/// reads it, it may not.
///
/// An operation, which the share sheet runs on a thread of its own: what it
/// keeps is set once and never changed.
final class HandoffFile: UIActivityItemProvider, @unchecked Sendable {
    private let file: URL
    private let give: @Sendable () -> Void

    init(_ job: HandoffJob) {
        file = job.file
        give = { job.give() }
        super.init(placeholderItem: job.file)
    }

    override var item: Any {
        // Asked by an app that was picked, not for the sheet's own look at the file.
        if activityType != nil { give() }
        return file
    }
}

/// What Handoff does, said while it does it: a sheet over the page for as
/// long as Apple Intelligence's model is reading it (HandoffJob), which is
/// seconds, so the wait is spent on something worth reading.
///
/// The sheet's three points are the handoff's three steps (Handoff.Step),
/// and how far the handoff is shows on them: a step done has a tick, the
/// one at work its own symbol in colour and moving, and a line down the
/// side fills as they go. Under the step that organises, a card says what is
/// going on with this page and how long it takes, then what the page turned
/// out to be and what of it will be shared. With that the sheet goes on to
/// the share sheet by itself; its button goes on without waiting. Where the
/// model isn't asked there is no wait and no sheet.
struct HandoffGuide: View {
    let job: HandoffJob
    let colour: SpaceColor
    /// The room under what the sheet ends with: `edge`, as beside it, or
    /// none where the sheet stands on the screen's own room for the home
    /// indicator, which is about as much.
    let foot: CGFloat
    /// On to the share sheet.
    let go: () -> Void

    /// The sheet's corner. What is drawn as a surface near its edge stands
    /// `edge` in from it with a corner of `inner`, so the two curves run
    /// side by side: the corner inside and the room around it come to the
    /// corner outside.
    static let corner: CGFloat = 32
    static let edge: CGFloat = 16
    private static let inner = corner - edge
    /// Words stand further in than surfaces do.
    private static let indent: CGFloat = 8
    /// How long the sheet stays at the least, and how long on what the page
    /// came to: long enough to read that, and never a sheet that only comes
    /// and goes.
    private static let shortest: Duration = .milliseconds(1_600)
    private static let pause: Duration = .milliseconds(900)

    /// Whether the sheet has come up: its parts arrive one after another.
    @State private var arrived = false
    @State private var since = ContinuousClock.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // As high as what it says. Where that is more than the screen has
        // (large text), it scrolls, the button with it.
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .tint(colour.color)
        .animation(.bar, value: job.stage)
        .sensoryFeedback(.success, trigger: job.stage) { _, now in
            if case .ready = now { true } else { false }
        }
        .onAppear {
            since = .now
            arrived = true
        }
        .task(id: job.stage) {
            // The person's own step is all that is left: said, shown for a moment, then on to it.
            guard job.stage.progress(of: .choose) == .working else { return }
            AccessibilityNotification.Announcement(job.stage.headline + ". " + job.stage.detail(selected: job.selected)).post()
            try? await Task.sleep(for: max(Self.pause, Self.shortest - since.duration(to: .now)))
            if !Task.isCancelled { go() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Handoff")
                    .font(.title2.bold())
                    .tracking(-0.3)
                Text("Give an assistant this page's context.")
                    .font(.body)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, Self.indent)
            .padding(.bottom, 24)
            .arriving(0, arrived, plainly: reduceMotion)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Handoff.Step.allCases, id: \.self) { step in
                    StepRow(step: step, progress: job.stage.progress(of: step), stage: step == .organise ? job.stage : nil,
                            selected: job.selected, colour: colour, lively: !reduceMotion)
                        .arriving(step.rawValue + 1, arrived, plainly: reduceMotion)
                }
            }
            .padding(.horizontal, Self.indent)
            .padding(.bottom, 22)
            Button(action: go) {
                Text("Share Now")
                    .font(.headline)
                    .foregroundStyle(colour.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(colour.color, in: RoundedRectangle(cornerRadius: Self.inner, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScale())
            .keyboardShortcut(.defaultAction)
            .arriving(4, arrived, plainly: reduceMotion)
            Text("Nothing is sent until you pick an app.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .arriving(5, arrived, plainly: reduceMotion)
        }
        .padding(.horizontal, Self.edge)
        .padding(.top, 30)
        .padding(.bottom, foot)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What the sheet says of each step. Every line is long enough to fill its
/// last line on every iPhone's width, so none ends on a word alone.
private extension Handoff.Step {
    var symbol: String {
        switch self {
        case .file: "doc.text"
        case .organise: "sparkles"
        case .choose: "square.and.arrow.up"
        }
    }

    /// How far up the symbol is moved on its round mark, as a part of the
    /// mark's size. A symbol is set by its outline's middle, and the share
    /// symbol's weight is its box, under a thin arrow: set that way it
    /// sits a point and a half low to the eye, where the tick and the
    /// sparkles sit half a point low (measured on the screen). A point up
    /// puts its weight where theirs is.
    var lift: CGFloat {
        switch self {
        case .choose: 1.0 / 28
        case .file, .organise: 0
        }
    }

    var title: String {
        switch self {
        case .file: "The context is one file"
        case .organise: "Apple Intelligence organises it"
        case .choose: "You ask in the app you choose"
        }
    }

    var text: String {
        switch self {
        case .file: "Safience writes the page's text and its address into a Markdown file."
        // The sheet shows only while the model is asked, so this is so wherever it is read.
        case .organise: "On this device, it works out what kind of page this is and how much of it to send."
        // The question is the person's to ask, there: what goes with the file is only one to start from (Handoff.prompt).
        case .choose: "Pick an assistant in the share sheet and ask your question there. A starting one goes with the file."
        }
    }
}

/// One step of the handoff: how far it is, on a mark at its side with a
/// line down to the next step, and what the sheet says of it.
private struct StepRow: View {
    let step: Handoff.Step
    let progress: Handoff.Progress
    /// How far the handoff is, for the step that says so of the page at
    /// hand (StageCard), under what it says of every page.
    let stage: Handoff.Stage?
    /// Whether the person has something selected on the page (Handoff.Stage.detail).
    let selected: Bool
    let colour: SpaceColor
    /// Whether the step at work moves (not under Reduce Motion).
    let lively: Bool

    private var isLast: Bool {
        step == Handoff.Step.allCases.last
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                StepMark(symbol: step.symbol, lift: step.lift, progress: progress, colour: colour, lively: lively)
                if !isLast {
                    // In the colour once this step is done: the way to the next is open.
                    Capsule()
                        .fill(progress == .done ? colour.color : Palette.faint)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.headline)
                Text(step.text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let stage {
                    StageCard(stage: stage, selected: selected, colour: colour)
                        .padding(.top, 8)
                }
            }
            // The title's line stands at the middle of the mark, which is the higher of the two.
            .padding(.top, 3)
            .padding(.bottom, isLast ? 0 : 18)
        }
        // As high as its words, which is what the line down the side takes its length from.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityValue(spoken)
    }

    private var spoken: String {
        switch progress {
        case .done: "Done"
        case .working: "In progress"
        case .waiting: "Next"
        }
    }
}

/// What is going on with the page at hand, or what it turned out to be, and
/// what that means for what is shared (Handoff.Stage.headline, detail): the
/// part of the sheet that changes, set apart on a ground of its own so the
/// eye finds it. A symbol says the same at a glance: a page being looked
/// through, then the kind of page it is, in the space's colour.
private struct StageCard: View {
    let stage: Handoff.Stage
    let selected: Bool
    let colour: SpaceColor

    private var found: Bool {
        if case .ready = stage { true } else { false }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: stage.symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(found ? colour.color : Palette.muted)
                    .id(stage.symbol)
                    .transition(.swap)
            }
            .frame(minWidth: 24)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(stage.headline)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                Text(stage.detail(selected: selected))
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .contentTransition(.opacity)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private extension Handoff.Stage {
    /// A symbol for what the card says: a page looked through while it is
    /// read, then the kind of page it turned out to be.
    var symbol: String {
        switch self {
        case .reading, .organising, .stopped: "doc.text.magnifyingglass"
        case .ready(.article): "newspaper"
        case .ready(.landing): "megaphone"
        case .ready(.app): "macwindow"
        case .ready(.product): "tag"
        case .ready(.thread): "bubble.left.and.bubble.right"
        case .ready(.listing): "list.bullet"
        case .ready(.media): "play.rectangle"
        case .ready(.other): "globe"
        case .wordsOnly: "link"
        }
    }
}

/// A step's mark: its symbol on a round ground while it waits, in the
/// space's colour and moving while it is at work, a tick on the colour once
/// it is done.
private struct StepMark: View {
    let symbol: String
    /// How far up the symbol is moved to look centred, as a part of the mark's size (Handoff.Step.lift).
    let lift: CGFloat
    let progress: Handoff.Progress
    let colour: SpaceColor
    let lively: Bool

    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(ground)
            if progress == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(colour.ink)
                    .transition(.swap)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(progress == .working ? colour.color : Palette.muted)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: progress == .working && lively)
                    .offset(y: -size * lift)
                    .transition(.swap)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var ground: Color {
        switch progress {
        case .done: colour.color
        case .working: colour.color.opacity(0.16)
        case .waiting: Palette.wash
        }
    }
}

/// A part of the sheet as it arrives: a little lower, clear and soft, then
/// in place, each part a moment after the one above it. Only a fade under
/// Reduce Motion.
private struct Arriving: ViewModifier {
    let order: Int
    let arrived: Bool
    let plainly: Bool

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || plainly ? 0 : 10)
            .blur(radius: arrived || plainly ? 0 : 4)
            .animation(.spring(duration: 0.45, bounce: 0).delay(0.08 + Double(order) * 0.08), value: arrived)
    }
}

private extension View {
    func arriving(_ order: Int, _ arrived: Bool, plainly: Bool) -> some View {
        modifier(Arriving(order: order, arrived: arrived, plainly: plainly))
    }
}

/// A symbol as it takes another's place: from small, clear and soft.
private struct Swapping: ViewModifier {
    let away: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(away ? 0.25 : 1)
            .opacity(away ? 0 : 1)
            .blur(radius: away ? 4 : 0)
    }
}

private extension AnyTransition {
    static let swap = AnyTransition.modifier(active: Swapping(away: true), identity: Swapping(away: false))
}
