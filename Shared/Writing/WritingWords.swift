import Foundation
import PadCore

/// The personal dictionary: Application Support/Safience/Writing/
/// dictionary.txt, one word a line, sorted — Harper Desktop's own format,
/// so the two apps' dictionaries can trade places.
enum WritingWords {
    private static var file: URL {
        Session.folder.appendingPathComponent("Writing/dictionary.txt")
    }

    static func load() -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return words(in: text)
    }

    static func save(_ words: [String]) {
        let unique = Array(Set(words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? (unique.joined(separator: "\n") + (unique.isEmpty ? "" : "\n"))
            .write(to: file, atomically: true, encoding: .utf8)
    }

    static func add(_ word: String) {
        let words = load()
        guard !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !words.contains(word) else { return }
        save(words + [word])
    }

    static func remove(_ word: String) {
        save(load().filter { $0 != word })
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    #if os(macOS)
    /// Harper Desktop's own dictionary, where the Mac has one, for "Add
    /// Harper Desktop's Words" in Settings › Writing; nil where there is none.
    static func harperDesktopWords() -> [String]? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let theirs = home.appendingPathComponent("Library/Application Support/harper-desktop/dictionary.txt")
        guard let text = try? String(contentsOf: theirs, encoding: .utf8) else { return nil }
        return words(in: text)
    }
    #endif
}
