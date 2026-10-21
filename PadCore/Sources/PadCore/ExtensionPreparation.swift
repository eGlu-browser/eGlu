import Foundation

/// Making an extension's verified package into the folder WebKit loads:
/// the shim (Scripts/extension-shim.js) put first in its worker, its
/// background scripts, its content scripts and its pages.
///
/// The verified original is kept as it came; this works on a fresh copy of
/// it, made again whenever the shim changes, so nothing is ever patched
/// twice and nothing the extension ships is lost.
public enum ExtensionPreparation {
    /// Where the shim goes in the folder. A package that brings a file of
    /// its own there isn't taken.
    public static let shimFile = "_safience/shim.js"
    /// What the folder was made from, the shim and the package: one made
    /// from others, or by an older preparation, is made again.
    public static let stampFile = "_safience/stamp"

    /// Raised when this file changes what it makes.
    static let version = 1

    static let shimMarks = ("/* Safience's shim, before the extension's own code (ExtensionPreparation) */",
                            "/* The extension's own code */")

    public enum Problem: Error, Equatable, Sendable {
        /// A name that leads out of the folder, or into Safience's part of it.
        case unsafeName(String)
        case tooLarge
        /// A file the archive holds that can't be unpacked here: encrypted,
        /// or packed in a way other than stored or deflated.
        case unreadable(String)
        case noManifest
        /// Two names that are one file on a Mac's disk, the second of which
        /// would be written over the first.
        case sameFile(String)
        /// A symbolic link: what it leads to isn't the package's.
        case link(String)
    }

    /// Every file of the folder, one at a time, as `write` takes them: the
    /// package's own, the manifest and the scripts and pages edited, then
    /// the shim, and `stamp` last. Throws before writing anything when a
    /// name or a size is wrong.
    public static func prepare(_ archive: Data, shim: String, stamp: String,
                               write: (_ path: String, _ data: Data) throws -> Void) throws {
        let bytes = [UInt8](archive)
        let entries = ZipFile.entries(in: bytes)
        try check(entries)
        guard let manifestEntry = entries.first(where: { $0.name == "manifest.json" }),
              let manifestData = ZipFile.unpack(manifestEntry, from: bytes)
        else { throw Problem.noManifest }
        let edited = try manifest(manifestData)
        let worker = edited.worker.map { normalized($0.path) }
        let shim = filled(shim, scripts: scriptList(entries, in: bytes), added: edited.added)
        for entry in entries where !entry.name.hasSuffix("/") {
            guard var data = ZipFile.unpack(entry, from: bytes) else { throw Problem.unreadable(entry.name) }
            if entry.name == "manifest.json" {
                data = edited.manifest
            } else if entry.name == worker {
                data = Self.worker(data, shim: shim, module: edited.worker?.module == true)
            } else if isPage(entry.name), let html = String(data: data, encoding: .utf8) {
                data = Data(page(html).utf8)
            }
            try write(entry.name, data)
        }
        try write(shimFile, Data(shim.utf8))
        try write(stampFile, Data(stamp.utf8))
    }

