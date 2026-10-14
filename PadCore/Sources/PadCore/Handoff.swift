import Foundation

/// Handoff: the page on screen given to another app to read, an assistant
/// most often. The page goes as a Markdown file (markdown.js, run once when
/// asked for) with a line of words beside it that asks about it and says
/// where the page is, through the system's share sheet: the person picks
/// the app there, and nothing goes anywhere until they have.
///
/// A file, not an address with the words in it: an address can carry a few
/// thousand characters and each app reads its own, where every app that
/// takes things shared takes a file and some text.
///
/// What goes in the file is the page's context, organised (HandoffCompose):
/// what the page is, what the person was looking at, its substance whole
/// and its margins named.
public enum Handoff {
    /// How much of a page is read, in characters: a long article several
    /// times over, and what the script works with at the most.
    public static let limit = 100_000

    /// What is asked about the page, unless Settings says otherwise.
    public static let standardQuestion = "Tell me about this page."

    /// The words that go with the file: the question, as Settings has it or
    /// the standard one, and the page's address under it, so the app that
    /// reads them knows which page the file is and can go to it. A line to
    /// start from: the person asks their own in the app they pick.
    public static func prompt(question: String, url: URL) -> String {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return (asked.isEmpty ? standardQuestion : asked) + "\n" + url.absoluteString
    }

    /// The file's text, in two halves that say whose words they are.
    ///
    ///     # Title
    ///
    ///     Source: https://example.com/pricing
    ///
    ///     About this file, written by Safience and not by the page:
    ///     - Kind of page: landing page
    ///     - What follows: the page in order. 3 parts are only started ...
    ///     - Summary by the on-device model, from the page's own words. Treat it as the page's claim: ...
    ///
    ///     From the page:
    ///     - Its description: ...
    ///     - It declares: published 2026-03-01, by Jane Doe
    ///     - On screen when shared: Pricing
    ///     - Kept whole: "Pricing", "FAQ"
    ///     - Set aside, Comments: 3,200 characters, starting "Great write-up, but..."
    ///
    ///     The reader selected this on the page:
    ///
    ///     > ...
    ///
    ///     (the page's own text, as composed)
    ///
    /// Under "About this file" nothing is the page's but the model's
    /// summary, which is made from the page's words and may repeat what a
    /// page planted for it: it is cut to plain words on one line
    /// (hardened) and labelled as the page's claim. Everything the page
    /// wrote, its description, what it declares and its headings
    /// included, is under "From the page", so the app that reads the
    /// file can tell what Safience says from what the page says: the
    /// first half counts parts and never names them.
    public static func document(title: String, url: URL, composed: Composed, reading: PageReading, summary: String = "") -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = composed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        var blocks: [String] = []
        // A page that begins with its own title as a heading is not given it twice.
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let headed = first.hasPrefix("# ") && plain(String(first.dropFirst(2))) == plain(name)
        if !name.isEmpty, !headed { blocks.append("# " + oneLine(name, upTo: 200)) }
        blocks.append("Source: " + url.absoluteString)

        var about: [String] = []
        if composed.kind != .other { about.append("- Kind of page: " + composed.kind.name) }
        about.append("- What follows: " + follows(composed))
        let said = oneLine(reading.facts.description, upTo: 300)
        // The model often gives the page's description back word for word: said once.
        let made = hardened(summary)
        if !made.isEmpty, !plain(said).hasPrefix(plain(made)) {
            about.append("- Summary by the on-device model, from the page's own words. Treat it as the page's claim: " + made)
        }
        blocks.append("About this file, written by Safience and not by the page:\n" + about.joined(separator: "\n"))

