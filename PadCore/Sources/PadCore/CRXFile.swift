import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

/// A Chrome extension as the Chrome Web Store hands it out: a CRX3 file, a
/// signed header in front of a ZIP archive.
///
/// A Chrome extension's id is not a name anybody chose: it is the first 16
/// bytes of the SHA-256 of its developer's public key, written as letters a
/// to p (`ExtensionID`). So a file is taken only when its header carries a
/// key that makes the id that was asked for, every signature in the header
/// holds over the archive, and, for a file from the store, one of them is
/// Google's. A file altered on the way, or an extension passed off under
/// another's id, fails one or the other.
///
/// The rules are Chromium's (components/crx_file/crx_verifier.cc, BSD
/// licence): the layout, refusing a header that holds a ZIP end marker,
/// every proof checked rather than one, RSA PKCS#1 v1.5 or ECDSA P-256, both
/// over SHA-256. Apple's frameworks do the cryptography; where they aren't
/// (Linux), nothing passes.
public enum CRXFile {
    /// Why a file wasn't taken, in words for the person.
    public enum Refusal: Error, Equatable, Sendable {
        case notCRX
        case oldFormat
        case badHeader
        case noDeveloperKey
        case notFromStore
        case badSignature
        case cantCheckHere

        public var reason: String {
            switch self {
            case .notCRX: return "What came back isn't a Chrome extension."
            case .oldFormat: return "The extension is in an old format that Chrome itself no longer takes."
            case .badHeader: return "The extension's file is damaged."
            case .noDeveloperKey: return "The extension isn't signed by the developer of the extension that was asked for."
            case .notFromStore: return "The extension isn't signed by the Chrome Web Store."
            case .badSignature: return "The extension's signature doesn't hold up: the file was changed after it was signed."
            case .cantCheckHere: return "Signatures can't be checked on this system."
            }
        }
    }

    public enum ProofKind: Equatable, Sendable {
        case rsa
        case ecdsa
    }

    /// One signature in the header, with the public key it is checked
    /// against, as DER SubjectPublicKeyInfo.
    public struct Proof: Equatable, Sendable {
        public var kind: ProofKind
        public var publicKey: Data
        public var signature: Data
    }

    /// The header, read but not yet checked.
    public struct Header: Equatable, Sendable {
        public var proofs: [Proof]
        /// The signed part of the header, a SignedData message, as it is in
        /// the file: the signatures cover these very bytes.
        public var signedData: Data
        /// The id the signed part says the file is for, or nil when it
        /// carries none.
        public var declaredID: String?
        /// Where the ZIP archive starts.
        public var archiveStart: Int
    }

    /// SHA-256 of Google's own key, "ecdsa_2017_public", whose proof every
    /// file from the Chrome Web Store carries (Chromium's kPublisherKeyHash).
    public static let storeKeyHash: [UInt8] = [
        0x61, 0xF7, 0xF2, 0xA6, 0xBF, 0xCF, 0x74, 0xCD, 0x0B, 0xC1, 0xFE,
        0x24, 0x97, 0xCC, 0x9B, 0x04, 0x25, 0x4C, 0x65, 0x8F, 0x79, 0xF2,
        0x14, 0x53, 0x92, 0x86, 0x7E, 0xA8, 0x36, 0x63, 0x67, 0xCF,
    ]

    /// Whether `data` starts the way a CRX file does.
    public static func isCRX(_ data: Data) -> Bool {
        data.count >= 4 && [UInt8](data.prefix(4)) == magic
    }

    static let magic: [UInt8] = Array("Cr24".utf8)
    static let signedPrefix: [UInt8] = Array("CRX3 SignedData".utf8) + [0]

    /// ZIP's end-of-directory markers. An archive is read from its end, so
    /// one inside the header could make the header itself read as the
    /// archive: Chromium refuses those.
    static let endMarkers: [[UInt8]] = [
        [0x50, 0x4B, 0x05, 0x06], [0x50, 0x4B, 0x06, 0x07], [0x50, 0x4B, 0x06, 0x06],
    ]

