import AppKit
import PadCore
import SwiftUI

/// Safience for Mac: the iPad's spaces, pinned tabs and blocking in Arc's
/// shape, a sidebar down the window's side and the page beside it, drawn
/// in Liquid Glass.
@main
struct SafienceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(for: WindowSeed.self) { $seed in
            BrowserView(seed: $seed)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands {
            BrowserCommands()
            #if DIRECT
            UpdateCommands()
            #endif
        }

        Settings {
            MacSettings()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 780, height: 620)
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
        // Before anything reads the workspace or the settings: they were in
        // the sandbox's container until the app left it (LeavingTheSandbox).
        LeavingTheSandbox.move()
        MainActor.assumeIsolated {
            Session.shared.start()
            #if DIRECT
            Updates.shared.start()
            #endif
        }
    }

    /// Links from other apps, once Safience is their browser, and web pages opened from Finder.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { Session.shared.open(urls) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Session.shared.saveNow() }
    }

    /// The last window closed leaves the app running, as Safari does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
