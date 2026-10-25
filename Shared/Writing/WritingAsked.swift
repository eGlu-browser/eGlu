import Foundation

/// Whether this build has asked about grammar checking: the welcome's
/// Writing step asks it on a first launch, the once-only sheet after an
/// update that brought checking. The build that asked is kept, so a build
/// that changes the question may ask once more, and a first launch the
/// welcome never finished asks the next time it resumes.
enum WritingAsked {
    static var wasAsked: Bool {
        UserDefaults.standard.string(forKey: "writingAsked") == build
    }

    static func markAsked() {
        UserDefaults.standard.set(build, forKey: "writingAsked")
    }

    private static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
