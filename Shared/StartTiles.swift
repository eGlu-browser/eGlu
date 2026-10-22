import PadCore
import SwiftUI

// A new tab's page, the iPad's and the Mac's alike: one column with the
// space's mark and name (SpaceMark), the way to an address, and the space's
// bookmarks as tiles (BookmarkFace) whose squares reach both edges of the
// column, as the field above them does (TileGrid), each part coming in after
// the one before it (arriving).

nonisolated enum StartMetrics {
    /// The column everything stands in, at its widest, and the least room on either side of it.
    static let column: CGFloat = 600
    static let margin: CGFloat = 32
    /// A tile's square and the icon in it.
    static let square: CGFloat = 64
    static let icon: CGFloat = 34
    /// The square's corner: the icon's (0.225 of its side) and the padding
    /// round it, so the two curves run side by side.
    static let corner = icon * 0.225 + (square - icon) / 2
    /// The least distance from one square's centre to the next.
    static let pitch: CGFloat = 96
    static let rowGap: CGFloat = 18
    /// The field's height.
    static let field: CGFloat = 44

    /// How far down the page the column starts: a little above the middle
    /// of a tall page, so it stands where the eye goes, and still near the
    /// top of a short one.
    static func top(in height: CGFloat) -> CGFloat {
        max(40, height * 0.14)
    }
}

/// The space's symbol on its colour, and its name under it.
struct SpaceMark: View {
    let space: Space

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: space.symbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(space.color.ink)
                .frame(width: 52, height: 52)
                .background(space.color.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(space.name)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A bookmark or a folder as a tile: the site's icon, or a folder in the
/// space's colour, on a rounded square that darkens a little under the
/// pointer, and its name under it in two lines at most.
struct BookmarkFace: View {
    let item: Bookmark
    let colour: SpaceColor
    let hovering: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: StartMetrics.corner, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.05))
                if item.isFolder {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(colour.color)
                        .accessibilityHidden(true)
                } else {
                    SiteIconView(url: item.url, size: StartMetrics.icon)
                }
            }
            .frame(width: StartMetrics.square, height: StartMetrics.square)
            Text(item.label)
                .font(.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .contentShape(Rectangle())
    }
}

/// Tiles in rows whose squares reach both edges of the column, as the field
/// and the heading above them do: as many to a row as stand `pitch` apart or
/// more, spread so the first square starts at the column's left edge and a
/// full row's last ends at its right; a row that isn't full, from the left.
/// Each tile is offered the room between its neighbours for its name.
struct TileGrid: Layout {
    var square = StartMetrics.square
    var pitch = StartMetrics.pitch
    var rowGap = StartMetrics.rowGap

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? square + pitch * CGFloat(max(subviews.count - 1, 0))
        let heights = rowHeights(of: subviews, in: width)
        return CGSize(width: width, height: max(heights.reduce(0, +) + rowGap * CGFloat(heights.count - 1), 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (count, step) = columns(in: bounds.width)
        let offer = ProposedViewSize(width: room(step), height: nil)
        var y = bounds.minY
        for (row, height) in rowHeights(of: subviews, in: bounds.width).enumerated() {
            for column in 0..<count {
                let index = row * count + column
                guard index < subviews.count else { break }
                subviews[index].place(at: CGPoint(x: bounds.minX + square / 2 + CGFloat(column) * step, y: y),
                                      anchor: .top, proposal: offer)
            }
            y += height + rowGap
        }
    }

    /// How many squares stand in a row, and how far apart their centres are.
    private func columns(in width: CGFloat) -> (count: Int, step: CGFloat) {
        let count = max(1, Int((width - square) / pitch) + 1)
        return (count, count > 1 ? (width - square) / CGFloat(count - 1) : pitch)
    }

    /// The width a tile's name has: the step less a little, so neighbours' names never touch.
    private func room(_ step: CGFloat) -> CGFloat {
        max(square, step - 6)
    }

    /// Each row as high as its tallest tile: a name in two lines makes its row taller.
    private func rowHeights(of subviews: Subviews, in width: CGFloat) -> [CGFloat] {
        let (count, step) = columns(in: width)
        let offer = ProposedViewSize(width: room(step), height: nil)
        return stride(from: 0, to: subviews.count, by: count).map { start in
            subviews[start..<min(start + count, subviews.count)].map { $0.sizeThatFits(offer).height }.max() ?? 0
        }
    }
}

extension View {
    /// In after the parts before it: faded and a little lower until `shown`,
    /// then in place `delay` seconds later; where motion is reduced, faded in
    /// where it stands.
    func arriving(_ shown: Bool, after delay: Double) -> some View {
        modifier(Arriving(shown: shown, delay: delay))
    }
}

private struct Arriving: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .animation(.bar.delay(delay), value: shown)
    }
}
