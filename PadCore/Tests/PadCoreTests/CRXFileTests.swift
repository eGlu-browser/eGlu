import XCTest
@testable import PadCore
#if canImport(CryptoKit) && canImport(Security)
import CryptoKit
import Security
#endif

final class CRXFileTests: XCTestCase {
    func testLettersAreHalfBytesFromAToP() {
        XCTAssertEqual(ExtensionID.letters([0x00, 0x1F, 0xFF]), "aabppp")
        XCTAssertTrue(ExtensionID.isValid(String(repeating: "p", count: 32)))
        XCTAssertFalse(ExtensionID.isValid(String(repeating: "q", count: 32)), "q is past p")
        XCTAssertFalse(ExtensionID.isValid(String(repeating: "a", count: 31)))
    }

    func testAnythingButCRX3IsRefusedBeforeItsSignatures() {
        XCTAssertThrowsError(try CRXFile.header(of: Data("PK\u{3}\u{4}".utf8))) { XCTAssertEqual($0 as? CRXFile.Refusal, .notCRX) }
        XCTAssertThrowsError(try CRXFile.header(of: Data("Cr24".utf8) + le32(2) + le32(0))) { XCTAssertEqual($0 as? CRXFile.Refusal, .oldFormat) }
        // A header longer than the file.
        XCTAssertThrowsError(try CRXFile.header(of: Data("Cr24".utf8) + le32(3) + le32(100))) { XCTAssertEqual($0 as? CRXFile.Refusal, .badHeader) }
        // A length that would overflow.
        XCTAssertThrowsError(try CRXFile.header(of: Data("Cr24".utf8) + le32(3) + le32(0xFFFF_FFFF))) { XCTAssertEqual($0 as? CRXFile.Refusal, .badHeader) }
    }

    func testAHeaderHoldingAZipEndMarkerIsRefused() {
        // A field carrying ZIP's end-of-directory marker: an unzipper reading
        // from the end could take the header for the archive.
        let header = field(4, Data([0x50, 0x4B, 0x05, 0x06]))
        let file = Data("Cr24".utf8) + le32(3) + le32(UInt32(header.count)) + header + Data("PK\u{3}\u{4}".utf8)
        XCTAssertThrowsError(try CRXFile.header(of: file)) { XCTAssertEqual($0 as? CRXFile.Refusal, .badHeader) }
    }

    func testACutShortHeaderIsRefused() {
        // A length-delimited field that says it is longer than what follows.
        let header = Data([0x12, 0x40, 0x01])
        let file = Data("Cr24".utf8) + le32(3) + le32(UInt32(header.count)) + header
        XCTAssertThrowsError(try CRXFile.header(of: file)) { XCTAssertEqual($0 as? CRXFile.Refusal, .badHeader) }
    }

    func testALengthPastWhatProtobufAllowsIsRefused() {
        // A length-delimited field whose length takes ten bytes and wraps.
        let header = Data([0x22] + [UInt8](repeating: 0x80, count: 9) + [0x02])
        let file = Data("Cr24".utf8) + le32(3) + le32(UInt32(header.count)) + header
        XCTAssertThrowsError(try CRXFile.header(of: file)) { XCTAssertEqual($0 as? CRXFile.Refusal, .badHeader) }
    }

    func testAHeaderOfManyEmptyFieldsIsRefusedBeforeItIsHeld() {
        // Millions of empty proofs, before any signature could be checked.
        let header = Data([UInt8](repeating: 0, count: 200_000).enumerated().map { $0.offset % 2 == 0 ? 0x12 : 0x00 })
        let file = Data("Cr24".utf8) + le32(3) + le32(UInt32(header.count)) + header
        XCTAssertThrowsError(try CRXFile.header(of: file)) { XCTAssertEqual($0 as? CRXFile.Refusal, .badHeader) }
        // And a header said to be larger than any real one.
        let huge = Data("Cr24".utf8) + le32(3) + le32(UInt32(CRXFile.largestHeader + 1)) + Data(count: CRXFile.largestHeader + 1)
        XCTAssertThrowsError(try CRXFile.header(of: huge)) { XCTAssertEqual($0 as? CRXFile.Refusal, .badHeader) }
    }

    func testVarintsPastSixtyFourBitsAreRefused() {
        var at = 0
        XCTAssertNil(Protobuf.varint([UInt8](repeating: 0xFF, count: 11), &at))
    }

