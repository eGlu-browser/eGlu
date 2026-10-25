import AppKit
import AuthenticationServices
import CryptoKit
import OSLog
import PadCore
import Security
import SwiftUI
import WebKit

// Passkeys and security keys, for a browser that isn't Safari. Copied from
// Search (github.com/driceroland/Search, MIT, its Passkeys.swift), with
// eGlu's names, its checks moved to PadCore (PasskeyRequest.swift) where
// they are tested, and the list under the sign-in field made for eGlu,
// which has no password list of its own for it to join.
//
// Only in a build signed with Apple's passkey entitlement for browsers
// (com.apple.developer.web-browser.public-key-credential), which Apple grants
// on request and which only a build signed with a provisioning profile that
// carries it may have (Release/mac.sh, PASSKEYS=1). Without it nothing here
// runs: no script goes into a page, no handler is added, and pages see
// WebKit's own navigator.credentials as they always have. Nor on a
// hands-off host (HandsOff), which gets no script of eGlu's in any build:
// Google's sign-in keeps WebKit's own, so its passkeys are left out.
//
// Left to WebKit, a site's request fails: WebKit answers navigator.credentials
// itself only for the app's own associated domains, and hands any other
// site's to AuthenticationServices in a way it refuses before any sheet, the
// entitlement notwithstanding (Search, 24 September 2026). And a sign-in page
// that offers your passkey under its name field (conditional mediation) has
// WebKit open an AutoFill operation with macOS's AuthenticationServicesAgent,
// held for as long as the page waits. If the app dies meanwhile (quit, crash,
// killed) the agent never lets go of it, and refuses every passkey request
// the app makes after that, before any sheet, until the Mac restarts: Search
// found that the same day.
//
// So eGlu carries the ceremony itself, as Chrome and Firefox do on the Mac,
// and never opens that operation: it takes the request from the page
// (passkeys.js), checks it against the frame it came from, and hands it to
// AuthenticationServices through the API made for browsers, with client data
// it writes: the origin in it is the one WebKit reports for the frame, never
// one the page states. The Mac's own sheet answers, with Touch ID and the
// passkeys in iCloud Keychain or a password app, an iPhone nearby over the QR
// code, or a security key, and what comes back goes to the page as the
// credential WebKit would have made.
//
// A sign-in page that offers your passkey under its name field gets the
// same, carried the same way: the request is checked and kept, waiting, and
// the Mac is asked only which passkeys it holds for the site, a question with
// no sheet and no operation left open. They are listed under the field while
// it has the keyboard (PasskeyList), and nothing reaches the page until you
// pick one: then the Mac's sheet, for that passkey alone, and the page's
// waiting request is answered with it. A new page, the page letting it go,
// or the page asking again ends the wait.
@MainActor
final class Passkeys: NSObject {
    static let shared = Passkeys()

    static let log = Logger(subsystem: "net.taehee.safience", category: "Passkeys")

    // MARK: Whether this build has them

