import Foundation

/// What checking other apps' text shares between the platform code and its
/// tests: how the caret is told apart from typing, which apps are checked,
/// and which part of a long field is linted (Docs/Tasks/03). Everything
/// here counts UTF-16 code units, as the Accessibility API and `NSString`
/// do — never character indices (Decided 3).
///
/// `CaretSettle` is Harper Desktop's caret tracker (caret_tracker.rs) as a
/// value type. While the person types, the word under the caret is
/// unfinished, so its lint would flicker with every key: it stays hidden
/// and opens nothing. A caret moved without the text changing (arrow keys,
/// a click) went there on purpose: a lint it rests in opens the panel.
/// Arriving in a field is neither: its lints show and nothing opens.
public struct CaretSettle: Sendable, Equatable {
    /// What a read of the caret led to.
    public enum Event: Sendable, Equatable {
        /// The caret moved into `lints[index]` and rested there `settle`:
        /// show the lint's panel.
        case visit(Int)
        /// The caret left the visited lint, a selection replaced the caret,
        /// or the text changed: hide the panel.
        case leave
    }

    /// How the caret got where it is.
    public enum Motion: Sendable, Equatable {
        /// The field was just focused.
        case arrived
        /// The text changed since the last read.
        case typed
        /// The caret moved and the text did not.
        case moved
    }

    /// A caret that moves this soon after the text changed is still typing:
    /// some apps report the caret one read after the text. A moved caret
    /// also rests this long in a lint before its panel opens, so arrow keys
    /// passing through words don't flash it.
    public static let settle: TimeInterval = 0.15

    /// The flagged ranges, in the field's UTF-16 units, swapped for a new
    /// set on each lint. A visit ends when its range is gone.
    public private(set) var lints: [Range<Int>] = []
    public private(set) var motion = Motion.arrived
    /// The lint being visited, whose panel is up unless something hid it.
    public var visited: Int? { visiting }

    private var caret: Int?
    private var movedAt: TimeInterval = 0
    private var typedAt: TimeInterval?
    private var pending: Int?
    private var visiting: Int?

    /// A field just arrived in, with its caret where the person left it:
    /// reading the same caret again is still the arrival.
    public init(caret: Int? = nil) {
        self.caret = caret
    }

    /// A fresh set of lints: the ranges the caret can rest in now.
    @discardableResult
    public mutating func set(lints: [Range<Int>], at time: TimeInterval) -> Event? {
        let visited = visiting.flatMap { self.lints.indices.contains($0) ? self.lints[$0] : nil }
        self.lints = lints
        // The visited lint survives the re-lint only while its range is unchanged.
        if let visiting, let visited, lints.indices.contains(visiting), lints[visiting] == visited {
            pending = nil
            return nil
        }
        // A caret moved into a word before its lint came opens it once it
        // has rested; after typing or on arrival, nothing opens.
        pending = restingLint()
        if let left = endVisit() { return left }
        guard let pending, time - movedAt >= Self.settle else { return nil }
        self.pending = nil
        visiting = pending
        return .visit(pending)
    }

    /// One read of the field: the caret's UTF-16 position (`nil` for a
    /// selection or none) and whether the text changed since the last.
    @discardableResult
    public mutating func moved(to caret: Int?, at time: TimeInterval, textChanged: Bool) -> Event? {
        if textChanged {
            motion = .typed
            typedAt = time
        } else if caret != self.caret, !settling(at: time) {
            motion = .moved
            movedAt = time
        }
        self.caret = caret

        guard let inside = restingLint() else {
            pending = nil
            return endVisit()
        }
        if inside == visiting { return nil }
        if inside == pending {
            guard time - movedAt >= Self.settle else { return nil }
            pending = nil
            visiting = inside
            return .visit(inside)
        }
        pending = inside
        return endVisit()
    }

    /// Time passing with no read: a pending visit whose caret has been
    /// still long enough fires.
    @discardableResult
    public mutating func tick(at time: TimeInterval) -> Event? {
        guard let pending, motion == .moved, time - movedAt >= Self.settle else { return nil }
        self.pending = nil
        visiting = pending
        return .visit(pending)
    }

    /// Whether `range` is the word being typed: the caret right after a
    /// word still counts as in it ("teh|" is mid-typing). Its underline
    /// waits until the caret moves on.
    public func isTyping(in range: Range<Int>) -> Bool {
        guard motion == .typed, let caret else { return false }
        return range.lowerBound <= caret && caret <= range.upperBound
    }

    private func settling(at time: TimeInterval) -> Bool {
        typedAt.map { time - $0 < Self.settle } ?? false
    }

    /// The lint a moved caret is in; none after typing or on arrival.
    private func restingLint() -> Int? {
        guard motion == .moved, let caret else { return nil }
        return lints.firstIndex { $0.lowerBound <= caret && caret <= $0.upperBound }
    }

