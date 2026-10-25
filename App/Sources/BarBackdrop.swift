import PadCore
import UIKit

/// What lies behind the phone bar, from its top to the window's foot: the
/// colour of the page's last points (`tint`), so the bar reads as the page's
/// foot going on under it. The page itself stops at the bar (Browser.layoutPanes),
/// so nothing of it is ever hidden here. Light or dark as the bar's ink is
/// (Browser.applySiteColor); with no page to go by (the start page), and
/// under Increase Contrast, the app's own ground.
final class BarBackdrop: UIView {
    /// The colour of the page's foot, or nil for the app's ground.
    var tint: UIColor? {
        didSet {
            guard tint != oldValue else { return }
            // Eased within one side, light or dark. Across it the bar's ink
            // flips in one frame (Browser.applySiteColor), and the ground
            // goes with it: light ink on a ground still light for a
            // quarter-second didn't read.
            refresh(animated: Self.isDark(tint) == Self.isDark(oldValue))
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: BarBackdrop, _) in
            self.refresh(animated: false)
        }
        refresh(animated: false)
    }

    required init?(coder: NSCoder) { nil }

    /// The side SiteColor.isDark puts the colour on, the one the ink follows.
    private static func isDark(_ colour: UIColor?) -> Bool {
        colour.flatMap { SiteColor($0) }?.isDark ?? false
    }

    private func refresh(animated: Bool) {
        let own = traitCollection.accessibilityContrast == .high ? nil : tint
        let ground = own ?? Palette.UI.ground.resolvedColor(with: traitCollection)
        guard animated, window != nil else {
            backgroundColor = ground
            return
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.backgroundColor = ground
        }
    }
}
