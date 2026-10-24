import AppKit
import PadCore

/// Report a Problem (Docs/ExtensionsDesign.md, section 4): what would be
/// sent about an extension, shown in full before anything goes, with room
/// for the person's own words; copied or saved for them to send where they
/// like. Nothing is sent by eGlu.
@MainActor
enum ExtensionReport {
    /// The report: the extension and its version, eGlu's and macOS's,
    /// what the checks found, and the problems kept on this Mac (where in
    /// the extension and which API, never the errors' own words).
    static func text(for id: String, in space: UUID? = nil) -> String {
        let extensions = Extensions.shared
        guard let item = extensions.installed.first(where: { $0.id == id }) else { return "" }
        var lines = [
            "eGlu extension report",
            "",
            "Extension: \(item.name), version \(item.version), \(ExtensionSettings.source(of: item))",
            "Its id: \(item.id)",
            "eGlu \(Extensions.egluVersion), macOS \(Extensions.macOSVersion)",
        ]
        // The window's space first: where the person saw what they report.
        let verdict = ([space].compactMap { $0 } + item.spaces).lazy.compactMap { extensions.verdicts[$0]?[id] }.first
        if let verdict {
            lines.append("What eGlu found: " + ([verdict.title + "."] + verdict.lines).joined(separator: " "))
        } else {
            lines.append("What eGlu found: nothing yet; it is off everywhere.")
        }
        if extensions.saidLooksWrong(id) { lines.append("You said its warnings look wrong.") }
        let records = extensions.records(of: id)
        lines.append("")
        lines.append("Problems kept on this Mac, the last \(ExtensionRecords.days) days:")
        if records.isEmpty { lines.append("None.") }
        let day = Date.FormatStyle(date: .abbreviated, time: .omitted)
        for record in records {
            let times = record.count == 1 ? "once" : "\(record.count) times"
            let when = record.first.formatted(day) == record.last.formatted(day)
                ? record.last.formatted(day) : "\(record.first.formatted(day)) to \(record.last.formatted(day))"
            lines.append("- In its \(record.place), version \(record.version): \(record.api) (\(record.kind)), \(times), \(when)")
        }
        lines += ["", "What happened, in your words:", "", ""]
        return lines.joined(separator: "\n")
    }

    /// The report in a sheet, editable, to copy or save.
    static func show(_ id: String, in window: WindowModel?) {
        guard let item = Extensions.shared.installed.first(where: { $0.id == id }),
              (window?.window ?? NSApp.keyWindow ?? Session.shared.frontWindow?.window) != nil
        else { return }
        let alert = NSAlert()
        alert.messageText = "Report a Problem with \u{201C}\(item.name)\u{201D}"
        alert.informativeText = "This is everything in the report. Add what happened, then copy it or save it, and send it where you like. eGlu sends nothing."
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 280))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let words = NSTextView(frame: scroll.bounds)
        words.autoresizingMask = [.width]
        words.font = .systemFont(ofSize: 12)
        words.isRichText = false
        words.textContainerInset = NSSize(width: 4, height: 6)
        words.string = text(for: id, in: window?.spaceID)
        scroll.documentView = words
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Save\u{2026}")
        alert.addButton(withTitle: "Cancel")
        Task {
            let answer = await Extensions.shared.present(alert, in: window)
            let report = words.string
            switch answer {
            case .alertFirstButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
            case .alertSecondButtonReturn:
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "\(item.name) report.txt"
                panel.allowedContentTypes = [.plainText]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try report.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    NSLog("eGlu: the report on extension \(item.id) couldn't be saved: \(error.localizedDescription)")
                    let failure = NSAlert()
                    failure.messageText = "The report couldn't be saved."
                    failure.informativeText = error.localizedDescription
                    _ = await Extensions.shared.present(failure, in: window)
                }
            default:
                break
            }
        }
    }
}
