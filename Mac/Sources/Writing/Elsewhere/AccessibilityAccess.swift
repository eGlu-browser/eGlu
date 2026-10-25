import AppKit
import Combine

/// Whether eGlu may read other apps' fields (Docs/Tasks/03). eGlu asks
/// only when Check in Other Apps is turned on, then looks again every two
/// seconds while it is on (as accessibility_watch.rs does): the person
/// grants it in System Settings without relaunching, and one who takes it
/// back there sees the checking stop.
@MainActor
final class AccessibilityAccess: ObservableObject {
    static let shared = AccessibilityAccess()

    /// The current answer. A build signed only to run on this Mac is a new
    /// binary to the system, so it asks again after each rebuild.
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var timer: Timer?

    private init() {}

    /// Start looking: the checker calls this while Check in Other Apps is
    /// on, and only then.
    func watch() {
        check()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Check in Other Apps is off: nothing left to look for.
    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    /// Ask: the system's own prompt, then the poll notices the grant.
    func ask() {
        watch()
        guard !isTrusted else { return }
        // The prompt key is a constant the system owns: not ours to release.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
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
