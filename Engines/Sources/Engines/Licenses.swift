import Foundation

/// The app's acknowledgements (Settings › Acknowledgements on iPhone and
/// iPad, About eGlu on the Mac): every crate built into the engines, its
/// licence and copyright notices, and each licence's text, from
/// `licenses.sh`'s `Licenses.txt`, shipped as a resource of this target.
public enum EngineLicenses {
    public static let text: String = {
        guard let url = Bundle.module.url(forResource: "Licenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The engines' licences did not load."
        }
        return text
    }()
}
