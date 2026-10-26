// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.

import AppKit
import SwiftUI

/// The panel's whole view: what a lint offers over another app's field.
struct PopupView: View {
    let data: PopupData
    /// The action and, for .applySuggestion, which suggestion's.
    let onAction: (PopupAction, Int) -> Void

    var body: some View {
        PopupCard(data: data, onAction: onAction)
            .frame(width: 320)
    }
}

/// The card's look, as the card over a page's own field has it
/// (writing.js): the lint's kind with its colour, its message, the
/// suggestions as pills (the first one dark, with the key that takes it),
/// and under a hairline what else can be done with the word.
struct PopupCard: View {
    let data: PopupData
    /// The action and, for .applySuggestion, which suggestion's.
    let onAction: (PopupAction, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Circle()
                    .fill(Color(nsColor: data.kindColor.color))
                    .frame(width: 8, height: 8)
                Text(data.kindName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    onAction(.close, 0)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(CardButtonStyle(shape: Circle(), size: CGSize(width: 22, height: 22)))
                .help(String(localized: "Close"))
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .padding(.top, 7)

            Text(markdownMessage)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            if !data.suggestions.isEmpty {
                PillFlow(spacing: 6) {
                    ForEach(Array(data.suggestions.prefix(5).enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            onAction(.applySuggestion, index)
                        } label: {
                            HStack(spacing: 6) {
                                Text(suggestion).lineLimit(1)
                                if index == 0 {
                                    Text(AcceptKey.symbols).opacity(0.65).fontWeight(.regular)
                                }
                            }
                            .font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                        }
                        .buttonStyle(PillStyle(first: index == 0))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            Divider()
                .padding(.top, 14)
            HStack(spacing: 0) {
                action(String(localized: "Ignore")) { onAction(.ignoreLint, 0) }
                if data.canAddToDictionary {
                    action(String(localized: "Add to Dictionary")) { onAction(.addToDictionary, 0) }
                }
                Spacer(minLength: 8)
                action(String(localized: "Turn Off This Rule")) { onAction(.disableRule, 0) }
            }
            .padding(7)
        }
    }

    private func action(_ title: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 12)).padding(.horizontal, 7)
        }
        .buttonStyle(CardButtonStyle(shape: Capsule(), size: nil))
    }

    private var markdownMessage: AttributedString {
        (try? AttributedString(markdown: data.message)) ?? AttributedString(data.message)
    }
}

/// A suggestion: a capsule, the first dark with light words, the rest a
/// faint fill; lit under the pointer, giving a little when pressed.
private struct PillStyle: ButtonStyle {
    let first: Bool

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, first: first)
    }
}

private struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let first: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(first ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .padding(.horizontal, 12)
            .frame(minWidth: 40, minHeight: 26)
            .background(Capsule().fill(first ? Color.primary.opacity(hovering ? 0.78 : 0.88)
                                             : Color.primary.opacity(hovering ? 0.12 : 0.07)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}

/// The close button and the actions at the foot: secondary words, lit
/// under the pointer in their own shape.
private struct CardButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    let size: CGSize?

    func makeBody(configuration: Configuration) -> some View {
        CardButtonBody(configuration: configuration, shape: shape, size: size)
    }
}

private struct CardButtonBody<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    let size: CGSize?
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .frame(width: size?.width, height: size?.height ?? 24)
            .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0)))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Pills in rows, as many to a row as fit, the next row under: the
/// suggestions, which are as wide as their words.
private struct PillFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
