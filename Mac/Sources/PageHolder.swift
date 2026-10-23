import AppKit

final class PageHolder: NSView {
    private weak var shown: NSView?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Metrics.card
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ view: NSView?) {
        if let view, view === shown, view.superview === self { needsLayout = true; return }
        // Only if it is still here: another window may have taken it already.
        if let shown, shown.superview === self { shown.removeFromSuperview() }
        shown = view
        guard let view else { return }
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // SwiftUI can update the holder's bounds without reattaching its page.
        // Always give WebKit the actual card viewport, including sidebar changes.
        if let shown, shown.superview === self, shown.frame != bounds { shown.frame = bounds }
    }
}
