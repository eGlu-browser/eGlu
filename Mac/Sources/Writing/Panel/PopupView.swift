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
            .frame(width: 260)
    }
}

/// The card's look, as the card over a page's own field has it with a
/// mouse (writing.js): a Mac menu, the lint's kind and message at its head
/// as a menu's title, its suggestions as rows (the first with the key that
/// takes it), and under a hairline what else can be done with the word,
/// each with its symbol. Every row's words start at one line, the symbols
/// and the kind's dot in a column before it. As a menu it has no close
/// button: the caret leaving the word closes it.
struct PopupCard: View {
    let data: PopupData
    /// The action and, for .applySuggestion, which suggestion's.
    let onAction: (PopupAction, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: MenuRowStyle.gap) {
                Circle()
                    .fill(Color(nsColor: data.kindColor.color))
                    .frame(width: 7, height: 7)
                    .frame(width: MenuRowStyle.column, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.kindName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(markdownMessage)
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, MenuRowStyle.padding)
            .padding(.top, 4)
            .padding(.bottom, 5)

            if !data.suggestions.isEmpty {
                separator
                ForEach(Array(data.suggestions.prefix(5).enumerated()), id: \.offset) { index, suggestion in
                    Button {
                        onAction(.applySuggestion, index)
                    } label: {
                        HStack(spacing: 12) {
                            Text(suggestion)
                                .fontWeight(index == 0 ? .semibold : .regular)
                                .lineLimit(1)
                            if index == 0 {
                                Spacer(minLength: 0)
                                Text(AcceptKey.symbols).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(MenuRowStyle(symbol: nil))
                }
            }

            separator
            action("eye.slash", String(localized: "Ignore")) { onAction(.ignoreLint, 0) }
            if data.canAddToDictionary {
                action("book.closed", String(localized: "Add to Dictionary")) { onAction(.addToDictionary, 0) }
            }
            action("nosign", String(localized: "Turn Off This Rule")) { onAction(.disableRule, 0) }
        }
        .padding(5)
        .accessibilityAction(named: Text("Close")) { onAction(.close, 0) }
    }

    private var separator: some View {
        Divider()
            .padding(.horizontal, MenuRowStyle.padding)
            .padding(.vertical, 4)
    }

    private func action(_ symbol: String, _ title: String, run: @escaping () -> Void) -> some View {
        Button(action: run) { Text(title) }
            .buttonStyle(MenuRowStyle(symbol: symbol))
    }

    /// The message, a quoted word in it heavier in the message's own type
    /// rather than a code font, as the page's card has it.
    private var markdownMessage: AttributedString {
        var text = (try? AttributedString(markdown: data.message)) ?? AttributedString(data.message)
        let quoted = text.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for range in quoted { text[range].inlinePresentationIntent = .stronglyEmphasized }
        return text
    }
}

/// A row of the card's, as a Mac menu draws one: its symbol (or room for
/// one) and its words, lit under the pointer and darker while pressed.
private struct MenuRowStyle: ButtonStyle {
    /// The column every row's symbol sits in, and the room after it.
    static let column: CGFloat = 16
    static let gap: CGFloat = 7
    static let padding: CGFloat = 8

    let symbol: String?

    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration, symbol: symbol)
    }
}

private struct MenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    let symbol: String?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: MenuRowStyle.gap) {
            Group {
                if let symbol {
                    Image(systemName: symbol).imageScale(.small)
                } else {
                    Color.clear
                }
            }
            .frame(width: MenuRowStyle.column, height: 14)
            configuration.label
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, MenuRowStyle.padding)
        .frame(minHeight: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
