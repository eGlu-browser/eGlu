#if canImport(CryptoKit) && canImport(Security)
import CryptoKit
import Foundation

/// The two ends of a conversation with Apple's Passwords helper: the Mac
/// app's program run over a pipe, or, in tests, something that answers as
/// it would.
@MainActor
public protocol AppleLink: AnyObject {
    var onMessage: (([String: Any]) -> Void)? { get set }
    var onEnd: (() -> Void)? { get set }
    func start() throws
    func send(_ message: [String: Any]) throws
    func stop()
}

/// A pairing with Apple's Passwords helper and the questions asked of it
/// (ApplePasswordsProtocol): the six-digit code typed, then names for a
/// site, then one password when its account is picked. The key lives in
/// memory only and dies with the helper; the next launch asks for a code
/// again, as Apple's extension does. Nothing about it is written anywhere.
/// Search's ApplePasswords (github.com/driceroland/Search, MIT: cf538b8,
/// 764d54f, 53b92d5), without its window and settings, which the Mac app
/// keeps (ApplePasswords.swift there).
@MainActor
public final class ApplePasswordsSession: ObservableObject {
    public enum State: Equatable, Sendable {
        /// Not talking to the helper.
        case idle
        /// Running it and starting a pairing.
        case starting
        /// The helper shows its code; waiting for it to be typed.
        case code
        /// Checking the code typed.
        case checking
        /// Paired: names can be asked for.
        case paired
    }

    @Published public private(set) var state: State = .idle
    /// Why the last attempt didn't work, in plain words; cleared by the next.
    @Published public private(set) var trouble: String?

    public struct Unavailable: LocalizedError {
        public let errorDescription: String?
        public init(errorDescription: String?) { self.errorDescription = errorDescription }
    }

    private let makeLink: () throws -> AppleLink
    private var link: AppleLink?
    private var client: SRPClient?
    private var numbers: (serverKey: [UInt8], salt: [UInt8])?
    private var key: SymmetricKey?
    /// A helper's answer, held as it came: a dictionary of JSON values,
    /// handed from the link to the question waiting for it on the main actor.
    private struct Reply: @unchecked Sendable {
        let value: [String: Any]
    }

    private var waiters: [Int: (id: Int, continuation: CheckedContinuation<Reply, Error>)] = [:]
    private var nextWaiter = 0
    private var busy = false
    private var queue: [CheckedContinuation<Void, Never>] = []
    private var tabNumbers: [UUID: Int] = [:]

    public init(makeLink: @escaping () throws -> AppleLink) {
        self.makeLink = makeLink
    }

    // MARK: Pairing

    /// Runs the helper and starts a pairing: the helper puts its code on
    /// screen. Only ever from a click of the person's.
    public func connect() async {
        guard state == .idle else { return }
        trouble = nil
        state = .starting
        do {
            try await exclusive {
                if link == nil {
                    let link = try makeLink()
                    link.onMessage = { [weak self] in self?.received($0) }
                    link.onEnd = { [weak self] in self?.ended() }
                    self.link = link
                    try link.start()
                }
                let hello = try await request(AppleMessages.hello(), timeout: 5)
                let capabilities = hello["capabilities"] as? [String: Any] ?? [:]
                if let version = capabilities["secretSessionVersion"] as? Int, version != 1 {
                    throw Unavailable(errorDescription: BrowserText.localized("This Mac's Passwords helper is too old"))
                }
                let client = SRPClient(base64: capabilities["shouldUseBase64"] as? Bool ?? false)
                let reply = try await request(AppleMessages.start(client), timeout: 15)
                numbers = try AppleMessages.readStart(reply, client)
                self.client = client
            }
            state = .code
        } catch {
            fail(error)
        }
    }

    /// The code the helper shows, as typed.
    public func enter(_ code: String) async {
        let code = code.filter(\.isNumber)
        guard state == .code, code.count == 6, let client, let numbers else { return }
        state = .checking
        trouble = nil
        do {
            let proof = try await Task.detached(priority: .userInitiated) {
                try client.prove(serverKey: numbers.serverKey, salt: numbers.salt, code: code)
            }.value
            try await exclusive {
                let reply = try await request(AppleMessages.verify(client, proof: proof), timeout: 15)
                try AppleMessages.readVerify(reply, client, proof: proof)
            }
            key = proof.key
            self.numbers = nil
            state = .paired
        } catch ApplePasswordsError.wrongCode {
            // The helper is done with that code: a new pairing shows a new one.
            self.numbers = nil
            self.client = nil
            state = .idle
            trouble = BrowserText.localized("That code didn't match. Connect again for a new one.")
        } catch {
            fail(error)
        }
    }

    /// Back to nothing: the helper told goodbye and stopped, every secret
    /// dropped. Also when the switch goes off and when the app quits.
    public func disconnect() {
        if let link {
            try? link.send(AppleMessages.end())
            link.onEnd = nil
            link.stop()
        }
        reset()
        state = .idle
    }

    // MARK: Asking

    /// The names the helper keeps for `host` (the page's own host, www and
    /// all). Usernames only; nothing secret. `wanted` is asked again just
    /// before the question goes, so one the caret has already left isn't
    /// sent (764d54f).
    public func logins(for host: String, tab: UUID, wanted: @MainActor () -> Bool = { true }) async -> [AppleLogin] {
        guard state == .paired else { return [] }
        do {
            return try await exclusive {
                guard wanted(), let client, let key else { return [] }
                let reply = try await request(
                    AppleMessages.loginNames(host: host, tab: number(of: tab), client: client, key: key), timeout: 8)
                return try AppleMessages.readLoginNames(AppleMessages.readSealed(reply, client, key: key))
            }
        } catch {
            dropIfSessionLost(error)
            return []
        }
    }

