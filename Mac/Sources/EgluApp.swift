import AppKit
import Engines
import OSLog
import PadCore
import SwiftUI

/// eGlu for Mac: the iPad's spaces, pinned tabs and blocking in Arc's
/// shape, a sidebar down the window's side and the page beside it, drawn
/// in Liquid Glass.
@main
struct EgluApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var launch = LaunchState.shared

    var body: some Scene {
        WindowGroup(id: "browser", for: WindowSeed.self) { $seed in
            LaunchWindow(seed: $seed)
        } defaultValue: { WindowSeed() }
        .defaultLaunchBehavior(.presented)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands {
            AboutCommands()
            if launch.ready {
                BrowserCommands()
                #if DIRECT
                UpdateCommands()
                #endif
            }
        }

        Settings {
            if launch.ready { WorkspaceSettings() } else { LaunchProgressView() }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 780, height: 620)
    }
}

private struct LaunchWindow: View {
    @Binding var seed: WindowSeed
    @ObservedObject private var launch = LaunchState.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Group {
            if launch.ready {
                WorkspaceWindow(seed: Binding(get: { seed }, set: { if let value = $0 { seed = value } }))
            } else { LaunchProgressView() }
        }
        .onAppear { launch.showWindow = { openWindow(value: WindowSeed()) }; launch.start() }
    }
}

private struct WorkspaceSettings: View {
    @ObservedObject private var session = Session.shared
    var body: some View { MacSettings().disabled(!session.canUseWorkspace) }
}

/// Do not create a browser model against temporary recovery identities.
private struct WorkspaceWindow: View {
    @Binding var seed: WindowSeed?
    @ObservedObject private var session = Session.shared

    var body: some View {
        if session.canUseWorkspace {
            BrowserView(seed: $seed)
        } else {
            WorkspaceRecoveryView()
                .frame(minWidth: 500, minHeight: 420)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Light or dark whatever the system's, from before any page is made (`-look dark`).
        if let look = UserDefaults.standard.string(forKey: "look") {
            NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        }
        #endif
        #if DEBUG
        // Proves the engines link (task 01 wires them in; nothing calls them
        // yet). Off the main thread: rules() builds Harper's whole rule set,
        // which launch need not wait for.
        Task.detached(priority: .utility) {
            Logger(subsystem: "net.taehee.safience", category: "engines")
                .log("engines linked: \((try? Grammar.rules().count) ?? -1) grammar rules")
        }
        #endif
        // Before anything reads the workspace or the settings: they were in
        // the sandbox's container until the app left it (LeavingTheSandbox).
        MainActor.assumeIsolated { LaunchState.shared.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The icon chosen in Settings, over the app's own that AppKit has just put in the Dock.
        MainActor.assumeIsolated { DockIcon.shared.start() }
    }

    /// Links from other apps, once eGlu is their browser, and web pages opened from Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { LaunchState.shared.open(urls) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        return MainActor.assumeIsolated {
            guard let showWindow = LaunchState.shared.showWindow else { return true }
            showWindow()
            // The event is handled. Allowing the default path would open a second window.
            return false
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // Quitting during migration must not initialize browser services.
            guard LaunchState.shared.ready else { return .terminateNow }
            // This flow owns the durable save and the explicit Quit Without Saving choice.
            return Session.shared.requestTermination(sender)
        }
    }

    /// The last window closed leaves the app running, as Safari does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
