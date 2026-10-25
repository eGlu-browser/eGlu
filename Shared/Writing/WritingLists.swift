// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.

import Engines
import SwiftUI

extension Dialect {
    /// The dialect's name in Settings › Writing's English picker.
    var name: String {
        switch self {
        case .american: return String(localized: "American")
        case .british: return String(localized: "British")
        case .canadian: return String(localized: "Canadian")
        case .australian: return String(localized: "Australian")
        case .indian: return String(localized: "Indian")
        }
    }
}

/// The rules Harper can check, grouped as it groups them, each with a
/// switch. `changed` is preferences.writingRules: only the differences
/// from Harper's defaults, so a rule put back where it was leaves the
/// dictionary.
struct WritingRuleList: View {
    let rules: [GrammarRule]
    @Binding var changed: [String: Bool]

    var body: some View {
        if rules.isEmpty {
            Text("eGlu could not read Harper's rules, so Harper checks with its defaults.")
                .foregroundStyle(.secondary)
        } else {
            Button(String(localized: "Restore Defaults")) { changed = [:] }
                .disabled(changed.isEmpty)
            ForEach(groups, id: \.name) { group in
                Section {
                    ForEach(group.rules, id: \.id) { rule in
                        Toggle(isOn: on(rule)) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(rule.label)
                                    if isChanged(rule) {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 6, height: 6)
                                            .help(String(localized: "You changed this rule from its default."))
                                            .accessibilityLabel(String(localized: "You changed this rule from its default."))
                                    }
                                }
                                if !rule.description.isEmpty {
                                    Text(rule.description)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .help(rule.description)
                                }
                            }
                        }
                    }
                } header: {
                    Text(group.name)
                }
            }
        }
    }

    /// Harper's group names, in the order its rules come.
    private var groups: [(name: String, rules: [GrammarRule])] {
        var order: [String] = []
        var byName: [String: [GrammarRule]] = [:]
        for rule in rules {
            if byName[rule.group] == nil { order.append(rule.group) }
            byName[rule.group, default: []].append(rule)
        }
        return order.map { ($0, byName[$0] ?? []) }
    }

    private func on(_ rule: GrammarRule) -> Binding<Bool> {
        Binding(
            get: { changed[rule.id] ?? rule.isOnByDefault },
            set: { on in
                if on == rule.isOnByDefault {
                    changed.removeValue(forKey: rule.id)
                } else {
                    changed[rule.id] = on
                }
            })
    }

    private func isChanged(_ rule: GrammarRule) -> Bool {
        (changed[rule.id] ?? rule.isOnByDefault) != rule.isOnByDefault
    }
}

/// The personal dictionary: a word a row, a field to add one. Kept in
/// Application Support/Safience/Writing/dictionary.txt (WritingWords), the
/// words Harper never flags.
struct WritingDictionaryList: View {
    @Binding var words: [String]
    @State private var newWord = ""

    private var trimmed: String { newWord.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool { words.contains(trimmed) }

    var body: some View {
        HStack {
            // Its name only for VoiceOver: in a form, a shown label would
            // stand beside the field and say what its Add button says.
            TextField(String(localized: "Add a word"), text: $newWord, prompt: Text("Add a word"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button(String(localized: "Add"), action: add)
                .disabled(trimmed.isEmpty || isDuplicate)
        }
        if words.isEmpty {
            Text("You haven't added any words yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(words, id: \.self) { word in
                LabeledContent(word) {
                    Button(String(localized: "Remove")) {
                        WritingWords.remove(word)
                        words = WritingWords.load()
                    }
                }
            }
        }
    }

    private func add() {
        guard !trimmed.isEmpty, !isDuplicate else { return }
        WritingWords.add(trimmed)
        words = WritingWords.load()
        newWord = ""
    }
}
