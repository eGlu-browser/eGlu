import AVFoundation
import Foundation
import PadCore
#if canImport(Speech)
import Speech
#endif

/// A recording's words into text, on the device and nowhere else
/// (Decided 7 and 8): the Speech framework's own analyzer where it is
/// there (iOS 26, macOS 26), and `SFSpeechRecognizer` held to on-device
/// before it. Only the device's own language where speech recognition
/// supports it; where it does not, there is no transcript at all, which
/// the file says (Flaw.cannotHear). Permission is asked the first time,
/// by the recognizer itself; a model the system has yet to fetch is
/// waited for while the guide says it is being got.
enum HandoffSpeech {

    /// What was heard: the words, the language they were heard in, and
    /// how many seconds of the recording they cover.
    struct Said: Sendable {
        var text: String
        var language: String
        var seconds: Int
    }

    /// How far it has got, for the guide's line under the step.
    enum Progress: Sendable {
        /// The speech model is being fetched by the system.
        case model
        /// Minutes of the recording heard so far.
        case minutes(Int)
    }

    /// Why there is no transcript to write.
    enum Flaw: Error {
        /// Speech recognition on this device can't transcribe this language.
        case cannotHear
    }

    /// The recording's first `upTo` seconds of words, with at most
    /// `within` seconds spent on them (what was heard by then is kept).
    /// Nil where the person said no; a Flaw.cannotHear where the device
    /// can't hear the language at all.
    @MainActor
    static func transcribe(_ file: URL, seconds total: TimeInterval, upTo: TimeInterval = 900,
                           within: TimeInterval = 90, progress: @escaping @MainActor (Progress) -> Void = { _ in }) async throws -> Said? {
        #if canImport(Speech)
        let heard = Partial(total: min(total, upTo), progress: progress)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    if #available(iOS 26.0, macOS 26.0, *) {
                        try await Self.analyze(file, upTo: upTo, heard: heard)
                    } else {
                        try await Self.recognize(file, upTo: upTo, heard: heard)
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(within))
                    try Task.checkCancellation()
                    throw TimedOut()
                }
                _ = try await group.next()
                group.cancelAll()
            }
        } catch is TimedOut {
            // What was heard in the time is kept, as far as it goes.
        } catch let flaw as Flaw {
            throw flaw
        } catch {
            return nil
        }
        let said = heard.said()
        return said.text.isEmpty ? nil : said
        #else
        return nil
        #endif
    }

    private struct TimedOut: Error {}

    /// What the recognizers have heard so far, whatever thread they say it on.
    private final class Partial: @unchecked Sendable {
        private let lock = NSLock()
        private var words = ""
        private var seconds = 0
        private var minute = 0
        var language = ""
        /// How many minutes there are to do, as the guide's line counts them.
        let total: Int
        let progress: @MainActor (Progress) -> Void

        init(total: TimeInterval, progress: @escaping @MainActor (Progress) -> Void) {
            self.total = max(1, Int(ceil(total / 60)))
            self.progress = progress
        }

        func model() {
            Task { @MainActor in progress(.model) }
        }

        /// More words heard, ending this many seconds in. Times given by
        /// both recognizers are of the end of what they last said.
        func add(_ text: String, at end: TimeInterval) {
            heard(text, isWhole: false, at: end)
        }

        /// A recognizer that gives its words again whole each time
        /// (SFSpeechRecognizer's partial results): replace, not append.
        func set(_ text: String, at end: TimeInterval) {
            heard(text, isWhole: true, at: end)
        }

        private func heard(_ text: String, isWhole: Bool, at end: TimeInterval) {
            lock.lock()
            if isWhole { if !text.isEmpty { words = text } }
            else if !text.isEmpty { words += (words.isEmpty ? "" : " ") + text }
            seconds = max(seconds, Int(end))
            let done = min(total, seconds / 60)
            let newMinute = done > minute
            if newMinute { minute = done }
            lock.unlock()
            if newMinute {
                Task { @MainActor in progress(.minutes(done)) }
            }
        }

        func said() -> Said {
            lock.lock()
            defer { lock.unlock() }
            return Said(text: words, language: language, seconds: seconds)
        }
    }

    #if canImport(Speech)
    /// The name a recording's language is called in the file, as the
    /// person knows it: "English".
    private static func name(of locale: Locale) -> String {
        locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? locale.identifier) ?? locale.identifier
    }

    /// SpeechAnalyzer and SpeechTranscriber, on iOS and macOS 26: no
    /// permission is asked, the system's model is fetched where it has
    /// yet to be, and the device's own language where it is supported.
    @available(iOS 26.0, macOS 26.0, *)
    private static func analyze(_ file: URL, upTo limit: TimeInterval, heard: Partial) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw Flaw.cannotHear
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            heard.model()
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw Flaw.cannotHear
            }
            try await request.downloadAndInstall()
        }
        heard.language = name(of: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let analyzed: Void = analyze(analyzer, file: file)
        for try await result in transcriber.results {
            let end = CMTimeRangeGetEnd(result.range).seconds
            heard.add(String(result.text.characters), at: end)
            if end >= limit { break }
        }
        try await analyzed
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func analyze(_ analyzer: SpeechAnalyzer, file: URL) async throws {
        let audio = try AVAudioFile(forReading: file)
        if let last = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalize(through: last)
        }
    }

    /// SFSpeechRecognizer before iOS and macOS 26, held to the device
    /// alone: only where it can hear the language on the device, and
    /// asked the person the first time a recording is handed off.
    private static func recognize(_ file: URL, upTo limit: TimeInterval, heard: Partial) async throws {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw Flaw.cannotHear
        }
        heard.language = name(of: Locale.current)
        let status = await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
        }
        guard status == .authorized else { return }
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        if #available(iOS 16, macOS 13, *) { request.addsPunctuation = true }
        var task: SFSpeechRecognitionTask?
        var finished = false
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let end = result.speechRecognitionMetadata?.speechDuration ?? 0
                    heard.set(result.bestTranscription.formattedString, at: end)
                    if end >= limit { task?.cancel() }
                }
                guard !finished, error != nil || result?.isFinal == true else { return }
                finished = true
                // A task cancelled at the limit is still a transcript.
                if let error, (error as NSError).code != 216 { done.resume(throwing: error) }
                else { done.resume() }
            }
        }
    }
    #endif
}
