import Foundation

/// The app's icon, as Settings › App icon offers it on the iPhone, the iPad
/// and the Mac, in the order it shows them: eGlu's own (Shared/eGlu.icon),
/// or one of the others, each the globe and pointer drawn in a style of its
/// own (an Icon Composer file in App/ named as the icon is).
///
/// A chosen icon is kept by that name: the iPhone and iPad by the name it is
/// compiled under (project.yml's ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES),
/// the Mac in its preferences (Mac/Sources/DockIcon.swift). Renaming one
/// drops it for whoever had chosen it, as Diazo, Lilac, Oxide, Citrus and
/// Midnight were dropped when they became Designer, Vista, Hardcover, Punk and
/// Astro. Globe was the app's own icon up to 1.0.7: whoever had it then has
/// eGlu now, and picks Globe to keep it.
public enum AppIcon: String, CaseIterable, Identifiable, Sendable {
    case eGlu
    case globe = "Globe"
    case designer = "Designer"
    case engineer = "Engineer"
    case signal = "Signal"
    case vista = "Vista"
    case hardcover = "Hardcover"
    case punk = "Punk"
    case astro = "Astro"

    public var id: String { rawValue }

    /// The name the icon is kept by; nil for the app's own, which is kept by none.
    public var alternateName: String? {
        self == .eGlu ? nil : rawValue
    }

    /// The icon kept by that name: the app's own for none, and nil for a
    /// name no icon has now.
    public init?(alternateName: String?) {
        guard let alternateName else {
            self = .eGlu
            return
        }
        guard let icon = AppIcon(rawValue: alternateName), icon != .eGlu else { return nil }
        self = icon
    }

    /// Its name under its picture. eGlu is the app's name in every language.
    public var title: String {
        switch self {
        case .eGlu: return "eGlu"
        case .globe: return BrowserText.localized("Globe")
        case .designer: return BrowserText.localized("Designer")
        case .engineer: return BrowserText.localized("Engineer")
        case .signal: return BrowserText.localized("Signal")
        case .vista: return BrowserText.localized("Vista")
        case .hardcover: return BrowserText.localized("Hardcover")
        case .punk: return BrowserText.localized("Punk")
        case .astro: return BrowserText.localized("Astro")
        }
    }
}