    static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    /// Whether the running app is signed with Apple's passkey entitlement for
    /// browsers. Asked of the process's own signature, as Session.canSync asks
    /// about iCloud: that is the only thing that decides it, and a profile in
    /// the bundle proves nothing on its own.
    static let entitled: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
        else { return false }
        return (value as? Bool) == true
    }()

    /// A test build's run with made-up passkeys, from the shell or Xcode:
    /// `-passkeyRehearsal YES`. Pages get eGlu's passkeys without the
    /// entitlement, every check is made as for real, and the answer is a
    /// credential made up on the spot (PasskeyReply.rehearsal), so neither
    /// macOS's question nor its sheet ever comes up and no real passkey is
    /// listed. Never in a release build.
    static let rehearsal: Bool = {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "passkeyRehearsal")
        #else
        false
        #endif
    }()

    /// Whether pages get eGlu's passkeys: in a build with the entitlement, and
    /// in a rehearsal. `defaults write net.taehee.safience passkeyRelay -bool
    /// NO` leaves an entitled build's pages with WebKit's own instead, to tell
    /// a fault of eGlu's from one of macOS's; sites' passkeys then fail as
    /// they do without the entitlement. Read once at launch: a page's scripts
    /// go in before it loads.
    static let relayed: Bool = {
        if rehearsal { return true }
        guard entitled else { return false }
        return UserDefaults.standard.object(forKey: "passkeyRelay") as? Bool ?? true
    }()

    // MARK: The Mac's permission

    /// Whether this Mac lets eGlu use its passkeys at all: a question macOS
    /// puts once to a browser other than Safari, the answer kept in System
    /// Settings › Privacy & Security.
    private static var access: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState {
        ASAuthorizationWebBrowserPublicKeyCredentialManager().authorizationStateForPlatformCredentials
    }

    /// Everyone waiting on that question while it is on screen.
    private static var asking: [() -> Void]?

    /// Asked before the first ceremony, where it makes sense (a site has just
    /// asked for a passkey), and then never again.
    private static func ensure(_ then: @escaping () -> Void) {
        guard entitled, access == .notDetermined else { return then() }
        if asking != nil {
            asking?.append(then)
            return
        }
        asking = [then]
        ASAuthorizationWebBrowserPublicKeyCredentialManager().requestAuthorizationForPublicKeyCredentials { _ in
            DispatchQueue.main.async {
                let everyone = asking ?? []
                asking = nil
                everyone.forEach { $0() }
            }
        }
    }

    // MARK: A ceremony

    /// The one on screen, and whom to answer when it ends. A new request ends
    /// the one before, as a page asking twice gets in any browser.
    private var controller: ASAuthorizationController?
    /// The page's one-time key for this request's PRF results (PasskeyReply.prf).
    private var prfKey: P256.KeyAgreement.PublicKey?
    /// Whether the request asked for PRF at all.
    private var wantedPRF = false
    private var token: String?
    private var answer: (([String: Any]) -> Void)?
    private weak var anchor: NSWindow?
    /// The page whose request it is: a new document there, or the tab
    /// closing, ends it, so its sheet never stays over another site.
    private weak var asker: WKWebView?
    /// Called off by their pages before they could start.
    private var withdrawn: Set<String> = []

    /// Where a request came from, as WebKit knows it rather than as the page says.
    struct Caller {
        let frame: PasskeyFrame
        let window: NSWindow?
        /// The page's view, for a request that waits under its field.
        weak var web: WKWebView?
    }

    func cancel(token: String?) {
        guard let token else { return }
        if let (key, waiting) = conditional.first(where: { $0.value.token == token }) {
            conditional[key] = nil
            waiting.answer(PasskeyFailure.aborted.reply)
            list.close(for: waiting.web)
            return
        }
        if token == self.token {
            let running = controller
            finish(PasskeyFailure.aborted.reply)
            running?.cancel()
        } else {
            withdrawn.insert(token)
        }
    }

    func perform(_ body: [String: Any], from caller: Caller, answer: @escaping ([String: Any]) -> Void) {
        guard let request = PasskeyRequest(body) else {
            return refuse(answer, PasskeyFailure("NotSupportedError", "Not a passkey request."))
        }
        // The page in front of you only (inFront). A rehearsal from the shell
        // is always behind.
        let focused = Self.rehearsal || Self.inFront(caller.web)
        let passed: PasskeyCheck.Passed
        switch PasskeyCheck.verdict(for: request, from: caller.frame, focused: focused, hasView: caller.web != nil,
                                    isSuffix: Self.isSuffix) {
        case .wait:
            return answer(PasskeyFailure.wait.reply)
        case .refused(let failure):
            return refuse(answer, failure)
        case .passed(let checked):
            passed = checked
        }
        // The verdict passes no request without a challenge.
        guard let challenge = request.challenge else { return refuse(answer, PasskeyFailure.notAllowed) }
        var clientData = ASPublicKeyCredentialClientData(challenge: challenge, origin: passed.origin)
        if let top = passed.topOrigin {
            clientData.topOrigin = top
            clientData.crossOrigin = .crossOrigin
        }

        if passed.underField, let web = caller.web {
            return wait(request, passed: passed, clientData: clientData, in: web, answer: answer)
        }
        // A request of the page's own, with a sheet: the one waiting under the
        // field is over, as in any browser. One from a frame leaves it, but
        // not its list over the sheet.
        if let web = caller.web {
            list.close(for: web)
            if caller.frame.isMain, let waiting = conditional.removeValue(forKey: ObjectIdentifier(web)) {
                waiting.answer(PasskeyFailure.replaced.reply)
            }
        }

        Self.log.notice("\(request.kind.rawValue, privacy: .public) for \(passed.rp, privacy: .public) from \(passed.origin, privacy: .public)")
        if Self.rehearsal {
            var reply = PasskeyReply.rehearsal(request.kind, origin: passed.origin, topOrigin: passed.topOrigin, challenge: challenge)
            if request.prf != nil {
                reply["prf"] = PasskeyReply.rehearsalPRF(enabled: request.kind == .create ? true : nil, for: PasskeyReply.pageKey(request))
            }
            return answer(reply)
        }
        let requests = request.kind == .get
            ? Self.assertion(request, rp: passed.rp, clientData: clientData)
            : Self.registration(request, rp: passed.rp, clientData: clientData)
        let page = PasskeyCheck.origin(of: Self.committed(caller.web))
        Self.ensure { [weak self, weak web = caller.web] in
            guard let self else { return }
            if let token = request.token, self.withdrawn.remove(token) != nil {
                return answer(PasskeyFailure.aborted.reply)
            }
            // macOS's question may have been on screen a while: the page must
            // still be there, the same site's, and in front.
            guard let web, PasskeyCheck.origin(of: Self.committed(web)) == page, Self.inFront(web) else {
                return answer(PasskeyFailure.notAllowed.reply)
            }
            self.begin(requests, token: request.token, from: web, answer: answer)
            self.prfKey = PasskeyReply.pageKey(request)
            self.wantedPRF = request.prf != nil
        }
    }

    private func begin(_ requests: [ASAuthorizationRequest], token: String?, from web: WKWebView,
                       answer: @escaping ([String: Any]) -> Void) {
        if let running = controller {
            let previous = self.answer
            clear()
            running.cancel()
            previous?(PasskeyFailure.replaced.reply)
        }
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        self.token = token
        self.answer = answer
        anchor = web.window
        asker = web
        controller.performRequests()
    }

    // MARK: Offered under the field

    /// A passkey the Mac holds for the site whose page is waiting for one.
    struct Offered: Identifiable, Equatable {
        let id: Data
        /// The account's name, as the site made it.
        let name: String
        /// Where it is kept: iCloud Keychain, a password app.
        let provider: String?
    }

    /// A page's request for a passkey from under its field, checked and
    /// waiting: what the Mac is asked with once you have picked one.
    private struct Waiting {
        let request: PasskeyRequest
        let rp: String
        let origin: String
        let clientData: ASPublicKeyCredentialClientData
        let answer: ([String: Any]) -> Void
        weak var web: WKWebView?
        var offered: [Offered] = []
        var token: String? { request.token }
    }

    /// One per page, by its view.
    private var conditional: [ObjectIdentifier: Waiting] = [:]
    private let list = PasskeyList()

    /// The passkeys to offer under the fields of this page; none when the
    /// page isn't waiting for one, or has gone to another site since.
    func offered(in web: WKWebView?) -> [Offered] {
        guard let web, let waiting = conditional[ObjectIdentifier(web)], waiting.web === web,
              waiting.origin == PasskeyCheck.origin(of: Self.committed(web))
        else { return [] }
        return waiting.offered
    }

    /// The page is gone (a new document, or the tab) and its request with
    /// it. The answer asks the page to keep waiting, which a page that is
    /// gone never hears.
    func forget(_ web: WKWebView) {
        if let running = controller, asker === web {
            finish(PasskeyFailure.wait.reply)
            running.cancel()
        }
        conditional[ObjectIdentifier(web)].map { $0.answer(PasskeyFailure.wait.reply) }
        conditional[ObjectIdentifier(web)] = nil
        list.close(for: web)
        for (key, waiting) in conditional where waiting.web == nil {
            waiting.answer(PasskeyFailure.wait.reply)
            conditional[key] = nil
        }
    }

    private func wait(_ request: PasskeyRequest, passed: PasskeyCheck.Passed, clientData: ASPublicKeyCredentialClientData,
                      in web: WKWebView, answer: @escaping ([String: Any]) -> Void) {
        let key = ObjectIdentifier(web)
        // Asked again: the one before is over, as in any browser, and its list.
        conditional[key].map { $0.answer(PasskeyFailure.replaced.reply) }
        list.close(for: web)
        conditional[key] = Waiting(request: request, rp: passed.rp, origin: passed.origin, clientData: clientData,
                                   answer: answer, web: web)
        let allowed = Set(request.allowed.map(\.id))
        // A rehearsal never asks the Mac: it would list the passkeys of
        // whoever is working beside it. One made up, for the site.
        if Self.rehearsal {
            return settle(key, token: request.token,
                          [Offered(id: PasskeyReply.rehearsalID, name: "probe@\(passed.rp)", provider: "Rehearsal")])
        }
        // Not asked for here: a site loading is no time for macOS's question.
        // Until it has been answered, the field offers none.
        guard Self.access == .authorized else { return }
        let token = request.token
        Task { @MainActor in
            let found = await ASAuthorizationWebBrowserPublicKeyCredentialManager().platformCredentials(forRelyingParty: passed.rp)
            let offered = found
                .filter { allowed.isEmpty || allowed.contains($0.credentialID) }
                .prefix(8)
                .map { found in
                    Offered(id: found.credentialID, name: found.name.isEmpty ? String(localized: "Passkey") : String(found.name.prefix(200)),
                            provider: found.providerName.isEmpty ? nil : found.providerName)
                }
            self.settle(key, token: token, Array(offered))
        }
    }

    /// What the Mac holds, for the request that is still the page's; shown at
    /// once if the field already has the keyboard.
    private func settle(_ key: ObjectIdentifier, token: String?, _ offered: [Offered]) {
        guard var waiting = conditional[key], waiting.token == token else { return }
        waiting.offered = offered
        conditional[key] = waiting
        Self.log.notice("\(offered.count, privacy: .public) offered under the field for \(waiting.rp, privacy: .public)")
        guard !offered.isEmpty, let web = waiting.web else { return list.close(for: waiting.web) }
        Task { @MainActor [weak web] in
            guard let web, let page = (web as? PageView)?.page else { return }
            let rect = await page.passkeyField()
            self.field(rect, in: web)
        }
    }

    /// Where the page's sign-in field is while it has the keyboard, from
    /// passkeys-bridge.js, in the page's points; nil once it has let go.
    func field(_ rect: CGRect?, in web: WKWebView) {
        let offered = offered(in: web)
        // Shown only for the page in front; once shown, it follows the field
        // even while a click on it has its own window in front.
        let allowed = Self.rehearsal || Self.inFront(web) || (NSApp.isActive && list.isShown(for: web))
        guard let rect, !offered.isEmpty, web.window != nil, allowed else {
            return list.close(for: web)
        }
        list.show(offered, under: rect, in: web) { [weak self, weak web] picked in
            guard let self, let web else { return }
            self.sign(in: web, with: picked.id)
        }
    }

    /// One of the passkeys under the field, picked from its list (which only
    /// the page in front is shown): the Mac's sheet for it alone, and the
    /// page's waiting request answered with what it gives.
    func sign(in web: WKWebView, with id: Data) {
        let key = ObjectIdentifier(web)
        guard let waiting = conditional[key], waiting.web === web,
              waiting.offered.contains(where: { $0.id == id }),
              waiting.origin == PasskeyCheck.origin(of: Self.committed(web)),
              Self.rehearsal || (NSApp.isActive && list.isShown(for: web))
        else { return }
        conditional[key] = nil
        list.close(for: web)
        Self.log.notice("picked under the field for \(waiting.rp, privacy: .public)")
        if Self.rehearsal {
            var reply = PasskeyReply.rehearsal(.get, origin: waiting.origin, challenge: waiting.clientData.challenge)
            if waiting.request.prf != nil {
                reply["prf"] = PasskeyReply.rehearsalPRF(enabled: nil, for: PasskeyReply.pageKey(waiting.request))
            }
            return waiting.answer(reply)
        }
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: waiting.rp)
            .createCredentialAssertionRequest(clientData: waiting.clientData)
        request.allowedCredentials = [ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: id)]
        request.userVerificationPreference = Self.verification(waiting.request.userVerification)
        request.prf = Self.prfAssertion(waiting.request.prf, only: id)
        Self.ensure { [weak self, weak web] in
            guard let self else { return }
            if let token = waiting.token, self.withdrawn.remove(token) != nil {
                return waiting.answer(PasskeyFailure.aborted.reply)
            }
            guard let web, waiting.origin == PasskeyCheck.origin(of: Self.committed(web)), NSApp.isActive, web.window != nil else {
                return waiting.answer(PasskeyFailure.notAllowed.reply)
            }
            self.begin([request], token: waiting.token, from: web, answer: waiting.answer)
            self.prfKey = PasskeyReply.pageKey(waiting.request)
            self.wantedPRF = waiting.request.prf != nil
        }
    }

    // MARK: Requests

    private static func assertion(_ request: PasskeyRequest, rp: String, clientData: ASPublicKeyCredentialClientData) -> [ASAuthorizationRequest] {
        let verification = verification(request.userVerification)
        let platform = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rp)
            .createCredentialAssertionRequest(clientData: clientData)
        platform.allowedCredentials = request.allowed.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0.id) }
        platform.userVerificationPreference = verification
        platform.prf = prfAssertion(request.prf, only: nil)
        let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: rp)
            .createCredentialAssertionRequest(clientData: clientData)
        key.allowedCredentials = request.allowed.map {
            ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(credentialID: $0.id, transports: transports($0.transports))
        }
        key.userVerificationPreference = verification
        return [platform, key]
    }

    private static func registration(_ request: PasskeyRequest, rp: String, clientData: ASPublicKeyCredentialClientData) -> [ASAuthorizationRequest] {
        // The verdict passes no registration without a user.
        guard let user = request.user else { return [] }
        let verification = verification(request.userVerification)
        let attestation = attestation(request.attestation)
        var requests: [ASAuthorizationRequest] = []
        if request.offersPlatform {
            let platform = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rp)
                .createCredentialRegistrationRequest(clientData: clientData, name: user.name, userID: user.id)
            platform.displayName = user.displayName
            platform.userVerificationPreference = verification
            platform.attestationPreference = attestation
            platform.excludedCredentials = request.excluded.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0.id) }
            if let prf = request.prf {
                platform.prf = prf.eval.map { .inputValues(.saltInput1($0.first, saltInput2: $0.second)) } ?? .checkForSupport
            }
            requests.append(platform)
        }
        if request.offersSecurityKey {
            let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: rp)
                .createCredentialRegistrationRequest(clientData: clientData, displayName: user.displayName, name: user.name, userID: user.id)
            key.credentialParameters = request.algorithms.map {
                ASAuthorizationPublicKeyCredentialParameters(algorithm: ASCOSEAlgorithmIdentifier(rawValue: $0))
            }
            key.userVerificationPreference = verification
            key.attestationPreference = attestation
            switch request.residentKey {
            case "required": key.residentKeyPreference = .required
            case "preferred": key.residentKeyPreference = .preferred
            default: key.residentKeyPreference = .discouraged
            }
            key.excludedCredentials = request.excluded.map {
                ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(credentialID: $0.id, transports: transports($0.transports))
            }
            requests.append(key)
        }
        return requests
    }

    /// The page's PRF salts, as AuthenticationServices takes them; `only`, a
    /// passkey picked under the field, keeps its own salts and no one else's.
    /// The salts go through untouched: macOS hashes them as the standard
    /// says, the way it does for Safari.
    private static func prfAssertion(_ prf: PasskeyRequest.PRF?, only: Data?) -> ASAuthorizationPublicKeyCredentialPRFAssertionInput? {
        guard let prf else { return nil }
        typealias Values = ASAuthorizationPublicKeyCredentialPRFAssertionInput.InputValues
        var byCredential: [Data: Values] = [:]
        for (id, values) in prf.byCredential where only == nil || only == id {
            byCredential[id] = .saltInput1(values.first, saltInput2: values.second)
        }
        if let values = prf.eval {
            return .inputValues(.saltInput1(values.first, saltInput2: values.second),
                                perCredentialInputValues: byCredential.isEmpty ? nil : byCredential)
        }
        return byCredential.isEmpty ? nil : .perCredentialInputValues(byCredential)
    }

    private static func transports(_ named: [String]) -> [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport] {
        let known = named.compactMap { name -> ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport? in
            switch name {
            case "usb": return .usb
            case "nfc": return .nfc
            case "ble": return .bluetooth
            default: return nil
            }
        }
        return known.isEmpty ? ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported : known
    }

    private static func verification(_ value: String) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch value {
        case "required": return .required
        case "discouraged": return .discouraged
        default: return .preferred
        }
    }

    private static func attestation(_ value: String) -> ASAuthorizationPublicKeyCredentialAttestationKind {
        switch value {
        case "direct": return .direct
        case "indirect": return .indirect
        case "enterprise": return .enterprise
        default: return .none
        }
    }

    // MARK: Answers

    private func finish(_ value: [String: Any]) {
        let answer = self.answer
        clear()
        answer?(value)
    }

    private func clear() {
        controller = nil
        token = nil
        answer = nil
        prfKey = nil
        wantedPRF = false
        asker = nil
    }

    private func refuse(_ answer: ([String: Any]) -> Void, _ failure: PasskeyFailure) {
        Self.log.notice("refused: \(failure.message, privacy: .public)")
        answer(failure.reply)
    }

    // MARK: Checks

    /// The address of the page a view shows, once it is that page's: a tab's
    /// committed address. WKWebView.url moves as soon as a navigation starts,
    /// while the page before and its frames can still ask; and before a
    /// pop-up's first page commits, its opener can still write into it. A
    /// view that is no page of eGlu's has only its url.
    static func committed(_ web: WKWebView?) -> URL? {
        guard let web else { return nil }
        if let page = (web as? PageView)?.page { return page.committed }
        return web.url
    }

    /// Whether a page is the one in front of you: eGlu in front, the page's
    /// window the key one with no sheet over it, and the page's view holding
    /// the keyboard, as a page does once it has been clicked. A tab behind, a
    /// window behind, the pane beside the one with the keys, or a tab under a
    /// Peek doesn't get to bring up the Mac's sheet over what you are looking at.
    static func inFront(_ web: WKWebView?) -> Bool {
        guard let web, let window = web.window, NSApp.isActive, window.isKeyWindow, window.attachedSheet == nil,
              let holder = window.firstResponder as? NSView
        else { return false }
        return holder.isDescendant(of: web)
    }

    /// WebKit's own test for a public suffix, from the list macOS keeps.
    /// Private to CFNetwork, as Search uses it: without it, a page's own host
    /// is the only relying party it gets and a frame only its page's host.
    nonisolated static let publicSuffix: (@convention(c) (CFString) -> Bool)? = {
        guard let symbol = dlsym(dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork", RTLD_NOW), "_CFHostIsDomainTopLevel")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString) -> Bool).self)
    }()

    static var isSuffix: ((String) -> Bool)? {
        publicSuffix.map { test in { name in test(name as CFString) } }
    }
}