    /// The password of the account picked, for `host`. macOS may ask for
    /// Touch ID first; that can take a while, so no short timeout.
    public func password(for user: String, host: String, tab: UUID) async -> (password: String, sites: [String])? {
        guard state == .paired else { return nil }
        do {
            return try await exclusive {
                guard let client, let key else { return nil }
                let reply = try await request(
                    AppleMessages.password(user: user, host: host, tab: number(of: tab), client: client, key: key), timeout: 120)
                return try AppleMessages.readPassword(AppleMessages.readSealed(reply, client, key: key), user: user)
                    .map { ($0.password, $0.sites) }
            }
        } catch {
            dropIfSessionLost(error)
            return nil
        }
    }

    // MARK: The line

    /// One question at a time: the helper's answers carry no number to tell
    /// two of the same kind apart.
    private func exclusive<T>(_ work: () async throws -> T) async throws -> T {
        while busy { await withCheckedContinuation { queue.append($0) } }
        busy = true
        defer {
            busy = false
            if !queue.isEmpty { queue.removeFirst().resume() }
        }
        return try await work()
    }

    private func request(_ message: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard let link, let command = message["cmd"] as? Int else { throw ApplePasswordsError.gone }
        nextWaiter += 1
        let id = nextWaiter
        let reply: Reply = try await withCheckedThrowingContinuation { continuation in
            waiters[command] = (id, continuation)
            do {
                try link.send(message)
            } catch {
                resolve(command, id: id, with: .failure(ApplePasswordsError.gone))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resolve(command, id: id, with: .failure(ApplePasswordsError.timedOut))
            }
        }
        return reply.value
    }

    private func resolve(_ command: Int, id: Int? = nil, with result: Result<Reply, Error>) {
        guard let waiter = waiters[command], id == nil || waiter.id == id else { return }
        waiters[command] = nil
        waiter.continuation.resume(with: result)
    }

    private func received(_ message: [String: Any]) {
        guard let command = message["cmd"] as? Int else { return }
        switch command {
        case AppleCommand.passwordsDisabled.rawValue, AppleCommand.reloginNeeded.rawValue:
            // iCloud Keychain turned off, or signed out: the pairing is over.
            disconnect()
            trouble = BrowserText.localized("Apple Passwords needs you to sign in again")
        default:
            resolve(command, with: .success(Reply(value: message)))
        }
    }

    /// The helper went: everything that was waiting fails, and the pairing
    /// with it.
    private func ended() {
        link = nil
        reset()
        state = .idle
    }

    private func reset() {
        let pending = waiters.values
        waiters = [:]
        pending.forEach { $0.continuation.resume(throwing: ApplePasswordsError.gone) }
        link = nil
        client = nil
        numbers = nil
        key = nil
        tabNumbers = [:]
    }

    private func fail(_ error: Error) {
        trouble = Self.words(for: error)
        disconnect()
    }

    private func dropIfSessionLost(_ error: Error) {
        switch error {
        case ApplePasswordsError.status(9), ApplePasswordsError.gone, ApplePasswordsError.notTheHelper:
            disconnect()
            trouble = BrowserText.localized("Apple Passwords was disconnected. Connect again to use it.")
        default:
            break
        }
    }

    private func number(of tab: UUID) -> Int {
        if let known = tabNumbers[tab] { return known }
        let next = tabNumbers.count + 1
        tabNumbers[tab] = next
        return next
    }

    nonisolated public static func words(for error: Error) -> String {
        switch error {
        case let error as Unavailable: return error.errorDescription ?? BrowserText.localized("Apple Passwords isn't available")
        case ApplePasswordsError.timedOut: return BrowserText.localized("Apple's Passwords helper didn't answer")
        case ApplePasswordsError.gone: return BrowserText.localized("Apple's Passwords helper wouldn't run for this copy of eGlu")
        case ApplePasswordsError.notTheHelper: return BrowserText.localized("The pairing couldn't be checked. Connect again.")
        case ApplePasswordsError.badHello, ApplePasswordsError.malformed:
            return BrowserText.localized("Apple's Passwords helper answered in a way eGlu doesn't know")
        default: return BrowserText.localized("Apple Passwords isn't available on this Mac")
        }
    }

    // MARK: Which accounts a page gets

    /// The host a page may be offered Apple Passwords for: an https page,
    /// with a host to ask about; nil for any other.
    nonisolated public static func offers(on url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    /// Only accounts kept for this site: the host, or anything sharing its
    /// registrable domain. The helper may know wider ties (a company's
    /// several domains); those are not offered. `wide` false: the host
    /// alone, for a box that only might be a sign-in's.
    nonisolated public static func belongs(_ sites: [String], to host: String, wide: Bool = true) -> Bool {
        let domain = Destination.registrable(bare(host))
        return sites.contains { site in
            let named = site.contains("://") ? (URL(string: site)?.host() ?? site) : site
            let bareSite = bare(named)
            return bareSite == bare(host) || (wide && Destination.registrable(bareSite) == domain)
        }
    }

    nonisolated private static func bare(_ host: String) -> String {
        let host = host.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
#endif
