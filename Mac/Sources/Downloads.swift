import AppKit
import PadCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Files a page hands over rather than shows, saved to Downloads under the
/// name the site gives them, as Safari saves them; listed at the foot of the
/// sidebar while the app runs.
@MainActor
final class Downloads: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = Downloads()

    struct Item: Identifiable {
        let id = UUID()
        var name: String
        var file: URL?
        var fraction: Double = 0
        var finished = false
        var failed = false
    }

    /// The newest first.
    @Published private(set) var items: [Item] = []
    /// Each download going, held here until it ends: it outlives a tab
    /// that was only its way in (Page.downloading).
    private var running: [ObjectIdentifier: (download: WKDownload, item: UUID, page: ObjectIdentifier?, watch: NSKeyValueObservation?)] = [:]

    var active: Bool {
        items.contains { !$0.finished && !$0.failed }
    }

    /// The share of what is downloading that has come, for the sidebar's ring.
    var fraction: Double {
        let going = items.filter { !$0.finished && !$0.failed }
        guard !going.isEmpty else { return 1 }
        return going.map(\.fraction).reduce(0, +) / Double(going.count)
    }

    func adopt(_ download: WKDownload, from page: Page) {
        download.delegate = self
        let item = Item(name: download.originalRequest?.url?.lastPathComponent ?? "Download")
        items.insert(item, at: 0)
        let watch = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.update(download) { $0.fraction = fraction } }
        }
        running[ObjectIdentifier(download)] = (download, item.id, ObjectIdentifier(page), watch)
    }

    /// Whether the page has a download going, which keeps it live.
    func isDownloading(for page: Page) -> Bool {
        running.values.contains { $0.page == ObjectIdentifier(page) }
    }

    private func update(_ download: WKDownload, _ change: (inout Item) -> Void) {
        guard let id = running[ObjectIdentifier(download)]?.item, let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func end(_ download: WKDownload) {
        running[ObjectIdentifier(download)]?.watch?.invalidate()
        running[ObjectIdentifier(download)] = nil
    }

    func reveal(_ item: Item) {
        guard let file = item.file else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    func clearFinished() {
        items.removeAll { $0.finished || $0.failed }
    }

    // MARK: WKDownloadDelegate

    /// Downloads, under the site's name for the file, with " 2", " 3" before
    /// the extension when a file already has it, or another download still
    /// going was given it before its file exists (DownloadName).
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Held as the file system compares names: "Report.pdf" holds "report.pdf" too.
        let held = Set(items.filter { !$0.finished && !$0.failed }.compactMap { $0.file.map { DownloadName.key($0.standardizedFileURL.path) } })
        let name = DownloadName.free(for: suggestedFilename) { candidate in
            let path = folder.appendingPathComponent(candidate).standardizedFileURL.path
            return held.contains(DownloadName.key(path)) || FileManager.default.fileExists(atPath: path)
        }
        let file = folder.appendingPathComponent(name)
        update(download) {
            $0.name = file.lastPathComponent
            $0.file = file
        }
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        update(download) {
            $0.finished = true
            $0.fraction = 1
        }
        if let file = items.first(where: { $0.id == running[ObjectIdentifier(download)]?.item })?.file {
            // The Downloads stack in the Dock bounces, as it does for Safari's.
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: file.path)
        }
        end(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        update(download) { $0.failed = true }
        end(download)
    }
}

/// The downloads of this run, newest first: a click shows one in Finder.
struct DownloadList: View {
    @ObservedObject var downloads = Downloads.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                if downloads.items.contains(where: { $0.finished || $0.failed }) {
                    Button("Clear") { downloads.clearFinished() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            if downloads.items.isEmpty {
                Text("Files you download show here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            ForEach(downloads.items) { item in
                Button {
                    downloads.reveal(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data))
                            .resizable()
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if item.failed {
                                Text("Failed").font(.caption).foregroundStyle(.red)
                            } else if !item.finished {
                                ProgressView(value: item.fraction).controlSize(.small)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(item.file == nil || !item.finished)
            }
        }
        .padding(10)
        .frame(width: 300)
    }
}