    /// The shim with what it is told of this extension written in: its
    /// scripts, for the worker's importScripts (an empty one marked "-"),
    /// the permissions the preparation added to its manifest, and the
    /// Chrome it says it is.
    static func filled(_ shim: String, scripts: [String], added: [String] = []) -> String {
        func json(_ list: [String]) -> String {
            (try? JSONSerialization.data(withJSONObject: list, options: [.withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        }
        return shim.replacingOccurrences(of: "/*__SAFIENCE_SCRIPTS__*/null", with: json(scripts))
            .replacingOccurrences(of: "/*__SAFIENCE_ADDED__*/[]", with: json(added))
            .replacingOccurrences(of: "__SAFIENCE_CHROME__", with: ExtensionStore.chromeVersion)
    }

    /// Every script in the package, as an address path: "/bg.js". One with
    /// nothing in it but space is "-/test.js".
    static func scriptList(_ entries: [ZipFile.Entry], in bytes: [UInt8]) -> [String] {
        entries.compactMap { entry -> String? in
            let lower = entry.name.lowercased()
            guard !entry.name.hasSuffix("/"), lower.hasSuffix(".js") || lower.hasSuffix(".mjs") else { return nil }
            // Only a small one can be empty of all but space.
            let blank = entry.size < 256 && (ZipFile.unpack(entry, from: bytes).map {
                String(decoding: $0, as: UTF8.self).allSatisfy(\.isWhitespace)
            } ?? false)
            return (blank ? "-/" : "/") + entry.name
        }
    }

    /// Larger unpacked than any store extension measured (Bitwarden, 25 MB
    /// packed) by far.
    static let largestUnpacked = 512 * 1024 * 1024

    static func check(_ entries: [ZipFile.Entry]) throws {
        if let bad = entries.first(where: { !isSafe(name: $0.name) }) { throw Problem.unsafeName(bad.name) }
        if let same = sameFile(in: entries.map(\.name)) { throw Problem.sameFile(same) }
        if let link = entries.first(where: \.isLink) { throw Problem.link(link.name) }
        // What is written is what each entry says it holds: a stored one
        // that says less than it has isn't unpacked (ZipFile.unpack).
        guard entries.reduce(0, { $0 + $1.size }) <= largestUnpacked,
              entries.allSatisfy({ $0.size <= ZipFile.largest })
        else { throw Problem.tooLarge }
    }

    /// A name that is, on a Mac's disk, one already given: its disks by
    /// default take neither case nor Unicode's ways of writing an accent
    /// apart, so "Manifest.json" would be written over the manifest.json
    /// that was read and shown. A file where a folder is counts too.
    static func sameFile(in names: [String]) -> String? {
        func key<S: StringProtocol>(_ path: S) -> String {
            String(path).decomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
        }
        var files = Set<String>()
        var folders = Set<String>()
        for name in names {
            let parts = name.split(separator: "/")
            for end in parts.indices.dropFirst() { folders.insert(key(parts[..<end].joined(separator: "/"))) }
            if name.hasSuffix("/") {
                folders.insert(key(name.dropLast()))
            } else if !files.insert(key(name)).inserted {
                return name
            }
        }
        return files.first(where: folders.contains)
    }

    /// Whether a name stays inside the folder it is unpacked into: not
    /// absolute, no "." or ".." or empty part, no backslash, and not in
    /// Safience's own folder.
    static func isSafe(name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0") else { return false }
        var parts = name.split(separator: "/", omittingEmptySubsequences: false)
        // A folder's own entry ends in "/".
        if name.hasSuffix("/") { parts.removeLast() }
        guard !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return false }
        return parts[0].lowercased() != "_safience"
    }

    /// How a manifest names a file, as the archive does: "/bg.js" and
    /// "./bg.js" are "bg.js".
    static func normalized(_ path: String) -> String {
        var path = Substring(path)
        while path.hasPrefix("./") || path.hasPrefix("/") { path = path.dropFirst(path.hasPrefix("/") ? 1 : 2) }
        return String(path)
    }

    static func isPage(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".html") || lower.hasSuffix(".htm")
    }

    /// The manifest with the shim first wherever scripts are listed, and
    /// native messaging added for the shim's way to Safience; what was
    /// added; and the worker file, which the shim goes in front of, and
    /// whether it is a module. The checks read the manifest as it came, so
    /// what was added here isn't counted as the extension's own asking.
    public static func manifest(_ data: Data) throws -> (manifest: Data, added: [String], worker: (path: String, module: Bool)?) {
        let text = ExtensionManifest.withoutComments(String(decoding: data, as: UTF8.self))
        guard var object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw ExtensionManifest.Problem.notJSON
        }
        var added: [String] = []
        var permissions = object["permissions"] as? [Any] ?? []
        if !permissions.contains(where: { $0 as? String == "nativeMessaging" }) {
            permissions.append("nativeMessaging")
            added.append("nativeMessaging")
        }
        object["permissions"] = permissions

        var worker: (path: String, module: Bool)?
        if var background = object["background"] as? [String: Any] {
            // A manifest for Chrome and Firefox at once names both; whichever
            // WebKit takes (the scripts, as Search found) has the shim.
            worker = (background["service_worker"] as? String).map { ($0, background["type"] as? String == "module") }
            if let scripts = background["scripts"] as? [Any], !scripts.isEmpty {
                background["scripts"] = [shimFile] + scripts
            }
            object["background"] = background
        }
        if let scripts = object["content_scripts"] as? [Any] {
            object["content_scripts"] = scripts.map { entry -> Any in
                guard var entry = entry as? [String: Any], let js = entry["js"] as? [Any], !js.isEmpty,
                      // The page's own world has no extension APIs to mend,
                      // and the page would see the shim there.
                      entry["world"] as? String != "MAIN"
                else { return entry }
                entry["js"] = [shimFile] + js
                return entry
            }
        }
        let out = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        return (out, added, worker)
    }

