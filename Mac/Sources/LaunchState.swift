import AppKit
import PadCore
import SwiftUI

/// Shows a window before legacy files are read or copied. No browser services
/// or workspace model are created while migration is incomplete.
@MainActor
final class LaunchState: ObservableObject {
    static let shared = LaunchState()
    @Published private(set) var ready = false
    @Published private(set) var detail = String(localized: "Checking existing browser data…")
    @Published private(set) var problem: String?
    private var task: Task<Void, Never>?
    private var waiting: [URL] = []
    var showWindow: (() -> Void)?

    func start() {
        guard !ready, task == nil else { return }
        problem = nil
        task = Task { [self] in
            do {
                if let request = LeavingTheSandbox.request() {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try LegacyDataMigration.run(library: request.library, bundle: request.bundle, completed: request.completed) { progress in
                            Task { @MainActor in
                                let files = progress.copiedFiles
                                if progress.item.hasPrefix("WebKit/Website") {
                                    self.detail = files > 0 ? String(localized: "Moving sign-ins and site data. \(files) files copied.") : String(localized: "Moving sign-ins and site data…")
                                } else if progress.item.hasPrefix("WebKit/") {
                                    self.detail = files > 0 ? String(localized: "Moving content blocking data. \(files) files copied.") : String(localized: "Moving content blocking data…")
                                } else {
                                    self.detail = files > 0 ? String(localized: "Moving spaces and bookmarks. \(files) files copied.") : String(localized: "Moving spaces and bookmarks…")
                                }
                            }
                        }
                    }.value
                    LeavingTheSandbox.finish(request, result: result)
                }
                ready = true
                // Let SwiftUI present the browser before optional startup services run.
                await Task.yield()
                Session.shared.start(afterLaunch: true)
                #if DIRECT
                Updates.shared.start()
                #endif
                if !waiting.isEmpty { Session.shared.open(waiting, fromOtherApp: true); waiting.removeAll() }
            } catch {
                problem = error.localizedDescription
            }
            task = nil
        }
    }

    /// Links from other apps, and web pages opened from Finder.
    func open(_ urls: [URL]) {
        if ready { Session.shared.open(urls, fromOtherApp: true) } else { waiting += urls; showWindow?() }
    }
}

struct LaunchProgressView: View {
    @ObservedObject private var launch = LaunchState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(launch.problem == nil ? String(localized: "Preparing Your Browser") : String(localized: "Browser Data Could Not Be Moved"))
                .font(.title2.weight(.semibold))
            if launch.problem == nil {
                ProgressView().controlSize(.large)
                Text(launch.detail).accessibilityAddTraits(.updatesFrequently)
                Text("Your existing browser data is being kept. You can quit and continue later.").foregroundStyle(.secondary)
            } else {
                Text("Your original data is intact. Free up storage or check access to your Library folder, then retry.")
                Text(launch.problem ?? "").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Retry") { launch.start() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(minWidth: 500, minHeight: 320)
    }
}
