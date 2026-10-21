import Foundation
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
/// Only on iOS and iPadOS 26 and later and on the Mac (whose least is 26),
/// on a device with Apple Intelligence turned on; FoundationModels is linked
/// weakly on iPhone and iPad (project.yml), so earlier versions start
/// without it and the address bar matches letters alone.
@MainActor
protocol Intelligence: AnyObject {
    /// It can answer now: Apple Intelligence on, its model downloaded. Taken
    /// as true until that has been found out (isKnown).
    var ready: Bool { get }
    /// Whether it has been found out yet if the model is there.
    var isKnown: Bool { get }
    /// Loads the model once there are words it may be asked about, so the
    /// first answer waits for it as little as it can.
    func prewarm()
    /// What the words might mean in the list, and, when asked for them,
    /// searches that finish the words. Nil when it couldn't answer: a
    /// refusal, a language it doesn't have, typing that moved on.
    func answer(_ question: Autocomplete.IntentQuestion, searches: Bool) async -> Autocomplete.IntentAnswer?
    /// How one thing answers the words (Autocomplete.gradeQuestion). Nil
    /// when it couldn't say, which is taken as not fitting.
    func grade(_ question: String) async -> Autocomplete.IntentGrade?
    /// What someone remembers of a page, as words and days to search the
    /// History list for (HistoryQuery.askInstructions). Nil when it couldn't say.
    func historyQuery(_ text: String, now: Date) async -> HistoryQuery?
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
    /// The system's model, once it has been looked up, and a session made
    /// ready for the next question. Both are made away from the main thread
    /// (prewarm), and only once words are typed that the model may be asked
    /// about (Suggestions.think): the framework's first use reads what the
    /// device can do and loads libraries of its own, and a session's
    /// prewarm starts the model loading. On the main thread, at the first
    /// tap on the address, that came before the keyboard was even asked
    /// for, and was a tenth of what the tap cost there.
    private var model: SystemLanguageModel?
    private var warm: LanguageModelSession?
    private var warming: Task<Void, Never>?

    /// Until the model has been looked up it is taken as ready: what is
    /// asked then waits for the answer (settled), and gets none if the
    /// model turns out not to be there.
    var ready: Bool {
        model?.isAvailable ?? true
    }

    var isKnown: Bool {
        model != nil
    }

    func prewarm() {
        guard warm == nil, warming == nil else { return }
        if let model, !model.isAvailable { return }
        let known = model
        let instructions = Autocomplete.intentInstructions
        warming = Task { [weak self] in
            let made = await Task.detached(priority: .userInitiated) { () -> (SystemLanguageModel, LanguageModelSession?) in
                let model = known ?? SystemLanguageModel.default
                guard model.isAvailable else { return (model, nil) }
                let session = LanguageModelSession(model: model, instructions: instructions)
                session.prewarm()
                return (model, session)
            }.value
            guard let self else { return }
            self.model = made.0
            self.warm = made.1
            self.warming = nil
        }
    }

    /// The model, once any looking up under way is done; nil when it can't answer.
    private func settled() async -> SystemLanguageModel? {
        if model == nil, warming == nil { prewarm() }
        await warming?.value
        guard let model, model.isAvailable else { return nil }
        return model
    }

    func answer(_ question: Autocomplete.IntentQuestion, searches: Bool) async -> Autocomplete.IntentAnswer? {
        guard let model = await settled() else { return nil }
        // A session for each question: a session keeps what it was asked
        // before, and a burst of typing would fill its context.
        let session = warm ?? LanguageModelSession(model: model, instructions: Autocomplete.intentInstructions)
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
        guard let model = await settled() else { return nil }
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

    func historyQuery(_ text: String, now: Date) async -> HistoryQuery? {
        guard let model = await settled() else { return nil }
        let session = LanguageModelSession(model: model, instructions: HistoryQuery.askInstructions)
        do {
            let reply = try await session.respond(to: HistoryQuery.askPrompt(text), generating: HistoryAsk.self,
                                                  options: GenerationOptions(sampling: .greedy)).content
            return HistoryQuery.asked(words: reply.words, when: reply.when, written: text, now: now)
        } catch {
            return nil
        }
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

/// What someone remembers of a page, as the History list searches it: the
/// words, and the days back from today it was in, when they said.
@available(iOS 26.0, *)
@Generable
struct HistoryAsk {
    @Guide(description: "Words to look for in the page's name, address or description, in the language they wrote in. Empty when they only said when")
    var words: String

    @Guide(description: "The words that say when, as they wrote them, such as last Friday, two weeks ago, in September or 지난 금요일. Empty when they didn't say when")
    var when: String
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
