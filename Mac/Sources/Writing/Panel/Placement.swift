// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.

import CoreGraphics

/// Which side of the flagged word the popup ended up on.
enum PopupEdge: Equatable {
    case below
    case above
}

/// Result of placing the popup next to a word.
struct PopupPlacement: Equatable {
    /// Popup frame in AppKit global coordinates (bottom-left origin).
    let frame: CGRect
    let edge: PopupEdge

    /// True when the popup could not go below the word and was placed above it.
    var flipped: Bool { edge == .above }
}

/// Pure geometry used to place the popup. Kept free of AppKit state so it can be unit tested.
enum PopupGeometry {
    /// Distance between the word and the popup.
    static let gap: CGFloat = 6
    /// Minimum distance between the popup and the edge of the visible screen area.
    static let margin: CGFloat = 8

    /// Converts a rect from Accessibility / Core Graphics global coordinates (origin at the
    /// top-left of the primary display, y grows down) to AppKit global coordinates (origin at the
    /// bottom-left of the primary display, y grows up).
    ///
    /// The flip uses the primary display's height for every monitor, because both coordinate
    /// systems are anchored to the primary display. Both systems use points, so display scale
    /// factors do not affect the conversion.
    static func appKitRect(fromTopLeft rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Point version of `appKitRect(fromTopLeft:primaryScreenHeight:)`.
    static func appKitPoint(fromTopLeft point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Picks the screen that shows the anchor: the one containing its center, otherwise the one
    /// with the largest overlap, otherwise the nearest one.
    static func screenIndex(for anchor: CGRect, screenFrames: [CGRect]) -> Int? {
        let center = CGPoint(x: anchor.midX, y: anchor.midY)

        if let index = screenFrames.firstIndex(where: { $0.contains(center) }) {
            return index
        }

        let overlaps = screenFrames.enumerated()
            .map { ($0.offset, area($0.element.intersection(anchor))) }
            .filter { $0.1 > 0 }

        if let best = overlaps.max(by: { $0.1 < $1.1 }) {
            return best.0
        }

        return screenFrames.enumerated()
            .min(by: { distance(from: center, to: $0.element) < distance(from: center, to: $1.element) })?
            .offset
    }

    /// Places a popup of `popupSize` next to `anchor` inside `visibleFrame`.
    ///
    /// All rects are in AppKit global coordinates. `visibleFrame` must already exclude the menu
    /// bar and the Dock.
    static func place(anchor: CGRect, popupSize: CGSize, visibleFrame: CGRect) -> PopupPlacement {
        let lowestY = visibleFrame.minY + margin
        let highestY = visibleFrame.maxY - margin

        let belowY = anchor.minY - gap - popupSize.height
        let aboveY = anchor.maxY + gap

        let fitsBelow = belowY >= lowestY && belowY + popupSize.height <= highestY
        let fitsAbove = aboveY >= lowestY && aboveY + popupSize.height <= highestY

        let edge: PopupEdge
        let y: CGFloat

        if fitsBelow {
            edge = .below
            y = belowY
        } else if fitsAbove {
            edge = .above
            y = aboveY
        } else {
            // Neither side fits: use the roomier side and clamp inside the visible frame. Only in
            // this case may the popup overlap the word.
            let spaceBelow = anchor.minY - gap - lowestY
            let spaceAbove = highestY - (anchor.maxY + gap)
            edge = spaceBelow >= spaceAbove ? .below : .above
            y = clamp(
                edge == .below ? belowY : aboveY,
                lower: lowestY,
                upper: highestY - popupSize.height
            )
        }

        // Align with the word's leading edge; shift left to keep the trailing margin, but never
        // past the leading edge of the visible frame.
        let trailingLimit = visibleFrame.maxX - margin - popupSize.width
        let x = max(min(anchor.minX, trailingLimit), visibleFrame.minX)

        return PopupPlacement(
            frame: CGRect(origin: CGPoint(x: x, y: y), size: popupSize),
            edge: edge
        )
    }

    /// Like a normal clamp, but when the range is empty (the popup is taller than the visible
    /// frame) it keeps the popup's top edge visible.
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        upper < lower ? upper : min(max(value, lower), upper)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
