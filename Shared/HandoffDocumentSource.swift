import CoreGraphics
import Engines
import Foundation
import PadCore
import PDFKit

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

    /// The file's bytes, or where they are read from.
    private let data: Data?
    private let url: URL?

    /// From bytes in hand: a file fetched through a tab (HandoffFetch).
    init(data: Data, name: String, address: URL? = nil) {
        self.data = data
        url = nil
        title = name
        self.address = address
    }

    /// From where the file is: a chosen or dropped file, or a download.
    init(file url: URL, name: String? = nil, address: URL? = nil) {
        data = nil
        self.url = url
        title = name ?? url.lastPathComponent
        self.address = address
    }

    /// A file over this many bytes is not read.
    static let sizeLimit = 200_000_000
    /// A PDF's pages read at the most.
    static let pageLimit = 300
    /// Pages that are only pictures read by Vision at the most.
    static let visionLimit = 30
    /// A PDF's seconds of reading at the most.
    static let readingLimit = Duration.seconds(20)

    func reading(limit: Int, into folder: URL) async -> Handoff.ReadOutcome {
        do {
            let (data, found) = try await Self.open(data: data, url: url, name: title)
            let (markdown, facts, truncated) = try await Self.convert(data, facts: found, room: limit)
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
    private static func open(data: Data?, url: URL?, name: String) async throws -> (Data, FileFacts) {
        let data = try await bytes(of: data, url: url)
        guard data.count <= sizeLimit else {
            throw DocumentProblem(message: String(localized: "Too large to read: ") + FileFacts.size(data.count) + ".")
        }
        var format = (try? await detect(data)).flatMap(FileFormat.init)
        if format == nil {
            format = FileFormat(ext: url?.pathExtension ?? (name as NSString).pathExtension)
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
    private static func convert(_ data: Data, facts: FileFacts, room: Int) async throws -> (String, FileFacts, Bool) {
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
        case .json, .xml, .zip:
            // PR4: JSON formatted, XML fenced, a ZIP's files walked.
            throw DocumentProblem(message: String(localized: "eGlu can't read this kind of file."))
        }
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
        case .json, .xml, .text, .zip: return nil
        }
    }
}
