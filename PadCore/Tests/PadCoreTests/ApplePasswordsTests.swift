#if canImport(CryptoKit) && canImport(Security)
import CryptoKit
import Foundation
@testable import PadCore
import XCTest

@MainActor
final class ApplePasswordsTests: XCTestCase {
    private struct Vectors: Decodable {
        struct SRP: Decodable {
            let base64: Bool
            let pin, TID, a, I, salt, B, m0A, M, HAMK, channel: String
            let requestPlain, requestIV, requestSDATA, replyPlain, replySDATA: String
        }
        struct PowMod: Decodable { let base, exp, out: String }
        let srp: [SRP]
        let powmods: [PowMod]
    }

    private var vectors: Vectors {
        try! JSONDecoder().decode(Vectors.self, from: Data(ApplePasswordsVectors.json.utf8))
    }

    private func bytes(_ hex: String) -> [UInt8] { [UInt8](Data(hexString: hex)!) }

    // MARK: - numbers

    func testGroupIsRFC5054() {
        XCTAssertEqual(SRPClient.group.bitLength, 3072)
        XCTAssertEqual(SRPClient.group.bytes.count, 384)
        XCTAssertEqual(Data(SRPClient.group.bytes.prefix(8)).hexString, "ffffffffffffffff")
        XCTAssertEqual(Data(SRPClient.group.bytes.suffix(8)).hexString, "ffffffffffffffff")
    }

    func testPowersMatchReference() {
        for vector in vectors.powmods {
            let out = SRPClient.modulus.power(SRPNumber(bytes: bytes(vector.base)), SRPNumber(bytes: bytes(vector.exp)))
            XCTAssertEqual(Data(out.bytes).hexString, vector.out)
        }
    }

    func testArithmetic() {
        let a = SRPNumber(hex: "ffffffffffffffffffffffff")!, one = SRPNumber(1)
        XCTAssertEqual(Data((a + one).bytes).hexString, "01000000000000000000000000")
        XCTAssertEqual((a + one) - one, a)
        XCTAssertEqual(Data((a * a).bytes).hexString, "fffffffffffffffffffffffe000000000000000000000001")
        XCTAssertEqual(SRPNumber(bytes: [0, 0, 5]).bytes, [5])
        XCTAssertEqual(SRPNumber(limbs: []).bytes, [0])
        XCTAssertEqual(SRPNumber(5).padded(4), [0, 0, 0, 5])
        let n = SRPClient.group
        XCTAssertEqual(SRPClient.modulus.subtract(one, SRPNumber(2)), n - one)
        XCTAssertEqual(SRPClient.modulus.multiply(n - one, n - one), one)
    }

    // MARK: - the handshake, against Apple's own extension's numbers

    private func client(for vector: Vectors.SRP) -> SRPClient {
        var draws = [bytes(vector.I), bytes(vector.a)]
        return SRPClient(base64: vector.base64) { _ in draws.removeFirst() }
    }

    func testHandshakeMatchesApplesExtension() throws {
        XCTAssertEqual(vectors.srp.count, 3)
        for vector in vectors.srp {
            let client = client(for: vector)
            XCTAssertEqual(client.tid, vector.TID)
            XCTAssertEqual(client.serialize(client.publicKey.bytes), vector.m0A)
            let proof = try client.prove(serverKey: bytes(vector.B), salt: bytes(vector.salt), code: vector.pin)
            XCTAssertEqual(Data(proof.m).hexString, vector.M)
            XCTAssertEqual(Data(proof.expected).hexString, vector.HAMK)
            XCTAssertEqual(proof.key.withUnsafeBytes { Data($0).hexString }, vector.channel)
            // A wrong code proves something else.
            let wrong = try client.prove(serverKey: bytes(vector.B), salt: bytes(vector.salt), code: "111111")
            XCTAssertNotEqual(wrong.m, proof.m)
        }
    }

    func testSaltWithLeadingZeroKeepsItsZero() throws {
        let vector = vectors.srp[2]
        XCTAssertTrue(vector.salt.hasPrefix("00"))
        let proof = try client(for: vector).prove(serverKey: bytes(vector.B), salt: bytes(vector.salt), code: vector.pin)
        XCTAssertEqual(Data(proof.m).hexString, vector.M)
    }

