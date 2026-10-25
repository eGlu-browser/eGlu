import AppKit
import Carbon

/// ⌃⌥G accepts the panel's first suggestion over another app's field
/// (Docs/Tasks/03): a global hot key, registered only while the panel has
/// a suggestion to take — any other time the keys are the other app's.
@MainActor
final class AcceptKey {
    static let shared = AcceptKey()

    /// The chord's symbols, as PadCore's Commands shows it and the panel
    /// hints it.
    static let symbols = "⌃⌥G"

    /// What a press does: set by the checker.
    var onAccept: () -> Void = {}

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    func enable() {
        guard hotKey == nil else { return }
        // One keyboard event kind: our own hot key pressed.
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, refcon in
            guard let refcon else { return noErr }
            Unmanaged<AcceptKey>.fromOpaque(refcon).takeUnretainedValue().pressed()
            return noErr
        }, 1, &kind, refcon, &handler)

        let id = EventHotKeyID(signature: OSType(0x45474C55 /* 'EGLU' */), id: 1)
        // kVK_ANSI_G with control and option: PadCore's ⌃⌥G chord.
        RegisterEventHotKey(UInt32(kVK_ANSI_G),
                            UInt32(controlKey | optionKey),
                            id, GetApplicationEventTarget(), 0, &hotKey)
    }

    func disable() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func pressed() {
        Task { @MainActor in self.onAccept() }
    }
}
