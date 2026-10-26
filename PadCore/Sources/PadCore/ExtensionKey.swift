import Foundation

/// A key an extension's command is given in Settings › Extensions: one
/// that types a character, with ⌘, ⌥ or ⌃, as a manifest's can be. eGlu
/// gives a command no key until the person gives it one, since ⌘ keys
/// belong to the page (Docs/ExtensionsDesign.md, section 2, Menus); what
/// the manifest suggests is offered. (Search's 9bd1966, 5970529, 6da963a)
public struct ExtensionKey: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let control = Modifiers(rawValue: 4)
        public static let shift = Modifiers(rawValue: 8)
    }

    /// The character, lowercased: a letter, a digit, or a punctuation key.
    public let key: String
    public let modifiers: Modifiers

    public init?(key: String, modifiers: Modifiers) {
        let lowered = key.lowercased()
        guard lowered.count == 1, let character = lowered.first, !character.isWhitespace, !character.isNewline,
              !modifiers.intersection([.command, .option, .control]).isEmpty
        else { return nil }
        self.key = lowered
        self.modifiers = modifiers
    }

    /// As kept: "cmd+opt+ctrl+shift+y", in that order.
    public var stored: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.shift) { parts.append("shift") }
        return (parts + [key]).joined(separator: "+")
    }

    public init?(stored: String) {
        var parts = stored.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "+" itself, kept as "...+" then an empty last part.
        if stored.hasSuffix("++") { parts.removeLast(2); parts.append("+") }
        guard let key = parts.popLast() else { return nil }
        var modifiers: Modifiers = []
        for part in parts {
            switch part {
            case "cmd": modifiers.insert(.command)
            case "opt": modifiers.insert(.option)
            case "ctrl": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        self.init(key: key, modifiers: modifiers)
    }

    /// As the Mac shows it: ⌃⌥⇧⌘ and the key.
    public var shown: String {
        var out = ""
        if modifiers.contains(.control) { out += "\u{2303}" }
        if modifiers.contains(.option) { out += "\u{2325}" }
        if modifiers.contains(.shift) { out += "\u{21E7}" }
        if modifiers.contains(.command) { out += "\u{2318}" }
        return out + key.uppercased()
    }

    /// A manifest's suggested key ("Alt+Shift+Y", "Command+Shift+K",
    /// "MacCtrl+Comma"), as Chrome reads it on a Mac: Ctrl and Command are
    /// ⌘, MacCtrl is ⌃. Nil for a media key or anything not read here.
    public init?(manifest: String) {
        let names: [String: String] = ["comma": ",", "period": ".", "space": " ", "home": "", "end": "", "pageup": "",
                                       "pagedown": "", "insert": "", "delete": "", "up": "", "down": "", "left": "", "right": ""]
        var modifiers: Modifiers = []
        var key: String?
        for part in manifest.split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part.lowercased() {
            case "ctrl", "command": modifiers.insert(.command)
            case "alt": modifiers.insert(.option)
            case "macctrl": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default:
                guard key == nil else { return nil }
                if let named = names[part.lowercased()] {
                    guard !named.isEmpty, named != " " else { return nil }
                    key = named
                } else {
                    guard part.count == 1 else { return nil }
                    key = part
                }
            }
        }
        guard let key else { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    /// A manifest command's suggested_key, as a Mac reads it: its "mac"
    /// key, else its "default", or the one string given for all.
    public init?(suggestedKey value: Any?) {
        let text = value as? String ?? (value as? [String: Any]).flatMap { ($0["mac"] ?? $0["default"]) as? String }
        guard let text else { return nil }
        self.init(manifest: text)
    }

    /// Keys never an extension's, whatever eGlu's menus have now: the
    /// Mac's own (quitting, hiding, the app switcher, Spotlight, logging
    /// out), eGlu's window and tab keys, ⌘W, ⌘T and ⌘N with ⇧ or ⌥, and
    /// the Developer menu's in both of the ways Settings offers (⌃⌥ and
    /// ⌥⌘), since switching would leave an extension's key on one.
    public var isReserved: Bool {
        let plain = modifiers.subtracting(.shift)
        if plain == .command, ["q", "h", "m", ",", "`", "w", "t", "n"].contains(key) { return true }
        if plain == [.command, .option], ["w", "t", "n", "h", "q", "m"].contains(key) { return true }
        if modifiers.contains(.command), modifiers.contains(.control), key == "q" { return true }
        if modifiers == [.control, .option], ["i", "j", "c", "e", "m"].contains(key) { return true }
        if modifiers == [.command, .option], ["i", "j", "c", "e", "r"].contains(key) { return true }
        if modifiers == [.control, .option, .shift], key == "r" { return true }
        return false
    }
}
