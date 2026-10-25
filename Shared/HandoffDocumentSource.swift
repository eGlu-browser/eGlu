import AVFoundation
import CoreGraphics
import Engines
import Foundation
import PadCore
import PDFKit
import UniformTypeIdentifiers
import WebKit

/// A document handed off: a file chosen or dropped, a download, or a file
/// behind a link, fetched through the tab's own web view (HandoffFetch).
/// The engines turn its bytes into Markdown (Documents), the Markdown
/// becomes a reading like a page's (HandoffDocument), and from there on
/// it is a handoff like any other (HandoffJob). Its kind is told by the
/// file's format, never counted and never asked of the model.
@MainActor
final class DocumentSource: HandoffSource {
    /// Where the file came from, for "Source:" and the prompt; nil for a
    /// file on the device (a local file has no address).
    let address: URL?
    /// The file's name, which the file's heading and its prompt say.
    let title: String
    let isFile = true
    /// What is known of the file, once read (FileFacts).
    private(set) var file: FileFacts?

    /// The file's bytes, or where they are read from. A `link` is fetched
    /// through the tab's own web view (HandoffFetch) when the file is read.
    private let data: Data?
    private let url: URL?
    private let link: URL?
    private weak var view: WKWebView?
    /// The format the tab's kind declared, where bytes and extension don't.
    private let hint: FileFormat?
    /// How far a recording's transcription has got, for the guide; the
    /// job sets it before the file is read.
    var tell: ((Handoff.Stage) -> Void)?

    /// From bytes in hand: a file fetched through a tab (HandoffFetch).
    init(data: Data, name: String, address: URL? = nil) {
        self.data = data
        url = nil
        link = nil
        view = nil
        title = name
        self.address = address
        hint = nil
    }

    /// From where the file is: a chosen or dropped file, or a download.
    init(file url: URL, name: String? = nil, address: URL? = nil, format hint: FileFormat? = nil) {
        data = nil
        self.url = url
        link = nil
        view = nil
        title = name ?? url.lastPathComponent
        self.address = address
        self.hint = hint
    }

    /// From a link to fetch through the tab's own web view, into the
    /// job's folder, when the file is read; its `address` the link's.
    init(link url: URL, view: WKWebView) {
        data = nil
        self.url = nil
        link = url
        self.view = view
        title = url.lastPathComponent
        address = url
        hint = nil
    }

    /// A file over this many bytes is not read.
    static let sizeLimit = 200_000_000
    /// A PDF's pages read at the most.
    static let pageLimit = 300
    /// Extensions a link's menu offers Hand Off for.
    static let linkExtensions: Set<String> = ["pdf", "doc", "docx", "docm", "ppt", "pptx", "xls", "xlsx",
                                             "xlsm", "odt", "ods", "odp", "rtf", "epub", "csv", "json",
                                             "xml", "txt", "zip", "jpg", "jpeg", "png", "heic", "heif",
                                             "gif", "webp", "tif", "tiff"]
    /// The kinds a file picker offers.
    static let contentTypes: [UTType] = linkExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    /// Pages that are only pictures read by Vision at the most.
    static let visionLimit = 30
    /// A PDF's seconds of reading at the most.
    static let readingLimit = Duration.seconds(20)

    func reading(limit: Int, into folder: URL) async -> Handoff.ReadOutcome {
        do {
            let (data, found) = try await Self.open(data: data, url: url, link: link, view: view, name: title,
                                                    hint: hint, into: folder)
            let (markdown, facts, truncated) = try await Self.convert(data, facts: found, room: limit, into: folder, tell: tell)
            file = facts
            let reading = HandoffDocument.reading(markdown: markdown, facts: facts, truncated: truncated)
            return reading.blocks.isEmpty ? .noReadableContent : .content(reading)
        } catch let problem as DocumentProblem {
            return .failed(problem.message)
        } catch let problem as EngineError {
            return problem.kind == .encrypted
                ? .protectedPage(Self.words(for: problem.kind))
                : .failed(Self.words(for: problem.kind))
        } catch {
            return .failed(String(localized: "The file could not be read."))
        }
    }

    func transcript(limit: Int) async -> Transcript? { nil }
    func picture(pixels: Int) async -> CGImage? { nil }

