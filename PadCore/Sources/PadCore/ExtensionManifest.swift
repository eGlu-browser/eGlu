import Foundation

/// What an extension's manifest.json says, as far as Safience needs it
/// before WebKit loads the extension: what it asks for, how its background
/// runs, where its scripts go and which pages it has. WebKit reads the
/// manifest again itself; this is for the install sheet and the checks.
public struct ExtensionManifest: Equatable, Sendable {
    public enum Background: Equatable, Sendable {
        /// Manifest V3's worker; `module` when it is an ES module.
        case worker(String, module: Bool)
        /// Manifest V2's background scripts, run in a page of WebKit's.
        case scripts([String], persistent: Bool)
        case page(String, persistent: Bool)
    }

    public struct ContentScript: Equatable, Sendable {
        public var matches: [String]
        public var scripts: [String]
        public var styles: [String]
        public var allFrames: Bool
        /// "ISOLATED", WebKit's and Chrome's default, or "MAIN".
        public var world: String
    }

    public var manifestVersion: Int
    public var name: String
    public var version: String
    /// API permissions: "storage", "tabs", "sidePanel".
    public var permissions: [String]
    public var optionalPermissions: [String]
    /// Sites: match patterns and "<all_urls>". Manifest V2 lists them among
    /// its permissions; they are taken out of those and put here.
    public var hostPermissions: [String]
    public var optionalHostPermissions: [String]
    public var background: Background?
    public var contentScripts: [ContentScript]
    public var popup: String?
    public var optionsPage: String?
    public var sidePanel: String?
    /// The manifest's `oauth2` section, which Chrome's sign-in
    /// (`identity.getAuthToken`) reads.
    public var usesChromeSignIn: Bool
    public var minimumChromeVersion: String?
    public var keys: Set<String>

    /// Every page and script the manifest names, for the scan.
    public var files: [String] {
        var files: [String] = []
        switch background {
        case .worker(let path, _): files.append(path)
        case .scripts(let paths, _): files += paths
        case .page(let path, _): files.append(path)
        case nil: break
        }
        files += contentScripts.flatMap(\.scripts)
        files += [popup, optionsPage, sidePanel].compactMap { $0 }
        return files
    }

    public enum Problem: Error, Equatable, Sendable {
        case notJSON
        case noVersion
    }

    /// Chrome reads manifests leniently: comments are allowed, and a byte
    /// order mark at the start. So are they here.
    public init(json data: Data) throws {
        let text = Self.withoutComments(String(decoding: data, as: UTF8.self))
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw Problem.notJSON
        }
        guard let version = object["version"] as? String else { throw Problem.noVersion }
        func strings(_ value: Any?) -> [String] { (value as? [Any])?.compactMap { $0 as? String } ?? [] }
        func isSite(_ entry: String) -> Bool { entry == "<all_urls>" || entry.contains("://") }

        keys = Set(object.keys)
        manifestVersion = object["manifest_version"] as? Int ?? 2
        name = object["name"] as? String ?? ""
        self.version = version
        let listed = strings(object["permissions"])
        let optional = strings(object["optional_permissions"])
        permissions = listed.filter { !isSite($0) }
        optionalPermissions = optional.filter { !isSite($0) }
        hostPermissions = strings(object["host_permissions"]) + listed.filter(isSite)
        optionalHostPermissions = strings(object["optional_host_permissions"]) + optional.filter(isSite)

        let background = object["background"] as? [String: Any]
        let persistent = background?["persistent"] as? Bool ?? true
        if let worker = background?["service_worker"] as? String {
            self.background = .worker(worker, module: background?["type"] as? String == "module")
        } else if let page = background?["page"] as? String {
            self.background = .page(page, persistent: persistent)
        } else if let scripts = background?["scripts"] as? [Any] {
            self.background = .scripts(scripts.compactMap { $0 as? String }, persistent: persistent)
        } else {
            self.background = nil
        }