    /// The header of a CRX3 file, its layout checked; the signatures are
    /// left for `archive(of:id:fromStore:)`.
    public static func header(of data: Data) throws -> Header {
        let first = [UInt8](data.prefix(12))
        guard first.count == 12, Array(first[0..<4]) == magic else { throw Refusal.notCRX }
        guard let version = le32(first, 4), version == 3 else { throw Refusal.oldFormat }
        guard let length = le32(first, 8), Int(length) <= data.count - 12, Int(length) <= largestHeader else {
            throw Refusal.badHeader
        }
        let start = data.startIndex.advanced(by: 12)
        let header = [UInt8](data[start..<start.advanced(by: Int(length))])
        guard !endMarkers.contains(where: { contains(header, $0) }) else { throw Refusal.badHeader }
        guard let fields = Protobuf.fields(header) else { throw Refusal.badHeader }

        var proofs: [Proof] = []
        var signedData: [UInt8]?
        for field in fields {
            switch field.number {
            case 2, 3:
                guard proofs.count < mostProofs, let parts = Protobuf.fields(field.bytes) else { throw Refusal.badHeader }
                let key = parts.last { $0.number == 1 }?.bytes ?? []
                let signature = parts.last { $0.number == 2 }?.bytes ?? []
                proofs.append(Proof(kind: field.number == 2 ? .rsa : .ecdsa, publicKey: Data(key), signature: Data(signature)))
            case 10000:
                signedData = field.bytes
            default:
                continue
            }
        }
        let signed = signedData ?? []
        guard let parts = Protobuf.fields(signed) else { throw Refusal.badHeader }
        let declared = parts.last { $0.number == 1 }.flatMap { $0.bytes.count == 16 ? ExtensionID.letters($0.bytes) : nil }
        return Header(proofs: proofs, signedData: Data(signed), declaredID: declared, archiveStart: 12 + Int(length))
    }

    /// A store file's header holds two proofs and a compressed list of its
    /// files' hashes, tens of kilobytes; nothing near this is real, and a
    /// header is read before anything in it is checked.
    static let largestHeader = 8 * 1024 * 1024
    static let mostProofs = 16

    /// What every proof in the file signs: a fixed prefix, the signed
    /// part's length in four little-endian bytes, the signed part, and the
    /// whole archive.
    public static func signedBytes(_ header: Header, in data: Data) -> Data {
        var message = Data(signedPrefix)
        let count = UInt32(header.signedData.count)
        message.append(contentsOf: [UInt8(count & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count >> 16 & 0xFF), UInt8(count >> 24)])
        message.append(header.signedData)
        message.append(data[data.startIndex.advanced(by: header.archiveStart)...])
        return message
    }

    /// The ZIP archive inside a CRX3 file, once the file is shown to be the
    /// extension `id`, signed by its developer and unchanged since; with
    /// `fromStore`, signed by the Chrome Web Store too. Store files must
    /// pass with it; a file the person chose (Install from File) passes
    /// without.
    public static func archive(of data: Data, id: String, fromStore: Bool) throws -> Data {
        let header = try Self.header(of: data)
        #if canImport(CryptoKit) && canImport(Security)
        guard header.declaredID == id,
              header.proofs.contains(where: { ExtensionID.id(forPublicKey: $0.publicKey) == id })
        else { throw Refusal.noDeveloperKey }
        if fromStore {
            guard header.proofs.contains(where: { Array(SHA256.hash(data: $0.publicKey)) == storeKeyHash })
            else { throw Refusal.notFromStore }
        }
        let message = signedBytes(header, in: data)
        for proof in header.proofs {
            guard holds(proof, over: message) else { throw Refusal.badSignature }
        }
        return Data(data[data.startIndex.advanced(by: header.archiveStart)...])
        #else
        throw Refusal.cantCheckHere
        #endif
    }

    #if canImport(CryptoKit) && canImport(Security)
    static func holds(_ proof: Proof, over message: Data) -> Bool {
        switch proof.kind {
        case .ecdsa:
            guard let key = try? P256.Signing.PublicKey(derRepresentation: proof.publicKey),
                  let signature = try? P256.Signing.ECDSASignature(derRepresentation: proof.signature)
            else { return false }
            return key.isValidSignature(signature, for: message)
        case .rsa:
            // Security takes an RSA key as PKCS#1, the inside of the
            // SubjectPublicKeyInfo Chrome writes.
            guard let pkcs1 = DER.rsaPublicKey(inSubjectPublicKeyInfo: [UInt8](proof.publicKey)) else { return false }
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
            guard let key = SecKeyCreateWithData(Data(pkcs1) as CFData, attributes as CFDictionary, nil) else { return false }
            return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, proof.signature as CFData, nil)
        }
    }
    #endif

    // MARK: Bytes

    static func le32(_ bytes: [UInt8], _ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= bytes.count else { return nil }
        return UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }

    static func contains(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, bytes.count >= needle.count else { return false }
        return (0...(bytes.count - needle.count)).contains { start in
            needle.indices.allSatisfy { bytes[start + $0] == needle[$0] }
        }
    }
}

