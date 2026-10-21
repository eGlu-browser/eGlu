import Foundation

/// How wide the tabs along the top are, on iPad and Mac alike. They share
/// the row, each never narrower than its name needs to read nor wider than
/// a long one needs; past that the row scrolls. The tab on screen, where it
/// is the address, is wider: room for where the page is, its … and its ✕.
public enum TabWidths {
    public static let narrowest: CGFloat = 120
    public static let widest: CGFloat = 240
    /// The tab on screen that is the address.
    public static let addressNarrowest: CGFloat = 260
    public static let addressWidest: CGFloat = 420

    /// The tab on screen's width and every other tab's, for `count` tabs in
    /// `room`, `gap` apart; `address` when the tab on screen is the address.
    public static func widths(count: Int, room: CGFloat, gap: CGFloat, address: Bool) -> (current: CGFloat, each: CGFloat) {
        guard count > 0 else { return (0, 0) }
        let space = max(room - gap * CGFloat(count - 1), 0)
        let even = space / CGFloat(count)
        guard address else {
            let each = min(max(even, narrowest), widest)
            return (each, each)
        }
        // Half as wide again as an even share, inside its bounds, and never past the row.
        let current = min(min(max(even * 1.5, addressNarrowest), addressWidest), max(space, addressNarrowest))
        guard count > 1 else { return (current, 0) }
        let each = min(max((space - current) / CGFloat(count - 1), narrowest), widest)
        return (current, each)
    }
}
