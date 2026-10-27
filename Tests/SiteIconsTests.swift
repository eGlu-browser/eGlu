import AppKit
import Combine
import XCTest

@MainActor
final class SiteIconsTests: XCTestCase {
    private let page = URL(string: "https://example.com/page")!

    func testImportedIconIsOnDiskWhenAnnouncedAndSurvivesCacheRemoval() async throws {
        let storage = try Storage()
        defer { storage.remove() }
        let icons = storage.icons()
        XCTAssertNil(icons.image(for: page))
        let png = try picture(.red)
        let saved = expectation(description: "Icon saved")
        let changes = icons.$revision.dropFirst().sink { _ in
            XCTAssertTrue(FileManager.default.fileExists(atPath: storage.file("example.com").path))
            saved.fulfill()
        }
        defer { changes.cancel() }
        icons.adopt(["example.com": png])
        await fulfillment(of: [saved], timeout: 10)

        try FileManager.default.removeItem(at: storage.caches)
        let reopened = storage.icons()
        try assertColour(reopened.image(for: page), .red)
        XCTAssertFalse(reopened.needs(page))
    }

    func testDownloadedIconSurvivesNewInstanceWithoutLoadingThePage() async throws {
        let storage = try Storage()
        defer { storage.remove() }
        let icons = storage.icons()
        let candidate = try XCTUnwrap(URL(string: "data:image/png;base64," + picture(.blue).base64EncodedString()))
        let saved = expectation(description: "Icon downloaded")
        let changes = icons.$revision.dropFirst().sink { _ in saved.fulfill() }
        defer { changes.cancel() }
        icons.learn([candidate], for: page)
        await fulfillment(of: [saved], timeout: 10)

        let reopened = storage.icons()
        try assertColour(reopened.image(for: page), .blue)
        XCTAssertFalse(reopened.needs(page))
    }

