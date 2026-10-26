import XCTest
@testable import PadCore

final class IconOpticsTests: XCTestCase {
    private let side = 64

    /// A square picture, opaque black where `drawn` says, clear elsewhere.
    private func picture(_ drawn: (Double, Double) -> Bool) -> [UInt8] {
        var bytes: [UInt8] = []
        for y in 0..<side {
            for x in 0..<side {
                // The pixel's middle, from -1 to 1 across the square.
                let u = (Double(x) + 0.5) / Double(side) * 2 - 1, v = (Double(y) + 0.5) / Double(side) * 2 - 1
                bytes += drawn(u, v) ? [0, 0, 0, 255] : [0, 0, 0, 0]
            }
        }
        return bytes
    }

    func testASquareIconIsDrawnAtItsSide() throws {
        let extent = try XCTUnwrap(IconOptics.extent(of: picture { _, _ in true }, side: side))
        XCTAssertEqual(extent.fill, 1, accuracy: 0.01)
        XCTAssertEqual(IconOptics.square(for: extent, side: 18), 18, accuracy: 0.01)
    }

    func testADiscIsDrawnAboutATenthLarger() throws {
        let extent = try XCTUnwrap(IconOptics.extent(of: picture { u, v in u * u + v * v <= 1 }, side: side))
        XCTAssertEqual(extent.fill, Double.pi / 4, accuracy: 0.03)
        XCTAssertEqual(IconOptics.square(for: extent, side: 18) / 18, 1.1, accuracy: 0.02)
    }

    func testARingIsAsLargeAsTheDiscRoundIt() throws {
        let ring = try XCTUnwrap(IconOptics.extent(of: picture { u, v in (0.8...1).contains(u * u + v * v) }, side: side))
        let disc = try XCTUnwrap(IconOptics.extent(of: picture { u, v in u * u + v * v <= 1 }, side: side))
        XCTAssertEqual(IconOptics.square(for: ring, side: 18), IconOptics.square(for: disc, side: 18), accuracy: 0.3)
    }

    func testAWideMarkIsWiderAndShorterWithinItsReach() throws {
        // Three times as wide as it is tall, in the middle of its square.
        let extent = try XCTUnwrap(IconOptics.extent(of: picture { _, v in abs(v) <= 1.0 / 3 }, side: side))
        XCTAssertEqual(extent.width / extent.height, 3, accuracy: 0.1)
        let square = IconOptics.square(for: extent, side: 18)
        XCTAssertEqual(square * extent.width, 18 * IconOptics.reach, accuracy: 0.01, "as wide as it may be")
        XCTAssertLessThan(square * extent.height, 18 * 0.6)
    }

    func testNothingDrawnHasNoExtent() {
        XCTAssertNil(IconOptics.extent(of: picture { _, _ in false }, side: side))
    }
}
