import AppKit
import Combine

/// Whether eGlu may read other apps' fields (Docs/Tasks/03). eGlu asks
/// only when Check in Other Apps is turned on, then watches every two
/// seconds until it is allowed — the person grants it in System Settings
/// without relaunching.
@MainActor
final class AccessibilityAccess: ObservableObject {
    static let shared = AccessibilityAccess()

    /// The current answer. A build signed only to run on this Mac is a new
    /// binary to the system, so it asks again after each rebuild.
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var timer: Timer?

    private init() {}

    /// Start watching: trusted or not, the answer is kept fresh so turning
    /// it on in System Settings works while eGlu stays open.
    func watch() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    /// Ask: the system's own prompt, then the poll notices the grant.
    func ask() {
        watch()
        guard !isTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        check()
    }

    /// Open the place in System Settings where eGlu is allowed.
    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func check() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }
}
