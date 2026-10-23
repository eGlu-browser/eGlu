import PadCore
import SwiftUI
import UniformTypeIdentifiers

/// Browsing remains unavailable until an existing workspace is readable again.
struct WorkspaceRecoveryView: View {
    @ObservedObject private var session = Session.shared
    @State private var choosingBackup = false
    @State private var actionFailed = false

    private var hasBackup: Bool {
        if case .loaded = WorkspaceFile.load(WorkspaceFile.backup(for: Session.workspaceFile)) { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Workspace Unavailable")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Browsing and sync are paused. Your saved data has not been removed.")
                VStack(alignment: .leading, spacing: 12) {
                    Button("Retry") {
                        actionFailed = !session.retryWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                    if hasBackup {
                        Button("Restore Backup") {
                            restore(WorkspaceFile.backup(for: Session.workspaceFile))
                        }
                        .buttonStyle(.bordered)
                    }
                    Button("Choose Backup") { choosingBackup = true }
                        .buttonStyle(.bordered)
                }
                if case .unsupportedVersion = session.workspaceProblem {
                    Text("This workspace uses a different file version. Open it with the version of Safience that saved it, or choose a compatible backup.")
                } else {
                    Text("Try again after your device is unlocked or storage is available, or restore a workspace backup.")
                }
                Text("Restoring a backup keeps copies of your current workspace, history and tab snapshots in a recovery folder. Only spaces saved in the backup will appear. Recent changes may be missing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if actionFailed {
                    Text("The workspace is still unavailable. Check that the file is readable and your device has free storage, then retry or choose another backup.")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("workspaceRecoveryError")
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, minHeight: 360)
        }
        .background(.background)
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let file):
                let scoped = file.startAccessingSecurityScopedResource()
                defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                restore(file)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { actionFailed = true }
            }
        }
        .accessibilityIdentifier("workspaceRecovery")
    }

    private func restore(_ file: URL) {
        do { try session.restoreWorkspace(from: file) }
        catch { actionFailed = true }
    }
}