    /// The file's bytes and what it is, told from the bytes themselves
    /// (Documents.detect) or, where they carry no signature, from the
    /// file's extension: CSV, JSON, XML, plain text and ZIP.
    private static func open(data: Data?, url: URL?, link: URL?, view: WKWebView?,
                             name: String, hint: FileFormat?, into folder: URL) async throws -> (Data, FileFacts) {
        var data = data
        if let link {
            guard let view else { throw DocumentProblem(message: String(localized: "The tab it was on is gone.")) }
            let fetched = try await HandoffFetch.fetch(link, with: view, into: folder)
            data = try await bytes(of: nil, url: fetched)
        }
        data = try await bytes(of: data, url: url)
        guard let data else { throw DocumentProblem(message: String(localized: "The file could not be read.")) }
        guard data.count <= sizeLimit else {
            throw DocumentProblem(message: String(localized: "Too large to read: ") + FileFacts.size(data.count) + ".")
        }
        var format = (try? await detect(data)).flatMap(FileFormat.init)
        if format == nil {
            format = FileFormat(ext: url?.pathExtension ?? (name as NSString).pathExtension)
        }
        if format == nil, HandoffPicture.isPicture(data) {
            format = .picture
        }
        if format == nil {
            format = hint
        }
        guard let format else {
            throw DocumentProblem(message: String(localized: "eGlu can't read this kind of file."))
        }
        return (data, FileFacts(format: format, name: name, bytes: data.count))
    }

