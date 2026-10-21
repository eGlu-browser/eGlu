import AppKit
import PadCore
import SwiftUI

// The Mac's window is the space's colour, seen through the desktop behind
// it, as Arc's is its theme's; the page is a card on it. What the app draws
// stays quiet: the sidebar's words and icons in the label colours, and the
// controls in Liquid Glass, which takes its colour from what is under it.

extension SpaceColor {
    /// The system's own shades, which turn lighter in the dark as Apple's colours do.
    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .teal: return .systemTeal
        case .indigo: return .systemIndigo
        case .gray: return .systemGray
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    /// Words on the colour: dark on the light ones, white on the rest.
    var ink: Color {
        self == .yellow ? Color.black.opacity(0.85) : .white
    }

    var name: String {
        rawValue.capitalized
    }
}

/// The greys the app draws with, by the iPad's names, so what the two share
/// (HandoffGuide) draws the same: each a pair, for light and for dark.
enum Palette {
    static let muted = pair(0.55, 0.58)
    /// What stands on glass is never a solid grey, which sits on the glass
    /// as a patch: a see-through dark lets the glass's own colour through
    /// and reads as a shade of it, as the iPad's bars' shade does.
    static let faint = dim(light: 0.12, dark: 0.32)
    static let wash = dim(light: 0.05, dark: 0.22)
    /// A hairline round a site's icon, so a white or a black one keeps its edge on glass.
    static let outline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.1)
    })
    /// Under what the pointer is on, and under what is held down: black in
    /// the light and white in the dark, strong enough to be seen at a
    /// glance on the sidebar's colour and on glass alike.
    static let hover = shade(light: 0.09, dark: 0.13)
    static let press = shade(light: 0.16, dark: 0.22)

    private static func pair(_ light: CGFloat, _ dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }

    /// See-through black, darker in the dark: a well in the glass.
    private static func dim(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(white: 0, alpha: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    private static func shade(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        })
    }
}

extension Animation {
    /// A highlight coming and going under the pointer: quick, and slowing as it ends.
    static let hover = Animation.easeOut(duration: 0.12)
}

/// The motion of everything in the window: a spring with no bounce, which
/// starts from wherever the last one left off when interrupted.
extension Animation {
    static let bar = Animation.spring(duration: 0.3, bounce: 0)
}

enum Metrics {
    /// The one step the window is spaced by: the page's card from the
    /// window's edges and from the sidebar, the sidebar's rows from its edges,
    /// and its groups (the top row, the address, the tiles, the tabs, the
    /// spaces) from each other.
    static let gap: CGFloat = 8
    /// The window's own corners, as macOS 26 draws a window with no toolbar.
    static let window: CGFloat = 16
    /// The page's card, `gap` inside the window's corners: smaller by as
    /// much, so the two curves run side by side.
    static let card: CGFloat = window - gap
    /// The glass buttons of the top row, and the cell the window's own
    /// buttons are centred in beside them (WindowButtons).
    static let control: CGFloat = 28
    /// The address, the share button, and the controls of the space bar.
    static let field: CGFloat = 32
    static let row: CGFloat = 34
    /// A row's corners: its 16-point icon's own (3.6) and the 9 points round it.
    static let rowCorner: CGFloat = 12
    /// A pinned tile: its icon 18 points, a little larger than a row's 16,
    /// 13 from the tile's top and foot, the tile's corners the icon's (4)
    /// and those 13.
    static let tile: CGFloat = 44
    static let tileIcon: CGFloat = 18
    static let tileCorner: CGFloat = 17
    /// A pane of rows (the command bar, the peeking sidebar): the rows'
    /// corners and the gap round them.
    static let pane: CGFloat = rowCorner + gap
}

/// A press that shows: the control gives a little, to 0.96, while held.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.bar, value: configuration.isPressed)
    }
}

// MARK: A site's icon

