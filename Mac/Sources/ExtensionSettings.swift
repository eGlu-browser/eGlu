import AppKit
import PadCore
import SwiftUI

/// Settings › Extensions: every extension, where it came from, what it may
/// read, and its switch in each space, grouped as the spaces are; the daily
/// update check; and the ways to add one (Docs/ExtensionsDesign.md, section 2).
struct ExtensionSettings: View {
    @ObservedObject private var extensions = Extensions.shared
    @ObservedObject private var session = Session.shared
    @AppStorage(Extensions.checksKey) private var checksDaily = true
    @State private var checking = false
    @State private var lastResult: String?

    var body: some View {
        Form {
            if extensions.installed.isEmpty {
                Section {
                    Text("No extensions yet. A Chrome Web Store page has an Add to Safience button.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(extensions.installed) { item in
                Section {
                    if extensions.isIncompatible(item.id) {
                        // No switches for one that can't run here: what it is, and Remove.
                        Label("Incompatible", systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .help(extensions.incompatibility(item.id))
                    } else {
                    Picker("Site access", selection: Binding(get: { item.siteAccess }, set: { extensions.setSiteAccess(item.id, $0) })) {
                        Text("On All Sites It Asks For").tag(Extensions.Installed.SiteAccess.allSites)
                        Text("When I Click It").tag(Extensions.Installed.SiteAccess.onClick)
                    }
                    ForEach(session.workspace.spaces) { space in
                        Toggle(isOn: Binding(get: { item.spaces.contains(space.id) },
                                             set: { extensions.turn(item.id, on: $0, in: space.id) })) {
                            HStack(spacing: 6) {
                                Image(systemName: space.symbol).foregroundStyle(space.color.color)
                                Text(space.name)
                                if item.spaces.contains(space.id), let warning = extensions.warning(item.id, in: space.id) {
                                    // A warning only when it doesn't work.
                                    Text(warning.title).font(.caption).foregroundStyle(.orange)
                                        .help(warning.lines.joined(separator: " "))
                                }
                            }
                        }
                    }
                    }
                    HStack {
                        if item.source == .unpacked {
                            Button("Reload") { extensions.reload(item.id) }
                        }
                        if extensions.saidLooksWrong(item.id) {
                            Button("Show Its Warnings Again") { extensions.setLooksWrong(item.id, false) }
                        } else if extensions.isWarned(item.id) {
                            Button("This Looks Wrong") { extensions.setLooksWrong(item.id, true) }
                        }
                        Button("Report a Problem\u{2026}") { ExtensionReport.show(item.id, in: Self.browserWindow()) }
                        Spacer()
                        Button("Remove from Safience\u{2026}", role: .destructive) {
                            if let window = Self.browserWindow() { extensions.confirmRemoval(of: item.id, in: window) }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(item.name)
                        Text("\(item.version), \(Self.source(of: item))")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Each space keeps its own sign-in and data for it. Turned off, it keeps them; removed from a space (the puzzle button\u{2019}s list, \u{2026}), they go.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Check for updates daily", isOn: $checksDaily)
                HStack {
                    Button(checking ? "Checking\u{2026}" : "Check Now") {
                        checking = true
                        Task {
                            let updated = await extensions.checkForUpdates(now: true)
                            checking = false
                            lastResult = updated == 0 ? "Everything is up to date." : "\(updated) updated."
                        }
                    }
                    .disabled(checking || !extensions.installed.contains { $0.source == .store })
                    if let lastResult {
                        Text(lastResult).foregroundStyle(.secondary)
                    } else if let last = Extensions.lastChecked {
                        Text("Last checked \(last.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("The check names your Chrome Web Store extensions to Google, as Chrome's does.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    // In the browser window, brought in front of Settings, or a new one.
                    Button("Chrome Web Store") {
                        Session.shared.open([URL(string: "https://chromewebstore.google.com/category/extensions")!])
                    }
                    // The sheet that follows is on the window in front, brought forward.
                    Button("Install from File\u{2026}") { extensions.addFromFile(in: Self.browserWindow()) }
                    Button("Load Unpacked\u{2026}") { extensions.loadUnpacked(in: Self.browserWindow()) }
                }
            } header: {
                Text("Add")
            }
        }
    }

    /// The browser window in front, brought in front of Settings, for what
    /// asks in a sheet.
    static func browserWindow() -> WindowModel? {
        let window = Session.shared.frontWindow
        window?.window?.makeKeyAndOrderFront(nil)
        return window
    }

    static func source(of item: Extensions.Installed) -> String {
        switch item.source {
        case .store: return "from the Chrome Web Store"
        case .file: return "from a file, signed by its developer"
        case .unsigned: return "from a file, unsigned"
        case .unpacked: return "loaded from a folder"
        }
    }
}