    /// An extension page with the shim first: right after its head's
    /// opening tag, not one in a comment; or after the doctype, or before
    /// everything, when it has none. As a file of the extension's own, so
    /// its default content security policy, which takes no inline script,
    /// takes it.
    public static func page(_ html: String) -> String {
        let tag = "<script src=\"/\(shimFile)\"></script>"
        var search = html.startIndex
        while let head = html.range(of: "<head", options: [.caseInsensitive], range: search..<html.endIndex) {
            if let comment = html.range(of: "<!--", range: search..<head.lowerBound) {
                search = html.range(of: "-->", range: comment.upperBound..<html.endIndex)?.upperBound ?? html.endIndex
                continue
            }
            // Not <header>.
            if let next = html[head.upperBound...].first, next == ">" || next.isWhitespace || next == "/",
               let close = html[head.upperBound...].firstIndex(of: ">") {
                var out = html
                out.insert(contentsOf: tag, at: out.index(after: close))
                return out
            }
            search = head.upperBound
        }
        if html.range(of: "<!doctype", options: [.caseInsensitive, .anchored],
                      range: html.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }).startIndex..<html.endIndex) != nil,
           let end = html.firstIndex(of: ">") {
            var out = html
            out.insert(contentsOf: tag, at: out.index(after: end))
            return out
        }
        return tag + html
    }

    /// The worker with the shim first, and otherwise byte for byte as it
    /// came. A module imports it, on its first line: a module's imports run
    /// before anything written in it, the shim's text too, and its lines
    /// stay where they were. A classic worker has the shim's text in front,
    /// between marks, as Search does, and its errors' line numbers grow by
    /// the lines put there; after the "use strict" it starts with, if it
    /// does, so it stays strict.
    public static func worker(_ source: Data, shim: String, module: Bool) -> Data {
        let bytes = [UInt8](source)
        let start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        if module {
            return Data(bytes[..<start]) + Data("import \"/\(shimFile)\";".utf8) + Data(bytes[start...])
        }
        let block = "\(shimMarks.0)\n\(shim)\n\(shimMarks.1)\n"
        guard let strict = strictness(of: bytes, from: start) else {
            return Data(bytes[..<start]) + Data(block.utf8) + Data(bytes[start...])
        }
        // A directive with no semicolon ends where the shim begins only
        // with one: a string followed by "(" is a call.
        return Data(bytes[..<strict.end]) + Data(((strict.ended ? "" : ";") + "\n" + block).utf8) + Data(bytes[strict.end...])
    }

    /// Where a script's directives end, when one of them is "use strict":
    /// the strings it starts with, each a statement of its own, past the
    /// space and comments around them; and whether a semicolon ends the
    /// last. A string that goes on into an expression ("use strict".length)
    /// is no directive, and ends them.
    static func strictness(of bytes: [UInt8], from start: Int) -> (end: Int, ended: Bool)? {
        func skipped(_ from: Int) -> Int {
            var at = from
            while at < bytes.count {
                if [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) {
                    at += 1
                } else if bytes[at...].starts(with: Array("//".utf8)) {
                    while at < bytes.count, bytes[at] != 0x0A { at += 1 }
                } else if bytes[at...].starts(with: Array("/*".utf8)) {
                    at += 2
                    while at < bytes.count, !bytes[at...].starts(with: Array("*/".utf8)) { at += 1 }
                    at = min(at + 2, bytes.count)
                } else {
                    break
                }
            }
            return at
        }
        var at = skipped(start)
        var strict = false
        var last: (end: Int, ended: Bool)?
        while at < bytes.count, bytes[at] == UInt8(ascii: "\"") || bytes[at] == UInt8(ascii: "'") {
            let quote = bytes[at]
            var close = at + 1
            while close < bytes.count, bytes[close] != quote, bytes[close] != 0x0A {
                close += bytes[close] == UInt8(ascii: "\\") ? 2 : 1
            }
            guard close < bytes.count, bytes[close] == quote else { break }
            var next = close + 1
            while next < bytes.count, bytes[next] == 0x20 || bytes[next] == 0x09 { next += 1 }
            let end: (end: Int, ended: Bool)
            if next < bytes.count, bytes[next] == UInt8(ascii: ";") {
                end = (next + 1, true)
            } else if next >= bytes.count || [0x0A, 0x0D].contains(bytes[next])
                        || bytes[next...].starts(with: Array("//".utf8)) || bytes[next...].starts(with: Array("/*".utf8)) {
                end = (close + 1, false)
            } else {
                break
            }
            // Written out exactly: "use\x20strict" is no directive.
            if Array(bytes[(at + 1)..<close]) == Array("use strict".utf8) { strict = true }
            last = end
            at = skipped(end.end)
        }
        return strict ? last : nil
    }

    /// A short fingerprint of the shim and of this preparation (64-bit
    /// FNV-1a), the stamp file's start; the package's own follows it.
    public static func stamp(for shim: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in shim.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return "\(version)-\(String(hash, radix: 16))"
    }
}
