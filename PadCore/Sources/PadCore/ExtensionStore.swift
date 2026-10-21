import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// A Chrome extension's id: 32 letters from a to p.
public enum ExtensionID {
    /// The letters for some bytes: each half-byte a letter, a for 0 to p
    /// for 15.
    public static func letters(_ bytes: some Sequence<UInt8>) -> String {
        String(bytes.flatMap { [$0 >> 4, $0 & 0x0F] }.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
    }

    public static func isValid(_ text: String) -> Bool {
        text.utf8.count == 32 && text.utf8.allSatisfy { (UInt8(ascii: "a")...UInt8(ascii: "p")).contains($0) }
    }

    /// The first id in some text: a bare id, a store link, an old
    /// chrome.google.com/webstore link. Not part of a longer run of
    /// letters.
    public static func first(in text: String) -> String? {
        let letters = Array(text.lowercased().utf8)
        var run = 0
        for (index, byte) in letters.enumerated() {
            let isLetter = (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            let isID = (UInt8(ascii: "a")...UInt8(ascii: "p")).contains(byte)
            run = isID ? run + 1 : 0
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            let endsHere = next.map { !(UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) } ?? true
            if run == 32, endsHere, isLetter {
                let start = index - 31
                let before = start > 0 ? letters[start - 1] : nil
                guard before.map({ !(UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0) }) ?? true else { continue }
                return String(decoding: letters[start...index], as: UTF8.self)
            }
        }
        return nil
    }

    #if canImport(CryptoKit)
    /// The id a public key makes: the first 16 bytes of its SHA-256.
    public static func id(forPublicKey key: Data) -> String {
        letters(Array(SHA256.hash(data: key)).prefix(16))
    }

    /// The id Chrome gives a folder loaded unpacked, from its path, as
    /// Chrome does: the folder's real path, links resolved, is the caller's
    /// to give. Native messaging hosts made for such a folder list this id.
    public static func id(forUnpackedPath path: String) -> String {
        letters(Array(SHA256.hash(data: Data(path.utf8))).prefix(16))
    }
    #endif
}

/// The Chrome Web Store, as every Chromium browser asks it: its pages for
/// an extension, the address a package comes from, and the update check.
public enum ExtensionStore {
    /// The version of Chrome the store is told it is talking to. The store
    /// won't hand out an extension whose minimum Chrome is newer, nor
    /// anything at all below 88; raised with releases.
    public static let chromeVersion = "140.0.0.0"

    static let endpoint = "https://clients2.google.com/service/update2/crx"

    /// The extension a store page is about: the id in its /detail/ path and
    /// nowhere else, so the listing the page shows is the one installed.
    /// Only on the store itself, over https, with no one's name before its
    /// host.
    public static func id(ofPage url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = Hosts.host(of: url)
        else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let detail: ArraySlice<String>
        switch host {
        case "chromewebstore.google.com":
            guard parts.first == "detail" else { return nil }
            detail = parts.dropFirst()
        case "chrome.google.com":
            guard parts.count > 1, parts[0] == "webstore", parts[1] == "detail" else { return nil }
            detail = parts.dropFirst(2)
        default:
            return nil
        }
        // /detail/<name>/<id> or /detail/<id>, and anything after either.
        // The name goes first when there is one: a name could itself be 32
        // letters from a to p, and isn't the id for being so.
        let segments = Array(detail.prefix(2))
        if segments.count == 2, ExtensionID.isValid(segments[1]) { return segments[1] }
        return segments.first.flatMap { ExtensionID.isValid($0) ? $0 : nil }
    }

    /// Where the package for `id` comes from: the store answers with a
    /// redirect to the file.
    public static func packageURL(for id: String) -> URL {
        var parts = URLComponents(string: endpoint)!
        parts.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&installsource=ondemand&uc"),
        ]
        return parts.url!
    }

    /// The update check: one request for many extensions, each its id and
    /// the version installed. Split so that no address gets long enough for
    /// a server to refuse it.
    public static func updateCheckURLs(for installed: [(id: String, version: ExtensionVersion)], longest: Int = 2000) -> [URL] {
        func url(_ batch: [(id: String, version: ExtensionVersion)]) -> URL {
            var parts = URLComponents(string: endpoint)!
            parts.queryItems = [
                URLQueryItem(name: "prodversion", value: chromeVersion),
                URLQueryItem(name: "acceptformat", value: "crx3"),
            ] + batch.map { URLQueryItem(name: "x", value: "id=\($0.id)&v=\($0.version)&uc") }
            return parts.url!
        }
        var urls: [URL] = []
        var batch: [(id: String, version: ExtensionVersion)] = []
        for item in installed {
            if !batch.isEmpty, url(batch + [item]).absoluteString.count > longest {
                urls.append(url(batch))
                batch = []
            }
            batch.append(item)
        }
        if !batch.isEmpty { urls.append(url(batch)) }
        return urls
    }

    /// Whether a package may be fetched from `url`: over https, from
    /// Google's own hosts, where the store's update replies point.
    public static func isPackageHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = Hosts.host(of: url)
        else { return false }
        return ["google.com", "googleusercontent.com", "gvt1.com"].contains { Hosts.host(host, isWithin: $0) }
    }
}