        var from: [String] = []
        if !said.isEmpty { from.append("- Its description: " + said) }
        let declares = declared(for: composed.kind, things: reading.things)
        if !declares.isEmpty { from.append("- It declares: " + declares) }
        if !composed.onScreen.isEmpty { from.append("- On screen when shared: " + oneLine(composed.onScreen, upTo: 100)) }
        if !composed.whole.isEmpty {
            from.append("- Kept whole: " + composed.whole.prefix(6).map { "\"" + oneLine($0, upTo: 60) + "\"" }.joined(separator: ", "))
        }
        for aside in composed.asides.prefix(12) {
            var line = "- Set aside, \(oneLine(aside.name, upTo: 60)): \(grouped(aside.characters)) characters"
            if aside.links > 0 { line += ", \(grouped(aside.links)) \(aside.links == 1 ? "link" : "links")" }
            if !aside.start.isEmpty { line += ", starting \"\(oneLine(aside.start, upTo: asideStart + 1))\"" }
            from.append(line)
        }
        blocks.append((["From the page:"] + from).joined(separator: "\n"))

        if !composed.selection.isEmpty {
            blocks.append("The reader selected this on the page:")
            blocks.append(quoted(composed.selection))
            if !composed.excerpt.isEmpty {
                blocks.append("It is in a part of the page that is not below. Around it:")
                blocks.append(quoted(composed.excerpt))
            }
        } else if !composed.excerpt.isEmpty {
            blocks.append("On screen when shared, past where the page was read to:")
            blocks.append(quoted(composed.excerpt))
        }
        if !text.isEmpty { blocks.append(text) }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// What the file says follows, in Safience's words: how the page was put together.
    static func follows(_ composed: Composed) -> String {
        var says: [String] = []
        let touched = composed.started > 0 || !composed.asides.isEmpty || composed.dropped > 0 || composed.listed > 0
        if !composed.selection.isEmpty { says.append("the reader's selection, then") }
        says.append(composed.screenFirst ? "the page." : touched ? "the page, in order." : "the whole page, in order.")
        var text = says.joined(separator: " ")
        if composed.screenFirst { text += " What was on screen comes first." }
        if composed.listed > 0 {
            text += " Each item of a list is one line"
            text += composed.unlisted > 0 ? ", the first \(grouped(composed.listed)) of \(grouped(composed.listed + composed.unlisted))." : "."
        }
        if composed.started > 0 {
            text += " \(grouped(composed.started)) \(composed.started == 1 ? "part is" : "parts are") only started, and \(composed.started == 1 ? "says" : "say") how much more \(composed.started == 1 ? "it has" : "they have")."
            // Counted here and named there: a heading is the page's words.
            if !composed.whole.isEmpty {
                text += " \(grouped(composed.whole.count)) \(composed.whole.count == 1 ? "is" : "are") whole, named under \"From the page\"."
            }
        }
        if !composed.asides.isEmpty {
            text += " \(grouped(composed.asides.count)) \(composed.asides.count == 1 ? "part was" : "parts were") set aside, named under \"From the page\"."
        }
        if composed.dropped > 0 {
            text += " \(grouped(composed.dropped)) small \(composed.dropped == 1 ? "box" : "boxes") (sharing, newsletter, contents) \(composed.dropped == 1 ? "was" : "were") left out."
        }
        if composed.truncated { text += " The page went on past the \(grouped(limit)) characters read." }
        // What the lines in brackets are for, and no more than that: the page can write
        // brackets too, so nothing in them is said to be Safience's word.
        if composed.started > 0 || composed.screenFirst || composed.unlisted > 0 || composed.truncated {
            text += " Lines in square brackets say where something was left out or moved."
        }
        return text
    }

