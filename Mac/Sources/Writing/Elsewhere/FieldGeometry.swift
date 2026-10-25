import AppKit
import ApplicationServices

/// Where a lint sits on screen: its rectangles in Accessibility's
/// top-left-origin coordinates (Docs/Tasks/03, step A3), in UTF-16 ranges
/// as Accessibility counts them (Decided 3).
///
/// AXBoundsForRange gives the bounds a range covers; a range over a line
/// break comes back as one tall box, so the range is split where the
/// bounds' height jumps until each rect is a line. Where the bounds call
/// is unsupported, Chromium's AXStaticText children are tried, then the
/// run's own frame with the text's width measured.
@MainActor
enum FieldGeometry {
    /// The rectangles the lint's `range` covers on screen (top-left origin).
    static func rects(for range: NSRange, in element: AXUIElement) -> [CGRect] {
        guard range.length > 0 else { return [] }
        return rects(for: range, in: element, depth: 0)
    }

    private static func rects(for range: NSRange, in element: AXUIElement, depth: Int) -> [CGRect] {
        if let rect = bounds(for: range, in: element) {
            // A line's height is the unit the split works against; a box no
            // taller than one and a half of them is one line.
            let line = lineHeight(in: element, at: range.location)
            if rect.height <= line * 1.5 || range.length == 1 || depth >= 8 {
                return [rect]
            }
            let middle = range.length / 2
            return rects(for: NSRange(location: range.location, length: middle), in: element, depth: depth + 1)
                + rects(for: NSRange(location: range.location + middle, length: range.length - middle), in: element, depth: depth + 1)
        }
        // The estimate holds only for a run of text, whose frame is its
        // text's own: a field's frame is wider than what it holds.
        if AX.string(element, kAXRoleAttribute) == kAXStaticTextRole {
            return [estimatedRect(for: range, in: element)].compactMap { $0 }
        }
        return chromiumRects(for: range, in: element) ?? []
    }

