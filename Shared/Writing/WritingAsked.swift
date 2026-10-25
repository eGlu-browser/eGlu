import Foundation

/// The "writingAsked" flag: the build number that asked the writing
/// question, written the moment either of its buttons is pressed (task 05).
/// Nil means never asked; once set, the question never comes back, which
/// answer the person gave notwithstanding.
enum WritingAsked {
    private static let key = "writingAsked"

    static var wasAsked: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static func markAsked() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        UserDefaults.standard.set(build, forKey: key)
    }
}