    func testTheRSAKeyComesOutOfItsSubjectPublicKeyInfo() {
        let pkcs1: [UInt8] = [0x30, 0x03, 0x02, 0x01, 0x05]
        XCTAssertEqual(DER.rsaPublicKey(inSubjectPublicKeyInfo: spki(rsa: pkcs1)), pkcs1)
        // An EC key's algorithm isn't rsaEncryption.
        var ec = spki(rsa: pkcs1)
        ec[6 + 8] = 0x02
        XCTAssertNil(DER.rsaPublicKey(inSubjectPublicKeyInfo: ec))
        XCTAssertNil(DER.rsaPublicKey(inSubjectPublicKeyInfo: Array(spki(rsa: pkcs1).dropLast())), "cut short")
        // Parameters other than NULL, as BoringSSL refuses them.
        var withInteger = spki(rsa: pkcs1)
        let null = withInteger.firstIndex(of: 0x05)!
        withInteger.replaceSubrange(null..<(null + 2), with: [0x02, 0x01, 0x01])
        withInteger[1] += 1
        withInteger[3] += 1
        XCTAssertNil(DER.rsaPublicKey(inSubjectPublicKeyInfo: withInteger))
        // A length in the long form that didn't need it.
        var longForm = spki(rsa: pkcs1)
        longForm.replaceSubrange(1..<2, with: [0x81, longForm[1]])
        XCTAssertNil(DER.rsaPublicKey(inSubjectPublicKeyInfo: longForm))
    }

    #if canImport(CryptoKit) && canImport(Security)
    func testADeveloperSignedFileGivesItsArchive() throws {
        let developer = try RSAKey()
        let crx = try make(archive: archive, id: developer.id, signers: [developer])
        XCTAssertEqual(try CRXFile.archive(of: crx, id: developer.id, fromStore: false), archive)
    }

    func testAnECDSADeveloperKeyWorksToo() throws {
        let developer = ECKey()
        let crx = try make(archive: archive, id: developer.id, signers: [developer])
        XCTAssertEqual(try CRXFile.archive(of: crx, id: developer.id, fromStore: false), archive)
    }

    func testAnotherExtensionsIDIsRefused() throws {
        let developer = try RSAKey()
        let impostor = try RSAKey()
        // Signed by its own key, claiming another's id.
        let crx = try make(archive: archive, id: developer.id, signers: [impostor])
        XCTAssertThrowsError(try CRXFile.archive(of: crx, id: developer.id, fromStore: false)) {
            XCTAssertEqual($0 as? CRXFile.Refusal, .noDeveloperKey)
        }
        // And a true file asked for as another extension.
        let own = try make(archive: archive, id: impostor.id, signers: [impostor])
        XCTAssertThrowsError(try CRXFile.archive(of: own, id: developer.id, fromStore: false)) {
            XCTAssertEqual($0 as? CRXFile.Refusal, .noDeveloperKey)
        }
    }

    func testAChangedArchiveIsRefused() throws {
        let developer = try RSAKey()
        var crx = try make(archive: archive, id: developer.id, signers: [developer])
        crx[crx.count - 1] ^= 0x01
        XCTAssertThrowsError(try CRXFile.archive(of: crx, id: developer.id, fromStore: false)) {
            XCTAssertEqual($0 as? CRXFile.Refusal, .badSignature)
        }
    }

    func testEveryProofMustHoldNotOnlyTheDevelopers() throws {
        // Chrome checks every signature; Search checked only the
        // developer's. A second proof that doesn't hold fails the file.
        let developer = try RSAKey()
        let other = ECKey()
        let crx = try make(archive: archive, id: developer.id, signers: [developer, other], spoil: 1)
        XCTAssertThrowsError(try CRXFile.archive(of: crx, id: developer.id, fromStore: false)) {
            XCTAssertEqual($0 as? CRXFile.Refusal, .badSignature)
        }
    }

    func testAStoreInstallNeedsGooglesProof() throws {
        let developer = try RSAKey()
        let notGoogle = ECKey()
        let crx = try make(archive: archive, id: developer.id, signers: [developer, notGoogle])
        XCTAssertThrowsError(try CRXFile.archive(of: crx, id: developer.id, fromStore: true)) {
            XCTAssertEqual($0 as? CRXFile.Refusal, .notFromStore)
        }
        XCTAssertNoThrow(try CRXFile.archive(of: crx, id: developer.id, fromStore: false), "a file the person chose needs only its developer's")
    }

