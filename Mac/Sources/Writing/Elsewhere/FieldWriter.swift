import AppKit
import ApplicationServices
import PadCore

/// Writing a suggestion back into another app's field, so the app's own
/// Undo takes it back (Docs/Tasks/03, B1; text_selection.rs). The text
/// under the range is read again first: a lint the person has already
/// edited away is dropped, not written over their typing.
@MainActor
enum FieldWriter {
    /// How the write ended.
    enum Outcome {
        /// The suggestion is in the field.
        case done
        /// The text under the lint had already changed; nothing written.
        case changed
        /// The field would not take the text; nothing written.
        case refused
    }

    /// How long Chromium gets to apply a selection it accepted, and how
    /// often it is asked meanwhile (text_selection.rs's wait_for_selection).
    private static let selectionWait: TimeInterval = 0.3
    private static let selectionPoll: Duration = .milliseconds(10)
    private static let deleteKey: CGKeyCode = 0x33

    /// Replace `range` (UTF-16 units) in `element`'s text with `text`,
    /// only while it still says `expected`.
    static func replace(range: NSRange, expected: String, with text: String,
                        in element: AXUIElement, app: NSRunningApplication) async -> Outcome {
        guard let whole = AX.string(element, kAXValueAttribute) else { return .refused }
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= (whole as NSString).length,
              (whole as NSString).substring(with: range) == expected else { return .changed }
        let was = AX.range(element, kAXSelectedTextRangeAttribute)
            .map { NSRange(location: $0.location, length: $0.length) }

        if FrontField.isChromium(element) {
            return await type(text, over: range, in: element, app: app, whole: whole, was: was)
        }

        // Through the selection, as typing does: rich text keeps its
        // formatting and the app records the edit for Undo.
        let selected = select(range, in: element)
        if selected == .success {
            let written = AX.set(element, kAXSelectedTextAttribute, to: text as CFTypeRef)
            if written == .success {
                if let was {
                    select(FieldEdit.selection(was, after: range, insertedLength: text.utf16.count), in: element)
                }
                return .done
            }
            if !cannotBeSet(written, kAXSelectedTextAttribute, in: element) {
                if let was { select(was, in: element) }
                return .refused
            }
        } else if !cannotBeSet(selected, kAXSelectedTextRangeAttribute, in: element) {
            return .refused
        }

        // The field takes no edit through its selection: its whole value is
        // set instead, which loses rich text and the app's Undo, so only
        // then, and only while it still says what was read.
        let updated = (whole as NSString).replacingCharacters(in: range, with: text)
        guard AX.string(element, kAXValueAttribute) == whole else {
            if selected == .success, let was { select(was, in: element) }
            return .changed
        }
        guard AX.set(element, kAXValueAttribute, to: updated as CFTypeRef) == .success else {
            if selected == .success, let was { select(was, in: element) }
            return .refused
        }
        if let was {
            select(FieldEdit.selection(was, after: range, insertedLength: text.utf16.count), in: element)
        }
        return .done
    }

    /// Whether a set failed because the attribute can't be set at all, the
    /// one failure the whole-value write is for (plan B1 step 4).
    private static func cannotBeSet(_ error: AXError, _ attribute: String, in element: AXUIElement) -> Bool {
        error == .attributeUnsupported || AX.isSettable(element, attribute) == false
    }

    // MARK: - The Chromium path

    /// Chromium selects through Accessibility but ignores text written
    /// through it: select the range, wait for the selection to take, and
    /// type the answer as key events to the app's process. An empty answer
    /// is the Delete key over the selection. The caret ends after the
    /// answer, as after typing: the old selection put back could land
    /// before the typed text, which arrives later.
    private static func type(_ text: String, over range: NSRange, in element: AXUIElement,
                             app: NSRunningApplication, whole: String, was: NSRange?) async -> Outcome {
        guard let chunks = FieldEdit.typingChunks(text) else { return .refused }
        guard select(range, in: element) == .success, await selection(of: element, becomes: range) else {
            if let was { select(was, in: element) }
            return .refused
        }
        // The wait let the person go on: keys go only to the same field,
        // still in front, still holding what was read. Typed anywhere else
        // they would land in whatever has the focus now.
        let pid = app.processIdentifier
        guard app.isActive,
              let focused = AX.element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              CFEqual(focused, element) else { return .refused }
        // Changed meanwhile, the caret is where the person put it now: left there.
        guard AX.string(element, kAXValueAttribute) == whole else { return .changed }
        if chunks.isEmpty { return press(deleteKey, units: nil, to: pid) ? .done : .refused }
        for chunk in chunks {
            guard press(0, units: chunk, to: pid) else { return .refused }
        }
        return .done
    }

    /// Chromium applies a selection a moment after accepting it.
    private static func selection(of element: AXUIElement, becomes range: NSRange) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + selectionWait
        while true {
            if let now = AX.range(element, kAXSelectedTextRangeAttribute),
               now.location == range.location, now.length == range.length { return true }
            if ProcessInfo.processInfo.systemUptime >= deadline { return false }
            try? await Task.sleep(for: selectionPoll)
        }
    }

    /// One key, down and up, to the app's process, carrying `units` as the
    /// text it types. No modifier flags: ⌃ and ⌥ are still held from ⌃⌥G,
    /// and would make the typing shortcuts.
    private static func press(_ key: CGKeyCode, units: [UInt16]?, to pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                return false
            }
            event.flags = []
            if let units {
                units.withUnsafeBufferPointer { buffer in
                    event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
            }
            event.postToPid(pid)
        }
        return true
    }

    // MARK: - The selection

    /// Select `range` in the field: where the answer lands for both paths.
    @discardableResult
    private static func select(_ range: NSRange, in element: AXUIElement) -> AXError {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return .failure }
        return AX.set(element, kAXSelectedTextRangeAttribute, to: value)
    }
}
