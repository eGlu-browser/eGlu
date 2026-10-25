import Engines
import SwiftUI

/// Settings › Licences: every crate the Rust engines link and its licence,
/// from `Licenses.txt` in the Engines package (`licenses.sh` writes it).
struct LicencesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        NavigationStack {
            text
                .navigationTitle(String(localized: "Licences"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { dismiss() }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            text
            HStack {
                Spacer()
                Button(String(localized: "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 560)
        #endif
    }

    private var text: some View {
        ScrollView {
            Text(EngineLicenses.text)
                .font(.footnote)
                .monospaced()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
    }
}
