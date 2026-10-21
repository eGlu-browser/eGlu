import CoreGraphics
import Foundation

/// The pinned tabs in a row of tabs along the top (iPad's TopTabs, the Mac's
/// TopTabBar), when they would take more of the row than is theirs: as many
/// as fit stay tiles, in their order, and the rest go behind a button that
/// says how many they are. The tab on screen always stays out; then the
/// open ones seen last. Those not opened yet, and then the longest unseen,
/// are the first to go behind the button.
public enum PinnedOverflow {
    /// The most of the row's width the pinned tiles take.
    public static let share: CGFloat = 0.3

    /// The tiles to show and the tabs behind the button, each in the order
    /// they are pinned in: `room` the row's width, `tile` a tile's and the
    /// button's width, `gap` between them; `live` the tabs with a page open.
    public static func split(_ pinned: [TabRecord], current: UUID?, live: Set<UUID>, room: CGFloat, tile: CGFloat,
                             gap: CGFloat) -> (shown: [TabRecord], hidden: [TabRecord]) {
        let width = room * share
        let fits = max(Int((width + gap) / (tile + gap)), 1)
        guard pinned.count > fits else { return (pinned, []) }
        // One place goes to the button; at least the tab on screen stays.
        let places = max(fits - 1, 1)
        let ranked = pinned.sorted { a, b in
            let rank = { (tab: TabRecord) in tab.id == current ? 0 : live.contains(tab.id) ? 1 : 2 }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.shown > b.shown
        }
        let kept = Set(ranked.prefix(places).map(\.id))
        return (pinned.filter { kept.contains($0.id) }, pinned.filter { !kept.contains($0.id) })
    }
}
