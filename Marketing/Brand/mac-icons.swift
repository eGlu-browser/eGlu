// Draws the Mac's pictures of the app icons (Mac/Assets.xcassets/AppIcons),
// which Settings › General › App Icon shows and the Dock takes: each icon in
// light and dark, as macOS draws an app's icon. Run it after changing an
// icon, from the repository's folder (it needs Icon Composer in Applications):
//
//     swiftc -O Marketing/Brand/mac-icons.swift -o /tmp/mac-icons && /tmp/mac-icons .
//
// macOS has no alternate icons and its asset catalog keeps only the light
// picture of an icon that isn't the app's own, so the pictures are Icon
// Composer's own renderings (its ictool), light and dark, set on macOS's icon
// grid: 824 points of the 1,024 with the shadow under them. The shadow is the
// system's, from the app's icon as Xcode compiles it; it is the shape's alone,
// the same under every icon.
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Bundle.image(forResource:) is AppKit's, which a script that names nothing
// else of it isn't linked with.
_ = NSApplication.shared

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let ictool = ProcessInfo.processInfo.environment["ICTOOL"]
    ?? "/Applications/Icon Composer.app/Contents/Executables/ictool"
/// AppIcon's (PadCore), in its order, with the file each is drawn from.
let icons = [("eGlu", "Shared/eGlu.icon")]
    + ["Globe", "Designer", "Engineer", "Signal", "Vista", "Hardcover", "Punk", "Astro"].map { ($0, "App/\($0).icon") }
/// macOS's icon grid: the icon's square, and where it sits on the canvas.
let canvas = 1024, body = 824, inset = 100
/// The pictures' size: the Dock's largest tile, 128 points, at 2x.
let output = 256

let work = FileManager.default.temporaryDirectory.appendingPathComponent("mac-icons-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw Failure("\(tool) \(arguments.joined(separator: " ")) failed") }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func image(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure("Can't read \(url.path)") }
    return image
}

/// The icon's square, as Icon Composer draws it for macOS in that rendition (Default or Dark).
func square(_ file: String, _ rendition: String) throws -> CGImage {
    let out = work.appendingPathComponent("\(UUID().uuidString).png")
    try run(ictool, [root.appendingPathComponent(file).path, "--export-image", "--output-file", out.path,
                     "--platform", "macOS", "--rendition", rendition,
                     "--width", "\(body)", "--height", "\(body)", "--scale", "1"])
    return try image(at: out)
}

/// An image's alpha on the canvas, drawn at `rect`, top row first.
func alpha(_ image: CGImage, in rect: CGRect) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: canvas * canvas)
    try bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: canvas, height: canvas, bitsPerComponent: 8,
                                      bytesPerRow: canvas, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { throw Failure("No alpha context") }
        context.draw(image, in: rect)
    }
    return bytes
}

/// The shadow under the app's own icon as Xcode compiles it for macOS: what
/// its picture has that Icon Composer's square hasn't, black.
func shadow() throws -> CGImage {
    let compiled = work.appendingPathComponent("Shadow.bundle/Contents/Resources")
    try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
    try run("/usr/bin/xcrun", ["actool", "--compile", compiled.path, "--platform", "macosx",
                               "--minimum-deployment-target", "26.0", "--app-icon", "eGlu",
                               "--output-partial-info-plist", work.appendingPathComponent("partial.plist").path,
                               root.appendingPathComponent("Shared/eGlu.icon").path])
    let info: [String: Any] = ["CFBundleIdentifier": "eglu.mac-icons.shadow", "CFBundlePackageType": "BNDL"]
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: work.appendingPathComponent("Shadow.bundle/Contents/Info.plist"))
    guard let bundle = Bundle(url: work.appendingPathComponent("Shadow.bundle")),
          let icon = bundle.image(forResource: "eGlu") else { throw Failure("No compiled icon") }
    var rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    guard let flattened = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
          flattened.width == canvas else { throw Failure("No \(canvas) px picture of the compiled icon") }
    let whole = try alpha(flattened, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    let own = try alpha(try square("Shared/eGlu.icon", "Default"),
                        in: CGRect(x: inset, y: inset, width: body, height: body))
    // The picture is the square over the shadow: where the square covers
    // part of a pixel, the shadow is what its alpha adds.
    var pixels = [UInt8](repeating: 0, count: canvas * canvas * 4)
    for i in 0..<(canvas * canvas) where own[i] < 255 {
        let picture = Double(whole[i]) / 255, covered = Double(own[i]) / 255
        pixels[i * 4 + 3] = UInt8(max(0, min(1, (picture - covered) / (1 - covered))) * 255 + 0.5)
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let made = CGImage(width: canvas, height: canvas, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: canvas * 4,
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw Failure("No shadow") }
    return made
}

func context(_ size: Int) throws -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.displayP3),
          let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure("No context") }
    context.interpolationQuality = .high
    return context
}

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw Failure("Can't write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure("Can't write \(url.path)") }
}

func json(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try (String(decoding: data, as: UTF8.self) + "\n").write(to: url, atomically: true, encoding: .utf8)
}

let catalog = root.appendingPathComponent("Mac/Assets.xcassets")
let folder = catalog.appendingPathComponent("AppIcons")
let info = ["info": ["author": "xcode", "version": 1]]
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
try json(info, to: catalog.appendingPathComponent("Contents.json"))
try json(info, to: folder.appendingPathComponent("Contents.json"))

let under = try shadow()
for (name, file) in icons {
    let set = folder.appendingPathComponent("AppIcon-\(name).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for (rendition, picture) in [("Default", "light"), ("Dark", "dark")] {
        let large = try context(canvas)
        large.draw(under, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
        large.draw(try square(file, rendition), in: CGRect(x: inset, y: inset, width: body, height: body))
        guard let drawn = large.makeImage() else { throw Failure("Nothing drawn for \(name)") }
        let small = try context(output)
        small.draw(drawn, in: CGRect(x: 0, y: 0, width: output, height: output))
        guard let made = small.makeImage() else { throw Failure("Nothing drawn for \(name)") }
        try write(made, to: set.appendingPathComponent("\(picture).png"))
    }
    // 2x: 128 points, the Dock's largest tile.
    try json([
        "images": [
            ["filename": "light.png", "idiom": "universal", "scale": "2x"],
            ["appearances": [["appearance": "luminosity", "value": "dark"]],
             "filename": "dark.png", "idiom": "universal", "scale": "2x"],
        ],
        "info": ["author": "xcode", "version": 1],
    ], to: set.appendingPathComponent("Contents.json"))
    print("AppIcon-\(name)")
}
