import AppKit
import PadCore
import SwiftUI

/// The menu bar: every command with its keys, as Safari and Arc have them.
/// A page hears each ⌘ key first, as in Safari; what it leaves comes here.
struct BrowserCommands: Commands {
    @FocusedObject private var window: WindowModel?
    @ObservedObject private var session = Session.shared
    @ObservedObject private var extensions = Extensions.shared
    /// The little window with the keys, if one has them: ⌘O, ⌘W, ⌘L, ⌘R and
    /// ⇧⌘C are its, as they are a browser window's (LittleWindow.swift).
    @ObservedObject private var littleWindows = LittleWindows.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { window?.commandBar = .newTab }
                .keyboardShortcut("t")
            Button("New Window") { open(space: window?.spaceID) }
                .keyboardShortcut("n")
            Button("New Little Window") { LittleWindow.open(nil, in: window?.spaceID) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Space") { window?.newSpace() }
            Divider()
            Button("Open Location…") {
                if let little = littleWindows.key { little.startTyping() } else { window?.commandBar = .here }
            }
            .keyboardShortcut("l")
            // A Peek's page, or a little window's, in a tab of its own, as Arc's ⌘O.
            Button("Open in New Tab") {
                if let little = littleWindows.key { little.openInTab() } else { window?.openPeekInTab() }
            }
            .keyboardShortcut("o")
            .disabled(littleWindows.key == nil && window?.peek == nil)
            Button("Reopen Closed Tab") { window?.reopenTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(session.workspace.closed.isEmpty)
            Divider()
            Button("Close Tab") {
                if let little = littleWindows.key { little.close() } else { window?.closeTab() }
            }
            .keyboardShortcut("w")
            Button("Close Window") {
                if let little = littleWindows.key { little.close() } else { window?.window?.performClose(nil) }
            }
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
            Button("Copy Link") {
                if let little = littleWindows.key { little.copyLink() } else { window?.copyLink() }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(littleWindows.key?.url == nil && window?.url == nil)
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
            Button("Reload Page") {
                if let little = littleWindows.key { little.reload() } else { window?.reload() }
            }
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
        CommandMenu("Extensions") {
            // This space's extensions, each with what the checks after its
            // install found (Docs/ExtensionsDesign.md, section 4).
            ForEach(extensions.installed) { item in
                if let window {
                    let on = item.spaces.contains(window.spaceID)
                    Menu(item.name) {
                        if on {
                            Button("Use \u{201C}\(item.name)\u{201D}") { extensions.run(item.id, in: window) }
                            if let verdict = extensions.verdicts[window.spaceID]?[item.id] {
                                Section(verdict.title) {
                                    ForEach(verdict.lines, id: \.self) { Text($0) }
                                }
                            }
                            Divider()
                            Button("Turn Off in This Space") { extensions.turn(item.id, on: false, in: window.spaceID) }
                            // Its data in this space goes too; turning it off keeps it.
                            Button("Remove from This Space") { extensions.remove(item.id, from: window.spaceID) }
                        } else {
                            Button("Turn On in This Space") { extensions.turn(item.id, on: true, in: window.spaceID) }
                        }
                        if item.source == .unpacked {
                            Button("Reload") { extensions.reload(item.id) }
                        }
                        Button("Remove from Safience") { extensions.remove(item.id) }
                    }
                }
            }
            if !extensions.installed.isEmpty { Divider() }
            Button("Add This Extension") {
                if let url = window?.url { extensions.add(fromStorePage: url, in: window) }
            }
            .disabled(window?.url.flatMap(ExtensionStore.id(ofPage:)) == nil)
            Button("Chrome Web Store") { window?.open(URL(string: "https://chromewebstore.google.com/category/extensions")!, newTab: true) }
            Button("Install from File\u{2026}") { extensions.addFromFile(in: window) }
            Button("Load Unpacked\u{2026}") { extensions.loadUnpacked(in: window) }
            // Their commands, by name; no keys unless the person gives them,
            // since ⌘ shortcuts belong to the page.
            if let window {
                ForEach(extensions.commands(in: window.spaceID), id: \.id) { entry in
                    Section(entry.name) {
                        ForEach(entry.commands, id: \.id) { command in
                            Button(command.title) { extensions.perform(command, of: entry.id, in: window.spaceID) }
                        }
                    }
                }
            }
            Divider()
            Button("Check for Extension Updates") { Task { await extensions.checkForUpdates(now: true) } }
                .disabled(!extensions.installed.contains { $0.source == .store })
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
