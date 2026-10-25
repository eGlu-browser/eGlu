import AppKit

/// The underlines over another app's field: one borderless panel per
/// screen, never taking focus or clicks, drawing each lint's rectangles
/// in its kind's colour (Docs/Tasks/03, Decided 9, 10).
///
/// Rectangles arrive in Accessibility's top-left-origin coordinates and
/// are drawn in AppKit's; the panel frames cover each screen whole so any
/// rect lands.
@MainActor
final class Underlines {
    static let shared = Underlines()

    /// One lint: its rectangles (top-left origin) and colour.
    struct Marks {
        var rects: [CGRect]
        var color: NSColor
    }

    private var panels: [ObjectIdentifier: Panel] = [:]
    private var marks: [Marks] = []
    private var screenObserver: NSObjectProtocol?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        }
    }

    /// Draw these marks; an empty list clears the screens.
    func show(_ marks: [Marks]) {
        self.marks = marks
        guard !marks.isEmpty else { clear(); return }
        for screen in NSScreen.screens {
            let panel = self.panel(for: screen)
            panel.view.marks = marks
            panel.orderFrontRegardless()
        }
    }

    func clear() {
        marks = []
        for panel in panels.values { panel.orderOut(nil) }
    }

    private func screensChanged() {
        // A screen going away keeps its panel: it may come back.
        for (id, panel) in panels where !NSScreen.screens.contains(where: { ObjectIdentifier($0) == id }) {
            panel.orderOut(nil)
        }
        if !marks.isEmpty { show(marks) }
    }

    private func panel(for screen: NSScreen) -> Panel {
        if let panel = panels[ObjectIdentifier(screen)] { return panel }
        let panel = Panel(contentRect: screen.frame,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panels[ObjectIdentifier(screen)] = panel
        return panel
    }

    /// The borderless window the marks are drawn in: see-through, above
    /// everything but the pointer, and deaf to the mouse.
    private final class Panel: NSPanel {
        let view = MarkView()

        override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                      backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
            super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            ignoresMouseEvents = true
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                  .stationary, .ignoresCycle]
            hidesOnDeactivate = false
            isReleasedWhenClosed = false
            view.frame = contentRect.size.asRect
            view.wantsLayer = true
            contentView = view
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// The view drawing the marks: a light fill over each rect and the
    /// underline itself under it, in the lint kind's colour.
    private final class MarkView: NSView {
        var marks: [Marks] = [] { didSet { needsDisplay = true } }

        override var isFlipped: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            guard let screen = window?.screen else { return }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            for mark in marks {
                mark.color.withAlphaComponent(0.1).setFill()
                mark.color.setStroke()
                for rect in mark.rects {
                    // Top-left-origin global → AppKit global → this panel.
                    let appKitY = primaryHeight - rect.maxY
                    let local = CGRect(
                        x: rect.minX - screen.frame.minX,
                        y: appKitY - screen.frame.minY,
                        width: rect.width, height: rect.height)
                    NSBezierPath(rect: local).fill()
                    let line = NSBezierPath()
                    line.lineWidth = 2
                    line.move(to: CGPoint(x: local.minX, y: local.minY + 1))
                    line.line(to: CGPoint(x: local.maxX, y: local.minY + 1))
                    line.stroke()
                }
            }
        }
    }
}

private extension CGSize {
    var asRect: CGRect { CGRect(origin: .zero, size: self) }
}
