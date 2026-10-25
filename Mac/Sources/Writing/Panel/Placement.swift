// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.

import AppKit
import Foundation

enum PopupGeometry {
    /// The vertical gap between the lint anchor and the panel card.
    static let panelGap: CGFloat = 6
    /// The inset kept between the card and the screen's visible edges.
    static let screenMargin: CGFloat = 8

    /// Accessibility rects use a top-left, global screen-space origin.
    /// Convert to AppKit bottom-left coordinates anchored at the primary screen.
    static func appKitRect(for rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else {
            return rect
        }
        let height = primary.frame.height
        let y = height - rect.maxY
        return CGRect(x: rect.minX, y: y, width: rect.width, height: rect.height)
    }

    /// Pick a position for the card around `anchor` in global top-left coordinates.
    static func place(anchor: CGRect, cardSize: CGSize) -> CGRect {
        guard let screen = screen(containing: anchor) else {
            return CGRect(origin: anchor.origin, size: cardSize)
        }

        let bounds = screen.frame.insetBy(dx: screenMargin, dy: screenMargin)
        let below = CGRect(
            x: anchor.minX,
            y: anchor.maxY + panelGap,
            width: cardSize.width,
            height: cardSize.height
        )
        let above = CGRect(
            x: anchor.minX,
            y: anchor.minY - panelGap - cardSize.height,
            width: cardSize.width,
            height: cardSize.height
        )

        // Prefer below when it fits; otherwise use the side that exposes more of the card.
        let candidates: [CGRect] = [below, above]
        var best = candidates[0]
        var bestArea: CGFloat = -1
        for candidate in candidates {
            let area = visibleArea(of: candidate, within: bounds)
            if area > bestArea {
                best = candidate
                bestArea = area
            }
        }

        var origin = best.origin
        if bestArea < cardSize.width * cardSize.height {
            let clampedX = clamp(origin.x, to: bounds.minX...max(bounds.minX, bounds.maxX - cardSize.width))
            let clampedY = clamp(origin.y, to: bounds.minY...max(bounds.minY, bounds.maxY - cardSize.height))
            origin = CGPoint(x: clampedX, y: clampedY)
        }

        return CGRect(origin: origin, size: cardSize)
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let appKitRect = appKitRect(for: rect)
        let center = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
        if let match = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return match
        }
        return NSScreen.screens.min(by: { distanceSquared(from: center, to: $0.frame) < distanceSquared(from: center, to: $1.frame) })
    }

    private static func visibleArea(of rect: CGRect, within bounds: CGRect) -> CGFloat {
        let intersection = rect.intersection(bounds)
        if intersection.isNull || intersection.isEmpty {
            return 0
        }
        return intersection.width * intersection.height
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
