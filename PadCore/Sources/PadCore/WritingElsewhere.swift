import Foundation

/// What checking other apps' text shares between the platform code and its
/// tests: how the caret is told apart from typing, which apps are checked,
/// and which part of a long field is linted (Docs/Tasks/03). Everything
/// here counts UTF-16 code units, as the Accessibility API and `NSString`
/// do — never character indices (Decided 3).
///
/// The panel over another app's field opens when the caret rests inside a
/// flagged range, not while the text under it is being typed: `CaretSettle`
/// is Harper Desktop's caret tracker as a value type.
public struct CaretSettle: Sendable, Equatable {
    /// What a read of the caret led to.
    public enum Event: Sendable, Equatable {
        /// The caret rested `settle` inside `lints[index]` without the text
        /// changing: show the lint's panel.
        case visit(Int)
        /// The caret left the visited lint, a selection replaced the caret,
        /// or the text changed: hide the panel.
        case leave
    }

    /// How long the caret stays put before a visit counts. The same wait
    /// tells a moved caret from one still catching up with typing.
    public static let settle: TimeInterval = 0.15

    /// The flagged ranges, in the field's UTF-16 units, swapped for a new
    /// set on each lint. A visit ends when its range is gone.
    public private(set) var lints: [Range<Int>] = []

    private var caret: Int?
    private var movedAt: TimeInterval
    private var typedAt: TimeInterval?
    private var pending: Int?
    private var visiting: Int?

    public init() {
        movedAt = 0
    }

    /// A fresh set of lints: the ranges the caret can rest in now.
    @discardableResult
    public mutating func set(lints: [Range<Int>], at time: TimeInterval) -> Event? {
        let visited = visiting.flatMap { self.lints.indices.contains($0) ? self.lints[$0] : nil }
        self.lints = lints
        pending = nil
        guard let visiting, let visited else { return nil }
        // The visited lint survives the re-lint only while its range is unchanged.
        if lints.indices.contains(visiting), lints[visiting] == visited { return nil }
        self.visiting = nil
        return .leave
    }

    /// One read of the field: the caret's UTF-16 position (`nil` for a
    /// selection or none) and whether the text changed since the last.
    @discardableResult
    public mutating func moved(to caret: Int?, at time: TimeInterval, textChanged: Bool) -> Event? {
        if textChanged {
            typedAt = time
            pending = nil
            let was = visiting
            visiting = nil
            self.caret = caret
            return was == nil ? nil : .leave
        }
        // A caret that moves this soon after the text changed is still
        // typing: some apps report the caret one read after the text.
        let settling = typedAt.map { time - $0 < Self.settle } ?? false

        self.caret = caret
        guard let caret, !settling else {
            pending = nil
            let was = visiting
            visiting = nil
            return was == nil ? nil : .leave
        }

        let inside = lints.firstIndex { $0.lowerBound <= caret && caret <= $0.upperBound }
        switch inside {
        case .some(let index) where index == visiting:
            return nil
        case .some(let index) where index == pending:
            if time - movedAt >= Self.settle {
                pending = nil
                visiting = index
                return .visit(index)
            }
            return nil
        case .some(let index):
            pending = index
            movedAt = time
            let was = visiting
            visiting = nil
            return was == nil ? nil : .leave
        case .none:
            pending = nil
            let was = visiting
            visiting = nil
            return was == nil ? nil : .leave
        }
    }

    /// Time passing with no read: a pending visit whose caret has been
    /// still long enough fires.
    @discardableResult
    public mutating func tick(at time: TimeInterval) -> Event? {
        guard let pending, time - movedAt >= Self.settle else { return nil }
        self.pending = nil
        visiting = pending
        return .visit(pending)
    }
}

/// Which apps' fields are checked (Docs/Tasks/03, Decided 6): the curated
/// list unless the person said otherwise, any other app only with Check
/// New Apps on or its own switch.
public enum WritingApps {
    /// On by default, by bundle identifier — Harper Desktop's own list.
    public static let curated: Set<String> = [
        "com.apple.TextEdit",
        "com.apple.mail",
        "com.apple.MobileSMS",
        "com.apple.Notes",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.bloombuilt.dayone-mac",
    ]

    /// Never checked whatever the settings say: Harper Desktop's own
    /// identifier (eGlu leaves the field to it). eGlu's own is added by the
    /// app at run time.
    public static let neverChecked: Set<String> = [
        "com.elijahpotter.harper-desktop",
    ]

    /// Whether `bundleID` is checked: the person's choice where they made
    /// one (a difference from `curated`, kept in `writingApps`), else the
    /// curated default, else Check New Apps.
    public static func isOn(_ bundleID: String, choices: [String: Bool], newApps: Bool) -> Bool {
        if let choice = choices[bundleID] { return choice }
        return curated.contains(bundleID) || newApps
    }
}

/// Which part of a field's text is linted (Decided 7), all in UTF-16 units.
public enum WritingSpan {
    /// The part of `range` inside `length` units; empty when it is outside.
    public static func clip(_ range: Range<Int>, toLength length: Int) -> Range<Int> {
        let clipped = Swift.max(range.lowerBound, 0)..<Swift.min(range.upperBound, length)
        return clipped.isEmpty ? 0..<0 : clipped
    }

    /// What to lint: the whole field up to `limit` UTF-16 units; beyond
    /// that, the paragraph with the caret and the two on each side, in the
    /// field's own offsets. The caret sits one unit past a paragraph's end
    /// as well, as a position right after it.
    public static func region(of text: String, caret: Int, limit: Int = 50_000) -> Range<Int> {
        let whole = text.utf16.count
        guard whole > limit else { return 0..<whole }

        // The paragraphs' spans, the line break counted into each.
        var spans: [Range<Int>] = []
        var start = 0
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A /* \n */ {
                spans.append(start..<offset)
                start = offset
            }
        }
        if start < whole || spans.isEmpty { spans.append(start..<whole) }

        let index = spans.firstIndex { caret < $0.upperBound }
            ?? (caret <= 0 ? spans.startIndex : spans.index(before: spans.endIndex))
        let first = Swift.max(0, index - 2)
        let last = Swift.min(spans.count - 1, index + 2)
        return spans[first].lowerBound..<spans[last].upperBound
    }
}