/// An extension's version as Chrome reads it: one to four whole numbers
/// with dots between, compared one by one, a missing one counting as 0, so
/// 1.2 and 1.2.0 are the same version. The first has no leading zero.
public struct ExtensionVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [UInt32]

    public init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [UInt32] = []
        for (index, piece) in pieces.enumerated() {
            guard !piece.isEmpty, piece.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
                  let number = UInt32(piece),
                  index > 0 || String(number) == piece
            else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    /// The parts without the zeros at the end, which change nothing.
    private var significant: ArraySlice<UInt32> {
        var parts = self.parts[...]
        while parts.last == 0 { parts = parts.dropLast() }
        return parts
    }

    public static func < (a: ExtensionVersion, b: ExtensionVersion) -> Bool {
        for index in 0..<max(a.parts.count, b.parts.count) {
            let x = index < a.parts.count ? a.parts[index] : 0
            let y = index < b.parts.count ? b.parts[index] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: ExtensionVersion, b: ExtensionVersion) -> Bool {
        a.significant == b.significant
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Array(significant))
    }
}

/// What the store's update check says of one extension.
public struct ExtensionUpdate: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case newer
        case current
        /// The store's own word for what went wrong, as "error-unknownApplication".
        case refused(String)
    }

    public var id: String
    public var status: Status
    public var version: ExtensionVersion?
    public var package: URL?
    public var sha256: String?
    public var size: Int?
}

/// The store's reply to an update check: `<gupdate>` XML in Google's
/// namespace, protocol 2.0, an `<app>` for each extension asked about and
/// an `<updatecheck>` in each (Chromium's
/// extensions/browser/updater/safe_manifest_parser.cc). The namespace may
/// come with a prefix, `<g:gupdate>`, as Chromium allows.
public enum ExtensionUpdateReply {
    static let namespace = "http://www.google.com/update2/response"

    public static func parse(_ data: Data) -> [ExtensionUpdate] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse(), reader.isGupdate else { return [] }
        return reader.updates
    }

    final class Reader: NSObject, XMLParserDelegate {
        var updates: [ExtensionUpdate] = []
        var isGupdate = false
        private var app: String?
        private var appStatus: String?
        private var answered = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard namespaceURI == ExtensionUpdateReply.namespace else { return }
            switch name {
            case "gupdate":
                isGupdate = attributes["protocol"] == "2.0"
            case "app":
                app = attributes["appid"]
                appStatus = attributes["status"]
                answered = false
            case "updatecheck":
                guard let id = app, ExtensionID.isValid(id), !answered else { return }
                answered = true
                updates.append(Self.update(id: id, appStatus: appStatus, attributes))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard name == "app", namespaceURI == ExtensionUpdateReply.namespace else { return }
            if let id = app, ExtensionID.isValid(id), !answered {
                updates.append(ExtensionUpdate(id: id, status: .refused(appStatus ?? "error"), version: nil, package: nil, sha256: nil, size: nil))
            }
            app = nil
        }

        static func update(id: String, appStatus: String?, _ attributes: [String: String]) -> ExtensionUpdate {
            let status = attributes["status"] ?? appStatus ?? "error"
            var update = ExtensionUpdate(id: id, status: .refused(status), version: nil, package: nil, sha256: nil, size: nil)
            switch status {
            case "noupdate":
                update.status = .current
            case "ok":
                guard let version = attributes["version"].flatMap(ExtensionVersion.init),
                      let package = attributes["codebase"].flatMap(URL.init(string:)),
                      ExtensionStore.isPackageHost(package)
                else { return update }
                update.status = .newer
                update.version = version
                update.package = package
                update.sha256 = attributes["hash_sha256"]?.lowercased()
                update.size = attributes["size"].flatMap { Int($0) }
            default:
                break
            }
            return update
        }
    }
}
