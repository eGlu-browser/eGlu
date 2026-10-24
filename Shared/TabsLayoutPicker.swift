import PadCore
import SwiftUI

/// Settings › Window › Tabs, on iPad and Mac: Horizontal or Vertical, each a
/// little window drawn as it would be, the way macOS's Appearance choices are
/// pictures. The tab on screen in the picture steps along its row (or down
/// its sidebar) once as the choice is made or the pointer comes onto it, and
/// rests; with Reduce Motion on it stays where it is.
struct TabsLayoutPicker: View {
    @Binding var selection: Preferences.TabsPlacement

    var body: some View {
        HStack(spacing: 14) {
            Choice(placement: .top, title: String(localized: "Horizontal"), selection: $selection)
            Choice(placement: .sidebar, title: String(localized: "Vertical"), selection: $selection)
        }
    }

    private struct Choice: View {
        let placement: Preferences.TabsPlacement
        let title: String
        @Binding var selection: Preferences.TabsPlacement
        @State private var step = 0
        @State private var stepping: Task<Void, Never>?
        @Environment(\.accessibilityReduceMotion) private var still

        private var chosen: Bool {
            selection == placement
        }

        var body: some View {
            Button {
                selection = placement
            } label: {
                VStack(spacing: 6) {
                    LayoutPicture(vertical: placement == .sidebar, step: step, lit: chosen)
                        .frame(width: 88, height: 58)
                        .padding(3)
                        .overlay {
                            // The ring is the picture's corner plus the gap to it, so the two curves run together.
                            RoundedRectangle(cornerRadius: LayoutPicture.corner + 3, style: .continuous)
                                .strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2)
                        }
                    Text(title)
                        .font(.callout.weight(chosen ? .medium : .regular))
                        .foregroundStyle(chosen ? .primary : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in if inside { play() } }
            .onChange(of: chosen) { _, now in if now { play() } }
            .accessibilityLabel(title)
            .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        }

        /// One pass along the tabs, a step at a time, back to the first.
        private func play() {
            guard !still, stepping == nil else { return }
            stepping = Task { @MainActor in
                for next in [1, 2, 0] {
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { break }
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { step = next }
                }
                stepping = nil
            }
        }
    }
}

/// A window with its tabs along the top, or down a sidebar: three tabs, the
/// one on screen (`step`) raised, a few lines of page beside them.
private struct LayoutPicture: View {
    let vertical: Bool
    let step: Int
    /// The choice made: the tab on screen in the accent colour, as a chosen thing is.
    let lit: Bool

    static let corner: CGFloat = 9

    var body: some View {
        let window = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        let tab = lit ? Color.accentColor : Color.primary.opacity(0.35)
        ZStack(alignment: .topLeading) {
            window.fill(Color.primary.opacity(0.05))
            window.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            if vertical {
                HStack(alignment: .top, spacing: 5) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index == step ? tab : Color.primary.opacity(0.14))
                                .frame(width: index == step ? 22 : 18, height: 5)
                        }
                    }
                    .frame(width: 24, alignment: .leading)
                    .padding(.top, 12)
                    page
                        .padding(.top, 6)
                }
                .padding(6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index == step ? tab : Color.primary.opacity(0.14))
                                .frame(width: index == step ? 22 : 16, height: 6)
                        }
                    }
                    .padding(.leading, 16)
                    page
                }
                .padding(6)
            }
        }
        .accessibilityHidden(true)
    }

    /// The page: a card with a few lines on it.
    private var page: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach([0.8, 0.55, 0.7], id: \.self) { share in
                        GeometryReader { box in
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: box.size.width * share, height: 3)
                        }
                        .frame(height: 3)
                    }
                }
                .padding(5)
            }
    }
}
