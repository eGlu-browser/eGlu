import PadCore
import SwiftUI
import UIKit

/// The command bar, on iPad: where an address is typed and everything else
/// is found, floating over the page as Arc's, Raycast's and Spotlight's do.
/// A new tab (⌘T, the + button) opens it empty with everything listed: the
/// open tabs, the spaces, every command with its keys (the cheat sheet of
/// the shortcuts), the parts of Settings. A click on the address, or ⌃⌥L,
/// opens it holding the page's address, selected, so typing replaces it.
/// What is typed goes to the tab on screen as an address or a search, or
/// narrows the rows to a tab to go to or a command to run (Suggestions).
///
/// It is the address field and the command palette in one: there is no
/// other place an address is typed on iPad, and no palette beside it. On a
/// phone the field is in the bar at the bottom instead (AddressEditor), with
/// the same rows over it.
struct CommandBar: View {
    @ObservedObject var window: WindowModel
    let act: (BarAction) -> Void

    static let fieldHeight: CGFloat = 54
    /// The rows it shows before they scroll: enough to see what kinds there
    /// are, and little enough that the page still shows under it.
    static let rowsShown: CGFloat = 8.5

    var body: some View {
        // Each turn at the bar is a field of its own (WindowModel.addressTurn):
        // one that starts while another is still up (⌘T with the bar open)
        // gets a new field, with nothing of the last one's text or focus. The
        // old field loses the keys as the page is given them on the way to
        // the new tab, and kept, it would take that for being put away and
        // cancel the turn that had just begun.
        CommandBarTurn(window: window, suggestions: window.suggestions, act: act)
            .id(window.addressTurn)
    }
}

/// One turn at the command bar: its field and the rows under it.
private struct CommandBarTurn: View {
    @ObservedObject var window: WindowModel
    @ObservedObject var suggestions: Suggestions
    let act: (BarAction) -> Void
    @State private var text = ""
    @State private var focused = false

    var body: some View {
        let rows = SuggestionRows.height(of: suggestions)
        let most = CommandBar.rowsShown * SuggestionRows.rowHeight
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .frame(width: 22)
                TypingField(text: $text, placeholder: AddressEditor.placeholder, fontSize: 17, focused: $focused,
                            selectsAll: true) { typed in act(.go(typed)) }
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.primary.opacity(0.3))
                            .frame(width: 32, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .hoverEffect(.highlight)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(height: CommandBar.fieldHeight)
            if rows > 0 {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                SuggestionRows(suggestions: suggestions) { row in act(.suggestion(row)) }
                    // As tall as its rows up to a point, and less where the
                    // window or the keyboard leaves less: then it scrolls.
                    .frame(idealHeight: min(rows, most), maxHeight: min(rows, most))
            }
        }
        // In Liquid Glass of the colour the row of tabs has, which is the
        // site's where the page has one (floatingGlass); the browser gives
        // the bar the light or dark look that goes with it (applySiteColor).
        .floatingGlass(cornerRadius: 20, tint: window.siteColor.map { Color(uiColor: $0.uiColor) } ?? Palette.ground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command bar")
        .onAppear { if window.editingAddress && !window.phone { begin() } }
        .onChange(of: text) { _, now in
            if !window.phone { suggestions.typed(now, in: window) }
        }
        .onChange(of: focused) { _, now in
            if !now && window.editingAddress && !window.phone { act(.cancelAddress) }
        }
        // Put away, the field lets go of the keys however typing ended.
        .onChange(of: window.editingAddress) { _, editing in if !editing { focused = false } }
    }

    /// The page's address, all of it selected, with the keys; or nothing,
    /// when everything is listed under the field.
    private func begin() {
        suggestions.begin(in: window)
        text = window.listsEverything ? "" : window.url.map(Destination.editable) ?? ""
        focused = true
    }
}