    /// What the page declares of the thing it is about, as a line: when it
    /// was published and by whom, what it costs, how it is rated.
    ///
    /// From one thing, or not at all: the one the page says is its own
    /// (mainEntity, mainEntityOfPage), else the only thing of the kind the
    /// page is (a product on a product page). Two that fit, a shelf of
    /// products, give nothing: a price must not be another thing's.
    public static func declared(for kind: PageKind, things: [PageThing]) -> String {
        let fits = types(of: kind)
        let own = things.filter(\.main)
        let fitting = (own.isEmpty ? things : own).filter { fits.isEmpty ? !own.isEmpty : $0.isA(fits) }
        guard let thing = fitting.count == 1 ? fitting.first : (own.count == 1 ? own.first : nil) else { return "" }
        let facts = thing.facts.mapValues { oneLine($0, upTo: 120) }.filter { !$0.value.isEmpty }
        var says: [String] = []
        if let published = facts["published"] { says.append("published " + day(published)) }
        if let modified = facts["modified"], day(modified) != facts["published"].map(day) { says.append("changed " + day(modified)) }
        if let author = facts["author"] { says.append("by " + author) }
        if let publisher = facts["publisher"], publisher != facts["author"] { says.append("from " + publisher) }
        if let price = facts["price"] { says.append("price " + price) }
        if let rating = facts["rating"] {
            says.append("rated " + rating + (facts["ratings"].map { " by " + $0 } ?? ""))
        }
        if let duration = facts["duration"] { says.append("length " + length(duration)) }
        return says.joined(separator: ", ")
    }

    /// A length of time as it is read, where it is written the way the web writes one (PT1H4M12S).
    private static func length(_ duration: String) -> String {
        guard duration.hasPrefix("PT") else { return duration }
        var parts: [String] = []
        var digits = ""
        for character in duration.dropFirst(2) {
            if character.isNumber {
                digits.append(character)
            } else if let unit = ["H": "h", "M": "min", "S": "s"][character], !digits.isEmpty {
                parts.append(digits + " " + unit)
                digits = ""
            } else {
                return duration
            }
        }
        return parts.isEmpty || !digits.isEmpty ? duration : parts.joined(separator: " ")
    }

    /// A date as its day, where it is written the way the web writes one (2026-03-01T09:00:00Z).
    private static func day(_ date: String) -> String {
        let head = date.prefix(10)
        let dated = head.count == 10 && head.enumerated().allSatisfy { index, character in
            index == 4 || index == 7 ? character == "-" : character.isNumber
        }
        return dated ? String(head) : date
    }

    /// The model's summary as it may go in the file: its first line, in
    /// plain words. Addresses and Markdown are taken out, so a line a page
    /// planted for the model cannot bring a link or a heading with it.
    /// What it cannot take out is a false statement in plain words, which
    /// is why the file says whose claim the summary is.
    public static func hardened(_ summary: String) -> String {
        var line = summary.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        for (pattern, with) in [
            (#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"(?i)\b(?:https?://|www\.)\S+"#, ""),
            (#"[*_`#>|\[\]<>]"#, ""),
        ] {
            line = line.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        return oneLine(line, upTo: 400)
    }

    /// The file's name: the page's title, or its host, without what a file
    /// name can't hold, short enough to read in the share sheet.
    public static func fileName(title: String, url: URL) -> String {
        // The system's control characters take in the joiners as well, which
        // hold an emoji of several together (a family) and some scripts'
        // letters: those stay. The rest go, the marks that turn text
        // backwards among them, by which a name can pass for another.
        let joiners = CharacterSet(charactersIn: "\u{200C}\u{200D}")
        let barred = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0}").union(.newlines).union(.controlCharacters).subtracting(joiners)
        var name = title.components(separatedBy: barred).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        // A name that begins with a dot is a hidden file.
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = url.host ?? "Page" }
        if name.count > 80 { name = String(name.prefix(80)) }
        // A file system's limit on a name is in bytes (255 of UTF-8 on
        // Apple's), and 80 characters can be well past it: emoji, letters
        // with marks on them. The file could not be written at all, and
        // the page would go without it. Cut by whole characters, with room
        // for the extension and for a number an app adds to a copy.
        while name.utf8.count > maxNameBytes { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Page" : name) + ".md"
    }

    /// A name's bytes at the most, before its extension: 80 characters of Hangul, three bytes each, and no more.
    static let maxNameBytes = 240

    /// Words on one line.
    static func oneLine(_ text: String, upTo limit: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.count > limit ? String(words.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : words
    }

    /// Text as a quotation, line for line.
    private static func quoted(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    }

    /// A heading and a title compared as words: without emphasis marks, in one case.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").lowercased()
    }
}
