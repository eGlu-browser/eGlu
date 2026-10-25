import AppKit
import Carbon.HIToolbox

/// ⌃⌥G accepts the panel's first suggestion over another app's field
/// (Docs/Tasks/03, B2; harperSwift's AcceptShortcut.swift): a global hot
/// key, registered only while the panel has a suggestion to take — any
/// other time the keys are the other app's. A system hot key works with
/// eGlu not the active app, which it isn't while the panel shows.
@MainActor
final class AcceptKey {
    static let shared = AcceptKey()

    /// The chord's symbols, as PadCore's Commands shows it and the panel
    /// hints it.
    nonisolated static let symbols = "⌃⌥G"

    /// What a press does: set by the checker.
    var onAccept: () -> Void = {}

    /// Ours among every hot key the app registers.
    nonisolated private static let id = EventHotKeyID(signature: OSType(0x45474C55 /* 'EGLU' */), id: 1)

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    func enable() {
        guard hotKey == nil else { return }
        installHandlerIfNeeded()
        // kVK_ANSI_G with control and option: PadCore's ⌃⌥G chord.
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(controlKey | optionKey),
                                         Self.id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { hotKey = nil }
    }

    func disable() {
        guard let hotKey else { return }
        UnregisterEventHotKey(hotKey)
        self.hotKey = nil
    }

    /// The handler stays for the app's life; only the hot key comes and goes.
    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var kind = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr, pressed.signature == AcceptKey.id.signature,
                  pressed.id == AcceptKey.id.id else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { AcceptKey.shared.onAccept() }
            return noErr
        }, 1, &kind, nil, &handler)
    }
}
