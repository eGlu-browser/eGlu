import Foundation

/// What eGlu and its Dock tile plug-in agree on (DockIcon.swift and
/// Mac/DockTile): this file is in both.
enum DockIconKeys {
    /// The chosen icon's name in the app's preferences (AppIcon.alternateName,
    /// PadCore), there only while one other than eGlu's own is chosen.
    static let choice = "appIcon"

    /// Posted by the app when the choice changes, with its bundle identifier
    /// as the object: the plug-in of another copy of eGlu, built with another
    /// identifier, doesn't take it.
    static let changed = Notification.Name("net.taehee.safience.appIconChanged")

    /// The icon's picture in the app's asset catalog, light and dark
    /// (Mac/Assets.xcassets/AppIcons, drawn by Marketing/Brand/mac-icons.swift).
    static func picture(_ name: String) -> String {
        "AppIcon-\(name)"
    }
}
