import PadCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The measuring tool's panel (MeasureModel): a card at the bottom of the
/// page's area: the Mac's at the window's trailing corner as the Handoff
/// panel, the iPad's over the page's foot. It reads what the page's overlay
/// says (the element picked, a distance, a colour) and its fields ask the
/// tool for its guides, a colour, and its end.
struct MeasurePanel: View {
    @Bindable var model: MeasureModel
    /// The note being written, emptied once it pins.
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let details = model.details {
                element(details)
                HStack {
                    TextField("Add Note…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            model.addNote(draft)
                            draft = ""
                        }
                    Button { model.addNote(draft); draft = "" } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain)
                        .disabled(model.details == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Pin the note to the element")
                }
            } else {
                Text("Point and click an element.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let distance = model.distance {
                row("To " + (distance.target.isEmpty ? "element" : distance.target), value: distanceText(distance))
            }
            colourRow
            if !model.notes.isEmpty {
                Divider()
                ForEach($model.notes) { $note in
                    noteRow($note)
                }
                Button("Copy for an Assistant") { copy(model.textForAssistant) }
                    .font(.system(size: 12))
            }
            Divider()
            guideFields
            HStack {
                Toggle("Rulers", isOn: $model.guides.rulers)
                    .font(.system(size: 12))
                Spacer()
                Button("Pick Colour") { model.pickColour() }
                    .disabled(model.colourBusy)
                Button("Stop") { model.end() }
            }
            .font(.system(size: 12))
        }
        .padding(12)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "ruler")
            Text("Measure").font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("Esc ends").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    /// A note pinned to an element: its number, its name, the note itself
    /// editable in place, and buttons to copy it or take it away.
    private func noteRow(_ note: Binding<MeasureNote>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(note.number.wrappedValue).").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.name.wrappedValue).lineLimit(1)
                TextField("Note", text: note.note)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { copy(MeasureNotes.line(note.wrappedValue) + "\n   Note: \(note.note.wrappedValue)") } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy this note")
            Button { model.removeNote(note.wrappedValue) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove the note")
        }
        .font(.system(size: 12))
    }

    /// A label and its value, the value copied on click.
    private func row(_ name: String, value: String, copyable: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value).lineLimit(3)
            Spacer(minLength: 0)
            if copyable {
                Button { copy(value) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Copy")
            }
        }
        .font(.system(size: 12, design: .monospaced))
    }

    /// What the selected element is: its tag, id and first classes; then its
    /// boxes, layout, type and colours, a row each.
    private func element(_ it: MeasureDetails) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Element", value: ([it.tag] + (it.id.isEmpty ? [] : ["#" + it.id]) + it.classes.map { "." + $0 })
                    .joined(separator: " "))
            row("Size", value: "\(rounded(it.width)) × \(rounded(it.height)) at \(rounded(it.x)), \(rounded(it.y))")
            row("Margin", value: it.margin.text.isEmpty ? "0" : it.margin.text)
            row("Padding", value: it.padding.text.isEmpty ? "0" : it.padding.text)
            row("Border", value: it.border.text.isEmpty ? "0" : it.border.text)
            let gaps = [it.rowGap, it.columnGap].filter { !$0.isEmpty && $0 != "normal" }
            row("Display", value: it.display + (gaps.isEmpty ? "" : ", gap " + gaps.joined(separator: " × ")))
            row("Type", value: [it.family, "\(it.size)/\(it.lineHeight)", it.weight]
                    .filter { !$0.isEmpty && $0 != "/" }.joined(separator: " "))
            row("Colour", value: [it.color, "on " + it.background].joined(separator: " "))
            if !it.radius.isEmpty { row("Radius", value: it.radius) }
        }
    }

    private var colourRow: some View {
        HStack(spacing: 8) {
            Text("Colour")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            if let colour = model.colour {
                Circle()
                    .fill(Color(red: Double(colour.red) / 255, green: Double(colour.green) / 255,
                                blue: Double(colour.blue) / 255))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.secondary.opacity(0.4)))
                Button { copy(colour.hex) } label: { Text(colour.hex) }
                    .buttonStyle(.plain)
                Button { copy(colour.rgb) } label: { Text(colour.rgb) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Text(model.colourBusy ? "Picking…" : "None picked")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .font(.system(size: 12, design: .monospaced))
    }

    /// The guides' settings (G shows them over the page): column count,
    /// gutter and margin, and the rows' step.
    private var guideFields: some View {
        HStack(spacing: 8) {
            field("Columns", value: $model.guides.columns)
            field("Gutter", value: $model.guides.gutter)
            field("Margin", value: $model.guides.margin)
            field("Rows", value: $model.guides.row)
        }
        .font(.system(size: 12))
    }

    private func field(_ name: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(name, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
        }
    }

    private func field(_ name: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(name, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
        }
    }

    private func distanceText(_ it: MeasureDistance) -> String {
        if it.inside {
            return "insets ↑\(rounded(it.insets.top)) →\(rounded(it.insets.right)) ↓\(rounded(it.insets.bottom)) ←\(rounded(it.insets.left))"
        }
        var parts: [String] = []
        if it.dx > 0 { parts.append("↔ \(rounded(it.dx))px") }
        if it.dy > 0 { parts.append("↕ \(rounded(it.dy))px") }
        return parts.isEmpty ? "touching" : parts.joined(separator: "  ")
    }

    private func rounded(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// A value to the pasteboard; the platform's own.
    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
