import AppKit
import ApplicationServices

/// Where a lint sits on screen: its rectangles in Accessibility's
/// top-left-origin coordinates (Docs/Tasks/03, Decided 8, 9).
///
/// AXBoundsForRange gives the bounds a range covers; a range over a line
/// break comes back as one tall box, so the range is split where the
/// bounds' height jumps until each rect is a line. Where the bounds call
/// is unsupported, Chromium's AXStaticText children are tried, then the
/// run's own frame with the text's width measured.
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
        return chromiumRects(for: range, in: element)
            ?? [estimatedRect(for: range, in: element)].compactMap { $0 }
    }

    /// One AXBoundsForRange probe: the range's screen rect (top-left origin).
    static func bounds(for range: NSRange, in element: AXUIElement) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue, &value) == .success,
              let point = value else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(point as! AXValue, .cgRect, &rect), !rect.isNull, !rect.isEmpty
        else { return nil }
        return rect
    }

    /// A line's height on screen: a one-unit probe near the range, else a
    /// plain 16 points.
    private static func lineHeight(in element: AXUIElement, at location: Int) -> CGFloat {
        let probe = bounds(for: NSRange(location: location, length: 1), in: element)
        return probe?.height ?? 16
    }

    // MARK: - The Chromium path (Decided 8)

    /// Chromium fields answer bounds queries on their AXStaticText children
    /// instead: find the children whose text covers the range and ask them.
    private static func chromiumRects(for range: NSRange, in element: AXUIElement) -> [CGRect]? {
        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
              let text = textValue as? String else { return nil }
        let children = staticTextChildren(of: element)
        guard !children.isEmpty else { return nil }

        // The children spell the whole value out in order: walk the text
        // and the children together until the range's characters are found.
        var rects: [CGRect] = []
        var covered = 0
        for child in children {
            var childValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childValue) == .success,
                  let childText = childValue as? String else { continue }
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
                if let rect = bounds(for: local, in: child) {
                    rects.append(rect)
                } else if let rect = estimatedRect(for: local, in: child) {
                    rects.append(rect)
                }
            }
            if covered >= range.location + range.length { break }
        }
        return rects.isEmpty ? nil : rects
    }

    /// The AXStaticText elements under `element`, depth-first and capped so
    /// a whole document of children cannot stall the timer.
    private static func staticTextChildren(of element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 12 else { return [] }
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           (roleValue as? String) == "AXStaticText" {
            return [element]
        }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return [] }
        var result: [AXUIElement] = []
        for child in children.prefix(200) {
            result.append(contentsOf: staticTextChildren(of: child, depth: depth + 1))
            if result.count > 400 { break }
        }
        return result
    }

    // MARK: - The last resort (Decided 9)

    /// No bounds anywhere: put the underline on the field's own frame,
    /// narrowed to the range's share of its text as the font measures it.
    private static func estimatedRect(for range: NSRange, in element: AXUIElement) -> CGRect? {
        var frameValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameValue) == .success,
              let value = frameValue else { return nil }
        var frame = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &frame), !frame.isNull else { return nil }

        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue) == .success,
              let text = textValue as? String, text.utf16.count > 0 else { return frame }

        let font = NSFont.systemFont(ofSize: 13)
        let whole = (text as NSString).size(withAttributes: [.font: font]).width
        guard whole > 0 else { return frame }
        let prefix = text.utf16.prefix(range.location)
        let prefixText = String(String.UnicodeScalarView(
            prefix.compactMap { Unicode.Scalar($0) }))
        let partText = String(String.UnicodeScalarView(
            text.utf16.dropFirst(range.location).prefix(range.length)
                .compactMap { Unicode.Scalar($0) }))
        let left = (prefixText as NSString).size(withAttributes: [.font: font]).width
        let width = max((partText as NSString).size(withAttributes: [.font: font]).width, 1)
        let scale = frame.width / whole
        return CGRect(x: frame.minX + left * scale, y: frame.minY,
                      width: min(width * scale, frame.width - left * scale), height: frame.height)
    }
}
