import SwiftUI

/// The question about checking English in pages, asked once: a step of
/// the first launch's welcome, or the small sheet an update that brought
/// checking shows (Browser.askAboutWritingIfNeeded). `offersOtherApps` is
/// where checking in other apps can also be offered: on a Mac, where an
/// extension makes that possible; never on iOS, which allows it nowhere.
struct WritingQuestion: View {
    var offersOtherApps = false
    /// The button row is drawn unless the view it is in answers another
    /// way: the welcome's footer buttons do its step's asking.
    var showsButtons = true
    var check: ((Bool) -> Void)? = nil
    var notNow: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Check your English as you write?")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Harper, a grammar checker, underlines mistakes in what you type in pages and suggests fixes. It works on this device, in English only, and sends nothing anywhere.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if showsButtons, let check, let notNow {
                VStack(spacing: 4) {
                    Button("Check My Writing") { check(false) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    if offersOtherApps {
                        Button("In Pages and Other Apps") { check(true) }
                    }
                    Button("Not Now", action: notNow)
                        .controlSize(.large)
                    Text("You can change this in Settings › Writing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("You can change this in Settings › Writing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: 460)
    }
}
