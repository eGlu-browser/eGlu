import Engines
import SwiftUI

/// Settings › Licences: every crate built into the Rust engines, its
/// licence and copyright notices, and each licence's text, from
/// `Licenses.txt` in the Engines package (`licenses.sh` writes it).
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

    /// The text a paragraph at a time, laid out as it scrolls into view: it
    /// holds every licence in full, some 50 KB, which as one Text would all
    /// be laid out before the sheet could open.
    private static let paragraphs = EngineLicenses.text
        .components(separatedBy: "\n\n")
        .filter { !$0.isEmpty }

    private var text: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Self.paragraphs.indices, id: \.self) { index in
                    Text(Self.paragraphs[index])
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.footnote)
            .monospaced()
            .textSelection(.enabled)
            .padding()
        }
    }
}
