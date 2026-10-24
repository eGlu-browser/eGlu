// Draws the eGlu symbol from ellipses, rectangles and a polygon with
// CoreGraphics' boolean operations (macOS 14 and later), then writes it as SVG,
// black and white, with preview PNGs. Redrawn from the sketch in the Figma file
// (node 31:8, "globe 1"). The app icon, Shared/eGlu.icon, has the FRAME=1 layers.
//
//     swiftc -O symbol.swift -o /tmp/symbol && /tmp/symbol .
//     COUNT=0 NAME=eglu-symbol-compact /tmp/symbol .     (without the motion crescents)
//     FRAME=1 NAME=eglu-icon /tmp/symbol .   (in the sketch's 800-point frame, the e's bowl centred
//                                             in it; and the e and the cursor apart, for the app icon)
//
// Every measure below can be tried from the environment (LEFT=20 /tmp/symbol .).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let p = ProcessInfo.processInfo.environment
func v(_ k: String, _ d: Double) -> CGFloat { CGFloat(Double(p[k] ?? "") ?? d) }

func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil)
}
func polygon(_ pts: [CGPoint]) -> CGPath {
    let m = CGMutablePath(); m.addLines(between: pts); m.closeSubpath(); return m
}

// Outer bowl: thick on the right, a hairline on the left (two offset ellipses).
let cx: CGFloat = 430, cy: CGFloat = 400, rx: CGFloat = 300, ry: CGFloat = 250
let left = v("LEFT", 18), right = v("RIGHT", 62), vert = v("VERT", 16)
let inL = cx - rx + left, inR = cx + rx - right
let outer = ellipse(cx, cy, rx, ry)
let bowl = outer.subtracting(ellipse((inL + inR) / 2, cy, (inR - inL) / 2, ry - vert))

// Meridian: an even ring inside, centred a little left of the bowl.
let mw = v("MW", 22), mcx = v("MCX", Double((inL + inR) / 2)), mrx = v("MRX", 144), mry = ry - 6
let meridian = ellipse(mcx, cy, mrx, mry).subtracting(ellipse(mcx, cy, mrx - mw, mry - mw))

// Equator, which is also the e's bar, clipped to the bowl.
let bar = v("BAR", 24)
let equator = rect(cx - rx - 1, cy - bar / 2, 2 * rx, bar).intersection(outer)

var mark = bowl.union(meridian).union(equator)
// The e's opening: everything right of centre between the bar and the lower terminals.
let apertureBottom = v("APB", 540)
mark = mark.subtracting(rect(mcx, cy + bar / 2, 500, apertureBottom - cy - bar / 2))

// Motion: crescents that hug the bowl's left side, built like it (two offset
// ellipses), each thinner, further out and shorter than the one inside it.
var trail = CGMutablePath() as CGPath
let gap = v("GAP", 24), cw = v("CW", 20), space = v("SPACE", 14)
var d = gap
for i in 0..<Int(v("COUNT", 3)) {
    let k = CGFloat(i)
    let w = cw - k * v("THIN", 5)
    let R = rx + d, Q = ry + d * v("QD", 0.5)
    let e = v("E0", 10) + k * v("EK", 55)        // taller cutter: shorter crescent
    let a = ellipse(cx - w, cy, R, Q)
    let b = ellipse(cx, cy, R, Q + e)
    trail = trail.union(a.subtracting(b))
    d += w + space
}
mark = mark.union(trail)

// Cursor: the classic arrow, upright, then tilted as in the sketch, with rounded corners. Drawn
// as the system's arrow is: the right wing's underside level, the left one at about 45 degrees,
// both notches cut in as deep, and the tail's sides parallel, so the tail runs straight out of the
// head rather than bending off its left side.
let r = v("ROUND", 9)
let local: [CGPoint] = [
    CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 236), CGPoint(x: 56, y: 186),
    CGPoint(x: 106, y: 286), CGPoint(x: 146, y: 266), CGPoint(x: 96, y: 166), CGPoint(x: 176, y: 166),
]
// Placed at the sketch's tip, (532, 427) after rounding, and about as tall as the sketch's (315).
let tilt = -v("TILT", 6.77) * .pi / 180
let scale = v("CS", 1.08)
let tip = CGPoint(x: v("TIPX", 541), y: v("TIPY", 436))
let placed = local.map { q in
    CGPoint(x: tip.x + scale * (q.x * cos(tilt) - q.y * sin(tilt)), y: tip.y + scale * (q.x * sin(tilt) + q.y * cos(tilt)))
}
let skeleton = polygon(placed)
let cursor = skeleton.union(skeleton.copy(strokingWithWidth: 2 * r, lineCap: .round, lineJoin: .round, miterLimit: 10))
let halo = skeleton.union(skeleton.copy(strokingWithWidth: 2 * (r + v("HALO", 16)), lineCap: .round, lineJoin: .round, miterLimit: 10))
let letter = mark.subtracting(halo)
mark = letter.union(cursor)

