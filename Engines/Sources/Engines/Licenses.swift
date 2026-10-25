import Foundation

/// The text the app's "Licences" button shows: every crate the engines link
/// and its licence, from `licenses.sh`'s `Licenses.txt`, shipped as a
/// resource of this target.
public enum EngineLicenses {
    public static let text: String = {
        guard let url = Bundle.module.url(forResource: "Licenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The engines' licences did not load."
        }
        return text
    }()
}
