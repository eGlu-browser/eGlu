#if DIRECT
import Combine
import Sparkle
import SwiftUI

/// Updates for the copy of eGlu downloaded from the website (the eGlu
/// Mac Direct target, Release/mac.sh): Sparkle 2 looks at the appcast on the
/// project's GitHub releases (SUFeedURL), checks the disk image's EdDSA
/// signature against the key in Info.plist (SUPublicEDKey) and installs it.
/// The app is outside the App Sandbox, so Sparkle replaces it itself, with no
/// installer service. The eGlu Mac target, run from Xcode, has none of this.
@MainActor
final class Updates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updates()

    /// Whether Check for Updates… can be chosen now: not while a check is under way.
    @Published private(set) var canCheck = false
    @Published var automatic = true {
        didSet { if controller?.updater.automaticallyChecksForUpdates != automatic { controller?.updater.automaticallyChecksForUpdates = automatic } }
    }

    private var controller: SPUStandardUpdaterController?
    private var watching: AnyCancellable?

    /// Started as the app starts (AppDelegate), so the scheduled check runs.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        automatic = controller.updater.automaticallyChecksForUpdates
        watching = controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] can in
            self?.canCheck = can
        }
        #if DEBUG
        // Release/update-test.sh: checks at once and installs what it finds,
        // without asking, for a test of the whole path from the shell.
        if UserDefaults.standard.bool(forKey: "updateTest") {
            controller.updater.automaticallyDownloadsUpdates = true
            controller.updater.checkForUpdatesInBackground()
        }
        #endif
    }

    func check() {
        controller?.checkForUpdates(nil)
    }

    #if DEBUG
    /// In the test, installed and opened again at once rather than when the app quits.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock: @escaping () -> Void) -> Bool {
        guard UserDefaults.standard.bool(forKey: "updateTest") else { return false }
        immediateInstallationBlock()
        return true
    }
    #endif
}

/// eGlu › Check for Updates…, after About eGlu.
struct UpdateCommands: Commands {
    @ObservedObject private var updates = Updates.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.check() }
                .disabled(!updates.canCheck)
        }
    }
}

/// Settings › General's line for updates.
struct UpdateSettings: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $updates.automatic)
            LabeledContent("Version \(Self.version)") {
                Button("Check Now") { updates.check() }
                    .disabled(!updates.canCheck)
            }
        } header: {
            Text("Updates")
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
}
#endif
