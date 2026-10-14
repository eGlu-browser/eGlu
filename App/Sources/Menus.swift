import PadCore
import UIKit

/// The app's menus, which are mostly an absence.
///
/// Every menu iPadOS puts in an app by itself (File, Edit, Format, View,
/// Window, Help, and the app menu's own items; the menu bar of iPadOS 26
/// shows them all) comes with shortcuts on ⌘: ⌘F, ⌘W, ⌘N, ⌘Z, ⌘B. A menu's
/// shortcut answers before the page hears the key, so Figma's ⌘Z, a page's
/// own ⌘F, a document's ⌘B would never reach the page. They are all taken
/// out, whichever of them this iPadOS has, and the browser's own commands
/// go in their place on ⌃⌥, which pages leave alone, but for the few keys
/// every browser keeps for itself, ⌘T and the like (Chord.Base). Two of iPadOS's stay,
/// without their ⌘ keys: the Window menu, which iPadOS shows in any case,
/// and the app menu's item that opens Safience's page in the Settings app.
/// What this device can do. An iPhone has one window, one pane, no tab
/// bar, and no keyboard shortcuts: UIKit builds the menus that carry them
/// on iPad and Mac only. Every list of commands asks here, so nothing is
/// offered that does nothing.
@MainActor
enum Device {
    static var phone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// The keys a command has, to show beside it: none where none work.
    static func keys(for command: Command) -> String? {
        phone ? nil : Shortcuts.chord(for: command)?.label
    }

    static func offers(_ command: Command) -> Bool {
        switch command {
        case .newWindow, .closeWindow: return UIApplication.shared.supportsMultipleScenes
        case .tabBar, .focusPage, .splitTab, .siteMode: return !phone
        // Only where Settings has turned it on, and only with Apple Intelligence to ask.
        case .handoff: return Session.shared.preferences.handoff && Session.shared.hasIntelligence
        default: return true
        }
    }

    /// Whether Settings has that part here: an iPhone's has no trackpad's,
    /// App Icon is there only where the system lets an app change it, and
    /// Handoff only where the device has Apple Intelligence.
    @MainActor static func offers(_ anchor: SettingsAnchor) -> Bool {
        if anchor == .appIcon, !UIApplication.shared.supportsAlternateIcons { return false }
        if anchor == .handoff, !Session.shared.hasIntelligence { return false }
        return anchor.isOffered(phone: phone)
    }

    /// "iPhone" or "iPad", for what the app says about this device.
    static var name: String {
        phone ? "iPhone" : "iPad"
    }
}

extension Command {
    /// An SF Symbol for the command, beside its name in the command bar.
    var symbol: String {
        switch self {
        case .everything: return "command"
        case .newTab: return "plus"
        case .closeTab: return "xmark"
        case .reopenTab: return "arrow.uturn.backward"
        case .address: return "link"
        case .reload: return "arrow.clockwise"
        case .stop: return "xmark.circle"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .nextTab: return "arrow.right.square"
        case .previousTab: return "arrow.left.square"
        case .nextSpace: return "arrow.down.square"
        case .previousSpace: return "arrow.up.square"
        case .newSpace: return "plus.square.on.square"
        case .newWindow: return "macwindow.badge.plus"
        case .closeWindow: return "xmark.rectangle"
        case .tabBar: return "menubar.rectangle"
        case .diagnostics: return "waveform.path.ecg"
        case .settings: return "gearshape"
        case .focusPage: return "keyboard"
        case .pinTab: return "pin"
        case .splitTab: return "rectangle.split.2x1"
        case .bookmark: return "star"
        case .share: return "square.and.arrow.up"
        case .siteMode: return "desktopcomputer"
        case .spaceSettings: return "slider.horizontal.3"
        case .importBookmarks: return "square.and.arrow.down"
        case .contentBlocking: return "shield"
        case .linkMenu: return "contextualmenu.and.cursorarrow"
        case .find: return "text.magnifyingglass"
        // Passed on, as a message is forwarded: not the share sheet's own arrow, which sits beside it.
        case .handoff: return "arrowshape.turn.up.right"
        }
    }
}

