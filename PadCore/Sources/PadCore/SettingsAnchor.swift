import Foundation

/// A part of Settings the address bar goes straight to: "change icon" typed
/// there offers App Icon, and taking the row opens Settings scrolled to it.
/// One for each section of the Settings screen (SettingsView), found by its
/// name and by the words for what is changed there.
public enum SettingsAnchor: String, CaseIterable, Sendable {
    case defaultBrowser
    case sync
    case appIcon
    case desktopView
    case addressBar
    case window
    case spaces
    case memory
    case trackpad
    case search
    case history
    case blocking
    case linkMenu
    case handoff
    case diagnostics
    case shortcuts

    /// The section, as its row names it.
    public var title: String {
        switch self {
        case .defaultBrowser: return "Default Browser"
        case .sync: return "iCloud Sync"
        case .appIcon: return "App Icon"
        case .desktopView: return "Desktop View Cursor Speed"
        case .addressBar: return "Address Bar"
        case .window: return "Tabs and Address Bar"
        case .spaces: return "Spaces and Bookmarks"
        case .memory: return "Memory"
        case .trackpad: return "Trackpad and Keyboard"
        case .search: return "Search Engine"
        case .history: return "History"
        case .blocking: return "Ads and Trackers"
        case .linkMenu: return "Link Menu"
        case .handoff: return "Handoff"
        case .diagnostics: return "Diagnostics"
        case .shortcuts: return "Keyboard Shortcuts"
        }
    }

    /// What is changed there, for the line under the name.
    public var detail: String {
        switch self {
        case .defaultBrowser: return "Open links from other apps here"
        case .sync: return "Spaces, bookmarks and tabs on your devices"
        case .appIcon: return "The Home Screen icon"
        case .desktopView: return "How far the cursor goes"
        case .addressBar: return "The page's address or its title"
        case .window: return "Tabs along the top or in a sidebar"
        case .spaces: return "Edit spaces, import bookmarks"
        case .memory: return "Tabs kept open off screen"
        case .trackpad: return "Scrolling, Tab and arrow keys, cursors"
        case .search: return "The engine, suggestions, Apple Intelligence"
        case .history: return "How long it is kept, clearing it"
        case .blocking: return "The content blocker and its lists"
        case .linkMenu: return "Sites with their own menus"
        case .handoff: return "A page and a question, to another app"
        case .diagnostics: return "The panel over the page"
        case .shortcuts: return "Every command's keys"
        }
    }

    /// Words it is also found by: what one wants done, not what the section
    /// is called.
    public var keywords: [String] {
        switch self {
        case .defaultBrowser: return ["set as default", "make default", "browser app", "open links"]
        case .sync: return ["sync", "icloud", "cloudkit", "other devices", "mac", "turn on sync"]
        case .appIcon:
            return ["change icon", "change app icon", "home screen icon", "alternate icon", "icon style", "logo"]
        case .desktopView: return ["cursor speed", "pointer speed", "sensitivity", "tracking speed"]
        case .addressBar: return ["show address", "show title", "url", "page title"]
        case .window:
            return ["layout", "compact", "separate", "tab layout", "hide tab bar", "show tab bar", "window", "sidebar",
                    "vertical tabs",
                    "show address", "show title", "url"]
        case .spaces: return ["manage spaces", "edit spaces", "rename space", "delete space", "reorder spaces", "profiles"]
        case .memory: return ["light tabs", "tabs kept open", "freeze tabs", "frozen tabs", "background tabs", "ram"]
        case .trackpad:
            return ["two-finger scroll", "scroll", "wheel", "tab key", "arrow keys", "page cursor", "pointer", "bridge"]
        case .search:
            return ["change search engine", "default search", "suggestions", "search suggestions", "autocomplete",
                    "apple intelligence"] + Engine.allCases.map { $0.title.lowercased() }
        case .history:
            return ["clear history", "delete history", "browsing history", "keep history", "forget", "erase"]
        case .blocking: return ["ad blocker", "adblock", "block ads", "content blocker", "privacy", "easylist"]
        case .linkMenu: return ["context menu", "long press", "right click", "secondary click", "own menus"]
        case .handoff:
            return ["ai", "ask ai", "assistant", "claude", "chatgpt", "gemini", "markdown", "summarize", "question", "prompt"]
        case .diagnostics: return ["debug", "hud", "show diagnostics", "user agent"]
        case .shortcuts: return ["shortcuts", "cheat sheet", "cheatsheet", "keys", "hotkeys", "key commands"]
        }
    }

    /// Whether Settings has the section on this kind of device: an iPhone
    /// has one bar and no trackpad, an iPad no Desktop View.
    public func isOffered(phone: Bool) -> Bool {
        switch self {
        case .desktopView, .addressBar: return phone
        case .window, .trackpad, .shortcuts: return !phone
        default: return true
        }
    }
}
