import Foundation

/// A filter WebKit's rule lists can't say, done by a script in the page
/// instead (blocker.js, scriptlets.js).
///
/// WebKit hides by plain CSS selectors and blocks by address, and nothing
/// else. The lists also hide by what an element says ("Sponsored"), by what
/// is inside it, by an XPath; they hide on every country's copy of a site
/// ("shop.*"); and they stop the scripts that put an "ad blocker detected"
/// wall up, by taking away what those scripts look for. Those are kept here,
/// each for the sites it names, and a page on one of those sites is given a
/// script with only its own (ScriptedTable.rules). A page on any other site
/// gets no script at all, so nothing runs where no list asks for it.
///
/// A filter for every site ("##div:has-text(Ad)") is left out: it would put
/// the script in every page.
public struct ScriptedFilter: Equatable, Sendable, Codable {
    /// One step in finding the elements a procedural filter means.
    public indirect enum Step: Equatable, Sendable, Codable {
        /// A CSS selector: from the document for a first step, from each
        /// element found so far after that (" > a", " .ad").
        case css(String)
        /// Keeps the elements whose text has this in it, or matches /this/.
        case text(String)
        /// Keeps the elements these steps find something inside.
        case has([Step])
        /// Keeps the elements these steps find nothing for.
        case not([Step])
        /// Goes up: so many ancestors, or to the nearest one matching a selector.
        case upward(String)
        case xpath(String)
        /// Keeps the elements whose computed style has "property: value" (or /value/).
        case style(String)
        /// Keeps the elements with at least so many characters of text.
        case length(Int)

        /// As blocker.js reads it.
        var value: [Any] {
            switch self {
            case .css(let selector): return ["css", selector]
            case .text(let needle): return ["text", needle]
            case .has(let steps): return ["has", steps.map(\.value)]
            case .not(let steps): return ["not", steps.map(\.value)]
            case .upward(let how): return ["up", how]
            case .xpath(let path): return ["xpath", path]
            case .style(let declaration): return ["style", declaration]
            case .length(let least): return ["len", least]
            }
        }
    }

    public enum Action: Equatable, Sendable, Codable {
        /// A plain selector WebKit's rules couldn't carry (a site named with
        /// a wildcard, say), hidden by a style sheet.
        case css(String)
        /// The elements the steps find, hidden.
        case hide([Step])
        /// The elements the steps find, given these declarations (":style(…)").
        case restyle([Step], String)
        /// A scriptlet, by its full name, with what it was given.
        case run(String, [String])
    }

    /// The sites it is for: hosts ("news.test", and everything under it) and
    /// entities ("shop.*", the name under any ending).
    public var domains: [String]
    /// The sites under those it is not for.
    public var unless: [String]
    public var action: Action
    /// "#@#", "#@?#", "#@$#": takes the same filter back on its sites, or on
    /// every site when it names none.
    public var exception: Bool

    // MARK: Reading a list's line

    /// The line's filters (a line of snippets can hold several), or none
    /// when it isn't one this can do.
    public static func parse(_ line: String) -> [ScriptedFilter] {
        guard let hash = line.firstIndex(of: "#") else { return [] }
        let rest = line[hash...]
        guard let marker = ["#@?#", "#@$#", "#?#", "#$#", "#@#", "##"].first(where: { rest.hasPrefix($0) }) else { return [] }
        let exception = marker.contains("@")
        let body = String(rest.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return [] }

        var domains: [String] = []
        var unless: [String] = []
        for entry in line[..<hash].split(separator: ",") {
            let excluded = entry.hasPrefix("~")
            guard let domain = site(excluded ? String(entry.dropFirst()) : String(entry)) else { continue }
            if excluded { unless.append(domain) } else { domains.append(domain) }
        }
        // For every site: only as an exception.
        if domains.isEmpty && !exception { return [] }
        let actions: [Action]
        if marker.contains("$") {
            actions = snippets(body)
        } else if body.hasPrefix("+js(") {
            actions = scriptlet(body).map { [$0] } ?? []
        } else if body.hasPrefix("^") {
            // HTML filtering: the page's source, before it is a page.
            actions = []
        } else {
            actions = hiding(body).map { [$0] } ?? []
        }
        return actions.map { ScriptedFilter(domains: domains.sorted(), unless: unless.sorted(), action: $0, exception: exception) }
    }

