import Foundation
import WebKit

/// A file fetched for a handoff through the tab's own web view, so the
/// space's sign-ins come with it: named into the job's folder by a
/// delegate of Handoff's own, and never in the Downloads list. Thirty
/// seconds at the most; a file on the device is copied, with the
/// security scope it is kept under where it was opened from Finder.
enum HandoffFetch {

    /// The file's place once fetched, or a thrown reason. Called off with
    /// the handoff, or out of time, the download is cancelled and not
    /// waited for.
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
        let fetched = await HandoffTime.value(by: .now + limit) { @MainActor in
            try? await Self.download(url, with: view, into: folder)
        }
        guard let fetched else { throw FetchError.failed }
        return fetched
    }

    /// A fetch's time at the most.
    static let limit = Duration.seconds(30)

    /// The download itself, named as the site suggests into the folder.
    /// Called off, the download is cancelled, and its wait ends there
    /// whether or not WebKit says so after.
    @MainActor
    private static func download(_ url: URL, with view: WKWebView, into folder: URL) async throws -> URL {
        let download = await view.startDownload(using: URLRequest(url: url))
        let fetch = Fetch(folder: folder)
        download.delegate = fetch
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { done in
                fetch.wait(done)
            }
        } onCancel: {
            Task { @MainActor in
                fetch.answer(.failure(CancellationError()))
                // What it had fetched is not kept to resume from: the handoff is over.
                _ = await download.cancel()
            }
        }
    }

    /// Why a fetch ended without a file.
    private enum FetchError: Error {
        case failed
    }

    /// The delegate of Handoff's own: it names the file in the job's
    /// folder and answers once, on finish, fail or cancel. Held until then.
    private final class Fetch: NSObject, WKDownloadDelegate {
        private let folder: URL
        private var waiting: CheckedContinuation<URL, Error>?
        /// What it came to, where that came before anyone waited.
        private var answered: Result<URL, Error>?
        private var held: Fetch?
        private var place: URL?

        init(folder: URL) {
            self.folder = folder
            super.init()
            held = self
        }

        func wait(_ continuation: CheckedContinuation<URL, Error>) {
            if let answered { continuation.resume(with: answered) } else { waiting = continuation }
        }

        func answer(_ result: Result<URL, Error>) {
            guard answered == nil else { return }
            answered = result
            waiting?.resume(with: result)
            waiting = nil
            held = nil
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
            // WebKit writes only where no file is: a name the site gives twice, or a retry, gets one of its own.
            let to = Self.free(suggestedFilename, in: folder)
            place = to
            completionHandler(to)
        }

        func downloadDidFinish(_ download: WKDownload) {
            if let place { answer(.success(place)) } else { answer(.failure(FetchError.failed)) }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            answer(.failure(error))
        }

        /// The name in the folder, or with a number before its extension
        /// where a file has it: "image 2.jpg".
        private static func free(_ name: String, in folder: URL) -> URL {
            let given = (name as NSString).lastPathComponent
            let named = given.isEmpty ? "file" : given
            var to = folder.appendingPathComponent(named)
            let base = (named as NSString).deletingPathExtension
            let ext = (named as NSString).pathExtension
            var number = 2
            while FileManager.default.fileExists(atPath: to.path) {
                to = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
                number += 1
            }
            return to
        }
    }
}

/// Time kept for a handoff's slow work, a file fetched or a page read by
/// Vision: what the work gives by a moment, or nil once the moment has
/// passed or the handoff is called off. Not a task group, which waits for
/// what it has called off to notice, and a download or Vision can take
/// long over that: the work is cancelled and left to wind down behind, as
/// HandoffJob leaves the model.
nonisolated enum HandoffTime {
    static func value<Value: Sendable>(by deadline: ContinuousClock.Instant,
                                       _ work: @escaping @Sendable () async -> Value?) async -> Value? {
        let answer = Answer<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { done in
                answer.wait(done)
                answer.keep(Task { answer.give(await work()) })
                answer.keep(Task {
                    try? await Task.sleep(until: deadline, clock: .continuous)
                    answer.give(nil)
                })
            }
        } onCancel: {
            answer.give(nil)
        }
    }

    /// The one answer a wait is given, whichever comes first: the work's,
    /// the time's or the call's off. The tasks that did not give it are
    /// cancelled. Under a lock: the three come from where they will.
    private final class Answer<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: CheckedContinuation<Value?, Never>?
        private var answered = false
        private var answer: Value?
        private var tasks: [Task<Void, Never>] = []

        func wait(_ continuation: CheckedContinuation<Value?, Never>) {
            lock.lock()
            guard !answered else {
                lock.unlock()
                continuation.resume(returning: answer)
                return
            }
            waiting = continuation
            lock.unlock()
        }

        func keep(_ task: Task<Void, Never>) {
            lock.lock()
            guard !answered else {
                lock.unlock()
                task.cancel()
                return
            }
            tasks.append(task)
            lock.unlock()
        }

        func give(_ value: Value?) {
            lock.lock()
            guard !answered else {
                lock.unlock()
                return
            }
            answered = true
            answer = value
            let waiting = self.waiting
            let tasks = self.tasks
            self.waiting = nil
            self.tasks = []
            lock.unlock()
            tasks.forEach { $0.cancel() }
            waiting?.resume(returning: value)
        }
    }
}
