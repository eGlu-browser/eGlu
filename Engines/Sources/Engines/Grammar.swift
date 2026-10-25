import EgluEnginesC
import Foundation

/// The English dialect Harper lints against.
public enum Dialect: String, Sendable, Codable {
    case american = "American"
    case british = "British"
    case canadian = "Canadian"
    case australian = "Australian"
}

/// The linter's settings, passed to `Grammar.init` and `Grammar.configure`.
/// `rules` lists only the differences from Harper's defaults; an unknown
/// rule name is ignored. `words` extends the dictionary.
public struct GrammarSettings: Sendable, Codable {
    public var dialect: Dialect?
    public var rules: [String: Bool]
    public var words: [String]

    public init(dialect: Dialect? = nil, rules: [String: Bool] = [:], words: [String] = []) {
        self.dialect = dialect
        self.rules = rules
        self.words = words
    }
}

/// One lint. `start` and `end` are UTF-16 code-unit offsets into the linted
/// text, matching `NSString` and the Accessibility API. `context` is the
/// stable identifier `Grammar.ignore(context:)` takes.
public struct GrammarLint: Sendable, Equatable {
    public enum Suggestion: Sendable, Equatable {
        case replace(String)
        case insert(String)
        case remove
    }

    public var start: Int
    public var end: Int
    public var rule: String
    public var kind: String
    public var message: String
    public var priority: Int
    public var suggestions: [Suggestion]
    public var context: String
}

/// One lint rule, for a settings screen: its id, label, description, group
/// and whether Harper's curated set turns it on.
public struct GrammarRule: Sendable, Equatable {
    public var id: String
    public var label: String
    public var description: String
    public var group: String
    public var isOnByDefault: Bool
}

/// The grammar engine. Calls are serialized on the actor; the underlying
/// linter is not thread-safe.
public actor Grammar {
    private let linter: OpaquePointer

    /// Quick enough for the main actor: it only reads the settings, and
    /// throws for ones the engine can't take. The dictionary and the rules
    /// are built later, on the engine's thread, by `warmUp()` or the first
    /// lint.
    public init(settings: GrammarSettings = GrammarSettings()) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard let linter = eglu_harper_new(settings.jsonString, &error) else {
            let json = error.map { String(cString: $0) } ?? "{}"
            eglu_free(error)
            throw EngineError(envelope: json)
        }
        self.linter = linter
    }

    deinit {
        eglu_harper_free(linter)
    }

    /// Rebuilds the lint group and merged dictionary from new settings.
    public func configure(settings: GrammarSettings) throws {
        let _: Bool = try Envelope.decode(eglu_harper_configure(linter, settings.jsonString))
    }

    /// Builds the dictionary and the rules (a few hundred milliseconds) and
    /// runs one lint, so the first real lint is quick. Without it, the first
    /// lint does the building.
    public func warmUp() throws {
        let _: Bool = try Envelope.decode(eglu_harper_warm_up(linter))
    }

    /// Lints `text`, plain or Markdown. Over 200,000 UTF-16 units throws
    /// `EngineError.Kind.tooLarge`.
    public func lint(_ text: String, markdown: Bool = false) throws -> [GrammarLint] {
        struct Answer: Decodable {
            struct Lint: Decodable {
                let start: Int
                let end: Int
                let rule: String
                let kind: String
                let message: String
                let priority: Int
                let suggestions: [[String: JSONValue]]
                let context: String
            }
            let lints: [Lint]
        }
        let answer: Answer = try Envelope.decode(
            eglu_harper_lint(linter, text, markdown ? "markdown" : "plain"))
        return answer.lints.map { lint in
            GrammarLint(
                start: lint.start,
                end: lint.end,
                rule: lint.rule,
                kind: lint.kind,
                message: lint.message,
                priority: lint.priority,
                suggestions: lint.suggestions.compactMap { suggestion in
                    if case .string(let replacement)? = suggestion["replace"] {
                        return .replace(replacement)
                    }
                    if case .string(let insertion)? = suggestion["insert"] {
                        return .insert(insertion)
                    }
                    if case .bool(true)? = suggestion["remove"] {
                        return .remove
                    }
                    return nil
                },
                context: lint.context)
        }
    }

    /// Hides one lint from now on, by the `context` a `GrammarLint` carried.
    public func ignore(context: String) throws {
        let _: Bool = try Envelope.decode(eglu_harper_ignore(linter, context))
    }

    /// Every rule, for a settings screen.
    public static func rules() throws -> [GrammarRule] {
        struct Answer: Decodable {
            let rules: [GrammarRule]
        }
        let answer: Answer = try Envelope.decode(eglu_harper_rules())
        return answer.rules
    }
}

extension GrammarRule: Decodable {}

extension GrammarSettings {
    var jsonString: String {
        struct Serializable: Encodable {
            let dialect: String?
            let rules: [String: Bool]
            let words: [String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try! encoder.encode(
            Serializable(dialect: dialect?.rawValue, rules: rules, words: words))
        return String(decoding: data, as: UTF8.self)
    }
}
