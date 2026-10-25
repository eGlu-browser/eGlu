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

/// The card's look: the lint's kind, its message as Markdown, and the
/// buttons under it.
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Button {
                    onAction(.close, 0)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Close"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Text(markdownMessage)
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)

            if !data.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(data.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        Button {
                            onAction(.applySuggestion, index)
                        } label: {
                            HStack {
                                Text(suggestion)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if index == 0 {
                                    Text(AcceptShortcutSymbols)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            HStack(spacing: 12) {
                Button(String(localized: "Ignore")) { onAction(.ignoreLint, 0) }
                if data.canAddToDictionary {
                    Button(String(localized: "Add to Dictionary")) { onAction(.addToDictionary, 0) }
                }
                Button(String(localized: "Turn Off This Rule")) { onAction(.disableRule, 0) }
                Spacer()
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
    }

    private var markdownMessage: AttributedString {
        (try? AttributedString(markdown: data.message)) ?? AttributedString(data.message)
    }
}

/// The accept key's hint on the first suggestion, as PadCore's chord shows it.
let AcceptShortcutSymbols = AcceptKey.symbols
