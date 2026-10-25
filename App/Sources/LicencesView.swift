import Engines
import SwiftUI

/// Settings › Acknowledgements, at the foot of Settings' list, where an
/// app's are: every crate built into the Rust engines, its licence and
/// copyright notices, and each licence's text, from `Licenses.txt` in the
/// Engines package (`licenses.sh` writes it). The Mac's are in About eGlu.
struct LicencesView: View {
    var body: some View {
        text
            .navigationTitle(String(localized: "Acknowledgements"))
            .navigationBarTitleDisplayMode(.inline)
    }

    /// The text a paragraph at a time, laid out as it scrolls into view: it
    /// holds every licence in full, some 50 KB, which as one Text would all
    /// be laid out before the page could open.
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
