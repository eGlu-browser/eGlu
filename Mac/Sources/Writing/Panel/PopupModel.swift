// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.

import AppKit
import Foundation

/// What the panel over another app's field needs from a lint. eGlu makes
/// this struct itself (Docs/Tasks/03): no JSON, no Rust side, and no
/// Clarity fields.
struct PopupData: Equatable {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        var color: NSColor {
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
        }
    }

    var kindName: String
    var kindColor: RGB
    /// Markdown.
    var message: String
    var suggestions: [String]
    var canAddToDictionary: Bool
}

/// A button the panel reports back to the checker, as Harper Desktop
/// numbers them.
enum PopupAction: Int {
    case close = 0
    case applySuggestion = 1
    case ignoreLint = 2
    case addToDictionary = 3
    case disableRule = 4
}

/// The lint kinds' colours, the same ones underlines and the panel use:
/// writing.js's KIND_COLORS (task 02).
enum WritingColors {
    static func rgb(for kind: String) -> PopupData.RGB {
        let hex: String
        switch kind {
        case "Agreement": hex = "#228B22"
        case "BoundaryError": hex = "#8B4513"
        case "Capitalization": hex = "#540D6E"
        case "Eggcorn": hex = "#FF8C00"
        case "Enhancement": hex = "#0EAD69"
        case "Formatting": hex = "#7D3C98"
        case "Grammar": hex = "#9B59B6"
        case "Malapropism": hex = "#C71585"
        case "Miscellaneous": hex = "#3BCEAC"
        case "Nonstandard": hex = "#008B8B"
        case "Punctuation": hex = "#D4850F"
        case "Readability": hex = "#2E8B57"
        case "Redundancy": hex = "#4682B4"
        case "Regionalism": hex = "#C061CB"
        case "Repetition": hex = "#00A67C"
        case "Spelling": hex = "#EE4266"
        case "Style": hex = "#FFD23F"
        case "Typo": hex = "#FF6B35"
        case "Usage": hex = "#1E90FF"
        case "WordChoice": hex = "#228B22"
        case "WordOrder": hex = "#4D4DFF"
        default: hex = "#808080"
        }
        return PopupData.RGB(hex: hex)
    }

    static func color(for kind: String) -> NSColor {
        rgb(for: kind).color
    }
}

extension PopupData.RGB {
    /// A "#RRGGBB" colour; anything else is black.
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }
}