// Square artboard with the mark centred on its bounds; or, with FRAME, the sketch's own 800-point
// frame, in which the e's bowl is centred top to bottom (its margins above and below are equal).
let framed = v("FRAME", 0) > 0
let box = mark.boundingBoxOfPath
let side = framed ? 800 : max(box.width, box.height) * v("PAD", 1.0)
var move = framed ? CGAffineTransform(translationX: 0, y: 0)
                  : CGAffineTransform(translationX: (side - box.width) / 2 - box.minX, y: (side - box.height) / 2 - box.minY)
let final = mark.copy(using: &move)!

func n(_ x: CGFloat) -> String {
    var s = String(format: "%.2f", Double(x))
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s == "-0" ? "0" : s
}
func svgPath(_ path: CGPath) -> String {
var svgD = ""
path.applyWithBlock { e in
    let el = e.pointee, q = el.points
    switch el.type {
    case .moveToPoint: svgD += "M\(n(q[0].x)) \(n(q[0].y))"
    case .addLineToPoint: svgD += "L\(n(q[0].x)) \(n(q[0].y))"
    case .addQuadCurveToPoint: svgD += "Q\(n(q[0].x)) \(n(q[0].y)) \(n(q[1].x)) \(n(q[1].y))"
    case .addCurveToPoint: svgD += "C\(n(q[0].x)) \(n(q[0].y)) \(n(q[1].x)) \(n(q[1].y)) \(n(q[2].x)) \(n(q[2].y))"
    case .closeSubpath: svgD += "Z"
    @unknown default: break
    }
}
return svgD
}
let svgD = svgPath(final)
let vb = "0 0 \(n(side)) \(n(side))"
let base = p["NAME"] ?? "eglu-symbol"
for (name, fill) in [(base, "#000000"), (base + "-white", "#FFFFFF")] {
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(vb)\" width=\"\(n(side))\" height=\"\(n(side))\">\n<title>eGlu</title>\n<path fill=\"\(fill)\" fill-rule=\"nonzero\" d=\"\(svgD)\"/>\n</svg>\n"
    try! svg.write(toFile: "\(out)/\(name).svg", atomically: true, encoding: .utf8)
}
// The icon's two layers, in the same frame: the letter (with its trail) and the cursor.
if framed {
    for (suffix, part) in [("-e", letter), ("-cursor", cursor)] {
        let d = svgPath(part.copy(using: &move)!)
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(vb)\" width=\"\(n(side))\" height=\"\(n(side))\">\n<path fill=\"#FFFFFF\" fill-rule=\"nonzero\" d=\"\(d)\"/>\n</svg>\n"
        try! svg.write(toFile: "\(out)/\(base)\(suffix).svg", atomically: true, encoding: .utf8)
    }
    let b = letter.boundingBoxOfPath, c = cursor.boundingBoxOfPath
    print("bowl/letter y", n(b.minY), n(b.maxY), "cursor", n(c.minX), n(c.minY), n(c.width), n(c.height))
}

// Previews: large, then the sizes it has to survive, on light and dark.
func png(_ path: String, _ sizes: [Int], dark: Bool) {
    let pad = 24, w = sizes.reduce(0) { $0 + $1 + pad } + pad, h = sizes.max()! + 2 * pad
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(dark ? CGColor(gray: 0.11, alpha: 1) : CGColor(gray: 0.97, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    var x = pad
    for s in sizes {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(x), y: CGFloat(h - pad))
        ctx.scaleBy(x: CGFloat(s) / side, y: -CGFloat(s) / side)
        ctx.addPath(final)
        ctx.setFillColor(dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
        x += s + pad
    }
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
png("\(out)/\(base)-preview-light.png", [640, 128, 64, 32, 16], dark: false)
png("\(out)/\(base)-preview-dark.png", [640, 128, 64, 32, 16], dark: true)
print("side", n(side), "bytes", svgD.count)
