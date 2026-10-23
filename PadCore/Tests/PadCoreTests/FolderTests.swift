import XCTest
@testable import PadCore

/// Bookmark folders: made, renamed, and bookmarks moved in and out of them.
final class FolderTests: XCTestCase {
    private func url(_ text: String) throws -> URL {
        try XCTUnwrap(URL(string: text))
    }

    func testAFolderHoldsBookmarksMovedIntoIt() throws {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        let linear = try XCTUnwrap(w.addBookmark(try url("https://linear.app/"), title: "Linear", in: work))
        let design = try XCTUnwrap(w.addFolder(named: "Design", in: nil, of: work))
        w.moveBookmark(linear, into: design, in: work)
        XCTAssertEqual(w.space(work)?.bookmarks.map(\.id), [design], "the link left the top level")
        XCTAssertEqual(Bookmarks.find(design, in: w.space(work)?.bookmarks ?? [])?.children?.map(\.id), [linear])
        XCTAssertEqual(w.bookmark(for: try url("https://linear.app"), in: work)?.id, linear, "still the same bookmark, at depth")
        w.moveBookmark(linear, into: nil, in: work)
        XCTAssertEqual(w.space(work)?.bookmarks.map(\.id), [design, linear], "back at the top level, at the end")
        w.removeBookmark(design, in: work)
        XCTAssertEqual(w.space(work)?.bookmarks.map(\.id), [linear])
    }

    func testAFolderNeverGoesIntoItselfOrItsOwn() throws {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        let outer = try XCTUnwrap(w.addFolder(named: "Outer", in: nil, of: work))
        let inner = try XCTUnwrap(w.addFolder(named: "Inner", in: outer, of: work))
        XCTAssertEqual(Bookmarks.find(outer, in: w.space(work)?.bookmarks ?? [])?.children?.map(\.id), [inner])
        let before = w
        w.moveBookmark(outer, into: outer, in: work)
        w.moveBookmark(outer, into: inner, in: work)
        XCTAssertEqual(w, before, "a folder inside itself would be lost")
        let link = try XCTUnwrap(w.addBookmark(try url("https://a.test/"), title: "A", in: work))
        w.moveBookmark(inner, into: link, in: work)
        XCTAssertEqual(Bookmarks.find(outer, in: w.space(work)?.bookmarks ?? [])?.children?.map(\.id), [inner],
                       "a link is not a folder to move into")
    }

    func testNothingIsPutIntoALink() throws {
        let link = Bookmark(title: "A", url: try url("https://a.test/"))
        var items = [link]
        XCTAssertFalse(Bookmarks.insert(Bookmark(title: "B", url: try url("https://b.test/")), into: link.id, of: &items))
        XCTAssertEqual(items, [link], "a link is left as it was")
        XCTAssertFalse(Bookmarks.insert(link, into: UUID(), of: &items), "no such folder")
        XCTAssertEqual(items, [link])
    }

    func testNamesAreTrimmedAndNeverEmpty() throws {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        let folder = try XCTUnwrap(w.addFolder(named: "  ", in: nil, of: work))
        XCTAssertEqual(Bookmarks.find(folder, in: w.space(work)?.bookmarks ?? [])?.title, "New Folder")
        w.renameBookmark(folder, to: " Reading ", in: work)
        XCTAssertEqual(Bookmarks.find(folder, in: w.space(work)?.bookmarks ?? [])?.title, "Reading")
        w.renameBookmark(folder, to: "", in: work)
        XCTAssertEqual(Bookmarks.find(folder, in: w.space(work)?.bookmarks ?? [])?.title, "Reading", "an empty name changes nothing")
        XCTAssertNil(w.addFolder(named: "Lost", in: UUID(), of: work), "no such parent")
    }

    func testTheOpenedFoldersEndWhereOneHasGone() throws {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        let outer = try XCTUnwrap(w.addFolder(named: "Outer", in: nil, of: work))
        let inner = try XCTUnwrap(w.addFolder(named: "Inner", in: outer, of: work))
        let bookmarks = { w.space(work)?.bookmarks ?? [] }
        XCTAssertEqual(Bookmarks.folders(along: [outer, inner], in: bookmarks()).map(\.id), [outer, inner])
        XCTAssertEqual(Bookmarks.folders(along: [inner], in: bookmarks()).map(\.id), [], "not at the top level")
        w.removeBookmark(inner, in: work)
        XCTAssertEqual(Bookmarks.folders(along: [outer, inner], in: bookmarks()).map(\.id), [outer], "gone: the path ends")
    }

    func testASidebarListsWhatAnOpenFolderHoldsAStepIn() throws {
        var w = Workspace.onFigma()
        let work = w.spaces[0].id
        let design = try XCTUnwrap(w.addFolder(named: "Design", in: nil, of: work))
        let linear = try XCTUnwrap(w.addBookmark(try url("https://linear.app/"), title: "Linear", in: work))
        w.moveBookmark(linear, into: design, in: work)
        let figma = try XCTUnwrap(w.addBookmark(try url("https://figma.com/"), title: "Figma", in: work))
        let bookmarks = w.space(work)?.bookmarks ?? []
        XCTAssertEqual(Bookmarks.rows(of: bookmarks, opening: []).map(\.item.id), [design, figma], "a folder closed: its own row only")
        let open = Bookmarks.rows(of: bookmarks, opening: [design])
        XCTAssertEqual(open.map(\.item.id), [design, linear, figma])
        XCTAssertEqual(open.map(\.depth), [0, 1, 0])
    }
}