    func testChannelMatchesApplesFraming() throws {
        for vector in vectors.srp {
            let client = client(for: vector)
            let key = SymmetricKey(data: bytes(vector.channel))
            // Ours: ciphertext and tag, then the IV.
            let sealed = try SecretChannel.seal(Data(vector.requestPlain.utf8), key: key, iv: bytes(vector.requestIV))
            XCTAssertEqual(client.serialize(sealed, prefix: false), vector.requestSDATA)
            XCTAssertEqual(Array(sealed.suffix(16)), bytes(vector.requestIV))
            // The helper's: the IV first.
            let reply = try SecretChannel.open(client.deserialize(vector.replySDATA)!, key: key)
            XCTAssertEqual(String(decoding: reply, as: UTF8.self), vector.replyPlain)
            // Tampered with, it doesn't open.
            var bad = client.deserialize(vector.replySDATA)!
            bad[bad.count - 1] ^= 1
            XCTAssertThrowsError(try SecretChannel.open(bad, key: key))
        }
    }

    func testRefusesNumbersNoHelperSends() {
        let client = SRPClient(base64: false)
        let n = SRPClient.group
        for b in [SRPNumber(limbs: []), n, n + SRPNumber(1)] {
            XCTAssertThrowsError(try client.prove(serverKey: b.bytes, salt: [1, 2, 3], code: "123456")) {
                guard case ApplePasswordsError.badHello = $0 else { return XCTFail("\($0)") }
            }
        }
        XCTAssertThrowsError(try client.prove(serverKey: [2], salt: [], code: "123456"))
    }

    // MARK: - the messages

