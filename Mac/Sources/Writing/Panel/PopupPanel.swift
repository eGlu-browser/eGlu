// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.

import AppKit
import Engines
import SwiftUI

/// The window the panel lives in: floating, click-through where empty,
/// and never the key window — typing stays in the app being checked.
final class PopupPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The card's chrome: the system's glass material behind the content.
struct PopupChrome<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                NSGlassEffectViewRepresentable()
            }
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NSGlassEffectViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // NSGlassEffectView is the system chrome on macOS 26; a visual
        // effect view is the closest look where it is missing.
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let view = glassClass.init(frame: .zero)
            if view.responds(to: Selector(("setCornerRadius:"))) {
                view.setValue(16.0, forKey: "cornerRadius")
            }
            return view
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.state = .active
        material.blendingMode = .behindWindow
        return material
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The hosting view that accepts the click that brings the pointer in,
/// since the panel never becomes key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSImage {
    /// A filled rounded-rect image used as a mask for the glass chrome.
    static func roundedMask(size: CGSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: radius, yRadius: radius).fill()
        image.unlockFocus()
        return image
    }
}

/// eGlu's name for Harper Desktop's PopupController: the panel's owner,
/// showing one lint over another app's field (Docs/Tasks/03).
@MainActor
final class WritingPanel {
    static let shared = WritingPanel()

    private var panel: PopupPanel?
    private var hosting: FirstClickHostingView<PopupChrome<PopupView>>?
    private var actions: ((PopupAction, Int) -> Void)?
    private var observers: [NSObjectProtocol] = []
    /// The lint's screen rect, top-left origin, for the "pointer rests on
    /// the card" check.
    private(set) var anchor: CGRect = .zero
    private(set) var isVisible = false

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // A new app in front leaves the old lint behind: hide.
            Task { @MainActor in self?.hide() }
        })
    }

    /// Show the panel for `lint` over `word`'s rect on screen (top-left
    /// origin, as Accessibility gives it). `actions` hears what the person
    /// clicks.
    func show(lint: GrammarLint, word: String, at rect: CGRect,
              suggestions: [String], canAddToDictionary: Bool,
              actions: @escaping (PopupAction, Int) -> Void) {
        self.actions = actions
        self.anchor = rect

        let data = PopupData(
            id: "\(lint.rule)-\(lint.start)",
            kindName: lint.kind,
            kindColor: WritingColors.rgb(for: lint.kind),
            ruleName: lint.rule,
            message: lint.message,
            suggestions: suggestions,
            flaggedText: word,
            canAddToDictionary: canAddToDictionary,
            anchor: rect
        )

        let view = PopupView(data: data) { [weak self] action, index in
            self?.dispatch(action, index)
        }
        let hosting = FirstClickHostingView(rootView: PopupChrome { view })
        hosting.setFrameSize(hosting.fittingSize)
        self.hosting = hosting

        let panel = self.panel ?? PopupPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.panel = panel
        panel.contentView = hosting

        let size = hosting.fittingSize
        panel.setContentSize(size)
        let placed = PopupGeometry.place(anchor: rect, cardSize: size)
        panel.setFrameOrigin(PopupGeometry.appKitRect(for: placed).origin)

        panel.orderFrontRegardless()
        isVisible = true
        announce(lint: lint)
        Motion.reveal(hosting)
        // ⌃⌥G is a hot key only while a suggestion is up to take
        // (Docs/Tasks/03): the keys are the other app's otherwise.
        if !suggestions.isEmpty { AcceptKey.shared.enable() }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        actions = nil
        AcceptKey.shared.disable()
        panel?.orderOut(nil)
    }

    /// Whether the top-left-origin screen point rests on the card: the
    /// caret timer uses it to leave the panel up under the pointer.
    func contains(topLeftPoint: CGPoint) -> Bool {
        guard let panel, isVisible else { return false }
        let height = NSScreen.screens.first?.frame.height ?? 0
        let point = CGPoint(x: topLeftPoint.x, y: height - topLeftPoint.y)
        return panel.frame.contains(point)
    }

    private func dispatch(_ action: PopupAction, _ index: Int) {
        let handler = actions
        hide()
        handler?(action, index)
    }

    private func reposition() {
        guard isVisible else { return }
        let placed = PopupGeometry.place(anchor: anchor, cardSize: panel?.frame.size ?? .zero)
        panel?.setFrameOrigin(PopupGeometry.appKitRect(for: placed).origin)
    }

    /// VoiceOver hears what lint the panel is for when it opens.
    private func announce(lint: GrammarLint) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: "\(lint.kind): \(lint.message)"]
        )
    }
}

/// Small window moves, reduced when the person asks for less motion.
enum Motion {
    static func reveal(_ view: NSView) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        view.layer?.removeAllAnimations()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.94
        grow.toValue = 1.0
        grow.duration = 0.12
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.wantsLayer = true
        view.layer?.add(grow, forKey: "reveal")
    }
}
