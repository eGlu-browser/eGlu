import Foundation

/// "Use your Apple passwords?": one quiet row under a sign-in box, for
/// someone who keeps their accounts in the Passwords app and hasn't found
/// the switch. Apple Passwords stays off until it is clicked.
///
/// Offered sparingly, and remembered so it stays that way:
/// - at most once per site (its registrable domain), whatever happens then;
/// - never again once it has gone unanswered twice in all, or once its ✕
///   said "don't offer again";
/// - only on an https page, from the page itself or a frame of its own site,
///   never a frame of another site;
/// - only where Apple's helper can be reached at all, in a build that may
///   run it (the passkey entitlement).
///
/// Search's ApplePasswordsOffer (github.com/driceroland/Search, MIT, e38bc87);
/// eGlu keeps no accounts of its own and has no private tabs, so neither
/// counts here.
public struct ApplePasswordsOffer {
    /// Where the answers are kept: the app's defaults, or a test's own suite.
    public let store: UserDefaults

    public static let offeredKey = "applePasswordsOffered"
    public static let unansweredKey = "applePasswordsOfferUnanswered"
    public static let neverKey = "applePasswordsOfferNever"
    /// Gone unanswered this many times, and it isn't offered again.
    public static let patience = 2

    public init(store: UserDefaults) {
        self.store = store
    }

    /// What the decision is made from, for the box the caret is in.
    public struct Field: Equatable {
        /// The page's address, as committed.
        public var page: URL?
        /// The host of the frame the box is in, when it isn't the page itself.
        public var frameHost: String?
        /// A box that goes with a password, not one for passkeys alone.
        public var passwords: Bool

        public init(page: URL?, frameHost: String? = nil, passwords: Bool = true) {
            self.page = page
            self.frameHost = frameHost
            self.passwords = passwords
        }
    }

    public struct Settings: Equatable {
        /// Apple Passwords already on: nothing to offer.
        public var appleOn: Bool
        /// Apple's helper can be run: the build may, and the Mac has it.
        public var helper: Bool

        public init(appleOn: Bool, helper: Bool) {
            self.appleOn = appleOn
            self.helper = helper
        }
    }

    /// The site the offer is counted against, if it may be offered under
    /// this box. Nil: not here, not now.
    public func site(for field: Field, _ settings: Settings) -> String? {
        guard !settings.appleOn, settings.helper, field.passwords,
              let host = ApplePasswordsOfferHost.https(field.page)
        else { return nil }
        let site = Destination.registrable(host)
        if let frame = field.frameHost?.lowercased(), Destination.registrable(frame) != site { return nil }
        guard !store.bool(forKey: Self.neverKey),
              store.integer(forKey: Self.unansweredKey) < Self.patience,
              !offered.contains(site)
        else { return nil }
        return site
    }

    public var offered: Set<String> { Set(store.stringArray(forKey: Self.offeredKey) ?? []) }

    /// It came up under a box on this site: not again here.
    public func shown(on site: String) {
        var sites = offered
        guard sites.insert(site).inserted else { return }
        store.set(sites.sorted(), forKey: Self.offeredKey)
    }

    /// It went without an answer: the caret left, or the list went.
    public func unanswered() {
        store.set(store.integer(forKey: Self.unansweredKey) + 1, forKey: Self.unansweredKey)
    }

    /// Its ✕: never again, anywhere.
    public func dismissed() {
        store.set(true, forKey: Self.neverKey)
    }

    /// Whether it will ever come up again.
    public var retired: Bool {
        store.bool(forKey: Self.neverKey) || store.integer(forKey: Self.unansweredKey) >= Self.patience
    }

    /// Back to never offered.
    public func forget() {
        for key in [Self.offeredKey, Self.unansweredKey, Self.neverKey] { store.removeObject(forKey: key) }
    }
}

/// The https page's host, as Apple Passwords may be offered for it.
enum ApplePasswordsOfferHost {
    static func https(_ url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host
    }
}
