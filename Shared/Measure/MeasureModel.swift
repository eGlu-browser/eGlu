import Foundation
import PadCore

/// A running measuring tool's state for its panel (measure.js): the element
/// it last told of and the distance under the pointer, the colour picked,
/// and the guide settings the fields edit. Its page makes one when the tool
/// starts and lets it go when the tool ends, so a run keeps nothing.
@MainActor @Observable
final class MeasureModel {
    /// The selected element, or nil before the first pick.
    var details: MeasureDetails?
    /// The distance under ⌥ or the last element tapped, nil while none.
    var distance: MeasureDistance?
    /// The last colour the picker came back with.
    var colour: MeasureColour?
    /// Whether a colour pick is on its way (the button says Picking…).
    var colourBusy = false
    /// The guide and ruler settings: the fields edit them, the page hears
    /// of each change, and preferences keep them for the next run.
    var guides: MeasureGuides {
        didSet {
            guard guides != oldValue else { return }
            guides.keep(in: &Session.shared.preferences)
            apply(argument)
        }
    }
    /// The guides and the x-ray over the page, switched here or with G and X
    /// on the page; for this run only.
    var showsGuides = false {
        didSet { if showsGuides != oldValue { apply(argument) } }
    }
    var showsXray = false {
        didSet { if showsXray != oldValue { apply(argument) } }
    }
    /// The run of the tool this is (Page.startMeasuring): what an earlier
    /// run says on its way out is not this one's.
    let run: Int
    /// The page's address, and the window's size and zoom as they are when
    /// the notes are copied, for what an assistant is given (Copy for an
    /// Assistant).
    var pageURL = ""
    var window: () -> String = { "" }
    /// The notes made, each with its element's details of when it was
    /// picked; their dots pin by number (MeasureNote). They are the tab's,
    /// kept by its Page while the tool comes and goes, and gone when the
    /// page navigates or closes (Decided 7).
    var notes: [MeasureNote] = [] {
        didSet { if notes != oldValue { notesChanged(notes) } }
    }
    var notesChanged: ([MeasureNote]) -> Void = { _ in }

    /// The five things only the page can do, given by its Page: take new
    /// settings, pick a colour, end the tool, and pin or unpin a note's dot.
    var apply: ([String: Any]) -> Void = { _ in }
    var pickColour: () -> Void = {}
    var end: () -> Void = {}
    var pin: (_ id: UUID, _ ref: Int, _ number: Int) -> Void = { _, _, _ in }
    var unpin: (_ id: UUID) -> Void = { _ in }

    init(guides: MeasureGuides, run: Int) {
        self.guides = guides
        self.run = run
    }

    /// What measure.js takes, at its start and with each change: the guides'
    /// settings, what shows, and the run.
    var argument: [String: Any] {
        guides.argument.merging(["guidesOn": showsGuides, "xray": showsXray, "run": run]) { _, new in new }
    }

    /// G, R or X pressed on the page: the switches follow, and the rulers'
    /// is kept, as the panel's own is.
    func said(guides shown: Bool, rulers: Bool, xray: Bool) {
        showsGuides = shown
        showsXray = xray
        guides.rulers = rulers
    }

    /// What the page said, one message of the three kinds.
    func said(_ details: MeasureDetails) {
        self.details = details
        distance = nil
    }

    /// A note written on the selected element: numbered in the order made,
    /// its dot pinned to the element by the page.
    func addNote(_ words: String) {
        guard let details, !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let note = MeasureNote(number: (notes.map(\.number).max() ?? 0) + 1, details: details, note: words)
        notes.append(note)
        pin(note.id, note.ref, note.number)
    }

    /// A note taken away, its dot unpinned.
    func removeNote(_ note: MeasureNote) {
        notes.removeAll { $0.id == note.id }
        unpin(note.id)
    }

    /// The notes as plain text an assistant can act on (Copy for an Assistant).
    var textForAssistant: String {
        MeasureNotes.text(page: pageURL, viewport: window(), notes: notes)
    }

    func said(_ distance: MeasureDistance) {
        self.distance = distance.gone ? nil : distance
    }
}
