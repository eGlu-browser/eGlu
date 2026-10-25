import Foundation
import PadCore

/// writing.js as a page gets it: the card's words from the String Catalog,
/// written in as data (Docs/Tasks/02 Decided 12), and the key that takes
/// the first suggestion, as the app shows it.
enum WritingScript {
    /// `acceptKey` is the key as menus write it (⌃⌥G), `acceptShortcut` as
    /// VoiceOver reads it (aria-keyshortcuts); nil where no key is shown.
    static func source(acceptKey: String?, acceptShortcut: String?) -> String {
        var keys: [String: String] = [:]
        if let acceptKey { keys["accept"] = acceptKey }
        if let acceptShortcut { keys["acceptShortcut"] = acceptShortcut }
        return Scripts.writing(strings: strings, keys: keys)
    }

    /// The card's buttons, and Harper's kinds of problem by name: Harper
    /// gives them as identifiers (WordChoice), shown here as words.
    private static let strings: [String: String] = [
        "card.close": String(localized: "Close"),
        "card.ignore": String(localized: "Ignore"),
        "card.addToDictionary": String(localized: "Add to Dictionary"),
        "card.disableRule": String(localized: "Turn Off This Rule"),
        "kind.Agreement": String(localized: "Agreement"),
        "kind.BoundaryError": String(localized: "Word Boundary"),
        "kind.Capitalization": String(localized: "Capitalisation"),
        "kind.Eggcorn": String(localized: "Eggcorn"),
        "kind.Enhancement": String(localized: "Enhancement"),
        "kind.Formatting": String(localized: "Formatting"),
        "kind.Grammar": String(localized: "Grammar"),
        "kind.Malapropism": String(localized: "Malapropism"),
        "kind.Miscellaneous": String(localized: "Miscellaneous"),
        "kind.Nonstandard": String(localized: "Nonstandard"),
        "kind.Punctuation": String(localized: "Punctuation"),
        "kind.Readability": String(localized: "Readability"),
        "kind.Redundancy": String(localized: "Redundancy"),
        "kind.Regionalism": String(localized: "Regionalism"),
        "kind.Repetition": String(localized: "Repetition"),
        "kind.Spelling": String(localized: "Spelling"),
        "kind.Style": String(localized: "Style"),
        "kind.Typo": String(localized: "Typo"),
        "kind.Usage": String(localized: "Usage"),
        "kind.WordChoice": String(localized: "Word Choice"),
        "kind.WordOrder": String(localized: "Word Order"),
    ]
}
