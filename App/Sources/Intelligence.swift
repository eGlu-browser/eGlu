import FoundationModels
import PadCore

/// Apple Intelligence's on-device model, asked what the words typed in the
/// address bar mean: which of the space's tabs, pinned tabs and bookmarks,
/// or which of the browser's commands, and what searches they are on the
/// way to (Autocomplete.intentQuestion). The model is on the device, and
/// nothing it reads leaves it.
///
/// It is asked in two steps. Asked to pick from the list it always picks
/// something, a web search typed or not, so its picks are only what the
/// words might mean; each is then asked about alone (grade), and only what
/// it grades as fitting is offered. That is what lets it offer nothing.
///
/// Only on iOS and iPadOS 26 and later, on a device with Apple Intelligence
/// turned on; FoundationModels is linked weakly (project.yml), so earlier
/// versions start without it and the address bar matches letters alone.
@MainActor
protocol Intelligence: AnyObject {
    /// It can answer now: Apple Intelligence on, its model downloaded.
    var ready: Bool { get }
    /// Loads the model as typing starts, so the first answer doesn't wait for it.
    func prewarm()
    /// What the words might mean in the list, and, when asked for them,
    /// searches that finish the words. Nil when it couldn't answer: a
    /// refusal, a language it doesn't have, typing that moved on.
    func answer(_ question: Autocomplete.IntentQuestion, searches: Bool) async -> Autocomplete.IntentAnswer?
    /// How one thing answers the words (Autocomplete.gradeQuestion). Nil
    /// when it couldn't say, which is taken as not fitting.
    func grade(_ question: String) async -> Autocomplete.IntentGrade?
}

/// What Settings says about Apple Intelligence on this device.
enum IntelligenceStatus {
    case ready
    /// Apple Intelligence is off in the Settings app.
    case turnedOff
    /// The model is still downloading.
    case preparing
    /// Before iOS 26, or a device without Apple Intelligence.
    case unsupported

    @MainActor static var current: IntelligenceStatus {
        guard #available(iOS 26.0, *) else { return .unsupported }
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return .ready }
        if case .unavailable(.appleIntelligenceNotEnabled) = availability { return .turnedOff }
        if case .unavailable(.modelNotReady) = availability { return .preparing }
        return .unsupported
    }

    /// The model, where this version of the system has it.
    @MainActor static func model() -> Intelligence? {
        guard #available(iOS 26.0, *) else { return nil }
        return OnDeviceIntelligence()
    }
}

@available(iOS 26.0, *)
@MainActor
private final class OnDeviceIntelligence: Intelligence {
    private let model = SystemLanguageModel.default
    private var warm: LanguageModelSession?

    var ready: Bool {
        model.isAvailable
    }

    func prewarm() {
        guard ready, warm == nil else { return }
        let session = makeSession()
        session.prewarm()
        warm = session
    }

    func answer(_ question: Autocomplete.IntentQuestion, searches: Bool) async -> Autocomplete.IntentAnswer? {
        guard ready else { return nil }
        // A session for each question: a session keeps what it was asked
        // before, and a burst of typing would fill its context.
        let session = warm ?? makeSession()
        warm = nil
        let options = GenerationOptions(sampling: .greedy)
        do {
            // The searches only where they will show: they are words to
            // write out, and the picks wait on them.
            if searches {
                let reply = try await session.respond(to: question.prompt, generating: AddressIntent.self, options: options).content
                return Autocomplete.IntentAnswer(picks: reply.items.map(\.pick), searches: reply.searches)
            }
            let reply = try await session.respond(to: question.prompt, generating: AddressPicks.self, options: options).content
            return Autocomplete.IntentAnswer(picks: reply.items.map(\.pick), searches: [])
        } catch {
            return nil
        }
    }

    func grade(_ question: String) async -> Autocomplete.IntentGrade? {
        guard ready else { return nil }
        // A session of its own for each thing: asked in one session, what it
        // said of the things before sways what it says of the next.
        let session = LanguageModelSession(model: model, instructions: Autocomplete.gradeInstructions)
        do {
            let reply = try await session.respond(to: question, generating: AddressGrade.self,
                                                  options: GenerationOptions(sampling: .greedy))
            switch reply.content.grade {
            case .askedFor: return .askedFor
            case .related: return .related
            case .unrelated: return .unrelated
            }
        } catch {
            return nil
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: Autocomplete.intentInstructions)
    }
}

/// An item the model picks from the list: its name first, which is what
/// makes it look for the line, then the line's number.
@available(iOS 26.0, *)
@Generable
struct AddressPick {
    @Guide(description: "The item's name, copied from the list")
    var name: String

    @Guide(description: "The item's number in the list")
    var number: Int

    var pick: Autocomplete.IntentPick {
        Autocomplete.IntentPick(number: number, name: name)
    }
}

/// The model's picks, in the shape the framework holds it to. Five at most,
/// which it would fill every time if a pick were taken at its word: each is
/// graded after (AddressGrade), and few pass.
@available(iOS 26.0, *)
@Generable
struct AddressPicks {
    @Guide(description: "The listed items the person means, best first. Empty when what they typed is a web search or has nothing to do with the list, which is the usual case",
           .maximumCount(5))
    var items: [AddressPick]
}

/// The picks and searches together, where the model's searches show: the
/// engine's aren't asked for.
@available(iOS 26.0, *)
@Generable
struct AddressIntent {
    @Guide(description: "The listed items the person means, best first. Empty when what they typed is a web search or has nothing to do with the list, which is the usual case",
           .maximumCount(5))
    var items: [AddressPick]

    @Guide(description: "Web searches that finish what the person is typing, in the language they type in",
           .maximumCount(3))
    var searches: [String]
}

/// How one thing answers the words typed: three grades, so that what is
/// only the right kind of place has somewhere to go but yes.
@available(iOS 26.0, *)
@Generable
struct AddressGrade {
    @Generable
    enum Grade {
        case askedFor
        case related
        case unrelated
    }

    @Guide(description: "askedFor when the words name the thing or say what it does; related when the thing is the kind of place or tool the words describe; unrelated when the words are about another subject")
    var grade: Grade
}
