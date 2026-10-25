import EgluEnginesC
import Foundation

/// A document format anydoc converts, named by its usual extension.
public enum DocumentFormat: String, Sendable, Codable {
    case doc, docx, odt, pdf, ppt, pptx, rtf, epub, excel, ods, odp, csv
}

/// A PDF's pages one by one, from `Documents.pdfPages`.
public struct PDFPages: Sendable, Equatable, Codable {
    public struct Page: Sendable, Equatable, Codable {
        /// The page number, 0-based.
        public var page: Int
        public var markdown: String
        /// The page holds no readable text (a scan or picture): it needs OCR.
        public var needsOCR: Bool
        public var reason: String?
    }

    public var pageCount: Int
    public var title: String?
    public var author: String?
    public var created: String?
    public var pages: [Page]
    /// 0-based numbers of pages holding tables / multi-column text.
    public var withTables: [Int]
    public var withColumns: [Int]
}

/// The documents engine: Office, OpenDocument, RTF, EPUB and CSV bytes to
/// Markdown, and PDFs page by page. Stateless; every call is `static`.
public enum Documents {
    /// The format the bytes are, or nil for the unknown. CSV has no
    /// signature and is never detected.
    public static func detect(_ bytes: Data) throws -> DocumentFormat? {
        struct Answer: Decodable {
            let format: String?
        }
        let answer: Answer = try Envelope.decode(
            bytes.withUnsafeBytes { buffer in
                eglu_document_detect(buffer.baseAddress, buffer.count)
            })
        return answer.format.flatMap(DocumentFormat.init(rawValue:))
    }

    /// The document's bytes as Markdown. `format` names the format; nil
    /// detects it from the bytes (CSV must always be given).
    public static func markdown(_ bytes: Data, format: DocumentFormat? = nil) throws
        -> (format: DocumentFormat?, markdown: String)
    {
        struct Answer: Decodable {
            let format: String?
            let markdown: String
        }
        let answer: Answer = try Envelope.decode(
            bytes.withUnsafeBytes { buffer in
                eglu_document_markdown(
                    buffer.baseAddress, buffer.count, format?.rawValue)
            })
        return (answer.format.flatMap(DocumentFormat.init(rawValue:)), answer.markdown)
    }

    /// A PDF's pages: its metadata and each page's Markdown with a
    /// `needsOCR` flag where the page holds no readable text. `pages` lists
    /// 0-based page numbers; nil extracts every page.
    public static func pdfPages(_ bytes: Data, pages: [Int]? = nil) throws -> PDFPages {
        struct Answer: Decodable {
            struct Page: Decodable {
                let page: Int
                let markdown: String
                let needsOCR: Bool
                let reason: String?
            }
            let pageCount: Int
            let title: String?
            let author: String?
            let created: String?
            let pages: [Page]
            let withTables: [Int]
            let withColumns: [Int]
        }
        let pagesJSON = try pages.map { pages in
            String(decoding: try JSONEncoder().encode(pages), as: UTF8.self)
        }
        let answer: Answer = try Envelope.decode(
            bytes.withUnsafeBytes { buffer in
                eglu_pdf_pages(buffer.baseAddress, buffer.count, pagesJSON)
            })
        return PDFPages(
            pageCount: answer.pageCount,
            title: answer.title,
            author: answer.author,
            created: answer.created,
            pages: answer.pages.map {
                PDFPages.Page(
                    page: $0.page, markdown: $0.markdown,
                    needsOCR: $0.needsOCR, reason: $0.reason)
            },
            withTables: answer.withTables,
            withColumns: answer.withColumns)
    }
}