/// Just enough of Protocol Buffers' wire format to read a CRX header: its
/// fields are all length-delimited; the others are stepped over. What
/// protobuf itself refuses is refused: varints past 64 bits, lengths past
/// 2 GB, field numbers past 2^29 - 1.
enum Protobuf {
    struct Field: Equatable {
        var number: Int
        var bytes: [UInt8]
    }

    /// A header has a handful of fields; a message with more is not one,
    /// and is not worth holding in memory to find out.
    static let mostFields = 64

    /// The length-delimited fields of a message, in order; nil when the
    /// message is cut short or isn't one.
    static func fields(_ bytes: [UInt8]) -> [Field]? {
        var fields: [Field] = []
        var count = 0
        var at = 0
        while at < bytes.count {
            count += 1
            guard count <= mostFields, let key = varint(bytes, &at), key <= UInt64(UInt32.max) else { return nil }
            let number = Int(key >> 3)
            guard (1...536_870_911).contains(number) else { return nil }
            switch key & 7 {
            case 0:
                guard varint(bytes, &at) != nil else { return nil }
            case 1:
                guard bytes.count - at >= 8 else { return nil }
                at += 8
            case 2:
                guard let length = varint(bytes, &at), length <= UInt64(Int32.max), length <= UInt64(bytes.count - at) else { return nil }
                fields.append(Field(number: number, bytes: Array(bytes[at..<(at + Int(length))])))
                at += Int(length)
            case 5:
                guard bytes.count - at >= 4 else { return nil }
                at += 4
            default:
                return nil
            }
        }
        return fields
    }

    /// At most ten bytes, the tenth holding only the 64th bit.
    static func varint(_ bytes: [UInt8], _ at: inout Int) -> UInt64? {
        var value: UInt64 = 0
        for index in 0..<10 {
            guard at < bytes.count else { return nil }
            let byte = bytes[at]
            at += 1
            if index == 9, byte > 1 { return nil }
            value |= UInt64(byte & 0x7F) << UInt64(7 * index)
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }
}

/// Just enough DER to take an RSA key out of a SubjectPublicKeyInfo, read
/// as strictly as Chromium's BoringSSL reads it: the algorithm exactly
/// rsaEncryption with NULL parameters, lengths in their shortest form,
/// nothing left over.
enum DER {
    /// rsaEncryption, 1.2.840.113549.1.1.1.
    static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

    /// The PKCS#1 RSAPublicKey inside `spki`, when it is an RSA key.
    static func rsaPublicKey(inSubjectPublicKeyInfo spki: [UInt8]) -> [UInt8]? {
        var at = 0
        guard let outer = element(spki, &at), outer.tag == 0x30, at == spki.count else { return nil }
        let body = outer.content
        var inBody = 0
        guard let algorithm = element(body, &inBody), algorithm.tag == 0x30 else { return nil }
        var inAlgorithm = 0
        guard let oid = element(algorithm.content, &inAlgorithm), oid.tag == 0x06, oid.content == rsaEncryption,
              let parameters = element(algorithm.content, &inAlgorithm), parameters.tag == 0x05, parameters.content.isEmpty,
              inAlgorithm == algorithm.content.count
        else { return nil }
        guard let key = element(body, &inBody), key.tag == 0x03, inBody == body.count,
              let unused = key.content.first, unused == 0
        else { return nil }
        return Array(key.content.dropFirst())
    }

    struct Element {
        var tag: UInt8
        var content: [UInt8]
    }

    /// One tag-length-value at `at`, which moves past it. A length in the
    /// long form must need it: no leading zero, nothing under 128.
    static func element(_ bytes: [UInt8], _ at: inout Int) -> Element? {
        guard at + 2 <= bytes.count else { return nil }
        let tag = bytes[at]
        var length = Int(bytes[at + 1])
        at += 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), at + count <= bytes.count, bytes[at] != 0 else { return nil }
            length = 0
            for byte in bytes[at..<(at + count)] { length = length << 8 | Int(byte) }
            guard length >= 0x80 else { return nil }
            at += count
        }
        guard length <= bytes.count - at else { return nil }
        defer { at += length }
        return Element(tag: tag, content: Array(bytes[at..<(at + length)]))
    }
}
