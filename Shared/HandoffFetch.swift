import Foundation
import WebKit

/// A file fetched for a handoff through the tab's own web view, so the
/// space's sign-ins come with it: named into the job's folder by a
/// delegate of Handoff's own, and never in the Downloads list. Thirty
/// seconds at the most; a file on the device is copied, with the
/// security scope it is kept under where it was opened from Finder.
enum HandoffFetch {

    /// The file's place once fetched, or a thrown reason.
    @MainActor
    static func fetch(_ url: URL, with view: WKWebView, into folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if url.isFileURL {
            #if os(macOS)
            FileAccess.open(url)
            #endif
            let to = folder.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: to)
            try FileManager.default.copyItem(at: url, to: to)
            return to
        }
        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { @MainActor in try await Self.download(url, with: view, into: folder) }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.limit))
                throw FetchError.timedOut
            }
            let first = try await group.next() ?? { throw FetchError.timedOut }()
            group.cancelAll()
            return first
        }
    }

    /// A fetch's seconds at the most.
    static let limit: TimeInterval = 30

    /// The download itself, named as the site suggests into the folder.
    @MainActor
    private static func download(_ url: URL, with view: WKWebView, into folder: URL) async throws -> URL {
        guard #available(iOS 18.4, macOS 15.4, *) else { throw FetchError.timedOut }
        let download = try await view.startDownload(using: URLRequest(url: url))
        return try await withCheckedThrowingContinuation { done in
            download.delegate = Fetch(folder: folder) { done.resume(with: $0) }
        }
    }

    /// Why a fetch ended without a file.
    private enum FetchError: Error {
        case timedOut
    }

    /// The delegate of Handoff's own: it names the file in the job's
    /// folder and answers once, on finish or fail. Held until then.
    private final class Fetch: NSObject, WKDownloadDelegate {
        private let folder: URL
        private let told: (Result<URL, Error>) -> Void
        private var held: Fetch?
        private var place: URL?

        init(folder: URL, told: @escaping (Result<URL, Error>) -> Void) {
            self.folder = folder
            self.told = told
            super.init()
            held = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
            let to = folder.appendingPathComponent(suggestedFilename)
            place = to
            completionHandler(to)
        }

        func downloadDidFinish(_ download: WKDownload) {
            if let place { told(.success(place)) } else { told(.failure(FetchError.timedOut)) }
            held = nil
        }

        func download(_ download: WKDownload, didFailWithError error: Error) {
            told(.failure(error))
            held = nil
        }
    }
}
