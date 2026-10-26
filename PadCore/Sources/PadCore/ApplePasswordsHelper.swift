#if os(macOS)
import Foundation
import Security

/// Apple's Passwords helper on this Mac: the program Apple's iCloud
/// Passwords extension for Chrome talks to, found on the system volume and
/// checked to be signed by Apple as that helper before it is run: a file
/// somewhere else claiming the name is never started. (Search's AppleHelper,
/// github.com/driceroland/Search, MIT, cf538b8)
public enum AppleHelper {
    /// Apple's iCloud Passwords extension for Chrome: the helper admits no
    /// other caller.
    public static let origin = "chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/"
    public static let identifier = "com.apple.PasswordManagerBrowserExtensionHelper"
    private static let places = [
        "/System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app",
        "/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app",
    ]

    /// The helper's program, if this Mac has it and it is Apple's.
    public static func program() -> URL? {
        places.lazy.compactMap { path -> URL? in
            let bundle = URL(fileURLWithPath: path)
            guard isApples(bundle) else { return nil }
            let program = bundle.appendingPathComponent("Contents/MacOS/PasswordManagerBrowserExtensionHelper")
            return FileManager.default.isExecutableFile(atPath: program.path) ? program : nil
        }.first
    }

    /// Signed by Apple, as that helper: its own designated requirement.
    public static func isApples(_ bundle: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard FileManager.default.fileExists(atPath: bundle.path),
              SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("identifier \"\(identifier)\" and anchor apple" as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }
}
#endif
