import Foundation
import WebKit
import Darwin

// The driver appends the actual PageHistory and both native learnAbout
// bodies. Only WebKit completion timing and local collaborators are synthetic.
enum HistoryKind: Equatable { case link, other }
enum History {
    static func pageKey(_ url: URL) -> String { url.absoluteString }
}
enum HandsOff {
    static func covers(_ url: URL) -> Bool { url.host == "accounts.google.com" }
}
@MainActor
final class Session {
    static let shared = Session()
    let workspace = FixtureWorkspace()
}
struct FixtureWorkspace {
    func tab(_ id: UUID) -> UUID? { id }
}
@MainActor
final class HistoryRecorder {
    struct Metadata { let title: String?; let summary: String? }
    static let shared = HistoryRecorder()
    var metadata: [Metadata] = []
    func isExpected(_ url: URL) -> Bool { false }
    func takeExpectation(_ url: URL) -> HistoryKind? { nil }
    func visit(space: UUID, url: URL, title: String?, kind: HistoryKind) -> UUID { UUID() }
    func forget(_ visit: UUID) {}
    func page(space: UUID, url: URL, title: String?, summary: String?) {
        metadata.append(Metadata(title: title, summary: summary))
    }
}
@MainActor
final class FixtureView {
    var url: URL? = URL(string: "https://notes.example/same")!
    var pending: [(Result<Any, Error>) -> Void] = []
    func callAsyncJavaScript(_ body: String, arguments: [String: Any], in frame: WKFrameInfo?, in world: WKContentWorld,
                             completionHandler: @escaping (Result<Any, Error>) -> Void) {
        pending.append(completionHandler)
    }
    func resolve(_ result: Result<Any, Error>) { pending.removeFirst()(result) }
}
@MainActor
final class FixturePage {
    static let world = WKContentWorld.world(name: "eGluHistoryDescriptionQA")
    let space = UUID()
    let tab = UUID()
    let view = FixtureView()
    var history = PageHistory()
    var committedProtected = false
    var isHandsOff: Bool { committedProtected || (view.url.map(HandsOff.covers) ?? false) }
    func enter() {
        history.decided(.linkActivated, url: view.url)
        history.committed(url: view.url, title: "Initial", entry: nil, space: space, tab: tab)
    }
}
typealias Page = FixturePage

@main
struct HistoryDescriptionAcceptance {
    @MainActor static func main() {
        var failures = 0
        var count = 0
        for (platform, read) in [("Mac", { (page: FixturePage) in page.learnAboutMac() }),
                                 ("iOS", { (page: FixturePage) in page.learnAboutApp() })] {
            func check(_ name: String, _ test: () -> Bool) {
                count += 1
                let passed = test()
                if !passed { failures += 1 }
                print("\(passed ? "PASS" : "FAIL") \(platform) \(name)")
            }
            func page() -> FixturePage {
                HistoryRecorder.shared.metadata = []
                let page = FixturePage()
                page.enter()
                return page
            }
            check("current visit accepts its description") {
                let page = page()
                read(page)
                guard page.view.pending.count == 1 else { return false }
                page.view.resolve(.success("A description"))
                return HistoryRecorder.shared.metadata.count == 1 && HistoryRecorder.shared.metadata.first?.summary == "A description"
            }
            check("same-URL new visit rejects the previous document result") {
                let page = page()
                read(page)
                page.enter()
                page.view.resolve(.success("Old document description"))
                return HistoryRecorder.shared.metadata.isEmpty
            }
            check("a changed URL rejects delayed work") {
                let page = page()
                read(page)
                page.view.url = URL(string: "https://notes.example/another")
                page.view.resolve(.success("Previous address"))
                return HistoryRecorder.shared.metadata.isEmpty
            }
            check("a discovered sign-in form rejects pending metadata") {
                let page = page()
                read(page)
                page.history.signInFound()
                page.view.resolve(.success("Sign-in description"))
                return HistoryRecorder.shared.metadata.isEmpty
            }
            check("protected hosts start no metadata read") {
                let page = page()
                page.view.url = URL(string: "https://accounts.google.com/same")
                page.enter()
                read(page)
                return page.view.pending.isEmpty && HistoryRecorder.shared.metadata.isEmpty
            }
            check("a retained protected document starts no metadata read") {
                let page = page()
                page.committedProtected = true
                read(page)
                return page.view.pending.isEmpty && HistoryRecorder.shared.metadata.isEmpty
            }
            check("a newly protected committed document rejects pending metadata") {
                let page = page()
                read(page)
                page.committedProtected = true
                page.view.resolve(.success("Protected document description"))
                return HistoryRecorder.shared.metadata.isEmpty
            }
            check("an unrecorded document starts no metadata read") {
                let page = page()
                page.history = PageHistory()
                read(page)
                return page.view.pending.isEmpty && HistoryRecorder.shared.metadata.isEmpty
            }
            check("a WebKit error adds no description") {
                let page = page()
                read(page)
                page.view.resolve(.failure(NSError(domain: "Fixture", code: 1)))
                return HistoryRecorder.shared.metadata.isEmpty
            }
            check("an empty description adds no metadata") {
                let page = page()
                read(page)
                page.view.resolve(.success(""))
                return HistoryRecorder.shared.metadata.isEmpty
            }
        }
        print("History description origins: \(count - failures)/\(count) native checks passed")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }
}