    /// A host, or an entity ("shop.*"), in lower-case ASCII as a page's host
    /// is; nil for anything else.
    static func site(_ text: String) -> String? {
        var name = text.trimmingCharacters(in: .whitespaces).lowercased()
        let entity = name.hasSuffix(".*")
        if entity { name.removeLast(2) }
        guard let domain = Domains.webKit(name) else { return nil }
        return entity ? domain + ".*" : domain
    }

    // MARK: Hiding

    /// The operators of the lists' procedural selectors this does, by the
    /// step each makes; a selector with any other is left out.
    static let operators: [String: (String) -> Step?] = [
        "has-text": { .text($0) },
        "-abp-contains": { .text($0) },
        "contains": { .text($0) },
        "-abp-has": { steps($0).map(Step.has) },
        "upward": { .upward($0) },
        "nth-ancestor": { Int($0) != nil ? .upward($0) : nil },
        "xpath": { .xpath($0) },
        "matches-css": { .style($0) },
        "min-text-length": { Int($0).map(Step.length) },
    ]
    /// Ones it doesn't: named so a selector with one is turned down, not
    /// handed to the page as CSS it would choke on.
    static let unsupported: Set<String> = [
        "-abp-properties", "matches-css-before", "matches-css-after", "matches-attr", "matches-path",
        "matches-media", "matches-prop", "others", "watch-attr", "shadow", "remove-attr", "remove-class",
    ]

    static func hiding(_ selector: String) -> Action? {
        var text = selector
        var declarations: String?
        // "…:style(opacity: 1 !important)" and "…:remove()" end a selector.
        if text.hasSuffix(")"), let open = lastCall(":style(", in: text) {
            declarations = String(text[text.index(open, offsetBy: ":style(".count)..<text.index(before: text.endIndex)])
            text = String(text[..<open])
        } else if text.hasSuffix(":remove()") {
            text.removeLast(":remove()".count)
        }
        guard let steps = steps(text).map(native), let first = steps.first else { return nil }
        // A chain starts from elements a selector or a path names. One that
        // starts with a test would be asked of every element on the page,
        // the page itself among them: ":has-text(ad)" alone hides it all.
        switch first {
        case .css, .xpath: break
        default: return nil
        }
        if let declarations {
            let cleaned = declarations.trimmingCharacters(in: .whitespaces)
            // Declarations only: nothing that could close the rule and open another.
            guard !cleaned.isEmpty, !cleaned.contains("{"), !cleaned.contains("}") else { return nil }
            return .restyle(steps, cleaned)
        }
        if steps.count == 1, case .css(let plain) = steps[0] { return .css(plain) }
        return .hide(steps)
    }