        contentScripts = ((object["content_scripts"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map {
            ContentScript(matches: strings($0["matches"]), scripts: strings($0["js"]), styles: strings($0["css"]),
                          allFrames: $0["all_frames"] as? Bool ?? false, world: $0["world"] as? String ?? "ISOLATED")
        }
        let action = (object["action"] ?? object["browser_action"] ?? object["page_action"]) as? [String: Any]
        popup = action?["default_popup"] as? String
        optionsPage = (object["options_ui"] as? [String: Any])?["page"] as? String ?? object["options_page"] as? String
        sidePanel = (object["side_panel"] as? [String: Any])?["default_path"] as? String
        usesChromeSignIn = object["oauth2"] != nil
        minimumChromeVersion = object["minimum_chrome_version"] as? String
    }

    /// The text without its // and /* */ comments, strings left as they
    /// are; and without a byte order mark.
    static func withoutComments(_ text: String) -> String {
        var out = ""
        var chars = Array(text.unicodeScalars)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var at = 0
        var inString = false
        while at < chars.count {
            let c = chars[at]
            let next = at + 1 < chars.count ? chars[at + 1] : nil
            if inString {
                out.unicodeScalars.append(c)
                if c == "\\", let next {
                    out.unicodeScalars.append(next)
                    at += 2
                    continue
                }
                if c == "\"" { inString = false }
                at += 1
            } else if c == "\"" {
                inString = true
                out.unicodeScalars.append(c)
                at += 1
            } else if c == "/", next == "/" {
                while at < chars.count, chars[at] != "\n" { at += 1 }
            } else if c == "/", next == "*" {
                at += 2
                while at < chars.count, !(chars[at] == "*" && at + 1 < chars.count && chars[at + 1] == "/") { at += 1 }
                at += 2
            } else {
                out.unicodeScalars.append(c)
                at += 1
            }
        }
        return out
    }
}

/// What WebKit and Safience answer, which every compatibility check
/// compares an extension against.
///
/// Neither half is written by hand from WebKit's documentation, which goes
/// stale: WebKit's half is what the Mac's own WebKit gave a test extension
/// that asked for everything (namespaces and their members), and Safience's
/// half is the list of what its shims answer.
public struct ExtensionAPITable: Equatable, Sendable {
    public enum Answer: Equatable, Sendable {
        /// WebKit answers it.
        case native
        /// Safience's shim answers it.
        case shim
        /// Safience's shim answers some of it, as `identity`, whose
        /// launchWebAuthFlow works and getAuthToken is refused.
        case part
        /// Answered, and nothing happens.
        case stub
        /// Asked for, and refused with an error.
        case refused
    }

    /// Paths, "tabs" or "tabs.move", and their answers. A member with no
    /// entry of its own takes its namespace's.
    public var answers: [String: Answer]

    /// What Safience's shims answer that WebKit lacks (Scripts/extension-shim.js,
    /// ExtensionAnswers.swift): kept beside them, read on top of what this
    /// Mac's WebKit has.
    public static let shims: [String: Answer] = [
        "sidePanel": .shim,
        "offscreen": .shim,
        "management": .part,
        "management.getSelf": .shim,
        "management.get": .shim,
        "runtime.getContexts": .shim,
    ]

    public init(answers: [String: Answer]) {
        self.answers = answers
    }

    /// The table for this Mac: what WebKit gave the test extension, then
    /// the shims' list on top for everything WebKit lacks.
    public init(webKit: [String: Set<String>], shims: [String: Answer]) {
        var answers: [String: Answer] = [:]
        for (namespace, members) in webKit {
            answers[namespace] = .native
            for member in members { answers["\(namespace).\(member)"] = .native }
        }
        for (path, answer) in shims where answers[path] == nil { answers[path] = answer }
        self.answers = answers
    }

    public func answer(for path: String) -> Answer? {
        if let answer = answers[path] { return answer }
        guard let dot = path.firstIndex(of: ".") else { return nil }
        let namespace = String(path[..<dot])
        // A member of a namespace WebKit has natively, not in its list, is
        // missing; a member of a shim's namespace is the shim's to answer.
        guard let whole = answers[namespace], whole != .native else { return nil }
        return whole
    }

    /// Whether a call to `path` does what it says: nothing answering it, a
    /// stub that does nothing, or a refusal all count as not.
    public func works(_ path: String) -> Bool {
        switch answer(for: path) {
        case .native, .shim, .part: return true
        case .stub, .refused, nil: return false
        }
    }
}

extension ExtensionManifest {
    /// The permissions it asked for that WebKit didn't take. WebKit keeps
    /// those it supports and drops the rest without a word, so after
    /// loading, what the context requests is all that is left: `kept` is
    /// its requested and optional permissions.
    public func dropped(kept: Set<String>) -> [String] {
        (permissions + optionalPermissions).filter { !kept.contains($0) }
    }

    /// What installing it allows it, as written down and compared on each
    /// update: its API permissions, and its sites as "site:<pattern>", those
    /// its content scripts run on included. An update that asks for one not
    /// among them is asked about again, as Search does.
    public var grants: [String] {
        var out = Set(permissions)
        out.formUnion((hostPermissions + contentScripts.flatMap(\.matches)).map { "site:" + $0 })
        return out.sorted()
    }
}
