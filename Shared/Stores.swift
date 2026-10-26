import ImageIO
import PadCore
import WebKit
#if canImport(UIKit)
import UIKit
#endif

/// Each space's cookies, sign-ins and site data, in a WebKit store of its own.
///
/// Made with `WKWebsiteDataStore(forIdentifier:)` and the space's id, so a
/// space's sign-ins survive relaunches and never mix with another space's:
/// two Figma accounts, one per space, both signed in. One object per space
/// for as long as the app runs, because WebKit shares processes and caches
/// between views that are given the same store object.
@MainActor
enum Stores {
    private static var made: [UUID: WKWebsiteDataStore] = [:]
    private static let erasingKey = "stores.erasing"

    static func store(for space: UUID) -> WKWebsiteDataStore {
        if let store = made[space] { return store }
        let store = WKWebsiteDataStore(forIdentifier: space)
        made[space] = store
        return store
    }

    /// A removed space's store, and everything in it, gone. What it holds is
    /// emptied at once; the store itself WebKit won't remove while a view
    /// still holds it, so it is written down and tried again at each launch
    /// until it goes.
    static func erase(_ space: UUID) {
        if let store = made.removeValue(forKey: space) {
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        }
        var pending = Set(UserDefaults.standard.stringArray(forKey: erasingKey) ?? [])
        pending.insert(space.uuidString)
        UserDefaults.standard.set(pending.sorted(), forKey: erasingKey)
        // A moment later, once the space's views have let go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { sweep() }
    }

    /// Removes the stores written down for removal. At launch, before any
    /// view holds one, and after an erase.
    ///
    /// WebKit is set up first, by making a store of its own that keeps
    /// nothing: `remove(forIdentifier:)` doesn't do that itself, and called
    /// before anything else of WebKit's at launch, it answered on a run loop
    /// WebKit hadn't made yet and stopped the app, at every launch while the
    /// removal stayed written down (iOS 27.1).
    static func sweep() {
        let pending = UserDefaults.standard.stringArray(forKey: erasingKey) ?? []
        guard !pending.isEmpty else { return }
        _ = WKWebsiteDataStore.nonPersistent()
        for text in pending {
            guard let id = UUID(uuidString: text), made[id] == nil else { continue }
            WKWebsiteDataStore.remove(forIdentifier: id) { error in
                guard error == nil else { return }
                Task { @MainActor in
                    let left = (UserDefaults.standard.stringArray(forKey: erasingKey) ?? []).filter { $0 != text }
                    UserDefaults.standard.set(left, forKey: erasingKey)
                }
            }
        }
    }
}

/// Pictures of frozen tabs, and what it takes to bring their page back where
/// it was (`WKWebView.interactionState`: the back and forward list and the
/// scroll position). Kept in Caches: the system may empty it, and then a
/// tab comes back without its picture, at its address. Files only, read and
/// written on its own queue: no actor's.
nonisolated enum Snapshots {
    static var folder: URL {
        var caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #if os(macOS)
        // Outside the sandbox the Mac's Caches folder is every app's:
        // eGlu's go in a folder of its own.
        caches.appendPathComponent(Bundle.main.bundleIdentifier ?? "Safience", isDirectory: true)
        #endif
        return caches.appendingPathComponent("Snapshots", isDirectory: true)
    }

    private static let files = PageSnapshotFiles(folder: folder)
    private static let pictures = DispatchQueue(label: "SnapshotPictures", qos: .utility)

    static func token(for tab: UUID, in space: UUID) -> PageSnapshotFiles.Token {
        files.token(for: tab, in: space)
    }

    static func isCurrent(_ token: PageSnapshotFiles.Token) -> Bool { files.isCurrent(token) }

    #if canImport(UIKit)
    static func save(_ picture: UIImage, url: URL?, using token: PageSnapshotFiles.Token) {
        pictures.async {
            guard files.isCurrent(token), let data = picture.jpegData(compressionQuality: 0.7) else { return }
            files.save(data, kind: .picture, url: url, using: token)
        }
    }

    static func picture(url: URL?, using token: PageSnapshotFiles.Token) -> UIImage? {
        files.data(kind: .picture, url: url, using: token).flatMap(UIImage.init(data:))
    }

    static func picture(url: URL?, using token: PageSnapshotFiles.Token,
                        _ done: @escaping @MainActor @Sendable (UIImage?) -> Void) {
        pictures.async {
            let image = picture(url: url, using: token)?.preparingForDisplay()
            DispatchQueue.main.async { done(files.isCurrent(token) ? image : nil) }
        }
    }

    static func thumbnail(url: URL?, using token: PageSnapshotFiles.Token, pixels: Int,
                          _ done: @escaping @MainActor @Sendable (UIImage?) -> Void) {
        pictures.async {
            var image: UIImage?
            if let data = files.data(kind: .picture, url: url, using: token),
               let source = CGImageSourceCreateWithData(data as CFData, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                ]
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
            }
            let made = image
            DispatchQueue.main.async { done(files.isCurrent(token) ? made : nil) }
        }
    }
    #endif

    static func save(state: Any?, url: URL?, using token: PageSnapshotFiles.Token) {
        guard let data = state as? Data else { return }
        files.save(data, kind: .state, url: url, using: token)
    }

    static func takeState(url: URL?, using token: PageSnapshotFiles.Token) -> Data? {
        files.takeState(url: url, using: token)
    }

    static func remove(_ tab: UUID) { files.invalidate(tab) }
    static func prune(keeping tabs: Set<UUID>) { files.prune(keeping: tabs) }
}