    private func decode(_ text: Any?) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data((text as? String ?? "").utf8))) as? [String: Any] ?? [:]
    }

    private func pake(_ object: [String: Any]) -> String {
        Data(try! JSONSerialization.data(withJSONObject: object)).base64EncodedString()
    }

    func testStartAsksForRFCProofOnly() {
        let client = SRPClient(base64: false)
        let message = AppleMessages.start(client)
        XCTAssertEqual(message["cmd"] as? Int, 2)
        let msg = decode(message["msg"])
        XCTAssertEqual(msg["QID"] as? String, "m0")
        XCTAssertEqual(msg["HSTBRSR"] as? String, "Chrome")
        let inner = (try? JSONSerialization.jsonObject(with: Data(base64Encoded: msg["PAKE"] as! String)!)) as! [String: Any]
        XCTAssertEqual(inner["TID"] as? String, client.tid)
        XCTAssertEqual(inner["MSG"] as? Int, 0)
        XCTAssertEqual(inner["PROTO"] as? [Int], [1])
        XCTAssertEqual(inner["VER"] as? String, "1.0")
    }

    func testReadStartRefusesDowngradeErrorsAndStrangers() {
        let client = SRPClient(base64: false)
        func reply(_ fields: [String: Any]) -> [String: Any] {
            var all: [String: Any] = ["TID": client.tid, "MSG": 1, "B": "0x05", "s": "0x01", "PROTO": 1]
            fields.forEach { all[$0] = $1 }
            return ["cmd": 2, "payload": ["QID": "m0", "PAKE": pake(all)]]
        }
        XCTAssertNoThrow(try AppleMessages.readStart(reply([:]), client))
        XCTAssertThrowsError(try AppleMessages.readStart(reply(["PROTO": 0]), client))
        XCTAssertThrowsError(try AppleMessages.readStart(reply(["ErrCode": 2]), client))
        XCTAssertThrowsError(try AppleMessages.readStart(reply(["TID": "0x1234"]), client))
        XCTAssertThrowsError(try AppleMessages.readStart(reply(["MSG": 3]), client))
        XCTAssertThrowsError(try AppleMessages.readStart(["cmd": 2], client))
    }

    func testReadVerify() throws {
        let vector = vectors.srp[0]
        let client = client(for: vector)
        let proof = try client.prove(serverKey: bytes(vector.B), salt: bytes(vector.salt), code: vector.pin)
        func reply(_ fields: [String: Any]) -> [String: Any] {
            var all: [String: Any] = ["TID": client.tid, "MSG": 3, "ErrCode": 0, "HAMK": vector.HAMK]
            fields.forEach { all[$0] = $1 }
            return ["cmd": 2, "payload": ["QID": "m2", "PAKE": pake(all)]]
        }
        XCTAssertNoThrow(try AppleMessages.readVerify(reply([:]), client, proof: proof))
        XCTAssertThrowsError(try AppleMessages.readVerify(reply(["ErrCode": 1]), client, proof: proof)) {
            XCTAssertEqual($0 as? ApplePasswordsError, .wrongCode)
        }
        var hamk = bytes(vector.HAMK)
        hamk[0] ^= 1
        XCTAssertThrowsError(try AppleMessages.readVerify(reply(["HAMK": Data(hamk).hexString]), client, proof: proof)) {
            XCTAssertEqual($0 as? ApplePasswordsError, .notTheHelper)
        }
        XCTAssertThrowsError(try AppleMessages.readVerify(reply(["HAMK": NSNull()]), client, proof: proof))
    }

    func testReadingAnswers() throws {
        let names = try AppleMessages.readLoginNames(["STATUS": 0, "Entries": [
            ["USR": "ada@example.test", "sites": ["example.test"]],
            ["USR": "Passwords not saved", "sites": ["example.test"]],
        ]])
        XCTAssertEqual(names.map(\.user), ["ada@example.test"])
        let numbered = try AppleMessages.readLoginNames(["STATUS": 0, "Entry_1": ["USR": "b", "sites": []],
                                                         "Entry_0": ["USR": "a", "sites": []]])
        XCTAssertEqual(numbered.map(\.user), ["a", "b"])
        XCTAssertEqual(try AppleMessages.readLoginNames(["STATUS": 3]), [])
        XCTAssertThrowsError(try AppleMessages.readLoginNames(["STATUS": 9])) {
            XCTAssertEqual($0 as? ApplePasswordsError, .status(9))
        }
        let found = try AppleMessages.readPassword(["STATUS": 0, "Entries": [
            ["USR": "other", "PWD": "x", "sites": ["example.test"]],
            ["USR": "ada", "PWD": "made-up-secret", "sites": ["example.test"]],
        ]], user: "ada")
        XCTAssertEqual(found?.password, "made-up-secret")
        XCTAssertNil(try AppleMessages.readPassword(["STATUS": 0, "Entries": [["USR": "ada", "PWD": "Not Included"]]], user: "ada"))
        XCTAssertNil(try AppleMessages.readPassword(["STATUS": 0, "Entries": [["USR": "eve", "PWD": "x"]]], user: "ada"))
    }

    // MARK: - which pages, which accounts

    func testOffersOnlyHttps() {
        XCTAssertEqual(ApplePasswordsSession.offers(on: URL(string: "https://Accounts.Example.com/login")), "accounts.example.com")
        XCTAssertNil(ApplePasswordsSession.offers(on: URL(string: "http://example.com/")))
        XCTAssertNil(ApplePasswordsSession.offers(on: URL(string: "file:///tmp/login.html")))
        XCTAssertNil(ApplePasswordsSession.offers(on: URL(string: "chrome-extension://abc/popup.html")))
        XCTAssertNil(ApplePasswordsSession.offers(on: nil))
    }

    func testAccountsMatchTheSite() {
        func belongs(_ sites: [String], _ host: String) -> Bool { ApplePasswordsSession.belongs(sites, to: host) }
        XCTAssertTrue(belongs(["example.com"], "accounts.example.com"))
        XCTAssertTrue(belongs(["www.example.com"], "example.com"))
        XCTAssertTrue(belongs(["https://login.example.com/"], "example.com"))
        XCTAssertTrue(belongs(["other.test", "example.com"], "example.com"))
        XCTAssertFalse(belongs(["example.net"], "example.com"))
        XCTAssertFalse(belongs(["evil-example.com"], "example.com"))
        XCTAssertFalse(belongs(["example.com.evil.test"], "example.com"))
        XCTAssertFalse(belongs(["bbc.co.uk"], "other.co.uk"))
        XCTAssertFalse(belongs(["mallory.blogspot.com"], "alice.blogspot.com"), "side by side under a suffix eGlu doesn't know")
        XCTAssertFalse(belongs(["attacker.co.za"], "bank.co.za"))
        XCTAssertFalse(belongs(["login.example.com"], "accounts.example.com"), "side by side: not offered")
        XCTAssertFalse(belongs(["co.uk"], "bbc.co.uk"), "a suffix is no site")
        XCTAssertFalse(belongs([], "example.com"))
        XCTAssertFalse(ApplePasswordsSession.belongs(["example.com"], to: "accounts.example.com", wide: false))
    }

    // MARK: - the helper on this Mac

    #if os(macOS)
    func testOnlyApplesSignedHelperIsRun() throws {
        // A bundle claiming the name, not signed by Apple, is never picked.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("apw-fake-\(UUID().uuidString)")
        let bundle = folder.appendingPathComponent("PasswordManagerBrowserExtensionHelper.app")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let program = bundle.appendingPathComponent("Contents/MacOS/PasswordManagerBrowserExtensionHelper")
        try "#!/bin/sh\n".write(to: program, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path)
        XCTAssertFalse(AppleHelper.isApples(bundle))
        // Apple's, where this Mac has it: only its signature is read, it is not run.
        let real = URL(fileURLWithPath: "/System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app")
        if FileManager.default.fileExists(atPath: real.path) {
            XCTAssertTrue(AppleHelper.isApples(real))
            XCTAssertEqual(AppleHelper.program()?.lastPathComponent, "PasswordManagerBrowserExtensionHelper")
        }
        // Something Apple signed that isn't the helper doesn't pass either.
        XCTAssertFalse(AppleHelper.isApples(URL(fileURLWithPath: "/System/Applications/Calculator.app")))
    }
    #endif

    // MARK: - the whole flow, against a made-up helper in memory

    func testPairAskAndFill() async throws {
        let fake = FakeHelper(code: "246810")
        let apple = ApplePasswordsSession(makeLink: { fake })
        await apple.connect()
        XCTAssertEqual(apple.state, .code)
        XCTAssertEqual(fake.handshakes, 1)
        // Names can't be asked for before pairing.
        let early = await apple.logins(for: "example.test", tab: UUID())
        XCTAssertEqual(early, [])

        await apple.enter("246810")
        XCTAssertEqual(apple.state, .paired)
        let tab = UUID()
        let names = await apple.logins(for: "accounts.example.test", tab: tab)
        XCTAssertEqual(names.map(\.user), ["ada@example.test"])
        XCTAssertEqual(fake.asked.last?["URL"] as? String, "accounts.example.test")
        XCTAssertEqual(fake.asked.last?["ACT"] as? Int, 5)
        XCTAssertNil(fake.asked.last?["PWD"])
        let found = await apple.password(for: "ada@example.test", host: "accounts.example.test", tab: tab)
        XCTAssertEqual(found?.password, "made-up-secret")
        XCTAssertEqual(fake.asked.last?["ACT"] as? Int, 2)
        let none = await apple.password(for: "nobody", host: "accounts.example.test", tab: tab)
        XCTAssertNil(none)

        // Off: the helper is told goodbye and stopped.
        apple.disconnect()
        XCTAssertEqual(apple.state, .idle)
        XCTAssertTrue(fake.ended)
        XCTAssertTrue(fake.stopped)
        let after = await apple.logins(for: "accounts.example.test", tab: tab)
        XCTAssertEqual(after, [])
    }

    func testWrongCodeNeedsANewPairing() async {
        let fake = FakeHelper(code: "246810")
        let apple = ApplePasswordsSession(makeLink: { fake })
        await apple.connect()
        await apple.enter("135791")
        XCTAssertEqual(apple.state, .idle)
        XCTAssertNotNil(apple.trouble)
        // The old code can't be tried again: Connect starts a new handshake.
        await apple.enter("246810")
        XCTAssertEqual(apple.state, .idle)
        await apple.connect()
        XCTAssertEqual(fake.handshakes, 2)
        await apple.enter("246810")
        XCTAssertEqual(apple.state, .paired)
    }

    func testNotACodeIsNotSent() async {
        let fake = FakeHelper(code: "246810")
        let apple = ApplePasswordsSession(makeLink: { fake })
        await apple.connect()
        await apple.enter("12345")
        await apple.enter("abcdef")
        XCTAssertEqual(apple.state, .code)
        XCTAssertEqual(fake.verifications, 0)
    }

    func testImpostorHelperIsRefused() async {
        let fake = FakeHelper(code: "246810")
        fake.lieAboutProof = true
        let apple = ApplePasswordsSession(makeLink: { fake })
        await apple.connect()
        await apple.enter("246810")
        XCTAssertEqual(apple.state, .idle)
        XCTAssertTrue(fake.stopped)
    }

    func testSignedOutOrHelperGoneDropsThePairing() async {
        let fake = FakeHelper(code: "246810")
        let apple = ApplePasswordsSession(makeLink: { fake })
        await apple.connect()
        await apple.enter("246810")
        XCTAssertEqual(apple.state, .paired)
        fake.onMessage?(["cmd": 10])
        XCTAssertEqual(apple.state, .idle)

        let again = FakeHelper(code: "111222")
        let other = ApplePasswordsSession(makeLink: { again })
        await other.connect()
        await other.enter("111222")
        XCTAssertEqual(other.state, .paired)
        again.onEnd?()
        XCTAssertEqual(other.state, .idle)
        let after = await other.logins(for: "example.test", tab: UUID())
        XCTAssertEqual(after, [])
    }

    func testHelperThatWontRunSaysSo() async {
        let apple = ApplePasswordsSession(makeLink: { throw ApplePasswordsSession.Unavailable(errorDescription: "Apple's Passwords helper isn't on this Mac") })
        await apple.connect()
        XCTAssertEqual(apple.state, .idle)
        XCTAssertEqual(apple.trouble, "Apple's Passwords helper isn't on this Mac")
    }

    func testOldHelperIsRefused() async {
        let fake = FakeHelper(code: "246810")
        fake.sessionVersion = 0
        let apple = ApplePasswordsSession(makeLink: { fake })
        await apple.connect()
        XCTAssertEqual(apple.state, .idle)
        XCTAssertEqual(fake.handshakes, 0)
    }

}

