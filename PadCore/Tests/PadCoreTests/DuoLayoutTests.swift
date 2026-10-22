import Foundation
import Testing
@testable import PadCore

/// The sidebar against the iPhone Duo's fold (Docs/iPhoneDuoDesign.md §5).
struct DuoLayoutTests {
    /// A 932-point-wide window folded like a book: a 20-point fold, margins
    /// included, down its middle.
    private let book = CGRect(x: 456, y: 0, width: 20, height: 678)

    private func sidebar(start: CGFloat = 0, fold: CGRect?, rightToLeft: Bool = false) -> DuoLayout.Sidebar {
        DuoLayout.sidebar(start: start, fold: fold, rightToLeft: rightToLeft, standard: 248, minimum: 200, gap: 8)
    }

    @Test func `folded like a book, the sidebar reaches the fold and the page starts past it`() {
        #expect(sidebar(fold: book) == DuoLayout.Sidebar(width: 456, gap: 20))
    }

    @Test func `from where the sidebar starts, not the window's edge`() {
        #expect(sidebar(start: 12, fold: book).width == 444)
    }

    @Test func `right to left, the sidebar fills the right half`() {
        #expect(sidebar(start: 932, fold: book, rightToLeft: true) == DuoLayout.Sidebar(width: 456, gap: 20))
    }

    @Test(arguments: [
        nil,
        // Like a laptop: the fold runs across.
        CGRect(x: 0, y: 330, width: 932, height: 20),
        // Nearer the edge than a sidebar can be narrow.
        CGRect(x: 150, y: 0, width: 20, height: 678),
        // Behind where the sidebar starts.
        CGRect(x: 0, y: 0, width: 20, height: 678),
    ] as [CGRect?])
    func `otherwise the sidebar is its own width`(fold: CGRect?) {
        #expect(sidebar(fold: fold) == DuoLayout.Sidebar(width: 248, gap: 8))
    }
}
