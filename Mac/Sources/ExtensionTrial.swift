import AppKit
import WebKit

/// An extension started on its own, before it is given a place: in a
/// controller that keeps nothing (non-persistent), with nothing granted,
/// no tab, no window and no answer to anything it asks of the app, so
/// nothing it does lands in a space. What an update is tried in before it
/// takes the old version's place (Docs/ExtensionsDesign.md, sections 3 and 4).
@MainActor
enum ExtensionTrial {
    struct Failed: LocalizedError {
        let why: String
        var errorDescription: String? { why }
    }

    /// Loads it and starts its background; throws if WebKit refuses it or
    /// says its background failed to load. A background that doesn't answer
    /// within eight seconds isn't taken for a failure: WebKit doesn't always
    /// call back, and only its error says it failed.
    static func start(_ package: WKWebExtension, id: String) async throws {
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        let context = WKWebExtensionContext(for: package)
        context.uniqueIdentifier = id
        context.baseURL = URL(string: "\(Extensions.scheme)://\(id)/")!
        try controller.load(context)
        defer { try? controller.unload(context) }
        guard package.hasBackgroundContent else { return }
        let error: Error? = await withCheckedContinuation { done in
            var finished = false
            let finish: (Error?) -> Void = { result in
                guard !finished else { return }
                finished = true
                done.resume(returning: result)
            }
            context.loadBackgroundContent { error in MainActor.assumeIsolated { finish(error) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(nil) }
        }
        let failed = context.errors.contains {
            let error = $0 as NSError
            return error.domain == WKWebExtensionContext.errorDomain
                && error.code == WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue
        }
        if let error { throw error }
        if failed { throw Failed(why: "Its background failed to start.") }
    }
}
