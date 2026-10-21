import AppKit
import PadCore
import SwiftUI

/// The menu bar: every command with its keys, as Safari and Arc have them.
/// A page hears each ⌘ key first, as in Safari; what it leaves comes here.
struct BrowserCommands: Commands {
    @FocusedObject private var window: WindowModel?
    @ObservedObject private var session = Session.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { window?.commandBar = .newTab }
                .keyboardShortcut("t")
            Button("New Window") { open(space: window?.spaceID) }
                .keyboardShortcut("n")
            Button("New Space") { window?.newSpace() }
            Divider()
            Button("Open Location…") { window?.commandBar = .here }
                .keyboardShortcut("l")
            Button("Reopen Closed Tab") { window?.reopenTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(session.workspace.closed.isEmpty)
            Divider()
            Button("Close Tab") { window?.closeTab() }
                .keyboardShortcut("w")
            Button("Close Window") { window?.window?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Share…") { window?.pageActionsShown = true }
                .disabled(window?.url == nil)
            if session.preferences.handoff, session.hasIntelligence {
                Button("Handoff Page…") { window?.startHandoff() }
                    .disabled(window?.canHandoff != true)
            }
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { window?.page?.print() }
                .keyboardShortcut("p")
                .disabled(window?.page == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Link") { window?.copyLink() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(window?.url == nil)
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find on Page…") { window?.startFinding() }
                .keyboardShortcut("f")
                .disabled(window?.page == nil)
            Button("Find Next") { window?.find() }
                .keyboardShortcut("g")
                .disabled(window?.findText.isEmpty ?? true)
            Button("Find Previous") { window?.find(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(window?.findText.isEmpty ?? true)
        }
        CommandGroup(replacing: .sidebar) {
            Button(window?.sidebarShown == false ? "Keep Sidebar Open" : "Hide Sidebar") { window?.toggleSidebar() }
                .keyboardShortcut("s")
                .disabled(window?.tabsInSidebar == false)
            Button(session.preferences.tabsPlacement == .top ? "Show Tabs in Sidebar" : "Show Tabs Along the Top") {
                session.preferences.tabsPlacement = session.preferences.tabsPlacement == .top ? .sidebar : .top
            }
            // The bar is under the tabs along the top; the sidebar has its own Bookmarks section.
            Button(session.preferences.bookmarksBar ? "Hide Bookmarks Bar" : "Show Bookmarks Bar") {
                withAnimation(.bar) { session.preferences.bookmarksBar.toggle() }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(window?.tabsInSidebar != false)
        }
        CommandGroup(before: .toolbar) {
            Button("Reload Page") { window?.reload() }
                .keyboardShortcut("r")
            Button("Stop Loading") { window?.stop() }
                .keyboardShortcut(".")
                .disabled(window?.loading != true)
            Divider()
            Button("Actual Size") { window?.page?.zoom(by: 0) }
                .keyboardShortcut("0")
            // ⌘= is the key under +, as every browser takes it.
            Button("Zoom In") { window?.page?.zoom(by: 1) }
                .keyboardShortcut("=")
            Button("Zoom Out") { window?.page?.zoom(by: -1) }
                .keyboardShortcut("-")
            Divider()
            Button(window?.blocksContentHere == false ? "Block Ads on This Site" : "Allow Ads on This Site") {
                window?.toggleBlocking()
            }
            .disabled(window?.url?.host == nil || !session.preferences.blocksContent)
            Divider()
        }
        CommandMenu("History") {
            Button("Back") { window?.back() }
                .keyboardShortcut("[")
                .disabled(window?.canGoBack != true)
            Button("Forward") { window?.forward() }
                .keyboardShortcut("]")
                .disabled(window?.canGoForward != true)
            Divider()
            Button("Show All History") { window?.historyShown = true }
                .keyboardShortcut("y")
                .disabled(window == nil)
            Button("Clear History…") { window?.historyClearing = true }
                .disabled(window == nil)
        }
        CommandMenu("Tabs") {
            Button("Show Next Tab") { window?.selectTab(by: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Show Previous Tab") { window?.selectTab(by: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Next Tab") { window?.selectTab(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Previous Tab") { window?.selectTab(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Divider()
            Button(window?.tab?.isPinned == true ? "Unpin Tab" : "Pin Tab") { window?.togglePin() }
                .keyboardShortcut("d")
                .disabled(window?.tab?.url == nil)
            Button(window?.isBookmarked == true ? "Remove Bookmark" : "Bookmark This Page") { window?.toggleBookmark() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(window?.url == nil)
            Button("Duplicate Tab") { window?.duplicate() }
                .disabled(window?.tab?.url == nil)
            Divider()
            // Split View: the tab on screen and another, side by side.
            Button(window?.split == nil ? "Split with New Tab" : "Separate Tabs") { window?.perform(.splitTab) }
                .keyboardShortcut("\\", modifiers: [.command, .option])
                .disabled(window?.tab == nil || window?.tab?.isPinned == true)
            Button("Swap Sides") { window?.swapSides() }
                .disabled(window?.split == nil)
            Divider()
            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Last Tab" : "Tab \(number)") { window?.selectTab(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")))
            }
        }
        CommandMenu("Spaces") {
            Button("Next Space") { window?.showSpace(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Space") { window?.showSpace(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            ForEach(Array(session.workspace.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button {
                    window?.showSpace(space.id)
                } label: {
                    Label(space.name, systemImage: space.symbol)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
            }
            Divider()
            Button("Space Settings…") { window?.spacesPanel = .list }
            Button("New Space") { window?.newSpace() }
        }
        CommandGroup(after: .appSettings) {
            Button("Make Safience the Default Browser…") { DefaultBrowser.ask() }
                .disabled(DefaultBrowser.isDefault)
        }
    }

    private func open(space: UUID?) {
        session.openWindow?(space)
    }
}

/// Safience as the browser that opens links from other apps: macOS asks the
/// person first, in a dialog of its own.
enum DefaultBrowser {
    static var isDefault: Bool {
        guard let probe = URL(string: "https://example.com"),
              let browser = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return false }
        return browser.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func ask() {
        let app = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { _ in }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { _ in }
    }
}