    /// The steps with what CSS can say by itself said in CSS: ":-abp-has(…)"
    /// around a plain selector is CSS's own ":has(…)", which WebKit matches
    /// as the page changes with no script looking again. Left as steps
    /// where joining would change the meaning: a list of selectors on
    /// either side ("a, b" would have the ":has" on "b" alone), a ":has"
    /// inside, which CSS doesn't nest, or one with no selector before it
    /// that names more than a child.
    static func native(_ steps: [Step]) -> [Step] {
        var out: [Step] = []
        // The last of `out` is a selector a ":has" was just joined to.
        var joined = false
        for step in steps {
            if case .has(let inner) = step, inner.count == 1, case .css(let inside) = inner[0], !inside.contains(":has(") {
                let call = ":has(" + inside.trimmingCharacters(in: .whitespaces) + ")"
                if out.isEmpty {
                    // With no selector before it, only one that names a
                    // child: ":has(> .ad)" is the element the ad is in,
                    // where ":has(.ad)" is every element around it, the
                    // page itself among them. That one stays a test with
                    // nothing to start from, and is left out (hiding).
                    guard inside.trimmingCharacters(in: .whitespaces).hasPrefix(">") else {
                        out.append(step)
                        continue
                    }
                    out.append(.css(call))
                    joined = true
                    continue
                }
                if case .css(let before) = out[out.count - 1], !before.contains(",") {
                    out[out.count - 1] = .css(before + call)
                    joined = true
                    continue
                }
            }
            // What comes after a joined ":has" goes on in the same selector.
            if joined, case .css(let after) = step, case .css(let before) = out[out.count - 1], !after.contains(",") {
                out[out.count - 1] = .css(before + after)
                continue
            }
            joined = false
            out.append(step)
        }
        return out
    }

    /// Where a call that runs to the very end of the text begins.
    private static func lastCall(_ call: String, in text: String) -> String.Index? {
        guard let open = text.range(of: call, options: .backwards)?.lowerBound else { return nil }
        let characters = Array(text[open...])
        guard let close = closing(characters, from: call.count) else { return nil }
        return close == characters.count - 1 ? open : nil
    }