@MainActor
enum Menus {
    static func build(_ builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        for child in builder.menu(for: .root)?.children ?? [] {
            // The app menu and the Window menu stay. iPadOS shows a Window
            // menu of its own whatever the app does (tiling, the open
            // windows), so the window's commands join it, not a second one.
            guard let menu = child as? UIMenu, menu.identifier != .application, menu.identifier != .window else { continue }
            builder.remove(menu: menu.identifier)
        }

        // The app menu: Safience's settings, where an app's settings go, and
        // iPadOS's own item, which opens Safience's page in the Settings app
        // (permissions, the default browser). iPadOS names that one
        // "Safience Settings…" too; it is named for where it goes instead.
        builder.replaceChildren(ofMenu: .application) { children in
            let system = children.compactMap { $0 as? UIMenu }.filter { $0.identifier == .preferences }
                .flatMap(\.children).map(withoutCommandKeys)
            for case let command as UICommand in system { command.title = "iPadOS Settings…" }
            let own = [keyCommand(.settings, title: "Settings…")].compactMap { $0 }
            return [UIMenu(title: "", identifier: Identifier.settings, options: .displayInline, children: own + system)]
        }

        // Each menu's commands are a group's (ShortcutGroup), the order the
        // command bar lists them in too.
        builder.insertSibling(menu(.go), afterMenu: .application)
        builder.insertSibling(tabsMenu(), afterMenu: Identifier.go)
        builder.insertSibling(menu(.spaces), afterMenu: Identifier.tabs)

        // Settings has its place in the app menu, above.
        let window = ShortcutGroup.window.commands.filter { $0 != .settings }.compactMap { keyCommand($0) }
        if let system = builder.menu(for: .window) {
            // Its own items keep their place, without ⌘ keys; the window's commands go first.
            builder.replace(menu: .window, with: system.replacingChildren(
                [UIMenu(title: "", identifier: Identifier.window, options: .displayInline, children: window)]
                    + system.children.map(withoutCommandKeys)
            ))
        } else {
            builder.insertSibling(UIMenu(title: "Window", identifier: Identifier.window, children: window),
                                  afterMenu: Identifier.spaces)
        }
    }

    /// A system item as it was, without its ⌘ shortcut: a shortcut on ⌘ answers
    /// before the page hears the key. The item still does what it did.
    private static func withoutCommandKeys(_ element: UIMenuElement) -> UIMenuElement {
        if let menu = element as? UIMenu {
            return menu.replacingChildren(menu.children.map(withoutCommandKeys))
        }
        guard let key = element as? UIKeyCommand, key.modifierFlags.contains(.command), let action = key.action else {
            return element
        }
        return UICommand(title: key.title, image: key.image, action: action, propertyList: key.propertyList,
                         alternates: key.alternates, discoverabilityTitle: key.discoverabilityTitle,
                         attributes: key.attributes, state: key.state)
    }

    enum Identifier {
        static let go = UIMenu.Identifier("Safience.Go")
        static let tabs = UIMenu.Identifier("Safience.Tabs")
        static let spaces = UIMenu.Identifier("Safience.Spaces")
        static let window = UIMenu.Identifier("Safience.Window")
        static let settings = UIMenu.Identifier("Safience.Settings")

        static func of(_ group: ShortcutGroup) -> UIMenu.Identifier {
            switch group {
            case .go: return go
            case .tabs: return tabs
            case .spaces: return spaces
            case .window: return window
            }
        }
    }

    private static func menu(_ group: ShortcutGroup) -> UIMenu {
        UIMenu(title: group.title, identifier: Identifier.of(group),
               children: group.commands.filter(Device.offers).compactMap { keyCommand($0) })
    }

    private static func tabsMenu() -> UIMenu {
        let main = ShortcutGroup.tabs.commands.compactMap { keyCommand($0) }
        let numbers = Shortcuts.tabNumbers.enumerated().map { index, chord -> UIKeyCommand in
            let title = index == 8 ? "Last Tab" : "Tab \(index + 1)"
            return UIKeyCommand(title: title, action: #selector(Browser.browserTab(_:)), input: input(chord.key),
                                modifierFlags: flags(chord), propertyList: index + 1)
        }
        return UIMenu(title: "Tabs", identifier: Identifier.tabs, children: main + [
            UIMenu(title: "", options: .displayInline, children: numbers),
        ])
    }

    private static func keyCommand(_ command: Command, title: String? = nil) -> UIKeyCommand? {
        guard let chord = Shortcuts.chord(for: command) else { return nil }
        return UIKeyCommand(title: title ?? command.title, action: #selector(Browser.browserCommand(_:)),
                            input: input(chord.key), modifierFlags: flags(chord), propertyList: command.rawValue)
    }

    private static func flags(_ chord: Chord) -> UIKeyModifierFlags {
        var flags: UIKeyModifierFlags
        switch chord.base {
        case .controlOption: flags = [.control, .alternate]
        case .command: flags = .command
        case .control: flags = .control
        }
        if chord.shift { flags.insert(.shift) }
        return flags
    }

    private static func input(_ key: Key) -> String {
        switch key {
        case .character(let c): return c
        case .left: return UIKeyCommand.inputLeftArrow
        case .right: return UIKeyCommand.inputRightArrow
        case .up: return UIKeyCommand.inputUpArrow
        case .down: return UIKeyCommand.inputDownArrow
        case .escape: return UIKeyCommand.inputEscape
        case .tab: return "\t"
        }
    }
}
