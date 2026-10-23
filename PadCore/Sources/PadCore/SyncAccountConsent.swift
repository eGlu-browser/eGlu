import Foundation

/// Permission to upload local data belongs to one verified Apple Account.
/// The current account is supplied by CloudKit each run, never trusted from disk.
public struct SyncAccountConsent: Codable, Equatable, Sendable {
    public enum Choice: String, Codable, Sendable { case needsChoice, keepLocal, sync }

    public private(set) var account: String?
    public private(set) var choice: Choice = .needsChoice
    public private(set) var requiresNewIdentities = false

    public init() {}

    /// A sign-out revokes permission even if the same account signs in later.
    public mutating func observe(_ current: String?, legacyIdentityUnknown: Bool = false) {
        guard let current else {
            choice = .needsChoice
            return
        }
        if account != current || legacyIdentityUnknown {
            requiresNewIdentities = requiresNewIdentities || account != nil || legacyIdentityUnknown
            account = current
            choice = .needsChoice
        }
    }

    public func allows(_ current: String?) -> Bool {
        current != nil && account == current && choice == .sync
    }

    /// A stale account-choice screen cannot approve a different account.
    @discardableResult
    public mutating func choose(_ choice: Choice, for current: String) -> Bool {
        guard account == current, choice != .needsChoice, choice != .sync || !requiresNewIdentities else { return false }
        self.choice = choice
        return true
    }

    /// Only after the workspace's new identities have been saved durably.
    public mutating func savedNewIdentities() { requiresNewIdentities = false }

    public static func read(from file: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }

    public func write(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
