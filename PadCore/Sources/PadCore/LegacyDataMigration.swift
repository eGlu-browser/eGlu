import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
            let targetInfo = try info(to)
            let sourceInfo: FileInfo?
            if targetInfo != nil && (source != "WebKit/WebsiteDataStore" || targetInfo?.directory != true) {
                // This outside directory is already authoritative; no legacy read is needed.
                sourceInfo = nil
            } else {
                sourceInfo = try info(from)
            }
            if source == "WebKit/WebsiteDataStore", targetInfo?.directory == true, sourceInfo?.directory == true {
                // Preserve each existing store as a unit, including its SQLite sidecars.
                // A parent folder created by another launch does not mean every store moved.
                preserved.insert(source)
                let children = try files.contentsOfDirectory(at: from, includingPropertiesForKeys: [.isDirectoryKey])
                for child in children {
                    let target = to.appendingPathComponent(child.lastPathComponent)
                    guard try info(target) == nil else { continue }
                    let staging = to.appendingPathComponent(".\(child.lastPathComponent).safience-migration")
                    try stage(child, to: staging) { count in progress(Progress(item: source, copiedFiles: count)) }
                    if try info(target) == nil { try files.moveItem(at: staging, to: target) }
                }
            } else if targetInfo != nil {
                // Existing outside workspace data is authoritative. The legacy container remains intact.
                preserved.insert(source)
            } else if sourceInfo != nil {
                try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staging = to.deletingLastPathComponent().appendingPathComponent(".\(to.lastPathComponent).safience-migration", isDirectory: true)
                let previousStaging = to.deletingLastPathComponent().appendingPathComponent(to.lastPathComponent + ".moving", isDirectory: true)
                if try info(staging) == nil, try info(previousStaging) != nil {
                    try files.moveItem(at: previousStaging, to: staging)
                }
                try stage(from, to: staging) { count in progress(Progress(item: source, copiedFiles: count)) }
                if try info(to) != nil {
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

    private struct FileInfo {
        let directory: Bool
        let symbolic: Bool
        let size: UInt64?
        let modified: Date?
    }

    /// Unlike fileExists, a denied probe must stop migration rather than checkpoint an absent source.
    private static func info(_ url: URL) throws -> FileInfo? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as? FileAttributeType
            return FileInfo(directory: type == .typeDirectory, symbolic: type == .typeSymbolicLink,
                            size: (attributes[.size] as? NSNumber)?.uint64Value,
                            modified: attributes[.modificationDate] as? Date)
        } catch {
            let error = error as NSError
            if missing(error) { return nil }
            throw error
        }
    }

    private static func missing(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain { return error.code == Int(ENOENT) || error.code == Int(ENOTDIR) }
        if error.domain == NSCocoaErrorDomain,
           error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return missing(underlying) }
        return false
    }

    private static func stage(_ source: URL, to destination: URL, progress: (Int) -> Void) throws {
        guard let sourceInfo = try info(source) else { throw CocoaError(.fileReadNoSuchFile) }
        if sourceInfo.directory {
            try copyDirectory(source, to: destination, progress: progress)
        } else {
            // copyItem preserves a symbolic link itself; it never enumerates its target.
            if try info(destination) != nil { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private struct Entry {
        let url: URL
        let relative: String
        let info: FileInfo
    }

    private static func inventory(_ directory: URL) throws -> [Entry] {
        guard try info(directory)?.directory == true else { throw CocoaError(.fileReadInvalidFileName) }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
                                                              errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw CocoaError(.fileReadUnknown) }
        var entries: [Entry] = []
        for case let url as URL in enumerator {
            guard enumerator.level > 0, let value = try info(url) else { throw CocoaError(.fileReadNoSuchFile) }
            if value.symbolic { enumerator.skipDescendants() }
            let relative = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
            entries.append(Entry(url: url, relative: relative, info: value))
        }
        if let enumerationError { throw enumerationError }
        return entries
    }

    private static func copyDirectory(_ source: URL, to destination: URL, progress: (Int) -> Void) throws {
        let files = FileManager.default
        // Finish this read before changing or pruning staging. An unreadable subtree is not an empty one.
        let sourceEntries = try inventory(source)
        if let existing = try info(destination), !existing.directory { throw CocoaError(.fileWriteFileExists) }
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        let stagedEntries = try inventory(destination)
        let wanted = Set(sourceEntries.map(\.relative))
        // Remove obsolete SQLite sidecars, stale files and abandoned copying files. Never follow links.
        for old in stagedEntries.reversed() where !wanted.contains(old.relative) {
            if try info(old.url) != nil { try files.removeItem(at: old.url) }
        }
        var count = 0
        for entry in sourceEntries {
            let from = entry.url
            let to = destination.appendingPathComponent(entry.relative)
            let values = entry.info
            let kept = try info(to)
            if values.directory {
                // A staged symlink must not redirect directory creation into an external location.
                if let kept, !kept.directory { throw CocoaError(.fileWriteFileExists) }
                try files.createDirectory(at: to, withIntermediateDirectories: true)
                continue
            }
            if let kept, !values.symbolic, !kept.symbolic,
               values.size == kept.size, values.modified == kept.modified,
               files.contentsEqual(atPath: from.path, andPath: to.path) { continue }
            try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            let copying = to.deletingLastPathComponent().appendingPathComponent(".safience-\(UUID().uuidString).copying")
            try files.copyItem(at: from, to: copying)
            if try info(to) != nil { try files.removeItem(at: to) }
            try files.moveItem(at: copying, to: to)
            count += 1
            if count == 1 || count.isMultiple(of: 100) { progress(count) }
        }
        progress(count)
    }
}