    /// The file's bytes, from where it is on the device: a dropped or
    /// chosen file's scope is the read's own.
    @concurrent
    private static func bytes(of data: Data?, url: URL?) async throws -> Data {
        if let data { return data }
        guard let url else { throw DocumentProblem(message: String(localized: "The file could not be read.")) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// What the bytes are, away from the main thread.
    @concurrent
    private static func detect(_ data: Data) async throws -> DocumentFormat? {
        try Documents.detect(data)
    }

    /// The document's bytes as Markdown, away from the main thread: the
    /// engines' synchronous work. The third value is `truncated`, true
    /// where the text was cut at `room` at a page's, a sheet's or a
    /// slide's boundary.
    @concurrent
    private static func convert(_ data: Data, facts: FileFacts, room: Int,
                                into folder: URL, tell: ((Handoff.Stage) -> Void)? = nil) async throws -> (String, FileFacts, Bool) {
        var facts = facts
        switch facts.format {
        case .pdf:
            // The first pages at most, each's Markdown; the rest in notRead.
            let asked = Array(0..<pageLimit)
            let whole = try Documents.pdfPages(data, pages: asked)
            facts.pages = whole.pageCount
            facts.title = whole.title
            facts.author = whole.author
            facts.created = whole.created
            facts.notRead = whole.pageCount > pageLimit ? Array(pageLimit + 1...whole.pageCount) : []
            var parts: [String] = []
            var size = 0
            var truncated = !facts.notRead.isEmpty
            // Pages that are only pictures: the first 30 such read on the
            // device by Vision, the whole reading in 20 seconds at most;
            // what is left is named in notRead.
            var pictures = 0
            let clock = ContinuousClock()
            let started = clock.now
            var document: PDFDocument?
            for page in whole.pages {
                var markdown = page.markdown
                if page.needsOCR {
                    pictures += 1
                    if pictures <= Self.visionLimit {
                        if document == nil { document = PDFDocument(data: data) }
                        if let document, let words = try? await HandoffVision.read(document, page: page.page) {
                            markdown = words
                        } else {
                            markdown = ""
                        }
                        if !markdown.isEmpty {
                            facts.readFromPictures.append(page.page + 1)
                        }
                    }
                    if markdown.isEmpty {
                        facts.notRead.append(page.page + 1)
                        continue
                    }
                }
                if size + markdown.count > room {
                    truncated = true
                    facts.notRead += Array(page.page + 1...min(whole.pageCount, pageLimit))
                    break
                }
                if !markdown.isEmpty { parts.append(markdown) }
                size += markdown.count
                // The reading's twenty seconds, checked page by page.
                if clock.now - started > Self.readingLimit {
                    truncated = true
                    facts.notRead += Array(page.page + 1...min(whole.pageCount, pageLimit))
                    break
                }
            }
            facts.notRead = Array(Set(facts.notRead)).sorted()
            return (parts.joined(separator: "\n\n"), facts, truncated)
        case .word, .openText, .rtf, .epub, .powerPoint, .openPresentation, .excel, .openSpreadsheet, .csv:
            guard let format = DocumentFormat(facts.format) else {
                throw DocumentProblem(message: String(localized: "eGlu can't read this kind of file."))
            }
            let answer = try Documents.markdown(data, format: format)
            return (cut(answer.markdown, to: room), facts, answer.markdown.count > room)
        case .text:
            return (String(decoding: data, as: UTF8.self), facts, false)
        case .json:
            return (HandoffDocument.json(data), facts, false)
        case .xml:
            return ("```xml\n" + String(decoding: data, as: UTF8.self) + "\n```", facts, false)
        case .zip:
            return try await archive(data, facts: facts, room: room, into: folder)
        case .picture:
            let (markdown, made) = try await picture(data, facts: facts)
            return (cut(markdown, to: room), made, markdown.count > room)
        case .audio, .video:
            return try await recording(data, facts: facts, into: folder, tell: tell)
        }
    }

    /// The picture read on the device: its own facts, the text in it by
    /// Vision, and what it shows by the model where the model looks at
    /// pictures (iOS 27). On the main actor, so it can ask the model;
    /// called from the engines' work and from an archive's walk alike.
    private static func picture(_ data: Data, facts: FileFacts) async throws -> (String, FileFacts) {
        guard let image = HandoffPicture.thumbnail(data),
              var facts = HandoffPicture.facts(data, into: facts) else {
            throw DocumentProblem(message: String(localized: "The file could not be read."))
        }
        let text = (try? await HandoffVision.read(image)) ?? ""
        var description = ""
        if let mind = await PageMinds.mind(), let said = await mind.describe(image), !said.isEmpty {
            description = "Described by the on-device model, which can be wrong: " + said
            facts.described = true
        }
        return (HandoffPicture.markdown(name: facts.name, description: description, text: text), facts)
    }

    /// The recording read on the device: its duration, its title,
    /// artist and album where the file names them, a video's size, and
    /// the first 15 minutes of its words (HandoffSpeech), which go into
    /// the reading as a YouTube's transcript goes (Transcript.blocks).
    /// The bytes are written to the job's folder for AVURLAsset, and
    /// the guide is told each minute that is done (HandoffJob.tell).
    private static func recording(_ data: Data, facts: FileFacts,
                                  into folder: URL, tell: ((Handoff.Stage) -> Void)?) async throws -> (String, FileFacts, Bool) {
        var facts = facts
        let name = "recording." + (((facts.name as NSString).pathExtension.isEmpty ? "m4a"
            : (facts.name as NSString).pathExtension) as String)
        let file = folder.appendingPathComponent(name)
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let asset = AVURLAsset(url: file)
        let seconds = Int(((try? await asset.load(.duration))?.seconds ?? 0).rounded())
        facts.duration = seconds > 0 ? seconds : nil
        for item in (try? await asset.load(.commonMetadata)) ?? [] {
            let value = try? await item.load(.stringValue)
            guard let value, !value.isEmpty else { continue }
            switch item.commonKey {
            case .commonKeyTitle: facts.title = value
            case .commonKeyArtist: facts.author = value
            case .commonKeyAlbumName: facts.album = value
            default: continue
            }
        }
        if facts.format == .video,
           let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 {
            facts.width = Int(size.width)
            facts.height = Int(size.height)
        }
        var markdown = "# \(facts.name)"
        let heard = try await HandoffSpeech.transcribe(file, seconds: TimeInterval(seconds)) { progress in
            switch progress {
            case .model: tell?(.speechModel)
            case .minutes(let done): tell?(.transcribing(done: done, of: max(1, min(15, Int(ceil(Double(seconds) / 60))))))
            }
        }
        if let heard {
            facts.transcribed = min(heard.seconds, seconds > 0 ? seconds : heard.seconds)
            facts.language = heard.language
            let transcript = Transcript(lines: Self.lines(in: heard.text), cut: seconds > heard.seconds + 30, generated: true)
            markdown += "\n\n" + transcript.blocks(room: 2_000_000).map(\.text).joined(separator: "\n\n")
        } else {
            markdown += "\n\nSpeech recognition on this device can't transcribe this language."
        }
        return (markdown, facts, false)
    }

    /// One line of a transcript per sentence: the speech framework gives
    /// words with no times, so they are not given any.
    private static func lines(in text: String) -> [Transcript.Line] {
        [Transcript.Line(words: text)]
    }

    /// The archive's files, each read as its kind under a heading with
    /// its name; the rest in skipped with why (HandoffArchive.walk).
    /// Encrypted or ZIP64: "eGlu can't open this archive."
    @concurrent
    private static func archive(_ data: Data, facts: FileFacts, room: Int,
                                into folder: URL) async throws -> (String, FileFacts, Bool) {
        var facts = facts
        let items = ZipFile.contents(of: data)
        guard ZipFile.isArchive(data), !items.isEmpty, !ZipFile.isZip64(data),
              !items.contains(where: \.encrypted) else {
            throw DocumentProblem(message: String(localized: "eGlu can't open this archive."))
        }
        let (read, skipped) = HandoffArchive.walk(items) {
            FileFormat(ext: ($0 as NSString).pathExtension) != nil
        }
        facts.entries = read
        facts.skipped = skipped
        var parts: [String] = [], size = 0
        for name in read {
            guard let inside = ZipFile.file(in: data, matching: { $0 == name }) else {
                facts.skipped.append("\(name) (could not be read)")
                continue
            }
            // Detected first, as for the file itself (a .docx's own mark).
            let inner = FileFacts(format: (try? await detect(inside)).flatMap(FileFormat.init)
                                      ?? FileFormat(ext: (name as NSString).pathExtension) ?? .text,
                                  name: name, bytes: inside.count)
            guard let (markdown, _, _) = try? await convert(inside, facts: inner, room: room, into: folder) else {
                facts.skipped.append("\(name) (could not be read)")
                continue
            }
            // A picture's own heading is its name again: the entry's heading stands for it.
            var body = markdown
            if body.hasPrefix("# \(name)\n") { body = String(body.dropFirst(name.count + 3)) }
            parts.append("## \(name)\n\n" + body)
            size += markdown.count
        }
        return (cut(parts.joined(separator: "\n\n"), to: room), facts, size > room)
    }

    /// Text cut at the room the file has, at a boundary of parts, so no
    /// paragraph, row or slide is left half in.
    private nonisolated static func cut(_ text: String, to room: Int) -> String {
        guard text.count > room else { return text }
        let within = text.prefix(room)
        guard let last = within.range(of: "\n\n", options: .backwards) else {
            return String(within)
        }
        return String(within[..<last.lowerBound])
    }

    /// What the guide can say, by what went wrong.
    private static func words(for kind: EngineError.Kind) -> String {
        switch kind {
        case .encrypted: return String(localized: "This file is protected by a password.")
        case .unsupported: return String(localized: "eGlu can't read this kind of file.")
        case .tooLarge: return String(localized: "Too large to read.")
        default: return String(localized: "The file could not be read.")
        }
    }

    /// Why a file was not read: the engines', or the limit's.
    struct DocumentProblem: Error {
        let message: String
    }
}

extension FileFormat {
    /// The file's kind from the kind the tab said it holds: a PDF, a
    /// text, CSV, JSON, XML or picture page ("application/ld+json" is JSON
    /// too; SVG is not read — the web view draws it and Vision can't).
    init?(mimeType: String) {
        switch mimeType {
        case "application/pdf": self = .pdf
        case "text/plain": self = .text
        case "text/csv": self = .csv
        case "application/json": self = .json
        case "application/xml", "text/xml": self = .xml
        default:
            if mimeType.hasSuffix("+json") { self = .json }
            else if mimeType.hasSuffix("+xml") { self = .xml }
            else if mimeType.hasPrefix("image/"), mimeType != "image/svg+xml" { self = .picture }
            else if mimeType.hasPrefix("audio/") { self = .audio }
            else if mimeType.hasPrefix("video/") { self = .video }
            else { return nil }
        }
    }

    /// The file's kind from the format the engines detected.
    init?(_ format: DocumentFormat) {
        switch format {
        case .doc, .docx: self = .word
        case .odt: self = .openText
        case .pdf: self = .pdf
        case .ppt, .pptx: self = .powerPoint
        case .rtf: self = .rtf
        case .epub: self = .epub
        case .excel: self = .excel
        case .ods: self = .openSpreadsheet
        case .odp: self = .openPresentation
        case .csv: self = .csv
        }
    }

    /// The format by the file's extension, where the bytes say nothing:
    /// CSV, JSON, XML, plain text and ZIP, and the engines' own.
    init?(ext: String) {
        switch ext.lowercased() {
        case "pdf": self = .pdf
        case "doc", "docx", "docm": self = .word
        case "odt": self = .openText
        case "rtf": self = .rtf
        case "epub": self = .epub
        case "ppt", "pptx": self = .powerPoint
        case "odp": self = .openPresentation
        case "xls", "xlsx", "xlsm": self = .excel
        case "ods": self = .openSpreadsheet
        case "csv": self = .csv
        case "json": self = .json
        case "xml": self = .xml
        case "txt", "text", "md", "markdown": self = .text
        case "zip": self = .zip
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff": self = .picture
        case "mp3", "m4a", "aac", "wav", "aif", "aiff", "ogg", "oga", "flac", "caf", "opus": self = .audio
        case "mp4", "mov", "m4v", "webm", "mkv", "avi": self = .video
        default: return nil
        }
    }
}

extension DocumentFormat {
    /// The engines' format for a file format, where they read one. It is
    /// never detected from bytes for CSV, and never asked for the rest.
    init?(_ format: FileFormat) {
        switch format {
        case .word: self = .docx
        case .openText: self = .odt
        case .pdf: self = .pdf
        case .powerPoint: self = .pptx
        case .rtf: self = .rtf
        case .epub: self = .epub
        case .excel: self = .excel
        case .openSpreadsheet: self = .ods
        case .openPresentation: self = .odp
        case .csv: self = .csv
        case .json, .xml, .text, .zip, .picture, .audio, .video: return nil
        }
    }
}