    /// A selector as steps: plain CSS up to an operator, the operator, the
    /// CSS after it, and so on. Nil for one with an operator this can't do
    /// or brackets that don't close.
    static func steps(_ selector: String) -> [Step]? {
        let characters = Array(selector.trimmingCharacters(in: .whitespaces))
        var out: [Step] = []
        var plain = ""
        var index = 0
        var quote: Character?
        var brackets = 0
        func flush() {
            // After an operator the CSS goes on from the elements found, so
            // its leading space or ">" is kept; before one it is a selector.
            let text = out.isEmpty ? plain.trimmingCharacters(in: .whitespaces) : plain
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.css(text)) }
            plain = ""
        }
        while index < characters.count {
            let character = characters[index]
            if let open = quote {
                plain.append(character)
                if character == "\\", index + 1 < characters.count {
                    plain.append(characters[index + 1])
                    index += 1
                } else if character == open {
                    quote = nil
                }
                index += 1
                continue
            }
            switch character {
            case "\\":
                plain.append(character)
                if index + 1 < characters.count {
                    plain.append(characters[index + 1])
                    index += 1
                }
            case "\"", "'":
                quote = character
                plain.append(character)
            case "[":
                brackets += 1
                plain.append(character)
            case "]":
                brackets -= 1
                if brackets < 0 { return nil }
                plain.append(character)
            case ":" where brackets == 0:
                var end = index + 1
                while end < characters.count, characters[end].isLetter || characters[end] == "-" { end += 1 }
                let name = String(characters[(index + 1)..<end]).lowercased()
                guard end < characters.count, characters[end] == "(" else {
                    // ":first-child", "::before": CSS's own, with nothing to read.
                    plain.append(character)
                    break
                }
                // A bracket that never closes: not a selector.
                guard let close = closing(characters, from: end + 1) else { return nil }
                let argument = String(characters[(end + 1)..<close])
                if unsupported.contains(name) { return nil }
                if let make = operators[name] {
                    flush()
                    guard let step = make(argument.trimmingCharacters(in: .whitespaces)) else { return nil }
                    out.append(step)
                } else if (name == "has" || name == "not"), isProcedural(argument) {
                    // CSS's own :has() and :not(), with an operator inside them.
                    flush()
                    guard let inner = steps(argument), !inner.isEmpty else { return nil }
                    out.append(name == "has" ? .has(inner) : .not(inner))
                } else {
                    // CSS's own, left as it is.
                    plain += ":" + name + "(" + argument + ")"
                }
                index = close
            default:
                plain.append(character)
            }
            index += 1
        }
        guard quote == nil, brackets == 0 else { return nil }
        flush()
        return out
    }

    /// Whether a selector has one of the lists' operators in it.
    static func isProcedural(_ selector: String) -> Bool {
        (Array(operators.keys) + Array(unsupported)).contains { selector.contains(":" + $0 + "(") }
    }

    /// The index of the ")" that closes a "(" just before `start`, past any
    /// brackets, quotes and escapes on the way.
    static func closing(_ characters: [Character], from start: Int) -> Int? {
        var depth = 1
        var quote: Character?
        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    // MARK: Scriptlets

    /// The scriptlets scriptlets.js has, by the names the lists call them.
    /// None of them touches cookies: those the lists have for cookies are
    /// left out, as nothing in Safience reads or writes a page's cookies.
    static let scriptlets: [String: String] = {
        let names: [String: [String]] = [
            "set-constant": ["set", "override-property-read"],
            "abort-on-property-read": ["aopr"],
            "abort-on-property-write": ["aopw"],
            "abort-current-script": ["acs", "acis", "abort-current-inline-script"],
            "abort-on-stack-trace": ["aost"],
            "no-setTimeout-if": ["nostif", "prevent-setTimeout"],
            "no-setInterval-if": ["nosiif", "prevent-setInterval"],
            "no-fetch-if": ["prevent-fetch"],
            "no-xhr-if": ["prevent-xhr"],
            "remove-node-text": ["rmnt"],
            "addEventListener-defuser": ["aeld", "prevent-addEventListener"],
            "remove-attr": ["ra"],
            "remove-class": ["rc"],
            "set-local-storage-item": [],
            "set-session-storage-item": [],
        ]
        var out: [String: String] = [:]
        for (name, others) in names {
            out[name.lowercased()] = name
            for other in others { out[other.lowercased()] = name }
        }
        return out
    }()

    /// "+js(set, adBlockDetected, false)": uBlock Origin's way of naming one.
    static func scriptlet(_ body: String) -> Action? {
        guard body.hasPrefix("+js("), body.hasSuffix(")") else { return nil }
        let arguments = split(String(body.dropFirst(4).dropLast()), at: ",")
        guard let first = arguments.first, let name = scriptletName(first) else { return nil }
        return .run(name, Array(arguments.dropFirst()))
    }

    /// "abort-on-property-read adblock; abort-on-property-write detect":
    /// Adblock Plus's way, one or several to a line.
    static func snippets(_ body: String) -> [Action] {
        // "selector { style }" is AdGuard's CSS, not a snippet.
        guard !body.contains("{") else { return [] }
        var out: [Action] = []
        for part in split(body, at: ";") {
            let words = split(part, at: " ").filter { !$0.isEmpty }
            guard let first = words.first else { continue }
            // All of a line's or none: half of one may be worse than none.
            guard let name = scriptletName(first) else { return [] }
            out.append(.run(name, Array(words.dropFirst())))
        }
        return out
    }

    static func scriptletName(_ text: String) -> String? {
        var name = text.trimmingCharacters(in: .whitespaces).lowercased()
        if name.hasSuffix(".js") { name.removeLast(3) }
        return scriptlets[name]
    }

    /// The parts between separators, past quotes and escaped separators,
    /// each trimmed and without the quotes round it.
    static func split(_ text: String, at separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count, characters[index + 1] == separator {
                current.append(separator)
                index += 2
                continue
            }
            if let open = quote {
                if character == open { quote = nil }
                current.append(character)
            } else if (character == "\"" || character == "'" || character == "`"), current.trimmingCharacters(in: .whitespaces).isEmpty {
                // A quote opens a part only at its start: "it's" is a word.
                quote = character
                current.append(character)
            } else if character == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }
        parts.append(current)
        return parts.map { part in
            var trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 2, let first = trimmed.first, "\"'`".contains(first), trimmed.last == first {
                trimmed = String(trimmed.dropFirst().dropLast())
            }
            return trimmed
        }
    }
}

