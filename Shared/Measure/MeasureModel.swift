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
    /// The page's address, and the window's size and zoom as the notes say
    /// them, for what an assistant is given (Copy, in the second part).
    var pageURL = ""
    var viewport = ""

    /// The three things only the page can do, given by its Page: take new
    /// settings, pick a colour, end the tool.
    var apply: ([String: Any]) -> Void = { _ in }
    var pickColour: () -> Void = {}
    var end: () -> Void = {}

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
