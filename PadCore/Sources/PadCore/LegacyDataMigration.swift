import Foundation

/// Copies legacy app data without replacing data already used outside the sandbox.
/// A checkpoint is committed after each directory. Staged files are published only
/// after their copy completes, so an interrupted directory can resume safely.
public enum LegacyDataMigration {
    public struct Progress: Sendable {
        public let item: String
        public let copiedFiles: Int
    }
    public struct Result: Sendable {
        public let completed: Set<String>
        public let preservedExisting: Set<String>
    }
    private struct Checkpoint: Codable {
        var completed: Set<String> = []
    }

    public static func run(library: URL, bundle: String, completed: Set<String> = [],
                           progress: @Sendable (Progress) -> Void = { _ in }) throws -> Result {
        let files = FileManager.default
        let container = library.appendingPathComponent("Containers/\(bundle)/Data/Library", isDirectory: true)
        let journal = library.appendingPathComponent("Application Support/Safience Migration/\(bundle).json")
        var checkpoint = (try? Data(contentsOf: journal)).flatMap { try? JSONDecoder().decode(Checkpoint.self, from: $0) } ?? Checkpoint()
        checkpoint.completed.formUnion(completed)
        var preserved: Set<String> = []
        let items = [("Application Support/Safience", "Application Support/Safience"),
                     ("WebKit/WebsiteDataStore", "WebKit/\(bundle)/WebsiteDataStore"),
                     ("WebKit/ContentRuleLists", "WebKit/\(bundle)/ContentRuleLists")]
        for (source, destination) in items where !checkpoint.completed.contains(source) {
            progress(Progress(item: source, copiedFiles: 0))
            let from = container.appendingPathComponent(source, isDirectory: true)
            let to = library.appendingPathComponent(destination, isDirectory: true)
            if source == "WebKit/WebsiteDataStore", files.fileExists(atPath: to.path), files.fileExists(atPath: from.path) {
                // Preserve each existing store as a unit, including its SQLite sidecars.
                // A parent folder created by another launch does not mean every store moved.
                preserved.insert(source)
                let children = try files.contentsOfDirectory(at: from, includingPropertiesForKeys: [.isDirectoryKey])
                for child in children {
                    let target = to.appendingPathComponent(child.lastPathComponent)
                    guard !files.fileExists(atPath: target.path) else { continue }
                    let staging = to.appendingPathComponent(".\(child.lastPathComponent).safience-migration")
                    if try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                        try copyDirectory(child, to: staging) { count in progress(Progress(item: source, copiedFiles: count)) }
                    } else {
                        if files.fileExists(atPath: staging.path) { try files.removeItem(at: staging) }
                        try files.copyItem(at: child, to: staging)
                    }
                    if !files.fileExists(atPath: target.path) { try files.moveItem(at: staging, to: target) }
                }
            } else if files.fileExists(atPath: to.path) {
                // Existing outside workspace data is authoritative. The legacy container remains intact.
                preserved.insert(source)
            } else if files.fileExists(atPath: from.path) {
                try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staging = to.deletingLastPathComponent().appendingPathComponent(".\(to.lastPathComponent).safience-migration", isDirectory: true)
                let previousStaging = to.deletingLastPathComponent().appendingPathComponent(to.lastPathComponent + ".moving", isDirectory: true)
                if !files.fileExists(atPath: staging.path), files.fileExists(atPath: previousStaging.path) {
                    try files.moveItem(at: previousStaging, to: staging)
                }
                try copyDirectory(from, to: staging) { count in progress(Progress(item: source, copiedFiles: count)) }
                if files.fileExists(atPath: to.path) {
                    preserved.insert(source)
                } else {
                    try files.moveItem(at: staging, to: to)
                }
            }
            checkpoint.completed.insert(source)
            try files.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(checkpoint).write(to: journal, options: .atomic)
        }
        return Result(completed: checkpoint.completed, preservedExisting: preserved)
    }

    private static func copyDirectory(_ source: URL, to destination: URL, progress: (Int) -> Void) throws {
        let files = FileManager.default
        let source = source.resolvingSymlinksInPath()
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var enumerationError: Error?
        guard let enumerator = files.enumerator(at: source, includingPropertiesForKeys: keys, errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw CocoaError(.fileReadUnknown) }
        var count = 0
        for case let from as URL in enumerator {
            guard enumerator.level > 0 else { throw CocoaError(.fileReadInvalidFileName) }
            let relative = from.pathComponents.suffix(enumerator.level).joined(separator: "/")
            let to = destination.appendingPathComponent(relative)
            let values = try from.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true && values.isSymbolicLink != true {
                try files.createDirectory(at: to, withIntermediateDirectories: true)
                continue
            }
            if let kept = try? to.resourceValues(forKeys: Set(keys)),
               values.isSymbolicLink == kept.isSymbolicLink,
               values.isSymbolicLink != true,
               values.fileSize == kept.fileSize, values.contentModificationDate == kept.contentModificationDate,
               files.contentsEqual(atPath: from.path, andPath: to.path) {
                continue
            }
            try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            let copying = to.deletingLastPathComponent().appendingPathComponent(".\(to.lastPathComponent).copying")
            if files.fileExists(atPath: copying.path) { try files.removeItem(at: copying) }
            try files.copyItem(at: from, to: copying)
            if files.fileExists(atPath: to.path) { try files.removeItem(at: to) }
            try files.moveItem(at: copying, to: to)
            count += 1
            if count == 1 || count.isMultiple(of: 100) { progress(count) }
        }
        progress(count)
        if let enumerationError { throw enumerationError }
    }
}