    func testTheIDIsTheKeysDigestAndAPathsForAFolder() {
        let key = Data("key".utf8)
        XCTAssertEqual(ExtensionID.id(forPublicKey: key), ExtensionID.letters(Array(SHA256.hash(data: key)).prefix(16)))
        XCTAssertTrue(ExtensionID.isValid(ExtensionID.id(forUnpackedPath: "/Users/someone/ext")))
        XCTAssertNotEqual(ExtensionID.id(forUnpackedPath: "/a"), ExtensionID.id(forUnpackedPath: "/b"))
    }

    // MARK: Making files

    private let archive = Data("PK\u{3}\u{4}an archive's bytes".utf8)

    private struct RSAKey: CRXSigner {
        let key: SecKey
        let publicKey: Data
        let kind = 2

        init() throws {
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
                  let pub = SecKeyCopyPublicKey(key),
                  let pkcs1 = SecKeyCopyExternalRepresentation(pub, &error) as Data?
            else { throw error!.takeRetainedValue() }
            self.key = key
            publicKey = Data(CRXFileTests.spki(rsa: [UInt8](pkcs1)))
        }

        var id: String { ExtensionID.id(forPublicKey: publicKey) }

        func sign(_ message: Data) throws -> Data {
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) as Data?
            else { throw error!.takeRetainedValue() }
            return signature
        }
    }

    private struct ECKey: CRXSigner {
        let key = P256.Signing.PrivateKey()
        var publicKey: Data { key.publicKey.derRepresentation }
        let kind = 3
        var id: String { ExtensionID.id(forPublicKey: publicKey) }

        func sign(_ message: Data) throws -> Data {
            try key.signature(for: message).derRepresentation
        }
    }

    /// A CRX3 file signed by `signers`, for `id`; `spoil` names a signer
    /// whose signature is made over something else.
    private func make(archive: Data, id: String, signers: [CRXSigner], spoil: Int? = nil) throws -> Data {
        let idBytes = Data(id.utf8.map { $0 - UInt8(ascii: "a") }.chunked(2).map { $0[0] << 4 | $0[1] })
        let signed = field(1, idBytes)
        var message = Data("CRX3 SignedData".utf8) + Data([0]) + le32(UInt32(signed.count)) + signed + archive
        var header = Data()
        for (index, signer) in signers.enumerated() {
            if index == spoil { message.append(0) }
            let signature = try signer.sign(message)
            if index == spoil { message.removeLast() }
            header += field(signer.kind, field(1, signer.publicKey) + field(2, signature))
        }
        header += field(10000, signed)
        return Data("Cr24".utf8) + le32(3) + le32(UInt32(header.count)) + header + archive
    }
    #endif

    // MARK: Bytes

    private func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)])
    }

    private func field(_ number: Int, _ bytes: Data) -> Data {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes
    }

    private func varint(_ value: UInt64) -> Data {
        var value = value
        var out = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    /// A SubjectPublicKeyInfo around an RSA key, as Chrome writes them.
    static func spki(rsa pkcs1: [UInt8]) -> [UInt8] {
        let algorithm: [UInt8] = [0x30, 0x0D, 0x06, 0x09] + DER.rsaEncryption + [0x05, 0x00]
        let bits: [UInt8] = [0x03] + length(pkcs1.count + 1) + [0x00] + pkcs1
        let body = algorithm + bits
        return [0x30] + length(body.count) + body
    }

    private func spki(rsa pkcs1: [UInt8]) -> [UInt8] { Self.spki(rsa: pkcs1) }

    static func length(_ count: Int) -> [UInt8] {
        if count < 0x80 { return [UInt8(count)] }
        if count < 0x100 { return [0x81, UInt8(count)] }
        return [0x82, UInt8(count >> 8), UInt8(count & 0xFF)]
    }
}

#if canImport(CryptoKit) && canImport(Security)
/// Something that signs a CRX: its key, which list its proof goes in (2 for
/// RSA, 3 for ECDSA), and its signature.
private protocol CRXSigner {
    var publicKey: Data { get }
    var kind: Int { get }
    func sign(_ message: Data) throws -> Data
}
#endif

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
