import SwiftUI

/// What a command did that leaves nothing on screen to show for it: a link
/// on the clipboard, a bookmark added or taken away, ads allowed on a site.
/// Said in a few words for a moment at the page's top right (ToastView),
/// and to VoiceOver; a new one takes the last one's place.
struct ActionToast: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let text: String
    /// A button beside the words (an element's picture offers Save): nil
    /// leaves the toast display-only, and untouchable as ever.
    var action: (title: String, run: () -> Void)?

    /// As long as one stays: long enough to read three words, short enough
    /// not to wait for.
    static let shown: Duration = .seconds(1.8)

    /// How long this one stays: one with a button, long enough to reach it
    /// with the pointer or VoiceOver.
    var duration: Duration {
        action == nil ? Self.shown : .seconds(6)
    }

    static func == (left: ActionToast, right: ActionToast) -> Bool { left.id == right.id }

    static var linkCopied: ActionToast { ActionToast(symbol: "link", text: String(localized: "Link Copied")) }

    static func bookmark(added: Bool) -> ActionToast {
        added ? ActionToast(symbol: "star.fill", text: String(localized: "Added to Bookmarks"))
              : ActionToast(symbol: "star.slash", text: String(localized: "Removed from Bookmarks"))
    }

    static func ads(blocked: Bool) -> ActionToast {
        blocked ? ActionToast(symbol: "shield", text: String(localized: "Blocking Enabled for This Site"))
                : ActionToast(symbol: "shield.slash", text: String(localized: "Ads Allowed on This Site"))
    }
}

/// A toast on Liquid Glass: a capsule with the toast's symbol and words.
/// It comes down a little into place and fades in, quick and without
/// bounce, and fades out; under Reduce Motion it only fades. It takes no
/// touch or click, so whatever is under it still gets them.
struct ToastView: View {
    let toast: ActionToast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast {
                HStack(spacing: 7) {
                    Image(systemName: toast.symbol)
                        .font(.caption.weight(.semibold))
                    Text(toast.text)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if let action = toast.action {
                        Button(action.title) { action.run() }
                            .buttonStyle(.plain)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
                .modifier(ToastGlass())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(y: -8).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                    removal: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0), value: toast?.id)
        // Only a toast with a button takes a touch or click, and only on it.
        .allowsHitTesting(toast?.action != nil)
        // Said to VoiceOver as it comes, rather than found on the screen;
        // one with a button is found too, so its button can be pressed.
        .accessibilityHidden(toast?.action == nil)
    }
}

/// Liquid Glass from iOS and macOS 26, the system's material before.
private struct ToastGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
