import AppKit
import SwiftUI

/// A symbol button as the Mac draws one in a sidebar: a plain button, with
/// nothing under it until the pointer is on it, then a rounded square that
/// darkens a step further while it is held. The sidebar keeps its glass for
/// what holds something (the address, the tiles, the tab on screen, the
/// spaces); its tools are plain.
struct PlainIcon: View {
    let symbol: String
    let help: String
    var enabled = true
    let action: () -> Void

    init(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(PlainIconStyle())
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// How a plain symbol button looks: its symbol in the label colour, dimmed
/// when it can't be pressed, on the highlight while the pointer is on it.
struct PlainIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlainIconBody(configuration: configuration)
    }
}

private struct PlainIconBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(enabled ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.45))
            .frame(width: Metrics.control, height: Metrics.control)
            .background(Highlight(hovering: hovering && enabled, pressed: configuration.isPressed && enabled,
                                  shape: RoundedRectangle(cornerRadius: 8, style: .continuous)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// What lies under a control the pointer is on, or one held down: a fill
/// in the control's own shape, coming and going quickly.
struct Highlight<S: Shape>: View {
    let hovering: Bool
    var pressed = false
    let shape: S

    var body: some View {
        shape
            .fill(pressed ? Palette.press : hovering ? Palette.hover : Color.clear)
            .animation(.hover, value: hovering)
            .animation(.hover, value: pressed)
    }
}

/// A row of a list in the sidebar or a popover: a plain button the width
/// of its list, highlighted under the pointer.
struct RowButtonStyle: ButtonStyle {
    var corner: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        RowButtonBody(configuration: configuration, corner: corner)
    }
}

private struct RowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let corner: CGFloat
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Highlight(hovering: hovering && enabled, pressed: configuration.isPressed && enabled,
                                  shape: RoundedRectangle(cornerRadius: corner, style: .continuous)))
            .onHover { hovering = $0 }
    }
}

/// A press that shows on what has no highlight of its own (a tile of
/// glass): it gives a little, to 0.96, and comes back with a spring.
struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}
