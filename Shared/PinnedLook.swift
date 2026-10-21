import PadCore
import SwiftUI
#if os(macOS)
import AppKit
/// A colour as each platform has one.
typealias TintColor = NSColor
#else
import UIKit
typealias TintColor = UIColor
#endif

// A pinned tab's look, the iPad's and the Mac's alike: how its icon is
// read (IconTint), drawn at rest and on screen (PinnedIcon), the soft plate
// of colour under it (Plate) and the light under the pointer (PointerGlow).

extension SiteImage {
    /// The picture's pixels, for reading.
    var cgPicture: CGImage? {
        #if os(macOS)
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        cgImage
        #endif
    }

    /// A picture of pixels, one to a point.
    static func made(_ picture: CGImage) -> SiteImage {
        #if os(macOS)
        NSImage(cgImage: picture, size: NSSize(width: picture.width, height: picture.height))
        #else
        UIImage(cgImage: picture)
        #endif
    }
}

extension TintColor {
    static func srgb(_ red: Double, _ green: Double, _ blue: Double) -> TintColor {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        #else
        UIColor(red: red, green: green, blue: blue, alpha: 1)
        #endif
    }

    /// Red, green and blue in sRGB, 0 to 1.
    var srgbComponents: (red: Double, green: Double, blue: Double) {
        #if os(macOS)
        let rgb = usingColorSpace(.sRGB) ?? self
        return (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
        #endif
    }
}

extension Color {
    init(tint: TintColor) {
        #if os(macOS)
        self.init(nsColor: tint)
        #else
        self.init(uiColor: tint)
        #endif
    }
}

extension Image {
    init(site: SiteImage) {
        #if os(macOS)
        self.init(nsImage: site)
        #else
        self.init(uiImage: site)
        #endif
    }
}

/// A hairline round a square icon, so a white or a black one keeps its edge
/// on glass: black in the light and white in the dark, at a tenth.
enum PinnedOutline {
    #if os(macOS)
    static let colour = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.1)
    })
    #else
    static let colour = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.1) : UIColor(white: 0, alpha: 0.1)
    })
    #endif
}

/// The colour of a site's icon's own ground, for the glass of its pinned
/// tab while it is on screen: the tile then reads as the icon run out to
/// its edges (Figma's black, Notion's white, Hacker News's orange). Read
/// along the edge of what is drawn of the icon, the median of its pixels
/// there. An icon that is a shape on a clear ground (Apple's, WebKit's) has
/// no ground of its own and is nil: the tab is then lit without a colour.
/// A site with no icon yet has its letter's.
@MainActor
enum IconTint {
    /// By site, for icons that have arrived: each is read once, and again
    /// when the site's icon is another picture (one chosen again, SiteIcons).
    private static var known: [String: Read<TintColor?>] = [:]
    private static var marks: [String: Read<SiteImage?>] = [:]
    private static var looks: [String: Read<Look>] = [:]
    private static var trims: [String: Read<SiteImage?>] = [:]

    /// How a pinned tile shows a site's icon (PinnedIcon).
    enum Look: Equatable {
        /// It fills a square of its own (Figma's app icon, Notion's,
        /// Hacker News's): shown as it is. Its ground, where its edge is all
        /// one colour, tints its tile on screen, under its mark.
        case own(ground: TintColor?)
        /// A badge: a shape on clear whose outline is all one colour, a
        /// disc or a lozenge (Pinterest's red, Discord's, Apple's white,
        /// Spotify's green), that stands out on the glass: shown as it is,
        /// with no square, a little larger where it is round. On screen its
        /// colour is the tile's, and what it holds stands on it: the badge's
        /// inside without the colour, or, all one colour, the badge itself
        /// in white or black, whichever stands out on that colour more.
        /// `fill`: how much of its box it covers, a disc about 0.79.
        case badge(colour: TintColor, solid: Bool, fill: Double)
        /// Any other shape on clear: a cluster of colours with nothing round
        /// it (Figma's logo, Slack's), or one lost on the glass in the light
        /// or the dark (GitHub's dark disc). Shown on a square of black or
        /// white, whichever it stands out on more, and on screen as the
        /// shape alone: in the words' colour on the space's where it is all
        /// one colour, in its own on its square's where it has several.
        case shape(square: TintColor, oneColour: Bool)
    }

