import AppKit
import PadCore
import SwiftUI

/// The app's icon on the Mac, chosen in Settings › General › App Icon from
/// the ones the iPhone and iPad offer (AppIcon). macOS has no alternate icons,
/// and a picture put in the app's own folder would break its signature, so the
/// icon is drawn over the Dock's tile instead: by the app while it is open
/// (the About window takes it from there too), and by its Dock tile plug-in
/// (Mac/DockTile) while it isn't. Finder and Spotlight show the app's own.
@MainActor
final class DockIcon: ObservableObject {
    static let shared = DockIcon()

    @Published private(set) var current: AppIcon
    /// Set as the address bar opens Settings at App Icon; the section, once
    /// scrolled into view, sets it back.
    @Published var reveal = false
    private var appearance: NSKeyValueObservation?

    /// Words the address bar finds App Icon by, as the iPhone and iPad's
    /// (SettingsAnchor.appIcon), with the Dock where they have the Home Screen.
    static let keywords = ["change icon", "change app icon", "dock icon", "alternate icon", "icon style", "logo"]

    private init() {
        // A name no icon has now (renamed since) is eGlu's own.
        current = AppIcon(alternateName: UserDefaults.standard.string(forKey: DockIconKeys.choice)) ?? .eGlu
    }

    /// At launch, once AppKit has put the app's own icon in the Dock, and
    /// from then on as the Mac turns light or dark: the Dock shows the picture
    /// it is given as it was drawn.
    func start() {
        show()
        appearance = NSApp.observe(\.effectiveAppearance) { _, _ in
            // Changes of appearance come on the main thread.
            MainActor.assumeIsolated { DockIcon.shared.show() }
        }
    }

    func choose(_ icon: AppIcon) {
        guard icon != current else { return }
        current = icon
        // Nil, for eGlu's own, takes the name away.
        UserDefaults.standard.set(icon.alternateName, forKey: DockIconKeys.choice)
        show()
        // For the plug-in: the tile stays as chosen once eGlu quits.
        DistributedNotificationCenter.default().postNotificationName(
            DockIconKeys.changed, object: Bundle.main.bundleIdentifier, userInfo: nil, deliverImmediately: true)
    }

    /// Settings, at General, with App Icon in view.
    func showInSettings() {
        // The pane MacSettings keeps, and opens on.
        UserDefaults.standard.set(SettingsPane.general.rawValue, forKey: "settingsPane")
        reveal = true
        Session.shared.openSettings?()
    }

    /// The icon's picture, which takes the light or the dark look of where it is drawn.
    static func picture(_ icon: AppIcon) -> NSImage? {
        NSImage(named: DockIconKeys.picture(icon.rawValue))
    }

    private func show() {
        guard current != .eGlu, let picture = Self.picture(current) else {
            // The app's own, which the Dock draws in its own style.
            NSApp.applicationIconImage = nil
            return
        }
        // Drawn in the Mac's look now: the Dock keeps what it was given.
        let look = NSAppearance(named: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua)
            ?? NSApp.effectiveAppearance
        NSApp.applicationIconImage = NSImage(size: picture.size, flipped: false) { rect in
            look.performAsCurrentDrawingAppearance { picture.draw(in: rect) }
            return true
        }
    }
}

/// Settings › General › App Icon: the icons the iPhone and iPad offer, in
/// their order, each as the Dock shows it; choosing one puts it there at once.
struct AppIconSettings: View {
    @ObservedObject private var icon = DockIcon.shared

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 14) {
                ForEach(AppIcon.allCases) { choice in
                    let chosen = choice == icon.current
                    Button { icon.choose(choice) } label: {
                        VStack(spacing: 4) {
                            Group {
                                if let picture = DockIcon.picture(choice) {
                                    Image(nsImage: picture).resizable()
                                }
                            }
                            .frame(width: Self.picture, height: Self.picture)
                            // Around the icon's square, which macOS draws at
                            // 824 of 1,024 points with the shadow under it.
                            .overlay {
                                RoundedRectangle(cornerRadius: Self.picture * 0.29, style: .continuous)
                                    .strokeBorder(chosen ? Color.accentColor : .clear, lineWidth: 2.5)
                                    .frame(width: Self.picture * 0.96, height: Self.picture * 0.96)
                            }
                            Text(choice.title)
                                .font(.caption)
                                .foregroundStyle(chosen ? .primary : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
            .background(Reveal(now: icon.reveal))
        } header: {
            Text("App Icon")
        } footer: {
            // As Settings' notes are (SettingsView.swift's Note).
            Text("Finder and Spotlight keep showing eGlu's own icon.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let picture: CGFloat = 72
}

/// Scrolls the section into view, when the address bar opened Settings at it.
private struct Reveal: NSViewRepresentable {
    let now: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard now else { return }
        // Once the form is laid out, with the section in it.
        DispatchQueue.main.async {
            view.scrollToVisible(view.bounds)
            DockIcon.shared.reveal = false
        }
    }
}