    /// One AXBoundsForRange probe: the range's screen rect (top-left origin).
    static func bounds(for range: NSRange, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange),
              let value = AX.value(element, kAXBoundsForRangeParameterizedAttribute, for: rangeValue),
              let rect = AX.rect(from: value),
              !rect.isNull, !rect.isEmpty else { return nil }
        return rect
    }

    /// The element's frame on screen: AXFrame where it answers, else its
    /// position and size.
    static func frame(of element: AXUIElement) -> CGRect? {
        if let frame = AX.rect(element, "AXFrame") { return frame }
        guard let origin = AX.point(element, kAXPositionAttribute),
              let size = AX.size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Where the field shows its text: its frame, cut to every scroll area
    /// around it, since a text view inside a scroll view is as tall as its
    /// whole text and has bounds for lines out of view, and a web page's
    /// field sits in the page's scroll area too.
    static func visibleFrame(of element: AXUIElement) -> CGRect? {
        guard var visible = frame(of: element) else { return nil }
        var current = element
        for _ in 0..<8 {
            guard let parent = AX.element(current, kAXParentAttribute) else { break }
            let role = AX.string(parent, kAXRoleAttribute)
            if role == kAXScrollAreaRole, let area = frame(of: parent) {
                visible = visible.intersection(area)
            }
            if role == kAXWindowRole || role == kAXApplicationRole { break }
            current = parent
        }
        return visible
    }

    /// The part of `rect` inside `visible`, or nil when less than half of
    /// it shows: a line scrolled out of the field isn't drawn over what is
    /// beside it.
    static func clip(_ rect: CGRect, to visible: CGRect?) -> CGRect? {
        guard let visible else { return rect }
        let part = rect.intersection(visible)
        guard !part.isNull, part.width > 0, part.height >= rect.height / 2 else { return nil }
        return part
    }

    /// A line's height on screen: a one-unit probe near the range, else a
    /// plain 16 points.
    private static func lineHeight(in element: AXUIElement, at location: Int) -> CGFloat {
        let probe = bounds(for: NSRange(location: location, length: 1), in: element)
        return probe?.height ?? 16
    }

    // MARK: - The Chromium path (accessibility_text.rs:358-409)

    /// Chromium fields answer bounds queries on their AXStaticText children
    /// instead: find the children whose text covers the range and ask them.
    private static func chromiumRects(for range: NSRange, in element: AXUIElement) -> [CGRect]? {
        guard let text = AX.string(element, kAXValueAttribute) else { return nil }
        let children = staticTextChildren(of: element)
        guard !children.isEmpty else { return nil }

        // The children spell the whole value out in order: walk the text
        // and the children together until the range's characters are found.
        var rects: [CGRect] = []
        var covered = 0
        for child in children {
            guard let childText = AX.string(child, kAXValueAttribute) else { continue }
            let childLength = childText.utf16.count
            let childStart = (text as NSString).range(
                of: childText,
                range: NSRange(location: covered, length: max(0, text.utf16.count - covered))
            )
            let start = childStart.location == NSNotFound ? covered : childStart.location
            let childRange = NSRange(location: start, length: childLength)
            covered = max(covered, start + childLength)

            if NSIntersectionRange(range, childRange).length > 0 {
                let inner = NSIntersectionRange(range, childRange)
                let local = NSRange(location: inner.location - start, length: inner.length)
                // A run wraps too: split it where its lines are.
                rects.append(contentsOf: self.rects(for: local, in: child))
            }
            if covered >= range.location + range.length { break }
        }
        return rects.isEmpty ? nil : rects
    }

    /// The AXStaticText elements under `element`, depth-first and capped so
    /// a whole document of children cannot stall the timer.
    private static func staticTextChildren(of element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 12 else { return [] }
        if AX.string(element, kAXRoleAttribute) == kAXStaticTextRole {
            return [element]
        }
        guard let children = AX.value(element, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        var result: [AXUIElement] = []
        for child in children.prefix(200) {
            result.append(contentsOf: staticTextChildren(of: child, depth: depth + 1))
            if result.count > 400 { break }
        }
        return result
    }

    // MARK: - The last resort (estimated_bounds.rs)

    /// No bounds anywhere: the range's place in a one-line run, from the
    /// run's frame and the widths of the text before and in the range,
    /// measured in the run's own font where Accessibility gives it, else
    /// the system font at 13 points. Only the widths' ratio to the whole
    /// matters, so the size the font is measured at doesn't.
    private static func estimatedRect(for range: NSRange, in element: AXUIElement) -> CGRect? {
        guard let frame = frame(of: element), frame.width > 0, frame.height > 0,
              let text = AX.string(element, kAXValueAttribute) else { return nil }
        let whole = text as NSString
        guard range.length > 0, NSMaxRange(range) <= whole.length else { return nil }

        let font = self.font(of: element, at: range) ?? NSFont.systemFont(ofSize: 13)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let full = whole.size(withAttributes: attributes).width
        guard full > 0 else { return nil }
        let scale = frame.width / full
        // A run that wraps is as wide as its column and several lines tall,
        // which makes its text look tiny for its height: no estimate holds.
        guard frame.height <= font.pointSize * scale * 2 else { return nil }

        // Substrings of the NSString, so an emoji's two units stay together.
        let left = whole.substring(to: range.location).size(withAttributes: attributes).width * scale
        let width = whole.substring(with: range).size(withAttributes: attributes).width * scale
        guard width > 0 else { return nil }
        return CGRect(x: frame.minX + left, y: frame.minY,
                      width: min(width, frame.width - left), height: frame.height)
    }

    // The system's own constants for the attributed string's font, not ours to release.
    private static let fontKey = NSAttributedString.Key(kAXFontTextAttribute.takeUnretainedValue() as String)
    private static let fontSizeKey = kAXFontSizeKey.takeUnretainedValue() as String
    private static let fontNameKey = kAXFontNameKey.takeUnretainedValue() as String

    /// The font at the start of `range`, from the attributed string
    /// Accessibility gives for it (its AXFont: a name and a size).
    private static func font(of element: AXUIElement, at range: NSRange) -> NSFont? {
        var cfRange = CFRange(location: range.location, length: 1)
        guard let parameter = AXValueCreate(.cfRange, &cfRange),
              let value = AX.value(element, kAXAttributedStringForRangeParameterizedAttribute, for: parameter),
              let string = value as? NSAttributedString, string.length > 0,
              let font = string.attribute(Self.fontKey, at: 0, effectiveRange: nil) as? [String: Any],
              let size = (font[Self.fontSizeKey] as? NSNumber)?.doubleValue, size > 0 else { return nil }
        let name = font[Self.fontNameKey] as? String
        return name.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
    }
}