/// A helper made up in Swift: it pairs with `code`, keeps one account, and
/// says what it was asked. The server's side of SRP-6a: B = kv + gᵇ,
/// S = (A·vᵘ)ᵇ.
@MainActor
private final class FakeHelper: AppleLink {
    var onMessage: (([String: Any]) -> Void)?
    var onEnd: (() -> Void)?
    let code: String
    var sessionVersion = 1
    var lieAboutProof = false
    private(set) var handshakes = 0
    private(set) var verifications = 0
    private(set) var asked: [[String: Any]] = []
    private(set) var ended = false
    private(set) var stopped = false
    private var tid = ""
    private var a = SRPNumber(1), b = SRPNumber(1), v = SRPNumber(1)
    private var salt: [UInt8] = []
    private var key: SymmetricKey?

    init(code: String) { self.code = code }

    func start() throws {}
    func stop() { stopped = true }

    private static func hash(_ parts: [UInt8]...) -> [UInt8] {
        var hasher = SHA256()
        parts.forEach { hasher.update(data: $0) }
        return Array(hasher.finalize())
    }

    private func json(_ text: Any?) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data((text as? String ?? "").utf8))) as? [String: Any] ?? [:]
    }

    private func b64(_ object: [String: Any]) -> String {
        try! JSONSerialization.data(withJSONObject: object).base64EncodedString()
    }

    private func answer(_ reply: [String: Any]) {
        DispatchQueue.main.async { self.onMessage?(reply) }
    }

    func send(_ message: [String: Any]) throws {
        let mod = SRPClient.modulus, n = SRPClient.group, g = SRPClient.generator
        switch message["cmd"] as? Int {
        case 14:
            answer(["cmd": 14, "capabilities": ["shouldUseBase64": false, "secretSessionVersion": sessionVersion]])
        case 0:
            ended = true
        case 2:
            let msg = json(message["msg"])
            let pake = (try? JSONSerialization.jsonObject(with: Data(base64Encoded: msg["PAKE"] as! String)!)) as! [String: Any]
            if msg["QID"] as? String == "m0" {
                handshakes += 1
                tid = pake["TID"] as! String
                a = SRPNumber(hex: pake["A"] as! String)!
                salt = SRPClient.secureRandom(16)
                b = SRPNumber(bytes: SRPClient.secureRandom(32))
                let x = SRPNumber(bytes: Self.hash(salt, Self.hash(Array("\(tid):\(code)".utf8))))
                v = mod.power(g, x)
                let k = SRPNumber(bytes: Self.hash(n.bytes, g.padded(384)))
                var bigB = mod.multiply(k, v) + mod.power(g, b)
                if !(bigB < n) { bigB = bigB - n }
                answer(["cmd": 2, "payload": ["QID": "m0", "PAKE": b64(["TID": tid, "MSG": 1, "B": "0x" + Data(bigB.bytes).hexString,
                                                                    "s": "0x" + Data(salt).hexString, "PROTO": 1, "VER": "1.0"])]])
            } else {
                verifications += 1
                let k = SRPNumber(bytes: Self.hash(n.bytes, g.padded(384)))
                let bigB = SRPNumber(bytes: {
                    var x = mod.multiply(k, v) + mod.power(g, b)
                    if !(x < n) { x = x - n }
                    return x.bytes
                }())
                let u = SRPNumber(bytes: Self.hash(a.padded(384), bigB.padded(384)))
                let s = mod.power(mod.multiply(a, mod.power(v, u)), b)
                let sessionKey = Self.hash(s.bytes)
                let hn = Self.hash(n.bytes), hg = Self.hash(g.padded(384))
                let m = Self.hash(zip(hn, hg).map { $0 ^ $1 }, Self.hash(Array(tid.utf8)), salt, a.bytes, bigB.bytes, sessionKey)
                let theirs = [UInt8](Data(hexString: pake["M"] as! String)!)
                guard theirs == m else {
                    answer(["cmd": 2, "payload": ["QID": "m2", "PAKE": b64(["TID": tid, "MSG": 3, "ErrCode": 1])]])
                    return
                }
                key = SymmetricKey(data: sessionKey.prefix(16))
                var hamk = Self.hash(a.bytes, m, sessionKey)
                if lieAboutProof { hamk[0] ^= 1 }
                answer(["cmd": 2, "payload": ["QID": "m2", "PAKE": b64(["TID": tid, "MSG": 3, "ErrCode": 0,
                                                                    "HAMK": Data(hamk).hexString])]])
            }
        case let command? where command == 4 || command == 5:
            guard let key else { return }
            let payload = json(message["payload"])
            let smsg = json(payload["SMSG"])
            let sealed = [UInt8](Data(hexString: smsg["SDATA"] as! String)!)
            let iv = Array(sealed.suffix(16)), body = sealed.dropLast(16)
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: body.dropLast(16), tag: body.suffix(16))
            let question = json(String(decoding: try AES.GCM.open(box, using: key), as: UTF8.self))
            asked.append(question)
            var reply: [String: Any] = ["STATUS": 3]
            if command == 4 {
                reply = ["STATUS": 0, "Entries": [["USR": "ada@example.test", "sites": ["example.test"]]]]
            } else if question["USR"] as? String == "ada@example.test" {
                reply = ["STATUS": 0, "Entries": [["USR": "ada@example.test", "PWD": "made-up-secret", "sites": ["example.test"]]]]
            }
            let replyIV = SRPClient.secureRandom(16)
            let out = try AES.GCM.seal(try JSONSerialization.data(withJSONObject: reply), using: key, nonce: AES.GCM.Nonce(data: replyIV))
            let framed = replyIV + [UInt8](out.ciphertext) + [UInt8](out.tag)
            answer(["cmd": command, "payload": ["QID": payload["QID"] ?? "", "SMSG": ["TID": tid, "SDATA": Data(framed).hexString]]])
        default:
            break
        }
    }
}
#endif
