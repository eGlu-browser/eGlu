import CoreGraphics
import Foundation
import FoundationModels
import PadCore

/// What the model is asked about a page for a handoff: what it reads
/// (Handoff.brief), from the fullest to the shortest, the shorter ones for
/// a prompt that turned out too long, and whether it is also to pick parts
/// of the page.
struct PageQuestion {
    let briefs: [String]
    let picks: Bool
}

/// Apple Intelligence's on-device model, asked once for a handoff what the
/// page on screen is: its kind, a sentence or two on it, and which of its
/// parts say the most (Handoff.kindInstructions, pickInstructions). The
/// model is on the device, and nothing it reads leaves it.
///
/// A thing of Handoff's own, apart from the address bar's use of the model
/// (Intelligence.swift): another question, another answer, and a session
/// for each handoff with nothing kept between them.
///
/// Only on iOS and iPadOS 26 and later, on a device with Apple Intelligence
/// turned on. Without it a handoff tells the page's kind by counting.
@MainActor
protocol PageMind: AnyObject {
    /// `picture` is asked for a small picture of the page only where the
    /// model looks at pictures (iOS 27) and `looks` says this page is worth
    /// one. Nil when it couldn't say: a refusal, a language it doesn't
    /// have, a handoff called off.
    func read(_ question: PageQuestion, looks: Bool, picture: @MainActor () async -> CGImage?) async -> PageAnswer?
}

enum PageMinds {
    /// The model, where this version of the system has it.
    @MainActor static func model() -> PageMind? {
        guard #available(iOS 26.0, *) else { return nil }
        return OnDevicePageMind()
    }

    /// Whether the model is left alone for now: in Low Power Mode, and
    /// while the device says it is hot. Running a language model is the
    /// most the app ever asks of the device, and what it adds to a handoff
    /// is an extra: the page's kind is still told by counting.
    static var spares: Bool {
        let process = ProcessInfo.processInfo
        return process.isLowPowerModeEnabled || process.thermalState == .serious || process.thermalState == .critical
    }
}

@available(iOS 26.0, *)
@MainActor
private final class OnDevicePageMind: PageMind {
    /// The system's model, once it has been looked up, away from the main
    /// thread: the framework's first use reads what the device can do and
    /// loads libraries of its own.
    private var model: SystemLanguageModel?

    /// How many tokens the brief may be: the model reads 4,096 at once,
    /// its instructions, the shape of its answer, a picture and the answer
    /// itself among them.
    private static let room = 2_400

    private func found() async -> SystemLanguageModel? {
        if model == nil {
            model = await Task.detached(priority: .userInitiated) { SystemLanguageModel.default }.value
        }
        guard let model, model.isAvailable else { return nil }
        return model
    }

    func read(_ question: PageQuestion, looks: Bool, picture: @MainActor () async -> CGImage?) async -> PageAnswer? {
        guard let model = await found() else { return nil }
        var briefs = question.briefs
        // Counted where the system counts, so that no try is spent on
        // finding out: the fullest that fits and those shorter, or the
        // shortest where none is known to.
        if #available(iOS 26.4, *) {
            var fitting: [String] = []
            for brief in briefs {
                if let tokens = try? await model.tokenCount(for: brief), tokens > Self.room { continue }
                fitting.append(brief)
            }
            briefs = fitting.isEmpty ? Array(briefs.suffix(1)) : fitting
        }
        guard let first = briefs.first, !Task.isCancelled else { return nil }
        var shown: CGImage?
        if #available(iOS 27.0, *), looks, model.capabilities.contains(.vision) { shown = await picture() }

        // With the picture, then without it, then with less to read: the
        // first that answers. A session each, since one that failed keeps
        // what it was asked.
        var tries: [(brief: String, picture: CGImage?)] = shown.map { [(first, $0)] } ?? []
        tries += briefs.map { ($0, nil) }
        for attempt in tries {
            guard !Task.isCancelled else { return nil }
            if let answer = await ask(model, attempt.brief, picture: attempt.picture, picks: question.picks) { return answer }
        }
        return nil
    }

    private func ask(_ model: SystemLanguageModel, _ brief: String, picture: CGImage?, picks: Bool) async -> PageAnswer? {
        let instructions = Handoff.kindInstructions + (picks ? Handoff.pickInstructions : "")
        let session = LanguageModelSession(model: model, instructions: instructions)
        let options = GenerationOptions(samplingMode: .greedy)
        if picks {
            let reply: PageReadWithPicks?
            if #available(iOS 27.0, *), let picture {
                reply = try? await session.respond(generating: PageReadWithPicks.self, options: options) {
                    brief
                    Attachment(picture)
                }.content
            } else {
                reply = try? await session.respond(to: brief, generating: PageReadWithPicks.self, options: options).content
            }
            guard let reply, !Task.isCancelled else { return nil }
            return PageAnswer(kind: reply.kind.kind, about: reply.about,
                              picks: reply.picks.map { PageAnswer.Pick(number: $0.number, name: $0.name) })
        }
        let reply: PageRead?
        if #available(iOS 27.0, *), let picture {
            reply = try? await session.respond(generating: PageRead.self, options: options) {
                brief
                Attachment(picture)
            }.content
        } else {
            reply = try? await session.respond(to: brief, generating: PageRead.self, options: options).content
        }
        guard let reply, !Task.isCancelled else { return nil }
        return PageAnswer(kind: reply.kind.kind, about: reply.about)
    }
}

/// What the model makes of a page for a handoff. What it is comes first:
/// having said that, the model picks the kind that fits its own words.
@available(iOS 26.0, *)
@Generable
struct PageRead {
    /// Four kinds, though Handoff knows eight: the model is right less
    /// often the more it has to choose from, and the other four are told
    /// by how a page is built (Handoff.kind).
    @Generable
    enum Kind {
        case article
        case landing
        case app
        case other

        var kind: PageKind {
            switch self {
            case .article: return .article
            case .landing: return .landing
            case .app: return .app
            case .other: return .other
            }
        }
    }

    @Guide(description: "One or two plain sentences in English saying what this page, product or tool is, from what the page says and shows. No Markdown")
    var about: String

    @Guide(description: "The kind of page: article, landing, app or other")
    var kind: Kind
}

/// A part the model picks from the list it was given: its name first,
/// which is what makes it look for the line, then the line's number.
@available(iOS 26.0, *)
@Generable
struct PagePick {
    @Guide(description: "The part's name, copied from the list")
    var name: String

    @Guide(description: "The part's number in the list")
    var number: Int
}

/// The same answer with the parts picked, on a page where parts would
/// otherwise only be started (Handoff.candidates).
@available(iOS 26.0, *)
@Generable
struct PageReadWithPicks {
    @Guide(description: "One or two plain sentences in English saying what this page, product or tool is, from what the page says and shows. No Markdown")
    var about: String

    @Guide(description: "The kind of page: article, landing, app or other")
    var kind: PageRead.Kind

    @Guide(description: "Up to three parts from the list that say the most about what the page offers. Empty when none stands out",
           .maximumCount(3))
    var picks: [PagePick]
}
