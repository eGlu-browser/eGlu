import AppKit
import ApplicationServices

/// Writing a suggestion back into another app's field, so the app's own
/// Undo takes it back (Docs/Tasks/03). The text under the range is read
/// again first: a lint the person has already edited away is dropped, not
/// written over their typing.
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

    /// Replace `range` (UTF-16 units) in `element`'s text with `text`,
    /// only while it still says `expected`.
    static func replace(range: NSRange, expected: String, with text: String,
                        in element: AXUIElement, app: NSRunningApplication) -> Outcome {
        guard let whole = readText(of: element) else { return .refused }
        guard let old = part(of: whole, at: range), old == expected else { return .changed }

        if isChromium(element) {
            return type(range: range, with: text, in: element, app: app)
        }

        // The direct write: select the lint's range, then answer as if the
        // selection were typed over. Both keep the app's undo intact.
        let was = selection(of: element)
        guard select(range, in: element) else { return .refused }
        let replaced = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if replaced == .success {
            restore(was, in: element, after: range, replacement: text)
            return .done
        }
        if replaced == .attributeUnsupported || replaced == .failure || replaced == .cannotComplete {
            // A field that answers no text setting at all gets its whole
            // value set — only if it still says what was read.
            guard let again = readText(of: element), again == whole else { return .changed }
            let updated = (whole as NSString).replacingCharacters(in: range, with: text)
            guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString,
                                               updated as CFTypeRef) == .success else { return .refused }
            return .done
        }
        return .refused
    }

    // MARK: - The Chromium path

    /// Chromium fields answer no text setting: select the range and type
    /// the answer as key events to the app's pid, in chunks of twenty
    /// UTF-16 units so no event is overlong. An empty answer is the Delete
    /// key — backspace would eat the character before the range.
    private static func type(range: NSRange, with text: String,
                             in element: AXUIElement, app: NSRunningApplication) -> Outcome {
        guard select(range, in: element) else { return .refused }
        let pid = app.processIdentifier
        if text.isEmpty {
            return post(key: 0x33 /* Delete */, to: pid) ? .done : .refused
        }
        let source = CGEventSource(stateID: .hidSystemState)
        var units = Array(text.utf16)
        while !units.isEmpty {
            let chunk = Array(units.prefix(20))
            units.removeFirst(min(20, units.count))
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                return .refused
            }
            // No flags: a stuck modifier would type something else.
            event.flags = []
            chunk.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count,
                                               unicodeString: buffer.baseAddress)
            }
            event.postToPid(pid)
        }
        return .done
    }

    private static func post(key: CGKeyCode, to pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return false
        }
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    // MARK: - The reads and sets

    private static func readText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    private static func part(of text: String, at range: NSRange) -> String? {
        guard range.location >= 0, range.location + range.length <= text.utf16.count else { return nil }
        let start = text.utf16.index(text.utf16.startIndex, offsetBy: range.location)
        let end = text.utf16.index(start, offsetBy: range.length)
        return String(String.UnicodeScalarView(
            text.utf16[start..<end].compactMap { Unicode.Scalar($0) }))
    }

    /// Whether the element is Chromium's: it carries a ChromeAXNodeId.
    static func isChromium(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return false }
        return list.contains("ChromeAXNodeId")
    }

    /// Select `range` in the field: where the answer lands for both paths.
    private static func select(_ range: NSRange, in element: AXUIElement) -> Bool {
        var cf = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cf) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success
    }

    /// The field's selected range, or nil.
    private static func selection(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let rangeValue = value else { return nil }
        var selected = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selected) else { return nil }
        return selected
    }

    /// The caret back where it was, moved by the answer's length delta:
    /// after the edit it ends up at the answer's end; before it, untouched.
    private static func restore(_ was: CFRange?, in element: AXUIElement,
                                after range: NSRange, replacement: String) {
        guard let was else { return }
        let delta = replacement.utf16.count - range.length
        var moved = was
        if was.location > range.location + range.length {
            moved.location = was.location + delta
        } else if was.location >= range.location {
            moved.location = range.location + replacement.utf16.count
            moved.length = 0
        }
        _ = select(NSRange(location: moved.location, length: moved.length), in: element)
    }
}
