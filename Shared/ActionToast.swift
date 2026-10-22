import SwiftUI

/// What a command did that leaves nothing on screen to show for it: a link
/// on the clipboard, a bookmark added or taken away, ads allowed on a site.
/// Said in a few words for a moment at the page's top right (ToastView),
/// and to VoiceOver; a new one takes the last one's place.
struct ActionToast: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let text: String

    /// As long as one stays: long enough to read three words, short enough
    /// not to wait for.
    static let shown: Duration = .seconds(1.8)

    static let linkCopied = ActionToast(symbol: "link", text: "Link Copied")

    static func bookmark(added: Bool) -> ActionToast {
        added ? ActionToast(symbol: "star.fill", text: "Added to Bookmarks")
              : ActionToast(symbol: "star.slash", text: "Removed from Bookmarks")
    }

    static func ads(blocked: Bool) -> ActionToast {
        blocked ? ActionToast(symbol: "shield", text: "Ads Blocked on This Site")
                : ActionToast(symbol: "shield.slash", text: "Ads Allowed on This Site")
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
                        .font(.system(size: 12, weight: .semibold))
                    Text(toast.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .modifier(ToastGlass())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(y: -8).combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .opacity),
                    removal: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0), value: toast?.id)
        .allowsHitTesting(false)
        // Said to VoiceOver as it comes, rather than found on the screen.
        .accessibilityHidden(true)
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
