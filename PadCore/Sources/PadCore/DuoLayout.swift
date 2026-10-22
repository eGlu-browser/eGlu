import Foundation

/// What the iPhone Duo's fold does to the window's layout, worked out
/// without UIKit so it can be tested anywhere (Docs/iPhoneDuoDesign.md §5).
public enum DuoLayout {
    /// The sidebar's width, and the room between its trailing edge and the
    /// page, in the window's points.
    public struct Sidebar: Equatable, Sendable {
        public let width: CGFloat
        /// From the sidebar's trailing edge to the page's leading one.
        public let gap: CGFloat
    }

    /// The sidebar while it shows. Folded like a book (the fold running top
    /// to bottom), it reaches the fold and the page starts past it, so each
    /// half of the display is one of the two. Folded like a laptop, fully
    /// open, or with the fold on the wrong side or too near the edge for a
    /// sidebar, it is its own width with the usual gap.
    ///
    /// - Parameters:
    ///   - start: where the sidebar starts: its left edge, or its right one
    ///     in right-to-left languages, where it stands on the right.
    ///   - fold: the active fold's frame, its margins included, or nil.
    ///   - rightToLeft: the sidebar stands on the right.
    ///   - standard: the sidebar's own width.
    ///   - minimum: the narrowest the sidebar goes to reach a fold.
    ///   - gap: the room between sidebar and page with no fold.
    public static func sidebar(start: CGFloat, fold: CGRect?, rightToLeft: Bool,
                               standard: CGFloat, minimum: CGFloat, gap: CGFloat) -> Sidebar {
        let usual = Sidebar(width: standard, gap: gap)
        guard let fold, fold.height > fold.width else { return usual }
        let width = rightToLeft ? start - fold.maxX : fold.minX - start
        guard width >= minimum else { return usual }
        return Sidebar(width: width, gap: fold.width)
    }
}
