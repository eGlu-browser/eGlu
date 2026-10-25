import AVFoundation
import Foundation
import PadCore
#if canImport(Speech)
import Speech
#endif

/// A recording's words into text, on the device and nowhere else
/// (Decided 7 and 8): the Speech framework's own analyzer where it is
/// there (iOS 26, macOS 26), and `SFSpeechRecognizer` held to on-device
/// before it. In the device's language where speech recognition on the
/// device hears it, else in English; where it hears neither, there is no
/// transcript, which the file says. Permission is asked the first time,
/// by the recognizer itself; a model the system has yet to fetch is
/// waited for while the guide says it is being got.
///
/// Only the first 15 minutes are heard: they are taken out of the
/// recording first, its sound alone (a video's too), so neither
/// recognizer is given the rest, and each comes to the end of what it
/// was given and stops.
nonisolated enum HandoffSpeech {

    /// What was heard: its lines with when each is said, the language
    /// they were heard in, and how many seconds of the recording they
    /// cover.
    struct Said: Sendable {
        var lines: [Transcript.Line]
        var language: String
        var seconds: Int
    }

    /// Why there is no transcript.
    enum Unheard: Error {
        /// Speech recognition on this device hears neither the device's
        /// language nor English.
        case language
        /// The person said no to speech recognition, or it is off.
        case permission
        /// Nothing was heard: no speech, or no sound to take.
        case silence
    }

    /// How far it has got, for the guide's line under the step.
    enum Progress: Sendable {
        /// The speech model is being fetched by the system.
        case model
        /// Minutes of the recording heard so far, of the minutes to hear.
        case minutes(Int, of: Int)
    }

    /// The recording's first `upTo` seconds of words, with at most
    /// `within` spent on them, the model's fetch included: what was heard
    /// by then is kept, and the recognizer is called off and not waited
    /// for (HandoffTime).
    static func transcribe(_ file: URL, seconds total: TimeInterval, upTo: TimeInterval = 900, within: Duration = .seconds(90),
                           in folder: URL, progress: @escaping @MainActor @Sendable (Progress) -> Void) async -> Result<Said, Unheard> {
        #if canImport(Speech)
        let deadline = ContinuousClock.now + within
        let heard = Partial(minutes: max(1, Int((min(total > 0 ? total : upTo, upTo) / 60).rounded(.up))), progress: progress)
        // Nil where it came to the end, or its time did: what was heard stands either way.
        let problem = await HandoffTime.value(by: deadline) { () async -> Unheard? in
            do {
                let sound = try await Self.sound(of: file, upTo: upTo, in: folder)
                defer { try? FileManager.default.removeItem(at: sound) }
                if #available(iOS 26.0, macOS 26.0, *) {
                    try await Self.analyze(sound, heard: heard)
                } else {
                    try await Self.recognize(sound, heard: heard, by: deadline)
                }
                // Heard to the end of what it was given, silence at the end and all.
                if total > 0 { heard.reached(min(total, upTo)) }
                return nil
            } catch let unheard as Unheard {
                return unheard
            } catch {
                // Called off or failed part way: what was heard so far stands.
                return nil
            }
        }
        if let problem, heard.isEmpty { return .failure(problem) }
        let said = heard.said()
        return said.lines.isEmpty ? .failure(.silence) : .success(said)
        #else
        return .failure(.language)
        #endif
    }

    /// The recording's sound, its first `upTo` seconds alone, as a file of
    /// its own in the job's folder: what the recognizers are given.
    private static func sound(of file: URL, upTo: TimeInterval, in folder: URL) async throws -> URL {
        let asset = AVURLAsset(url: file)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw Unheard.silence }
        let out = folder.appendingPathComponent("heard-\(UUID().uuidString).m4a")
        session.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: upTo, preferredTimescale: 600))
        #if os(iOS)
        if #available(iOS 18, *) {
            try await session.export(to: out, as: .m4a)
        } else {
            try await exported(session, to: out)
        }
        #else
        try await session.export(to: out, as: .m4a)
        #endif
        return out
    }

    #if os(iOS)
    /// Before iOS 18, the export's own way, called off with the task.
    private static func exported(_ session: AVAssetExportSession, to out: URL) async throws {
        session.outputURL = out
        session.outputFileType = .m4a
        let export = Exporting(session)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                export.session.exportAsynchronously {
                    if export.session.status == .completed {
                        done.resume()
                    } else {
                        done.resume(throwing: export.session.error ?? Unheard.silence)
                    }
                }
            }
        } onCancel: {
            export.session.cancelExport()
        }
    }

    /// The export session, between the thread it was begun on and those
    /// its end and its cancel come from: AVFoundation's to keep safe.
    private final class Exporting: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }
    #endif

    /// What the recognizers have heard so far, whatever thread they say it on.
    private final class Partial: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [Transcript.Line] = []
        /// SFSpeechRecognizer gives its words again whole each time: they replace, not add.
        private var whole: [Transcript.Line]?
        private var seconds = 0
        private var minute = 0
        private var spoken = ""
        /// How many minutes there are to hear, as the guide's line counts them.
        let minutes: Int
        let progress: @MainActor @Sendable (Progress) -> Void

        init(minutes: Int, progress: @escaping @MainActor @Sendable (Progress) -> Void) {
            self.minutes = minutes
            self.progress = progress
        }

        var language: String {
            get { lock.withLock { spoken } }
            set { lock.withLock { spoken = newValue } }
        }

        var isEmpty: Bool { lock.withLock { lines.isEmpty && (whole ?? []).isEmpty } }

        func model() {
            let progress = progress
            Task { @MainActor in progress(.model) }
        }

        /// More words heard, from `start` to `end` seconds in.
        func add(_ text: String, from start: TimeInterval, to end: TimeInterval) {
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !words.isEmpty else { return }
            heard(at: end) { $0.lines.append(Transcript.Line(time: Self.time(start), words: words)) }
        }

        /// What SFSpeechRecognizer has heard so far, given whole each time.
        func set(_ lines: [Transcript.Line], to end: TimeInterval) {
            heard(at: end) { $0.whole = lines }
        }

        private func heard(at end: TimeInterval, _ change: (Partial) -> Void) {
            let done: Int? = lock.withLock {
                change(self)
                seconds = max(seconds, Int(end))
                let now = min(minutes, seconds / 60)
                guard now > minute else { return nil }
                minute = now
                return now
            }
            if let done {
                let progress = progress, minutes = minutes
                Task { @MainActor in progress(.minutes(done, of: minutes)) }
            }
        }

        /// Heard to `end`, where the recognizer came to the end of the sound.
        func reached(_ end: TimeInterval) {
            lock.withLock { seconds = max(seconds, Int(end)) }
        }

        func said() -> Said {
            lock.withLock { Said(lines: whole ?? lines, language: spoken, seconds: seconds) }
        }

        /// A moment in the recording as a transcript writes it: 4:05, 1:02:10.
        static func time(_ seconds: TimeInterval) -> String {
            let whole = max(0, Int(seconds))
            let (hours, minutes, rest) = (whole / 3600, whole / 60 % 60, whole % 60)
            return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
        }
    }

    #if canImport(Speech)
    /// The name a recording's language is called in the file, as the
    /// person knows it: "English".
    private static func name(of locale: Locale) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? locale.identifier)
            ?? locale.identifier
    }

    /// SpeechAnalyzer and SpeechTranscriber, on iOS and macOS 26: no
    /// permission is asked, the system's model is fetched where it has
    /// yet to be. The analyzer finishes at the end of the sound it was
    /// given, and its results end with it.
    @available(iOS 26.0, macOS 26.0, *)
    private static func analyze(_ sound: URL, heard: Partial) async throws {
        var found = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        if found == nil { found = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale = found else { throw Unheard.language }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            heard.model()
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
                throw Unheard.language
            }
            try await request.downloadAndInstall()
        }
        heard.language = name(of: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await withTaskCancellationHandler {
            async let analyzed: Void = finish(analyzer, hearing: sound)
            for try await result in transcriber.results {
                heard.add(String(result.text.characters), from: result.range.start.seconds,
                          to: CMTimeRangeGetEnd(result.range).seconds)
            }
            try await analyzed
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    /// The sound given to the analyzer whole, then its results finalized
    /// and the analysis finished, which ends the transcriber's results:
    /// finalizing alone leaves them open for more.
    @available(iOS 26.0, macOS 26.0, *)
    private static func finish(_ analyzer: SpeechAnalyzer, hearing sound: URL) async throws {
        let audio = try AVAudioFile(forReading: sound)
        if let last = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
    }

    /// SFSpeechRecognizer before iOS and macOS 26, held to the device
    /// alone: in the device's language or else English, where it hears
    /// that on the device, and asked the person the first time a recording
    /// is handed off. Called off, the recognition and the question both are.
    private static func recognize(_ sound: URL, heard: Partial, by deadline: ContinuousClock.Instant) async throws {
        let recognizer = [Locale.current, Locale(identifier: "en-US")].lazy
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.isAvailable && $0.supportsOnDeviceRecognition }
        guard let recognizer else { throw Unheard.language }
        heard.language = name(of: recognizer.locale)
        // The question unanswered is no reason to wait past the time: it is left behind, as the rest is.
        let status = await HandoffTime.value(by: deadline) { () async -> SFSpeechRecognizerAuthorizationStatus? in
            await withCheckedContinuation { done in
                SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0) }
            }
        }
        guard status == .authorized else { throw Unheard.permission }
        let request = SFSpeechURLRecognitionRequest(url: sound)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let running = Running()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                running.start(done) {
                    recognizer.recognitionTask(with: request) { result, error in
                        if let result {
                            let segments = result.bestTranscription.segments
                            let end = segments.last.map { $0.timestamp + $0.duration } ?? 0
                            heard.set(Self.lines(of: result.bestTranscription.formattedString), to: end)
                        }
                        if let error { running.end(.failure(error)) } else if result?.isFinal == true { running.end(.success(())) }
                    }
                }
            }
        } onCancel: {
            running.cancel()
        }
    }

    /// The recognizer's words in lines of about a paragraph's sentences,
    /// with no times: SFSpeechRecognizer gives them for each word alone.
    private static func lines(of text: String) -> [Transcript.Line] {
        var lines: [Transcript.Line] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence, !sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(Transcript.Line(words: sentence.trimmingCharacters(in: .whitespaces)))
            }
        }
        return lines
    }

    /// One recognition task and the wait for it, ended once: by the task,
    /// or called off, which cancels the task.
    private final class Running: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: CheckedContinuation<Void, Error>?
        private var task: SFSpeechRecognitionTask?
        private var over = false

        func start(_ continuation: CheckedContinuation<Void, Error>, _ make: () -> SFSpeechRecognitionTask) {
            lock.lock()
            guard !over else {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            waiting = continuation
            lock.unlock()
            let made = make()
            let late: Bool = lock.withLock {
                task = made
                return over
            }
            if late { made.cancel() }
        }

        func end(_ result: Result<Void, Error>) {
            let waiting: CheckedContinuation<Void, Error>? = lock.withLock {
                guard !over else { return nil }
                over = true
                defer { self.waiting = nil }
                return self.waiting
            }
            waiting?.resume(with: result)
        }

        func cancel() {
            let task = lock.withLock { self.task }
            end(.failure(CancellationError()))
            task?.cancel()
        }
    }
    #endif
}