    /// The site's icon cut to what it draws: the clear space a site leaves
    /// round its icon, more for some than for others, goes, so that icons
    /// are sized by what is seen of them (PinnedIcon).
    static func trimmed(for url: URL?) -> SiteImage? {
        guard let key = IconKey.of(url), let image = SiteIcons.shared.image(for: url) else { return nil }
        if let read = trims[key], read.picture === image { return read.value }
        var cut: SiteImage? = image
        if let picture = image.cgPicture,
           let space = CGColorSpace(name: CGColorSpace.sRGB) {
            let width = picture.width, height = picture.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            var minX = width, minY = height, maxX = -1, maxY = -1
            if drawn {
                for y in 0..<height {
                    for x in 0..<width where bytes[(y * width + x) * 4 + 3] >= 26 {
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        minY = min(minY, y)
                        maxY = max(maxY, y)
                    }
                }
            }
            // The bitmap's rows run from its top, as CGImage's cropping counts them.
            if maxX >= minX, maxY >= minY, maxX - minX + 1 < width || maxY - minY + 1 < height,
               let piece = picture.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) {
                cut = SiteImage.made(piece)
            }
        }
        trims[key] = Read(picture: image, value: cut)
        return cut
    }

    /// How the site's icon is shown on a pinned tile; nil until it has one.
    static func look(for url: URL?) -> Look? {
        guard let key = IconKey.of(url), let image = SiteIcons.shared.image(for: url) else { return nil }
        if let read = looks[key], read.picture === image { return read.value }
        let read: Look
        if let shape = shape(of: image) {
            read = shape
        } else {
            _ = color(for: url)
            read = .own(ground: known[key]?.value ?? nil)
        }
        looks[key] = Read(picture: image, value: read)
        return read
    }

    /// A shape on clear: under half the edge of the box round what is solid
    /// is itself solid (a square with clear space round it is still a
    /// square); nil for an icon that fills its square.
    ///
    /// A badge where seven in ten of the pixels along its outline are near
    /// their median colour, and its most standing-out part (its 5% that
    /// stand out most) is seen on both the light glass and the dark: 0.15 or
    /// more apart in OKLab, where hue and how strong a colour is count as
    /// well as lightness. By lightness alone Spotify's green on the light
    /// glass (1.4 to 1) is as lost as GitHub's dark disc on the dark (1.3 to
    /// 1), which it plainly isn't; in OKLab the green is 0.27 away and the
    /// dark disc 0.07. A square is put round only what would be lost.
    /// Its colours, all one or several, are within a tenth of the way to
    /// white of their average on every channel or not; a boxed shape's
    /// square is the black or the white it stands out on more, on average.
    private static func shape(of image: SiteImage) -> Look? {
        let side = 48
        guard let bytes = pixels(of: image, side: side) else { return nil }
        func alpha(_ x: Int, _ y: Int) -> Double { Double(bytes[(y * side + x) * 4 + 3]) / 255 }
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where alpha(x, y) >= 0.6 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        var ring = 0, solid = 0
        for y in minY...maxY {
            for x in minX...maxX where x - minX < 2 || maxX - x < 2 || y - minY < 2 || maxY - y < 2 {
                ring += 1
                if alpha(x, y) >= 0.6 { solid += 1 }
            }
        }
        guard Double(solid) < Double(ring) * 0.5 else { return nil }
        func colour(_ x: Int, _ y: Int) -> [Double] {
            let i = (y * side + x) * 4, a = max(alpha(x, y), 0.01)
            // Premultiplied: divided back out.
            return (0..<3).map { Double(bytes[i + $0]) / 255 / a }
        }
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && x < side && y >= 0 && y < side && alpha(x, y) >= 0.6
        }
        var channels: [[Double]] = [[], [], []]
        var outline: [[Double]] = []
        var lights: [Double] = []
        var labs: [(Double, Double, Double)] = []
        var onWhite = 0.0, onBlack = 0.0
        for y in 0..<side {
            for x in 0..<side where alpha(x, y) >= 0.5 {
                let rgb = colour(x, y)
                for c in 0..<3 { channels[c].append(rgb[c]) }
                let light = 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
                lights.append(light)
                labs.append(oklab(rgb[0], rgb[1], rgb[2]))
                onWhite += 1.05 / (light + 0.05)
                onBlack += (light + 0.05) / 0.05
                if opaque(x, y), !opaque(x + 1, y) || !opaque(x - 1, y) || !opaque(x, y + 1) || !opaque(x, y - 1) {
                    outline.append(rgb)
                }
            }
        }
        guard !channels[0].isEmpty else { return nil }
        let oneColour = channels.allSatisfy { values in
            let mean = values.reduce(0, +) / Double(values.count)
            return (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)).squareRoot() < 0.1
        }
        if !outline.isEmpty {
            let median = (0..<3).map { c in outline.map { $0[c] }.sorted()[outline.count / 2] }
            let near = outline.filter { abs($0[0] - median[0]) + abs($0[1] - median[1]) + abs($0[2] - median[2]) < 0.3 }.count
            // The glass of a pinned tile, as it is in the light and in the dark.
            func standsOut(on glass: (Double, Double, Double)) -> Bool {
                let apart = labs.map { lab -> Double in
                    let (l, a, b) = (lab.0 - glass.0, lab.1 - glass.1, lab.2 - glass.2)
                    return (l * l + a * a + b * b).squareRoot()
                }.sorted()
                return apart[min(apart.count - 1, Int(Double(apart.count) * 0.95))] >= 0.15
            }
            if Double(near) >= Double(outline.count) * 0.7,
               standsOut(on: oklab(0.88, 0.9, 0.94)), standsOut(on: oklab(0.2, 0.22, 0.27)) {
                let fill = Double(lights.count) / Double((maxX - minX + 1) * (maxY - minY + 1))
                return .badge(colour: TintColor.srgb(min(median[0], 1), min(median[1], 1), min(median[2], 1)),
                              solid: oneColour, fill: fill)
            }
        }
        return .shape(square: onWhite >= onBlack ? .white : .black, oneColour: oneColour)
    }

    /// White or near-black on `colour`, whichever stands out on it more.
    static func ink(on colour: TintColor) -> Color {
        let rgb = colour.srgbComponents
        let light = 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
        return 1.05 / (light + 0.05) >= (light + 0.05) / 0.05 ? .white : Color.black.opacity(0.85)
    }

    /// sRGB as OKLab (Björn Ottosson's): lightness, then green to red and
    /// blue to yellow, where equal distances look about equally far apart.
    private static func oklab(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
        let (r, g, b) = (linear(red), linear(green), linear(blue))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// A channel of sRGB as light, for WCAG's luminance.
    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// The icon drawn at `side` pixels a side, as premultiplied RGBA bytes.
    private static func pixels(of image: SiteImage, side: Int) -> [UInt8]? {
        guard let picture = image.cgPicture,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(picture, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? bytes : nil
    }

    /// What was read of a site's icon, and the picture it was read from,
    /// held so that no other picture can come to be taken for it.
    private struct Read<Value> {
        let picture: SiteImage
        let value: Value
    }

    /// The icon without its ground (`ground`): what it draws, standing on
    /// clear. On the pinned tile on screen, whose glass is tinted with that
    /// ground, the icon has no square left to show: only its mark, on its
    /// own colour in glass. Nil for an icon with no ground of its own.
    static func mark(for url: URL?) -> SiteImage? {
        guard let key = IconKey.of(url), let image = trimmed(for: url) else { return nil }
        if let made = marks[key], made.picture === image { return made.value }
        // Read the ground first; an icon with none keeps its own look.
        _ = color(for: url)
        var ground = known[key]?.value ?? nil
        if case .badge(let colour, _, _)? = look(for: url) { ground = colour }
        let made = ground.flatMap { knockout(image, ground: $0) }
        marks[key] = Read(picture: image, value: made)
        return made
    }

    /// Pixels near the ground's colour go clear, smoothly, and those partly
    /// of it keep the colour that is left once the ground is taken out of
    /// them, so the mark's edge carries no fringe of the ground.
    private static func knockout(_ image: SiteImage, ground: TintColor) -> SiteImage? {
        let side = 96
        guard let picture = image.cgPicture,
              let space = CGColorSpace(name: CGColorSpace.sRGB),

              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.interpolationQuality = .high
        // Whole and centred, its proportions kept: a trimmed icon is near square, not always square.
        let scale = CGFloat(side) / max(image.size.width, image.size.height, 1)
        let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        context.draw(picture, in: CGRect(x: (CGFloat(side) - fitted.width) / 2, y: (CGFloat(side) - fitted.height) / 2,
                                         width: fitted.width, height: fitted.height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        let (gr, gg, gb) = ground.srgbComponents
        for i in stride(from: 0, to: side * side * 4, by: 4) {
            let a = Double(bytes[i + 3]) / 255
            guard a > 0 else { continue }
            let r = Double(bytes[i]) / 255 / a, g = Double(bytes[i + 1]) / 255 / a, b = Double(bytes[i + 2]) / 255 / a
            let distance = ((r - gr) * (r - gr) + (g - gg) * (g - gg) + (b - gb) * (b - gb)).squareRoot()
            // Clear within 0.1 of the ground, whole from 0.4, eased between.
            let t = min(max((distance - 0.1) / 0.3, 0), 1)
            let kept = t * t * (3 - 2 * t)
            guard kept > 0 else {
                bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 0
                continue
            }
            func own(_ value: Double, _ under: Double) -> Double { min(max((value - under * (1 - kept)) / kept, 0), 1) }
            let alpha = a * kept
            bytes[i] = UInt8(own(r, gr) * alpha * 255)
            bytes[i + 1] = UInt8(own(g, gg) * alpha * 255)
            bytes[i + 2] = UInt8(own(b, gb) * alpha * 255)
            bytes[i + 3] = UInt8(alpha * 255)
        }
        guard let made = context.makeImage() else { return nil }
        return SiteImage.made(made)
    }

    static func color(for url: URL?) -> Color? {
        guard let key = IconKey.of(url) else { return nil }
        guard let image = SiteIcons.shared.image(for: url) else {
            return SiteIconView.letterColor(for: url).color
        }
        if let read = known[key], read.picture === image { return read.value.map { Color(tint: $0) } }
        let read = ground(of: image)
        known[key] = Read(picture: image, value: read)
        return read.map { Color(tint: $0) }
    }

    /// The icon drawn at 48 pixels; the box round what of it is solid (an
    /// icon may come with clear space round it); and the two pixels along
    /// that box's inside. Half or more of them solid and mostly of one
    /// colour is a ground, and that colour is theirs.
    private static func ground(of image: SiteImage) -> TintColor? {
        let side = 48
        guard let picture = image.cgPicture,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(picture, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        func alpha(_ x: Int, _ y: Int) -> Double { Double(bytes[(y * side + x) * 4 + 3]) / 255 }
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where alpha(x, y) >= 0.6 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let band = 2
        var edge: [(r: Double, g: Double, b: Double)] = []
        var ring = 0
        for y in minY...maxY {
            for x in minX...maxX where x - minX < band || maxX - x < band || y - minY < band || maxY - y < band {
                ring += 1
                let a = alpha(x, y)
                guard a >= 0.6 else { continue }
                // Premultiplied: divided back out.
                let i = (y * side + x) * 4
                edge.append((Double(bytes[i]) / 255 / a, Double(bytes[i + 1]) / 255 / a, Double(bytes[i + 2]) / 255 / a))
            }
        }
        guard Double(edge.count) >= Double(ring) * 0.5 else { return nil }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let r = median(edge.map(\.r)), g = median(edge.map(\.g)), b = median(edge.map(\.b))
        // A ground is one colour: most of the edge near the median, not a picture running off it.
        let near = edge.filter { abs($0.r - r) + abs($0.g - g) + abs($0.b - b) < 0.3 }.count
        guard Double(near) >= Double(edge.count) * 0.6 else { return nil }
        return TintColor.srgb(min(r, 1), min(g, 1), min(b, 1))
    }
}

/// The densest of the open tile's tint: a soft plate of the icon's ground
/// under its mark (K3, from a sheet of looks: 26 points, corners of 8,
/// softened by 6). While the pointer is on the tile it leans well toward
/// it, out from under the mark, and spreads a little, so the colour can be
/// seen to follow; at rest it drifts by a point or so, slowly, as light
/// through glass would. It holds still where Reduce Motion is on, and
/// leans without spreading.
struct Plate: View {
    let ground: Color
    /// Toward the pointer; nil while it is elsewhere.
    let toward: CGSize?
    /// Its side, corner and softening: the sidebar's tile's, or smaller in the row along the top.
    var side: CGFloat = 26
    var corner: CGFloat = 8
    var blur: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || toward != nil)) { context in
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(ground)
                .frame(width: side, height: side)
                .blur(radius: blur)
                .scaleEffect(toward == nil || reduceMotion ? 1 : 1.25)
                .offset(toward ?? drift(at: context.date))
        }
    }

    /// Where the plate leans: toward the pointer, three fifths of the way
    /// from the tile's middle, as far as `reach` either way; nil while the
    /// pointer is elsewhere.
    static func lean(toward pointer: CGPoint?, in size: CGSize, reach: CGSize) -> CGSize? {
        guard let pointer, size.width > 0 else { return nil }
        let x = (pointer.x - size.width / 2) * 0.6
        let y = (pointer.y - size.height / 2) * 0.6
        return CGSize(width: min(max(x, -reach.width), reach.width), height: min(max(y, -reach.height), reach.height))
    }

    /// A slow loop of about a point and a half across and one down, its
    /// two periods apart so it never quite repeats.
    private func drift(at date: Date) -> CGSize {
        guard !reduceMotion else { return .zero }
        let t = date.timeIntervalSinceReferenceDate
        return CGSize(width: cos(t * 2 * .pi / 7) * 1.5, height: sin(t * 2 * .pi / 5) * 1)
    }
}

/// A pinned tab's icon, in the sidebar's tile and the row's, the same in
/// every space and every look of the screen (IconTint.Look), and every icon
/// as large to the eye as the others: each is cut to what it draws first
/// (IconTint.trimmed), so the clear space a site leaves round it counts for
/// nothing.
///
/// At rest: an icon that fills its own square fills the square; a badge (a
/// disc of one colour round what it holds) is as it is, a little larger
/// where it is round, as large to the eye as a square (`badgeSide`); any
/// other shape on clear stands on a square of black or white, inside it at
/// its optical size (`symbolFrame`). On screen, in a window in front: the
/// icon's colour is the tile's, in a soft plate leaning to the pointer, and
/// the icon is what stands on it, at the size it has at rest: an own icon's
/// or a badge's mark without its ground (a badge of one colour, itself in
/// white or black); a shape alone, in its own colours on its square's
/// colour, or, all one colour, in the words' colour on the space's. A
/// window behind greys tinted glass, so its tile shows the icon at rest.
struct PinnedIcon: View {
    let url: URL?
    /// On screen, in a window in front.
    let open: Bool
    let colour: SpaceColor
    /// A square icon's side.
    let size: CGFloat
    let lean: CGSize?
    var plate = (side: CGFloat(26), corner: CGFloat(8), blur: CGFloat(6))
    @ObservedObject private var icons = SiteIcons.shared
    @Environment(\.colorScheme) private var scheme

    /// The tile's colour on screen: the icon's ground, a shape's square, or
    /// for a shape of one colour the space's; a letter's until the icon
    /// comes; nil for an icon whose edge is no one colour.
    static func ground(for url: URL?, colour: SpaceColor) -> Color? {
        switch IconTint.look(for: url) {
        case .own(let ground)?: return ground.map { Color(tint: $0) }
        case .badge(let badge, _, _)?: return Color(tint: badge)
        case .shape(let square, let oneColour)?: return oneColour ? colour.color : Color(tint: square)
        case nil: return IconTint.color(for: url)
        }
    }

    /// Where a shape is drawn in a square of `square` points: as large to the
    /// eye as a round one 72% of the square across, its width and height
    /// multiplying to that one's, so a tall, narrow logo (Figma's) is not
    /// lost beside a round one (GitHub's); and never more than 82% of the
    /// square either way, so it never meets the square's edge.
    static func symbolFrame(of picture: SiteImage, square: CGFloat) -> CGSize {
        let aspect = picture.size.width / max(picture.size.height, 1)
        let height = square * 0.72 / aspect.squareRoot()
        let width = height * aspect
        let fit = min(1, square * 0.82 / max(width, height))
        return CGSize(width: (width * fit).rounded(), height: (height * fit).rounded())
    }

    /// A badge's side beside squares of `square` points: as large as theirs
    /// to the eye, so larger the less of its box it covers (a disc, about
    /// 0.79 of it, by a tenth), and never by more than an eighth.
    static func badgeSide(fill: Double, square: CGFloat) -> CGFloat {
        (square * min(max((0.95 / max(fill, 0.01)).squareRoot(), 1), 1.125)).rounded()
    }

    var body: some View {
        let look = IconTint.look(for: url)
        let trimmed = IconTint.trimmed(for: url)
        if open, let ground = Self.ground(for: url, colour: colour), let look, let trimmed {
            Group {
                if case .shape(_, true) = look {
                    // A firmer plate under a shape of one colour, for its ink to stand out on the space's colour.
                    Plate(ground: ground, toward: lean, side: plate.side + 4, corner: plate.corner + 1, blur: plate.blur - 1)
                } else {
                    Plate(ground: ground, toward: lean, side: plate.side, corner: plate.corner, blur: plate.blur)
                }
            }
            .transition(.opacity)
            Group {
                switch look {
                case .shape(_, true):
                    let frame = Self.symbolFrame(of: trimmed, square: size)
                    ink.mask { picture(trimmed) }
                        .frame(width: frame.width, height: frame.height)
                case .shape:
                    let frame = Self.symbolFrame(of: trimmed, square: size)
                    picture(trimmed).frame(width: frame.width, height: frame.height)
                case .own:
                    picture(IconTint.mark(for: url) ?? trimmed).frame(width: size, height: size)
                case .badge(let badge, let solid, let fill):
                    let side = Self.badgeSide(fill: fill, square: size)
                    if solid {
                        IconTint.ink(on: badge).mask { picture(trimmed) }
                            .frame(width: side, height: side)
                    } else {
                        picture(IconTint.mark(for: url) ?? trimmed).frame(width: side, height: side)
                    }
                }
            }
            .transition(.opacity)
        } else if case .badge(_, _, let fill)? = look, let trimmed {
            // As it is: the badge is its own ground, and needs no square.
            let side = Self.badgeSide(fill: fill, square: size)
            picture(trimmed)
                .frame(width: side, height: side)
                .transition(.opacity)
        } else if let look, let trimmed {
            let corner = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            Group {
                switch look {
                case .shape(let square, _):
                    let frame = Self.symbolFrame(of: trimmed, square: size)
                    ZStack {
                        corner.fill(Color(tint: square))
                        picture(trimmed).frame(width: frame.width, height: frame.height)
                    }
                    .frame(width: size, height: size)
                case .own, .badge:
                    picture(trimmed)
                        .frame(width: size, height: size)
                        .clipShape(corner)
                }
            }
            // A hairline keeps a white or black square from running into the glass.
            .overlay { corner.strokeBorder(PinnedOutline.colour, lineWidth: 0.5) }
            .transition(.opacity)
        } else {
            // No icon yet: its letter, on its colour.
            SiteIconView(url: url, size: size)
                .transition(.opacity)
        }
    }

    /// A picture whole, in its own colours, as large as its frame lets it be.
    private func picture(_ image: SiteImage) -> some View {
        Image(site: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }

    /// A shape of one colour on the space's: white, or dark where white
    /// would stand out too little, on yellow, and on gray in the light,
    /// where the tile is lighter than the colour itself (3 to 1 at the
    /// least, as WCAG asks of what isn't text).
    private var ink: Color {
        colour == .gray && scheme == .light ? Color.black.opacity(0.85) : colour.ink
    }
}

/// A soft light under the pointer while it is on a pinned tile, following
/// it as light on glass would: on every tile, whether or not its icon has a
/// ground for a plate.
struct PointerGlow: View {
    let pointer: CGPoint?
    var radius: CGFloat = 30
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { box in
            if let pointer {
                RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.2 : 0.7), Color.white.opacity(0)],
                               center: UnitPoint(x: pointer.x / max(box.size.width, 1), y: pointer.y / max(box.size.height, 1)),
                               startRadius: 0, endRadius: radius)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    #if DEBUG
    /// Where a debug build puts the pointer on the open tile, in the tile's
    /// own fractions, for a picture of it: `-hoverPinned 0.8,0.3`.
    static let debugSpot: CGPoint? = {
        let parts = (UserDefaults.standard.string(forKey: "hoverPinned") ?? "").split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }()
    #endif
}