/// What one page's scripts are given: the filters for its site and no other.
public struct PageRules: Equatable, Sendable {
    public var css: [String] = []
    public var hide: [[ScriptedFilter.Step]] = []
    public var restyle: [(steps: [ScriptedFilter.Step], declarations: String)] = []
    public var run: [(name: String, arguments: [String])] = []

    public init() {}

    public static func == (a: PageRules, b: PageRules) -> Bool {
        a.css == b.css && a.hide == b.hide && a.run.map(\.name) == b.run.map(\.name)
            && a.run.map(\.arguments) == b.run.map(\.arguments)
            && a.restyle.map(\.steps) == b.restyle.map(\.steps) && a.restyle.map(\.declarations) == b.restyle.map(\.declarations)
    }

    public var isEmpty: Bool { css.isEmpty && hide.isEmpty && restyle.isEmpty && run.isEmpty }
    /// Whether there is anything for the script that hides (blocker.js).
    public var hides: Bool { !css.isEmpty || !hide.isEmpty || !restyle.isEmpty }

    /// For blocker.js, in the app's own world.
    public var hidingJSON: String {
        Self.json(["css": css, "hide": hide.map { $0.map(\.value) },
                   "style": restyle.map { ["steps": $0.steps.map(\.value), "css": $0.declarations] as [String: Any] }])
    }

    /// For scriptlets.js, in the page's world.
    public var scriptletsJSON: String {
        Self.json(run.map { [$0.name] + $0.arguments })
    }

    /// Changes when the rules do: what a page's scripts are known by (Page.prepare).
    public var stamp: String {
        ContentBlocking.stableHash(hidingJSON + scriptletsJSON)
    }

    static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "null"
        }
        // The two line ends JSON allows in a string and older JavaScript didn't.
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}

/// Every scripted filter of the lists in use, found by site.
public struct ScriptedTable: Equatable, Sendable, Codable {
    public private(set) var filters: [ScriptedFilter] = []
    /// A site or entity to the filters for it, by their place in `filters`.
    private var bySite: [String: [Int]] = [:]

    public init() {}

    public init(_ all: [ScriptedFilter]) {
        let exceptions = all.filter(\.exception)
        for var filter in all where !filter.exception {
            var everywhere = false
            for exception in exceptions where exception.action == filter.action {
                if exception.domains.isEmpty { everywhere = true } else { filter.unless += exception.domains }
            }
            if everywhere { continue }
            let index = filters.count
            filters.append(filter)
            for domain in filter.domains { bySite[domain, default: []].append(index) }
        }
    }

    public var count: Int { filters.count }

    /// The names a host is filed under: itself and each name above it, and
    /// each of those as an entity, with one ending or two taken off ("co.uk").
    static func keys(for host: String) -> [String] {
        let labels = host.split(separator: ".").map(String.init)
        guard !labels.isEmpty else { return [] }
        var out: [String] = []
        for start in labels.indices {
            let rest = labels[start...]
            out.append(rest.joined(separator: "."))
            for dropped in 1...2 where rest.count > dropped {
                out.append(rest.dropLast(dropped).joined(separator: ".") + ".*")
            }
        }
        return out
    }

    /// What a page at `host` is given: nothing, on most sites.
    public func rules(forHost host: String?) -> PageRules {
        var out = PageRules()
        guard let host = Hosts.normal(host), !bySite.isEmpty else { return out }
        let keys = Self.keys(for: host)
        let names = Set(keys)
        var seen = Set<Int>()
        for key in keys {
            for index in bySite[key] ?? [] where seen.insert(index).inserted {
                let filter = filters[index]
                if filter.unless.contains(where: names.contains) { continue }
                switch filter.action {
                case .css(let selector): out.css.append(selector)
                case .hide(let steps): out.hide.append(steps)
                case .restyle(let steps, let declarations): out.restyle.append((steps, declarations))
                case .run(let name, let arguments): out.run.append((name, arguments))
                }
            }
        }
        return out
    }
}
