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

    /// From bytes in hand: a file fetched through a tab (HandoffFetch).
    init(data: Data, name: String, address: URL? = nil) {
        self.data = data
        url = nil
        link = nil
        view = nil
        title = name
        self.address = address
    }

    /// From where the file is: a chosen or dropped file, or a download.
    init(file url: URL, name: String? = nil, address: URL? = nil) {
        data = nil
        self.url = url
        link = nil
        view = nil
        title = name ?? url.lastPathComponent
        self.address = address
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
    }

    /// A file over this many bytes is not read.
    nonisolated static let sizeLimit = 200_000_000
    /// A PDF's pages read at the most.
    nonisolated static let pageLimit = 300
    /// Extensions a link's menu offers Handoff for.
    static let linkExtensions: Set<String> = ["pdf", "doc", "docx", "docm", "ppt", "pptx", "xls", "xlsx",
                                             "xlsm", "odt", "ods", "odp", "rtf", "epub", "csv", "json",
                                             "xml", "txt", "zip"]
    /// The kinds a file picker offers.
    static let contentTypes: [UTType] = linkExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    /// Pages that are only pictures read by Vision at the most.
    nonisolated static let visionLimit = 30
    /// A PDF's seconds of reading at the most, from when it is opened:
    /// what is read by then goes, and the rest is named as not read.
    nonisolated static let readingLimit = Duration.seconds(20)

    func reading(limit: Int, into folder: URL) async -> Handoff.ReadOutcome {
        do {
            let opened = try await Self.open(data: data, url: url, link: link, view: view, name: title, into: folder)
            let (reading, facts) = try await Self.convert(opened.data, facts: opened.facts, engine: opened.engine, room: limit)
            file = facts
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
    /// file's extension: CSV, JSON, XML, plain text and ZIP. `engine` is
    /// the engines' own name for it, which says more than its kind does:
    /// a .doc is Word's as a .docx is, and needs another reader.
    private static func open(data: Data?, url: URL?, link: URL?, view: WKWebView?, name: String, into folder: URL) async throws
        -> (data: Data, facts: FileFacts, engine: DocumentFormat?) {
        var given = data
        if let link {
            guard let view else { throw DocumentProblem(message: String(localized: "The tab it was on is gone.")) }
            let fetched = try await HandoffFetch.fetch(link, with: view, into: folder)
            given = try await bytes(of: nil, url: fetched)
        }
        let data = try await bytes(of: given, url: url)
        guard data.count <= sizeLimit else {
            throw DocumentProblem(message: String(localized: "Too large to read: \(FileFacts.size(data.count))."))
        }
        let ext = url?.pathExtension ?? (name as NSString).pathExtension
        let engine = (try? await detect(data)) ?? DocumentFormat(ext: ext)
        guard let format = engine.flatMap(FileFormat.init) ?? FileFormat(ext: ext) else {
            throw DocumentProblem(message: String(localized: "eGlu can't read this kind of file."))
        }
        return (data, FileFacts(format: format, name: name, bytes: data.count), engine)
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

    /// The document's bytes read, away from the main thread: the engines'
    /// synchronous work, and the reading made of their Markdown, cut at
    /// `room` where a page, a sheet or a part of the file ends.
    @concurrent
    private static func convert(_ data: Data, facts: FileFacts, engine: DocumentFormat?, room: Int) async throws
        -> (PageReading, FileFacts) {
        let (markdown, facts, truncated) = try await markdown(data, facts: facts, engine: engine, room: room)
        return (HandoffDocument.reading(markdown: markdown, facts: facts, truncated: truncated), facts)
    }

    /// The document's Markdown and what is known of it, the third value
    /// `truncated`: true where it was cut to fit `room`, or a PDF's time ran out.
    @concurrent
    private static func markdown(_ data: Data, facts: FileFacts, engine: DocumentFormat?, room: Int) async throws
        -> (String, FileFacts, Bool) {
        var facts = facts
        switch facts.format {
        case .pdf:
            // The time from here: the engines' reading of the pages counts too.
            return try await pdf(data, facts: facts, room: room, by: .now + readingLimit)
        case .word, .openText, .rtf, .epub, .powerPoint, .openPresentation, .excel, .openSpreadsheet, .csv:
            guard let format = engine ?? DocumentFormat(facts.format) else {
                throw DocumentProblem(message: String(localized: "eGlu can't read this kind of file."))
            }
            let whole = try Documents.markdown(data, format: format).markdown
            // What an Office file says of itself; the engines give its words alone.
            let declared = HandoffDocument.declared(in: data)
            if facts.format == .word { facts.pages = declared.pages }
            if facts.format == .powerPoint { facts.slides = declared.slides }
            if facts.format == .excel || facts.format == .openSpreadsheet { facts.sheets = HandoffDocument.sheets(in: whole) }
            facts.title = declared.title
            facts.author = declared.author
            facts.created = declared.created
            let fitted = HandoffDocument.fitted(whole, room: room)
            facts.unread = fitted.unread
            return (fitted.markdown, facts, fitted.truncated)
        case .text:
            let fitted = HandoffDocument.fitted(String(decoding: data, as: UTF8.self), room: room)
            facts.unread = fitted.unread
            return (fitted.markdown, facts, fitted.truncated)
        case .json, .xml, .zip:
            // PR4: JSON formatted, XML fenced, a ZIP's files walked.
            throw DocumentProblem(message: String(localized: "eGlu can't read this kind of file."))
        }
    }

    /// A PDF's first pages, each's Markdown in order, and the first 30
    /// that are only pictures read on the device by Vision (Decided 6
    /// and 7). Nothing is begun past `deadline`, nor waited for past it,
    /// nor once the handoff is called off: the pages from there are named
    /// as not read, as those past the first 300 and past `room` are.
    @concurrent
    private static func pdf(_ data: Data, facts: FileFacts, room: Int, by deadline: ContinuousClock.Instant) async throws
        -> (String, FileFacts, Bool) {
        var facts = facts
        let whole = try Documents.pdfPages(data, pages: Array(0..<pageLimit))
        facts.pages = whole.pageCount
        facts.title = whole.title
        facts.author = whole.author
        facts.created = whole.created
        let last = min(whole.pageCount, pageLimit)
        var notRead = whole.pageCount > pageLimit ? Array(pageLimit + 1...whole.pageCount) : []
        var truncated = !notRead.isEmpty
        var parts: [String] = []
        var size = 0
        var pictures = 0
        var document: PDFDocument?
        for page in whole.pages {
            let number = page.page + 1
            guard ContinuousClock.now < deadline, !Task.isCancelled else {
                truncated = true
                notRead += Array(number...max(number, last))
                break
            }
            var markdown = page.markdown
            if page.needsOCR {
                pictures += 1
                markdown = ""
                if pictures <= visionLimit {
                    if document == nil { document = PDFDocument(data: data) }
                    if let image = document.flatMap({ HandoffVision.draw($0, page: page.page) }) {
                        markdown = await HandoffTime.value(by: deadline) { (try? await HandoffVision.read(image)) ?? "" } ?? ""
                    }
                }
                guard !markdown.isEmpty else {
                    notRead.append(number)
                    continue
                }
            }
            if size + markdown.count > room {
                truncated = true
                notRead += Array(number...max(number, last))
                break
            }
            if page.needsOCR { facts.readFromPictures.append(number) }
            if !markdown.isEmpty { parts.append(markdown) }
            size += markdown.count + 2
        }
        facts.notRead = Array(Set(notRead)).sorted()
        return (parts.joined(separator: "\n\n"), facts, truncated)
    }

    /// What the guide can say, by what went wrong.
    private static func words(for kind: EngineError.Kind) -> String {
        switch kind {
        case .encrypted: return String(localized: "This file is protected by a password.")
        case .unsupported: return String(localized: "eGlu can't read this kind of file.")
        case .tooLarge: return String(localized: "This file is too large to read.")
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
    nonisolated init?(_ format: DocumentFormat) {
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
    nonisolated init?(ext: String) {
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
    /// The engines' format by the file's extension, where the bytes say
    /// nothing the engines know: CSV always, and a file too short or
    /// damaged to tell.
    nonisolated init?(ext: String) {
        switch ext.lowercased() {
        case "pdf": self = .pdf
        case "doc": self = .doc
        case "docx", "docm": self = .docx
        case "odt": self = .odt
        case "rtf": self = .rtf
        case "epub": self = .epub
        case "ppt": self = .ppt
        case "pptx": self = .pptx
        case "odp": self = .odp
        case "xls", "xlsx", "xlsm": self = .excel
        case "ods": self = .ods
        case "csv": self = .csv
        default: return nil
        }
    }

    /// The engines' format for a file format, where they read one. It is
    /// never detected from bytes for CSV, and never asked for the rest.
    nonisolated init?(_ format: FileFormat) {
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