extension Passkeys: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchor ?? NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            guard controller === self.controller else { return }
            let credential = authorization.credential
            if let got = credential as? ASAuthorizationPublicKeyCredentialAssertion {
                let platform = credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion
                Self.log.notice("signed in")
                var reply = PasskeyReply.assertion(
                    id: got.credentialID, clientData: got.rawClientDataJSON, authenticatorData: got.rawAuthenticatorData,
                    signature: got.signature, user: got.userID,
                    attachment: platform?.attachment == .platform ? "platform" : "cross-platform"
                )
                if let prf = platform?.prf {
                    reply["prf"] = PasskeyReply.prf(enabled: nil, first: Self.bytes(prf.first), second: prf.second.map(Self.bytes), for: prfKey)
                }
                finish(reply)
            } else if let made = credential as? ASAuthorizationPublicKeyCredentialRegistration {
                let platform = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration
                Self.log.notice("made one")
                var reply = PasskeyReply.registration(
                    id: made.credentialID, clientData: made.rawClientDataJSON, attestation: made.rawAttestationObject ?? Data(),
                    transports: platform == nil ? ["usb"] : ["hybrid", "internal"],
                    attachment: platform?.attachment == .platform ? "platform" : "cross-platform"
                )
                if let prf = platform?.prf {
                    reply["prf"] = PasskeyReply.prf(enabled: prf.isSupported, first: prf.first.map(Self.bytes),
                                                    second: prf.second.map(Self.bytes), for: prfKey)
                } else if wantedPRF {
                    // A security key, which can't: the site is told so.
                    reply["prf"] = ["enabled": false]
                }
                finish(reply)
            } else {
                finish(PasskeyFailure("NotAllowedError", "The authenticator answered with something else.").reply)
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            guard controller === self.controller else { return }
            Self.log.notice("failed: \(String(describing: error), privacy: .public)")
            // A credential it already holds is what a site is told; anything
            // else (no, the sheet closed, the time ran out) a site may not
            // tell apart.
            let error = error as NSError
            if error.domain == ASAuthorizationError.errorDomain, error.code == ASAuthorizationError.Code.matchedExcludedCredential.rawValue {
                finish(PasskeyFailure.alreadyHeld.reply)
            } else {
                finish(PasskeyFailure.notAllowed.reply)
            }
        }
    }

    private static func bytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}

