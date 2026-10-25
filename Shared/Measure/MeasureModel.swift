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
        didSet { moved() }
    }
    /// The page's address, and the window's size and zoom as the notes say
    /// them, for what an assistant is given (Copy, in the second part).
    var pageURL = ""
    var viewport = ""

    /// The three things only the page can do, given by its Page: take new
    /// settings, pick a colour, end the tool.
    var apply: (MeasureGuides) -> Void = { _ in }
    var pickColour: () -> Void = {}
    var end: () -> Void = {}

    init(guides: MeasureGuides) {
        self.guides = guides
    }

    /// A field moved: the running tool hears of it, and preferences keep it.
    private func moved() {
        apply(guides)
        Session.shared.preferences.measureColumns = guides.columns
        Session.shared.preferences.measureGutter = guides.gutter
        Session.shared.preferences.measureMargin = guides.margin
        Session.shared.preferences.measureRow = guides.row
        Session.shared.preferences.measureRulers = guides.rulers
    }

    /// What the page said, one message of the three kinds.
    func said(_ details: MeasureDetails) {
        self.details = details
        distance = nil
    }

    func said(_ distance: MeasureDistance) {
        self.distance = distance.gone ? nil : distance
    }

    /// The tool ended on its own (Escape), or the page is asked to stop.
    func ended() {
        details = nil
        distance = nil
        end()
    }
}
