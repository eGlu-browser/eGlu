import Foundation

/// How large a site's icon is drawn on its pinned tile, so that every icon
/// is as large to the eye as the others, whatever its shape: a square app
/// icon (Hacker News's), a disc (Discord's, GitHub's), a knot of lines
/// (ChatGPT's) or a wide mark (Are.na's).
///
/// The eye takes a shape's size from the outline round it, not from its box
/// or its ink: a disc as wide as a square looks smaller than it, and a knot
/// of thin lines as large as the disc round it. So each icon's outline (its
/// convex hull) is made to cover as much as a square icon's rounded square
/// does: a disc is drawn about a tenth wider than a square, a wide mark
/// shorter and wider, and none more than 1.2 times the square's side either
/// way, so a long one keeps to the room the tile gives it.
public enum IconOptics {
    /// What a picture draws, in a square it is fitted into: its box's width
    /// and height as fractions of the square's side, and how much of that
    /// box its outline covers, 0 to 1.
    public struct Extent: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public let fill: Double
    }

    /// How much of its square an icon clipped to an app icon's rounded square
    /// covers (corners of 0.225 of its side): what every icon is matched to.
    public static let squareFill = 1 - (4 - Double.pi) * 0.225 * 0.225

    /// As far as an icon goes, either way, beside a square icon's side.
    public static let reach = 1.2

    /// The extent of what is drawn in `pixels`, `side` by `side`
    /// premultiplied RGBA with rows from the top: where its alpha is half
    /// or more. Nil where nothing is.
    public static func extent(of pixels: [UInt8], side: Int) -> Extent? {
        guard side > 0, pixels.count >= side * side * 4 else { return nil }
        // Each row's outermost solid pixels, by their corners: the hull of all of them is the hull of these.
        var corners: [(x: Double, y: Double)] = []
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            var left = -1, right = -1
            for x in 0..<side where pixels[(y * side + x) * 4 + 3] >= 128 {
                if left < 0 { left = x }
                right = x
            }
            guard left >= 0 else { continue }
            minX = min(minX, left)
            maxX = max(maxX, right)
            minY = min(minY, y)
            maxY = max(maxY, y)
            corners += [(Double(left), Double(y)), (Double(left), Double(y + 1)),
                        (Double(right + 1), Double(y)), (Double(right + 1), Double(y + 1))]
        }
        guard maxX >= minX else { return nil }
        let width = Double(maxX - minX + 1), height = Double(maxY - minY + 1)
        return Extent(width: width / Double(side), height: height / Double(side),
                      fill: min(area(ofHullOf: corners) / (width * height), 1))
    }

    /// The side of the square to draw a picture of `extent` in, beside a
    /// square icon drawn `side` across: so its outline covers as much as
    /// that square's rounded square, its proportions kept, within `reach`.
    public static func square(for extent: Extent, side: Double) -> Double {
        guard extent.width > 0, extent.height > 0 else { return side }
        let aspect = extent.width / extent.height
        // Never less than a third: a scatter of dots would grow without end.
        let fill = min(max(extent.fill, 1.0 / 3), squareFill)
        var height = (side * side * squareFill / fill / aspect).squareRoot()
        var width = height * aspect
        let longest = max(width, height)
        if longest > side * reach {
            width *= side * reach / longest
            height *= side * reach / longest
        }
        return width / extent.width
    }

    /// The area of the convex hull round `points` (Andrew's monotone chain).
    private static func area(ofHullOf points: [(x: Double, y: Double)]) -> Double {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard sorted.count >= 3 else { return 0 }
        func turn(_ o: (x: Double, y: Double), _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [(x: Double, y: Double)] = [], upper: [(x: Double, y: Double)] = []
        for point in sorted {
            while lower.count >= 2, turn(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 { lower.removeLast() }
            lower.append(point)
        }
        for point in sorted.reversed() {
            while upper.count >= 2, turn(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 { upper.removeLast() }
            upper.append(point)
        }
        let hull = Array(lower.dropLast()) + Array(upper.dropLast())
        var twice = 0.0
        for (i, p) in hull.enumerated() {
            let q = hull[(i + 1) % hull.count]
            twice += p.x * q.y - q.x * p.y
        }
        return abs(twice) / 2
    }
}