/// The page's side: requests handed over, answers handed back, and where the
/// sign-in field is while it has the keyboard.
final class PasskeyRelay: NSObject, WKScriptMessageHandlerWithReply {
    /// As passkeys-bridge.js names it.
    static let name = "egluPasskeys"

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                           replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        MainActor.assumeIsolated {
            guard message.world == Page.world, let body = message.body as? [String: Any] else {
                return replyHandler(nil, "Not a request")
            }
            switch body["kind"] as? String {
            case "cancel":
                Passkeys.shared.cancel(token: body["token"] as? String)
                return replyHandler(true, nil)
            case "field":
                if message.frameInfo.isMainFrame, let web = message.webView {
                    let rect = (body["rect"] as? [String: Any]).flatMap(Self.rect)
                    Passkeys.shared.field(rect, in: web)
                }
                return replyHandler(true, nil)
            default:
                let origin = message.frameInfo.securityOrigin
                let caller = Passkeys.Caller(
                    frame: PasskeyFrame(scheme: origin.protocol, host: origin.host, port: origin.port,
                                        isMain: message.frameInfo.isMainFrame, page: Passkeys.committed(message.webView),
                                        ancestors: body["ancestors"] as? [String]),
                    window: message.webView?.window,
                    web: message.webView
                )
                Passkeys.shared.perform(body, from: caller) { replyHandler($0, nil) }
            }
        }
    }

    private static func rect(_ value: [String: Any]) -> CGRect? {
        guard let x = value["x"] as? Double, let y = value["y"] as? Double,
              let width = value["width"] as? Double, let height = value["height"] as? Double,
              width > 0, height > 0
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// The passkeys the Mac holds for a site, listed under its sign-in field
/// while the field has the keyboard: a popover from the field, which leaves
/// the keyboard where it is, so typing a name goes on as before. A row picked
/// brings up the Mac's sheet for that passkey alone; a click anywhere else
/// puts the list away until the field is clicked again.
@MainActor
final class PasskeyList: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private weak var web: WKWebView?

    func show(_ offered: [Passkeys.Offered], under rect: CGRect, in web: WKWebView, pick: @escaping (Passkeys.Offered) -> Void) {
        let spot = Self.spot(rect, in: web)
        // Already there for this page and these passkeys: it follows the field.
        if let popover, popover.isShown, self.web === web,
           (popover.contentViewController as? NSHostingController<PasskeyRows>)?.rootView.offered == offered {
            popover.positioningRect = spot
            return
        }
        close(for: self.web)
        let rows = PasskeyRows(offered: offered, site: Passkeys.committed(web)?.host() ?? "") { [weak self] picked in
            // Picked while the list is still up, which is what lets it count.
            pick(picked)
            self?.close(for: web)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: rows)
        popover.delegate = self
        self.popover = popover
        self.web = web
        popover.show(relativeTo: spot, of: web, preferredEdge: web.isFlipped ? .maxY : .minY)
        // The keyboard stays in the field.
        if let window = web.window, !window.isKeyWindow { window.makeKey() }
        Passkeys.log.notice("\(offered.count, privacy: .public) listed under the field")
        #if DEBUG
        // A rehearsal from the shell picks the first, as a click on it would
        // (`-passkeyRehearsalPick YES`, Tests/passkeys-rehearsal.py).
        if Passkeys.rehearsal, UserDefaults.standard.bool(forKey: "passkeyRehearsalPick"), let first = offered.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard self?.popover === popover else { return }
                rows.pick(first)
            }
        }
        #endif
    }

    func isShown(for web: WKWebView) -> Bool {
        popover?.isShown == true && self.web === web
    }

    func close(for web: WKWebView?) {
        guard let popover, web == nil || self.web === web || self.web == nil else { return }
        self.popover = nil
        self.web = nil
        popover.close()
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if (notification.object as? NSPopover) === popover {
                popover = nil
                web = nil
            }
        }
    }

    /// The field's place in the view: the page's points, zoomed as the page is.
    private static func spot(_ rect: CGRect, in web: WKWebView) -> CGRect {
        let scale = web.pageZoom * web.magnification
        var spot = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        if !web.isFlipped { spot.origin.y = web.bounds.height - spot.maxY }
        return spot.intersection(web.bounds).isNull ? CGRect(x: spot.minX, y: 0, width: max(spot.width, 1), height: 1) : spot
    }
}

/// The rows of PasskeyList: each passkey's account, and where it is kept.
struct PasskeyRows: View {
    let offered: [Passkeys.Offered]
    let site: String
    let pick: (Passkeys.Offered) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(offered) { passkey in
                Button {
                    pick(passkey)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(passkey.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(passkey.provider.map { "\(String(localized: "Passkey")) · \($0)" } ?? String(localized: "Passkey"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PasskeyRowStyle())
            }
        }
        .padding(6)
        .frame(width: 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Passkeys for \(site)"))
    }
}

private struct PasskeyRowStyle: ButtonStyle {
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(configuration.isPressed ? 0.3 : hovered ? 0.18 : 0)))
            .onHover { hovered = $0 }
    }
}
