import PadCore
import SwiftUI
import UIKit

/// Whether eGlu is the default browser, as iPadOS tells it, and the way
/// to Settings to make it so.
///
/// iPadOS answers only so often (UIApplication.isDefault(_:) is rate-limited
/// and throws when asked too soon), so the last answer is kept and shown
/// until it may be asked again.
@MainActor
final class DefaultBrowser: ObservableObject {
    static let shared = DefaultBrowser()

    enum Status: String {
        case unknown, isDefault, notDefault
    }

    @Published private(set) var status: Status

    private static let key = "defaultBrowserStatus"

    private init() {
        status = UserDefaults.standard.string(forKey: Self.key).flatMap(Status.init(rawValue:)) ?? .unknown
    }

    /// Asks iPadOS again, keeping the last answer when it won't say.
    func refresh() {
        guard #available(iOS 18.2, *) else { return }
        do {
            status = try UIApplication.shared.isDefault(.webBrowser) ? .isDefault : .notDefault
            UserDefaults.standard.set(status.rawValue, forKey: Self.key)
        } catch {
            // Rate-limited, or not known on this iPad: the last answer stands.
        }
    }

    /// Settings › Apps › Default Apps where iPadOS has it (18.3 and later),
    /// otherwise the app's own page in Settings.
    func openSettings() {
        var page = UIApplication.openSettingsURLString
        if #available(iOS 18.3, *) { page = UIApplication.openDefaultApplicationsSettingsURLString }
        guard let url = URL(string: page) else { return }
        UIApplication.shared.open(url)
    }
}

/// Settings' first section: eGlu as the default browser.
struct DefaultBrowserSection: View {
    @ObservedObject var browser = DefaultBrowser.shared

    var body: some View {
        Section {
            if browser.status == .isDefault {
                Label("eGlu is your default browser", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
            } else {
                Button("Make eGlu the Default Browser…") { browser.openSettings() }
            }
        } header: {
            SettingsHeader("Default browser", .defaultBrowser)
        } footer: {
            // The step the button leaves to do, and nothing once it is done.
            if browser.status != .isDefault {
                Text("In Settings, choose Browser App, then eGlu.")
            }
        }
        .onAppear { browser.refresh() }
    }
}