    private mutating func endVisit() -> Event? {
        let was = visiting
        visiting = nil
        return was == nil ? nil : .leave
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

/// Which part of a field's text is linted (Decided 7), and where lints go
/// when it changes, all in UTF-16 units.
public enum WritingSpan {
    /// One change to a field's text: the part of the old text it replaced
    /// and the length of what took its place. Typing, pasting and deleting
    /// are each one; what the two texts share at their start and end is
    /// what it left alone. Next to repeated characters the change could
    /// have been in more than one place ("a teh" to "a a teh"), so it is
    /// kept at both ends of where it could be.
    public struct Edit: Sendable, Equatable {
        /// The part of the old text replaced, as far right as it can be.
        public var replaced: Range<Int>
        /// The same, as far left as it can be.
        public var leftmost: Range<Int>
        public var length: Int

        public init(replaced: Range<Int>, leftmost: Range<Int>? = nil, length: Int) {
            self.replaced = replaced
            self.leftmost = leftmost ?? replaced
            self.length = length
        }
    }

    /// The edit that turns `old` into `new`.
    public static func edit(from old: String, to new: String) -> Edit {
        let before = Array(old.utf16)
        let after = Array(new.utf16)
        let shortest = Swift.min(before.count, after.count)
        func sharedStart(upTo limit: Int) -> Int {
            var count = 0
            while count < limit, before[count] == after[count] { count += 1 }
            return count
        }
        func sharedEnd(upTo limit: Int) -> Int {
            var count = 0
            while count < limit, before[before.count - 1 - count] == after[after.count - 1 - count] { count += 1 }
            return count
        }
        // As far right: the shared start first, the end from what is left.
        let start = sharedStart(upTo: shortest)
        let end = sharedEnd(upTo: shortest - start)
        // As far left: the shared end first.
        let leftEnd = sharedEnd(upTo: shortest)
        let leftStart = sharedStart(upTo: shortest - leftEnd)
        return Edit(replaced: start..<(before.count - end),
                    leftmost: leftStart..<(before.count - leftEnd),
                    length: after.count - start - end)
    }

    /// Where `range` of the old text is after `edit`, or nil when the edit
    /// touched it or ran up against it: a word typed onto is another word,
    /// and its lint waits for the next run instead of being drawn from an
    /// offset that no longer holds. A range wholly before the edit wherever
    /// it was stays; one wholly after it moves; one inside a run of repeats,
    /// where either holds, goes too.
    public static func shift(_ range: Range<Int>, by edit: Edit) -> Range<Int>? {
        if edit.replaced.isEmpty, edit.length == 0 { return range }
        let before = range.upperBound < edit.replaced.lowerBound
        let after = range.lowerBound > edit.leftmost.upperBound
        switch (before, after) {
        case (true, false):
            return range
        case (false, true):
            let delta = edit.length - edit.replaced.count
            return (range.lowerBound + delta)..<(range.upperBound + delta)
        default:
            return nil
        }
    }

    /// Whether a caret is in the part `region` of a field `length` units
    /// long: a caret one unit past a paragraph's break is in the next one,
    /// but one at the very end of the text is in the last.
    public static func covers(_ region: Range<Int>, caret: Int, length: Int) -> Bool {
        region.contains(caret) || (caret == region.upperBound && region.upperBound == length)
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

/// Writing a suggestion back into another app's field (Docs/Tasks/03,
/// B1), in UTF-16 units: text_selection.rs's rules.
public enum FieldEdit {
    /// `text` as pieces of at most `limit` UTF-16 units, the most one key
    /// event reliably carries, never splitting a character (an emoji's two
    /// units in two events would type two broken halves). Nil for text with
    /// a line break, a tab or another control character: typed into a chat
    /// app, a return sends the message and a tab moves the focus.
    public static func typingChunks(_ text: String, limit: Int = 20) -> [[UInt16]]? {
        let breaks: Set<Unicode.Scalar> = ["\u{2028}", "\u{2029}"]
        guard !text.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control || breaks.contains($0)
        }) else { return nil }
        var chunks: [[UInt16]] = []
        func add(_ units: [UInt16]) {
            if let last = chunks.last, last.count + units.count <= limit {
                chunks[chunks.count - 1].append(contentsOf: units)
            } else {
                chunks.append(units)
            }
        }
        for character in text {
            let units = Array(character.utf16)
            if units.count <= limit {
                add(units)
            } else {
                // A character longer than a piece (a long emoji sequence)
                // goes a scalar at a time: a scalar is never split.
                for scalar in character.unicodeScalars { add(Array(String(scalar).utf16)) }
            }
        }
        return chunks
    }

    /// Where the person's selection goes after `edited` became
    /// `insertedLength` units long: before the edit it stays, after it it
    /// moves by the change in length, and one that overlapped the edit ends
    /// up after the new text. A caret right at the start of the edit counts
    /// as inside it, since that caret is what opened the suggestion.
    public static func selection(_ selection: NSRange, after edited: NSRange, insertedLength: Int) -> NSRange {
        let editedEnd = edited.location + edited.length
        let selectionEnd = selection.location + selection.length
        let isBefore = selectionEnd < edited.location
            || (selection.length > 0 && selectionEnd == edited.location)
        if isBefore { return selection }
        if selection.location >= editedEnd {
            return NSRange(location: selection.location + insertedLength - edited.length,
                           length: selection.length)
        }
        return NSRange(location: edited.location + insertedLength, length: 0)
    }
}