    func testSVGsLightAndDarkIconsAreBothSavedBeforeAnnouncement() async throws {
        let storage = try Storage()
        defer { storage.remove() }
        let icons = storage.icons()
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="96" height="96">
          <style>rect { fill: red; } @media (prefers-color-scheme: dark) { rect { fill: blue; } }</style>
          <rect width="96" height="96"/>
        </svg>
        """
        let candidate = try XCTUnwrap(URL(string: "data:image/svg+xml;base64," + Data(svg.utf8).base64EncodedString()))
        let saved = expectation(description: "Both looks saved")
        let changes = icons.$revision.dropFirst().sink { _ in
            XCTAssertTrue(FileManager.default.fileExists(atPath: storage.file("example.com~dark").path))
            saved.fulfill()
        }
        defer { changes.cancel() }
        icons.learn([candidate], for: page)
        await fulfillment(of: [saved], timeout: 20)

        let reopened = storage.icons()
        try assertColour(reopened.image(for: page), .red)
        try assertColour(reopened.image(for: page, dark: true), .blue)
    }

    func testCachedLightAndDarkIconsMigrateWithoutRefetching() throws {
        let storage = try Storage()
        defer { storage.remove() }
        try storage.write(picture(.red), key: "example.com", root: storage.caches)
        try storage.write(picture(.blue), key: "example.com~dark", root: storage.caches)

        let icons = storage.icons()
        try assertColour(icons.image(for: page), .red)
        try assertColour(icons.image(for: page, dark: true), .blue)
        XCTAssertFalse(icons.needs(page))
        try FileManager.default.removeItem(at: storage.caches)

        let reopened = storage.icons()
        try assertColour(reopened.image(for: page), .red)
        try assertColour(reopened.image(for: page, dark: true), .blue)
        XCTAssertFalse(reopened.needs(page))
    }

    func testFormerIconsMigrateButStillNeedReselection() throws {
        let storage = try Storage()
        defer { storage.remove() }
        try storage.write(picture(.red), key: "example.com", root: storage.caches, former: true)
        try storage.write(picture(.blue), key: "example.com~dark", root: storage.caches, former: true)

        let icons = storage.icons()
        try assertColour(icons.image(for: page), .red)
        try assertColour(icons.image(for: page, dark: true), .blue)
        XCTAssertTrue(icons.needs(page))
        try FileManager.default.removeItem(at: storage.caches)

        let reopened = storage.icons()
        try assertColour(reopened.image(for: page), .red)
        try assertColour(reopened.image(for: page, dark: true), .blue)
        XCTAssertTrue(reopened.needs(page))
    }

    func testDurableIconTakesPrecedenceOverCachedIcon() throws {
        let storage = try Storage()
        defer { storage.remove() }
        try storage.write(picture(.red), key: "example.com", root: storage.support)
        try storage.write(picture(.blue), key: "example.com", root: storage.caches)
        try assertColour(storage.icons().image(for: page), .red)
    }

    func testCorruptDurableIconFallsBackToAndMigratesCachedIcon() throws {
        let storage = try Storage()
        defer { storage.remove() }
        try storage.write(Data("not an image".utf8), key: "example.com", root: storage.support)
        try storage.write(picture(.blue), key: "example.com", root: storage.caches)
        try assertColour(storage.icons().image(for: page), .blue)
        try FileManager.default.removeItem(at: storage.caches)
        try assertColour(storage.icons().image(for: page), .blue)
    }

    func testReplacingFormerIconDoesNotResurrectItsDarkLookAfterRelaunch() async throws {
        let storage = try Storage()
        defer { storage.remove() }
        for root in [storage.support, storage.caches] {
            try storage.write(picture(.blue), key: "example.com~dark", root: root)
            try storage.write(picture(.blue), key: "example.com~dark", root: root, former: true)
        }
        try storage.write(picture(.blue), key: "example.com", root: storage.caches, former: true)
        let icons = storage.icons()
        let saved = expectation(description: "Replacement saved")
        let changes = icons.$revision.dropFirst().sink { _ in saved.fulfill() }
        defer { changes.cancel() }
        icons.adopt(["example.com": try picture(.red)])
        await fulfillment(of: [saved], timeout: 10)

        try assertColour(storage.icons().image(for: page, dark: true), .red)
        for root in [storage.support, storage.caches] {
            for former in [false, true] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: storage.file("example.com~dark", root: root, former: former).path))
            }
        }
    }

    func testUnreadableStorageStillShowsIconForThisRun() async throws {
        let storage = try Storage()
        defer { storage.remove() }
        try Data().write(to: storage.support)
        let icons = storage.icons()
        let saved = expectation(description: "Icon available in memory")
        let changes = icons.$revision.dropFirst().sink { _ in saved.fulfill() }
        defer { changes.cancel() }
        icons.adopt(["example.com": try picture(.red)])
        await fulfillment(of: [saved], timeout: 10)
        try assertColour(icons.image(for: page), .red)
    }

    private func picture(_ colour: NSColor) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<32 {
            for x in 0..<32 { bitmap.setColor(colour, atX: x, y: y) }
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func assertColour(_ image: SiteImage?, _ expected: NSColor, file: StaticString = #filePath, line: UInt = #line) throws {
        let image = try XCTUnwrap(image, file: file, line: line)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil), file: file, line: line)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let colour = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB),
                                   file: file, line: line)
        let expected = try XCTUnwrap(expected.usingColorSpace(.deviceRGB))
        XCTAssertEqual(colour.redComponent, expected.redComponent, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(colour.greenComponent, expected.greenComponent, accuracy: 0.02, file: file, line: line)
        XCTAssertEqual(colour.blueComponent, expected.blueComponent, accuracy: 0.02, file: file, line: line)
    }

    private struct Storage {
        let root: URL
        var support: URL { root.appendingPathComponent("Application Support") }
        var caches: URL { root.appendingPathComponent("Caches") }

        init() throws {
            root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        }

        func icons() -> SiteIcons { SiteIcons(applicationSupport: support, caches: caches) }

        func file(_ key: String, root: URL? = nil, former: Bool = false) -> URL {
            (root ?? support).appendingPathComponent("Safience/" + (former ? "SiteIcons" : "Icons") + "/" + key + ".png")
        }

        func write(_ data: Data, key: String, root: URL, former: Bool = false) throws {
            let file = file(key, root: root, former: former)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
