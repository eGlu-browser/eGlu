import AppKit

/// eGlu's tile in the Dock while eGlu isn't open: the icon chosen in Settings
/// › General › App Icon, which the app draws there itself while it is open
/// (Mac/Sources/DockIcon.swift). macOS loads this plug-in, named in the app's
/// Info.plist (NSDockTilePlugIn), into a process of the Dock's own while eGlu
/// is kept in the Dock. It reads the choice from eGlu's preferences, hears it
/// change from the app, and draws nothing over eGlu's own icon.
@objc(EgluDockTile)
final class EgluDockTile: NSObject, NSDockTilePlugIn {
    private var tile: NSDockTile?
    private var changes: NSObjectProtocol?
    private var appearance: NSKeyValueObservation?

    /// eGlu.app, which has this plug-in in its Contents/PlugIns, and its
    /// identifier, which names its preferences: whichever copy of eGlu this is.
    private let app: Bundle? = Bundle(url: Bundle(for: EgluDockTile.self).bundleURL
        .deletingLastPathComponent()    // PlugIns
        .deletingLastPathComponent()    // Contents
        .deletingLastPathComponent())   // eGlu.app

    func setDockTile(_ dockTile: NSDockTile?) {
        if let changes { DistributedNotificationCenter.default().removeObserver(changes) }
        changes = nil
        appearance = nil
        tile = dockTile
        // Nil when eGlu is taken out of the Dock: nothing more to draw.
        guard dockTile != nil, let id = app?.bundleIdentifier else { return }
        changes = DistributedNotificationCenter.default().addObserver(forName: DockIconKeys.changed, object: id,
                                                                      queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.draw() }
        }
        appearance = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            // Changes of appearance come on the main thread.
            MainActor.assumeIsolated { self?.draw() }
        }
        MainActor.assumeIsolated { draw() }
    }

    @MainActor private func draw() {
        guard let tile, let app, let id = app.bundleIdentifier else { return }
        // Read again from the file: the app has just changed it.
        CFPreferencesAppSynchronize(id as CFString)
        let name = CFPreferencesCopyAppValue(DockIconKeys.choice as CFString, id as CFString) as? String
        if let name, let picture = app.image(forResource: DockIconKeys.picture(name)) {
            tile.contentView = Picture(picture, frame: NSRect(origin: .zero, size: tile.size))
        } else {
            // eGlu's own, as the Dock draws it.
            tile.contentView = nil
        }
        tile.display()
    }
}

/// The picture, light or dark as the Dock is: the tile is drawn once, so the
/// appearance it is drawn in is said, not left to the view.
private final class Picture: NSView {
    private let picture: NSImage

    init(_ picture: NSImage, frame: NSRect) {
        self.picture = picture
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSApplication.shared.effectiveAppearance.performAsCurrentDrawingAppearance {
            picture.draw(in: bounds)
        }
    }
}
