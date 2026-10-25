import EgluEnginesC
import Foundation

/// What an engine call went wrong with, by the `kind` in its error envelope.
public struct EngineError: Error, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case needsOCR
        case unsupported
        case malformed
        case encrypted
        case resourceLimit
        case missingPart
        case io
        case panic
        case tooLarge
        case unknown
    }

    public var kind: Kind
    public var message: String
}

extension EngineError {
    /// An `{"error":{"kind":…,"message":…}}` JSON string.
    init(envelope json: String) {
        struct Body: Decodable {
            struct Detail: Decodable {
                let kind: String?
                let message: String?
            }
            let error: Detail?
        }
        let body = try? JSONDecoder().decode(
            Body.self, from: Data(json.utf8))
        kind = Kind(rawValue: body?.error?.kind ?? "") ?? .unknown
        message = body?.error?.message ?? json
    }
}

/// One helper decodes every `{"ok":…}`/`{"error":…}` answer and frees the C
/// string with `eglu_free`.
enum Envelope {
    private struct Body<T: Decodable>: Decodable {
        struct Failure: Decodable {
            let kind: String
            let message: String?
        }
        let ok: T?
        let error: Failure?
    }

    static func decode<T: Decodable>(_ answer: UnsafeMutablePointer<CChar>?) throws -> T {
        guard let answer else {
            throw EngineError(kind: .panic, message: "the engine answered a null string")
        }
        defer { eglu_free(answer) }
        let json = String(cString: answer)
        guard let data = json.data(using: .utf8) else {
            throw EngineError(kind: .unknown, message: "the answer was not UTF-8")
        }
        let envelope = try JSONDecoder().decode(Body<T>.self, from: data)
        if let ok = envelope.ok {
            return ok
        }
        if let error = envelope.error {
            throw EngineError(
                kind: EngineError.Kind(rawValue: error.kind) ?? .unknown,
                message: error.message ?? "")
        }
        throw EngineError(kind: .unknown, message: json)
    }
}


/// A JSON value where the shape does not matter (one suggestion's fields).
enum JSONValue: Decodable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .other
        }
    }
}
