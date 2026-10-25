import AppKit
import PadCore

/// Edit › Spelling and Grammar, where a Mac's checking is: Harper's switch
/// (Settings › Writing's first) and Accept Writing Suggestion (⌃⌥G) at its
/// top, then the system's own items.
///
/// SwiftUI's Edit menu has no such submenu, and a `Commands` button can't
/// stand for the system's items: those are answered by the field or page
/// with the keys, which sets each one's checkmark. So the submenu is
/// AppKit's, with the system's actions sent to whatever has the keys, and
/// Check Spelling While Typing shows WebKit's real state, off while Harper
/// checks (WritingSpelling). SwiftUI fills the Edit menu again as it opens,
/// taking out what it didn't put there, so the submenu goes back in as
/// soon as SwiftUI is done; between openings it stays, for ⌃⌥G.
@MainActor
final class WritingMenu: NSObject, NSMenuItemValidation {
    static let shared = WritingMenu()

    private lazy var spellingItem: NSMenuItem = {
        let title = String(localized: "Spelling and Grammar")
        let menu = NSMenu(title: title)
        menu.items = [writingItem, acceptItem, .separator()] + Self.systemItems()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }()

    private lazy var writingItem: NSMenuItem = {
        let item = NSMenuItem(title: String(localized: "Check Grammar and Spelling in Pages"),
                              action: #selector(toggleWriting(_:)), keyEquivalent: "")
        item.target = self
        return item
    }()

    private lazy var acceptItem: NSMenuItem = {
        // On ⌃⌥, the browser's own keys, which pages leave alone.
        let item = NSMenuItem(title: String(localized: "Accept Writing Suggestion"),
                              action: #selector(acceptSuggestion(_:)), keyEquivalent: "g")
        item.keyEquivalentModifierMask = [.control, .option]
        item.target = self
        return item
    }()

    /// AppKit's own Spelling and Grammar items, with no target, so they go
    /// to the field or page with the keys. Without Safari's ⌘: and ⌘;: a
    /// ⌘ key is the page's, and eGlu's own keys are ⌃⌥.
    private static func systemItems() -> [NSMenuItem] {
        let items: [(String, Selector)?] = [
            (String(localized: "Show Spelling and Grammar"), #selector(NSTextView.showGuessPanel(_:))),
            (String(localized: "Check Document Now"), #selector(NSTextView.checkSpelling(_:))),
            nil,
            (String(localized: "Check Spelling While Typing"), #selector(NSTextView.toggleContinuousSpellChecking(_:))),
            (String(localized: "Check Grammar With Spelling"), #selector(NSTextView.toggleGrammarChecking(_:))),
            (String(localized: "Correct Spelling Automatically"), #selector(NSTextView.toggleAutomaticSpellingCorrection(_:))),
        ]
        return items.map { entry in
            guard let (title, action) = entry else { return .separator() }
            return NSMenuItem(title: title, action: action, keyEquivalent: "")
        }
    }

    private var watching: [NSObjectProtocol] = []
    private var placing = false

    /// Once, at launch, when the workspace is ready.
    func start() {
        guard watching.isEmpty else { return }
        let center = NotificationCenter.default
        // SwiftUI posts its items as they go in: once they are all in, the
        // Edit menu gets the submenu back.
        for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification] {
            watching.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeSoon() }
            })
        }
        place()
    }

    private func placeSoon() {
        guard !placing else { return }
        placing = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            placing = false
            place()
        }
    }

    /// The submenu after Find Previous, as Safari has it after Find, unless
    /// it is in the Edit menu already. An item can be in one menu only, so
    /// it leaves an Edit menu SwiftUI has since let go of first.
    private func place() {
        guard let edit = NSApp.mainMenu.flatMap(Self.editMenu(in:)) else { return }
        guard spellingItem.menu !== edit else { return }
        spellingItem.menu?.removeItem(spellingItem)
        let findPrevious = String(localized: "Find Previous")
        let after = edit.items.lastIndex { $0.title == findPrevious }
            ?? edit.items.lastIndex { $0.action == #selector(NSText.selectAll(_:)) }
            ?? edit.items.count - 1
        edit.insertItem(spellingItem, at: after + 1)
    }

    /// The menu bar's menu with Paste in it, whatever it is called in the
    /// Mac's language.
    private static func editMenu(in bar: NSMenu) -> NSMenu? {
        bar.items.lazy.compactMap(\.submenu).first { menu in
            menu.items.contains { $0.action == #selector(NSText.paste(_:)) }
        }
    }

    /// The browser window with the keys, as the menu bar's other commands
    /// take it: none while Settings or a little window has them.
    private var window: WindowModel? {
        Session.shared.allWindows.first { $0.window?.isKeyWindow == true }
    }

    @objc private func toggleWriting(_ sender: NSMenuItem) {
        Session.shared.preferences.writing.toggle()
    }

    @objc private func acceptSuggestion(_ sender: NSMenuItem) {
        window?.perform(.acceptWritingSuggestion)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleWriting(_:)):
            item.state = Session.shared.preferences.writing ? .on : .off
            return Session.shared.canUseWorkspace
        case #selector(acceptSuggestion(_:)):
            // Only while a card is open on a word: ⌃⌥G is then its first fix.
            return window?.page?.writingCardOpen == true
        default:
            return false
        }
    }
}