/// A site's icon as SiteIcons has it, or its first letter on a colour of
/// its own until it does.
struct SiteIconView: View {
    let url: URL?
    var size: CGFloat = 16
    @ObservedObject private var icons = SiteIcons.shared
    /// A drawn icon with a dark look of its own shows it on a dark screen.
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        let lightGround = icons.needsLightGround(url, dark: scheme == .dark)
        Group {
            if let image = icons.image(for: url, dark: scheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    // A dark shape on clear, on a dark screen: on a light ground, as Safari shows it.
                    .padding(lightGround ? size * 0.14 : 0)
                    .background { if lightGround { Color.white.opacity(0.92) } }
            } else if url == nil {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(.secondary)
            } else {
                ZStack {
                    Self.letterColor(for: url).color
                    Text(letter)
                        .font(.system(size: size * 0.6, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private static func site(of url: URL?) -> String {
        guard let host = url?.host() else { return "" }
        return Destination.registrable(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }

    private var letter: String {
        Self.site(of: url).first.map { String($0).uppercased() } ?? "•"
    }

    /// The same colour for a site every time: from its name, not at random.
    static func letterColor(for url: URL?) -> SpaceColor {
        let palette: [SpaceColor] = [.blue, .purple, .pink, .red, .orange, .green, .teal, .indigo]
        let sum = site(of: url).unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }
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
    private static var known: [String: Read<NSColor?>] = [:]
    private static var marks: [String: Read<NSImage?>] = [:]
    private static var looks: [String: Read<Look>] = [:]
    private static var trims: [String: Read<NSImage?>] = [:]

    /// How a pinned tile shows a site's icon (PinnedIcon).
    enum Look: Equatable {
        /// It fills a square of its own (Figma's app icon, Notion's,
        /// Hacker News's): shown as it is. Its ground, where its edge is all
        /// one colour, tints its tile on screen, under its mark.
        case own(ground: NSColor?)
        /// A badge: a shape on clear whose outline is all one colour, a
        /// disc or a lozenge (Pinterest's red, Discord's, Apple's white,
        /// Spotify's green), that stands out on the glass: shown as it is,
        /// with no square, a little larger where it is round. On screen its
        /// colour is the tile's, and what it holds stands on it: the badge's
        /// inside without the colour, or, all one colour, the badge itself
        /// in white or black, whichever stands out on that colour more.
        /// `fill`: how much of its box it covers, a disc about 0.79.
        case badge(colour: NSColor, solid: Bool, fill: Double)
        /// Any other shape on clear: a cluster of colours with nothing round
        /// it (Figma's logo, Slack's), or one lost on the glass in the light
        /// or the dark (GitHub's dark disc). Shown on a square of black or
        /// white, whichever it stands out on more, and on screen as the
        /// shape alone: in the words' colour on the space's where it is all
        /// one colour, in its own on its square's where it has several.
        case shape(square: NSColor, oneColour: Bool)
    }

    /// The site's icon cut to what it draws: the clear space a site leaves
    /// round its icon, more for some than for others, goes, so that icons
    /// are sized by what is seen of them (PinnedIcon).
    static func trimmed(for url: URL?) -> NSImage? {
        guard let key = IconKey.of(url), let image = SiteIcons.shared.image(for: url) else { return nil }
        if let read = trims[key], read.picture === image { return read.value }
        var cut: NSImage? = image
        if let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
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
                cut = NSImage(cgImage: piece, size: NSSize(width: piece.width, height: piece.height))
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
    /// stand out most) stands out from both the light glass and the dark at
    /// 2 to 1 or more: a lower bar than WCAG's 3 to 1 for what isn't text,
    /// since a square is put round only what would be lost without one.
    /// Its colours, all one or several, are within a tenth of the way to
    /// white of their average on every channel or not; a boxed shape's
    /// square is the black or the white it stands out on more, on average.
    private static func shape(of image: NSImage) -> Look? {
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
        var onWhite = 0.0, onBlack = 0.0
        for y in 0..<side {
            for x in 0..<side where alpha(x, y) >= 0.5 {
                let rgb = colour(x, y)
                for c in 0..<3 { channels[c].append(rgb[c]) }
                let light = 0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
                lights.append(light)
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
            // The glass of a pinned tile, as light as it is in the light and in the dark.
            func standsOut(on glass: Double) -> Bool {
                let ratios = lights.map { (max($0, glass) + 0.05) / (min($0, glass) + 0.05) }.sorted()
                return ratios[min(ratios.count - 1, Int(Double(ratios.count) * 0.95))] >= 2
            }
            if Double(near) >= Double(outline.count) * 0.7, standsOut(on: 0.7), standsOut(on: 0.045) {
                let fill = Double(lights.count) / Double((maxX - minX + 1) * (maxY - minY + 1))
                return .badge(colour: NSColor(srgbRed: min(median[0], 1), green: min(median[1], 1), blue: min(median[2], 1), alpha: 1),
                              solid: oneColour, fill: fill)
            }
        }
        return .shape(square: onWhite >= onBlack ? .white : .black, oneColour: oneColour)
    }

    /// White or near-black on `colour`, whichever stands out on it more.
    static func ink(on colour: NSColor) -> Color {
        let rgb = colour.usingColorSpace(.sRGB) ?? colour
        let light = 0.2126 * linear(Double(rgb.redComponent)) + 0.7152 * linear(Double(rgb.greenComponent))
            + 0.0722 * linear(Double(rgb.blueComponent))
        return 1.05 / (light + 0.05) >= (light + 0.05) / 0.05 ? .white : Color.black.opacity(0.85)
    }

    /// A channel of sRGB as light, for WCAG's luminance.
    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// The icon drawn at `side` pixels a side, as premultiplied RGBA bytes.
    private static func pixels(of image: NSImage, side: Int) -> [UInt8]? {
        guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
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
        let picture: NSImage
        let value: Value
    }

    /// The icon without its ground (`ground`): what it draws, standing on
    /// clear. On the pinned tile on screen, whose glass is tinted with that
    /// ground, the icon has no square left to show: only its mark, on its
    /// own colour in glass. Nil for an icon with no ground of its own.
    static func mark(for url: URL?) -> NSImage? {
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
    private static func knockout(_ image: NSImage, ground: NSColor) -> NSImage? {
        let side = 96
        guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ground = ground.usingColorSpace(.sRGB),
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
        let gr = Double(ground.redComponent), gg = Double(ground.greenComponent), gb = Double(ground.blueComponent)
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
        return NSImage(cgImage: made, size: NSSize(width: side, height: side))
    }

    static func color(for url: URL?) -> Color? {
        guard let key = IconKey.of(url) else { return nil }
        guard let image = SiteIcons.shared.image(for: url) else {
            return SiteIconView.letterColor(for: url).color
        }
        if let read = known[key], read.picture === image { return read.value.map { Color(nsColor: $0) } }
        let read = ground(of: image)
        known[key] = Read(picture: image, value: read)
        return read.map { Color(nsColor: $0) }
    }

    /// The icon drawn at 48 pixels; the box round what of it is solid (an
    /// icon may come with clear space round it); and the two pixels along
    /// that box's inside. Half or more of them solid and mostly of one
    /// colour is a ground, and that colour is theirs.
    private static func ground(of image: NSImage) -> NSColor? {
        let side = 48
        guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
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
        return NSColor(srgbRed: min(r, 1), green: min(g, 1), blue: min(b, 1), alpha: 1)
    }
}

// MARK: The window behind everything

/// The desktop seen through the window, blurred, as a Mac sidebar is: the
/// ground the space's colour is laid over.
struct Backdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The space's colour over the blurred desktop: stronger at the top, where
/// the sidebar's space name is, fading toward the foot; paler in the dark,
/// where a strong colour would glare beside the page.
struct SpaceWash: View {
    let color: SpaceColor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.26 : 0.34
        ZStack {
            Backdrop()
            LinearGradient(colors: [color.color.opacity(strength), color.color.opacity(strength * 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .animation(.easeInOut(duration: 0.35), value: color)
        }
        .ignoresSafeArea()
    }
}
