import CoreGraphics
import Foundation
import PDFKit
import Vision

/// A page that is only a picture, read on the device by Vision: drawn
/// with PDFKit at twice its points, then read as a document on 26 and
/// after (paragraphs, lists, tables), or as lines joined into paragraphs
/// where they are close, before it.
enum HandoffVision {

    /// The page's words as Markdown; "" where nothing was read.
    @concurrent
    static func read(_ document: PDFDocument, page number: Int) async throws -> String {
        guard let image = draw(document, page: number) else { return "" }
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await Self.document(image)
        }
        return try Self.lines(image)
    }

    /// The page drawn white at twice its points: Vision reads it the better.
    static func draw(_ document: PDFDocument, page number: Int) -> CGImage? {
        guard let page = document.page(at: number) else { return nil }
        let box = page.bounds(for: .mediaBox)
        let size = CGSize(width: box.width * 2, height: box.height * 2)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: 2, y: 2)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// The document's own reading: paragraphs as paragraphs, lists as
    /// items, tables as GitHub tables.
    @available(iOS 26.0, macOS 26.0, *)
    @concurrent
    private static func document(_ image: CGImage) async throws -> String {
        let found = try await RecognizeDocumentsRequest().perform(on: image)
        return found.map { markdown(of: $0.document) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// One document's Markdown: its title, then paragraphs, lists and
    /// tables, as the engines' writers give them.
    @available(iOS 26.0, macOS 26.0, *)
    private static func markdown(of content: DocumentObservation.Container) -> String {
        var parts: [String] = []
        if let title = content.title { parts.append("# " + title.transcript) }
        parts += content.paragraphs.map(\.transcript)
        parts += content.lists.map { list in
            list.items.map { "- \($0.itemString)" }.joined(separator: "\n")
        }
        parts += content.tables.map(markdown(of:))
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// A table as GitHub's: the first row its head, one row a line.
    @available(iOS 26.0, macOS 26.0, *)
    private static func markdown(of table: DocumentObservation.Container.Table) -> String {
        let rows = table.rows.map { row in
            row.map { cell in cell.content.text.transcript.replacingOccurrences(of: "|", with: "\\|") }
        }
        guard let header = rows.first else { return "" }
        var lines = ["| " + header.joined(separator: " | ") + " |",
                     "| " + header.map { _ in "---" }.joined(separator: " | ") + " |"]
        lines += rows.dropFirst().map { "| " + $0.joined(separator: " | ") + " |" }
        return lines.joined(separator: "\n")
    }

    /// Lines read before 26: each joined to the next where they are
    /// close, making the paragraphs a picture lost.
    private static func lines(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let found = request.results, !found.isEmpty else { return "" }
        let lines = found.compactMap { each -> (text: String, box: CGRect)? in
            guard let text = each.topCandidates(1).first?.string else { return nil }
            return (text, each.boundingBox)
        }.sorted { $0.box.maxY > $1.box.maxY }
        var parts: [String] = []
        var current: [String] = []
        var last: CGRect?
        for (text, box) in lines {
            if let last, last.minY - box.maxY < box.height / 2 {
                current.append(text)
            } else {
                if !current.isEmpty { parts.append(current.joined(separator: " ")) }
                current = [text]
            }
            last = box
        }
        if !current.isEmpty { parts.append(current.joined(separator: " ")) }
        return parts.joined(separator: "\n\n")
    }
}
