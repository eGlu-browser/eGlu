import CoreGraphics
import Foundation

/// Document Picture-in-Picture, which Chrome has and WebKit doesn't: a site
/// asks for a small window that stays above every other, with a blank page
/// of its own in it, and moves part of itself there. Google Meet's call
/// window is one (developer.chrome.com/docs/web-platform/document-picture-in-picture).
///
/// Safience for Mac gives the sites listed here `documentPictureInPicture`,
/// written in picture.js on `window.open`: the page opens a blank window at
/// `marker`, which is same-origin and in the page's own process, so the
/// page gets the real `Window` it expects and can move its elements into it.
/// The app sees the marker where the page opens that window and floats it
/// (Mac/Sources/PictureWindow.swift) instead of making a sign-in pop-up.
/// Only for the Mac: on iPad and iPhone the call apps have apps of their own.
public enum DocumentPicture {
    /// The sites given the API. A site that finds `documentPictureInPicture`
    /// may take other Chrome-only paths with it, so it is a list, not every site.
    public static let hosts = ["meet.google.com"]

    /// Whether the page at `url` is given the API: on a listed host, or one
    /// of `extra` (a test build's own page), and never a hands-off one.
    public static func covers(_ url: URL?, extra: [String] = []) -> Bool {
        guard let host = Hosts.host(of: url), !HandsOff.covers(url) else { return false }
        return (hosts + extra).contains { Hosts.host(host, isWithin: $0) }
    }

    /// The address picture.js opens its window at: a blank page, with what
    /// the site asked for after the mark.
    public static let marker = "safience-picture"

    /// What a site asked for in `requestWindow`, as picture.js writes it in the address it opens.
    public struct Request: Equatable, Sendable {
        /// The window may show Back to Tab (`disallowReturnToOpener` not set).
        public var returnsToOpener = true
        /// Where the window first opens, not where it was last (`preferInitialWindowPlacement`).
        public var initialPlacement = false

        public init(returnsToOpener: Bool = true, initialPlacement: Bool = false) {
            self.returnsToOpener = returnsToOpener
            self.initialPlacement = initialPlacement
        }

        /// The request in an address picture.js opened, or nil for any other address.
        /// Read from the address's text: an `about:` URL is not hierarchical, and
        /// the URL WebKit hands over (an NSURL's) gives no fragment for one.
        public init?(url: URL?) {
            guard let text = url?.absoluteString, let hash = text.firstIndex(of: "#"),
                  text[..<hash].lowercased() == "about:blank"
            else { return nil }
            let fragment = String(text[text.index(after: hash)...])
            let parts = (fragment.removingPercentEncoding ?? fragment).split(separator: "&").map(String.init)
            guard parts.first == DocumentPicture.marker else { return nil }
            returnsToOpener = !parts.contains("noreturn")
            initialPlacement = parts.contains("initial")
        }
    }

    /// The window's size when the site asks for none, as a video's.
    public static let standardSize = CGSize(width: 480, height: 270)
    /// No smaller than this, so the title bar's buttons and a face still fit.
    public static let smallest = CGSize(width: 240, height: 135)
    /// No more of the screen than this, in each direction.
    public static let largestShare: CGFloat = 0.8

    /// The size asked for, kept between the smallest and a share of the
    /// screen's room. Either side asked for alone, or nothing, is the standard size.
    public static func size(width: Double?, height: Double?, within room: CGSize) -> CGSize {
        var size = standardSize
        if let width, let height, width > 0, height > 0 { size = CGSize(width: width, height: height) }
        let widest = max(smallest.width, room.width * largestShare)
        let tallest = max(smallest.height, room.height * largestShare)
        return CGSize(width: min(max(size.width, smallest.width), widest).rounded(),
                      height: min(max(size.height, smallest.height), tallest).rounded())
    }

    /// Where a window of `size` first opens: the room's lower right corner, inset as Chrome's is.
    public static func origin(for size: CGSize, in room: CGRect, inset: CGFloat = 24) -> CGPoint {
        CGPoint(x: max(room.minX, room.maxX - size.width - inset), y: room.minY + inset)
    }
}
