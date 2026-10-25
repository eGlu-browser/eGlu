import Foundation

/// What the measuring tool (measure.js) says about an element, decoded from
/// its `details` message: its boxes, layout, type and colours, its name for
/// a note, and its first words.
public struct MeasureDetails: Sendable, Equatable {
    public var tag = ""
    public var id = ""
    public var classes: [String] = []
    public var width = 0.0
    public var height = 0.0
    public var x = 0.0
    public var y = 0.0
    public var margin: Sides = Sides()
    public var padding: Sides = Sides()
    public var border: Sides = Sides()
    public var display = ""
    public var rowGap = ""
    public var columnGap = ""
    public var family = ""
    public var size = ""
    public var weight = ""
    public var lineHeight = ""
    public var letterSpacing = ""
    public var color = ""
    public var background = ""
    public var radius = ""
    /// The name the element is known by in a note (nameOf in measure.js).
    public var name = ""
    /// Its first words, to say it by in a note.
    public var text = ""
    /// Its handle back in the page, for pinning a note's dot to it.
    public var ref = 0

    public init() {}

    public struct Sides: Sendable, Equatable {
        public var top = 0.0
        public var right = 0.0
        public var bottom = 0.0
        public var left = 0.0
        public init() {}
        public init(top: Double, right: Double, bottom: Double, left: Double) {
            self.top = top
            self.right = right
            self.bottom = bottom
            self.left = left
        }
    }

    /// The element's look in one line, for the "Now:" of a note to an
    /// assistant: padding, type, colours and radius.
    public var current: String {
        var parts: [String] = []
        let pad = padding.text
        if !pad.isEmpty { parts.append("padding \(pad)") }
        let type = [family, [size, lineHeight].filter { !$0.isEmpty }.joined(separator: "/"), weight]
            .filter { !$0.isEmpty }.joined(separator: " ")
        if !type.isEmpty { parts.append(type) }
        if !color.isEmpty {
            parts.append(background.isEmpty || background == "rgba(0, 0, 0, 0)" ? color : "\(color) on \(background)")
        }
        if !radius.isEmpty, radius != "0px" { parts.append("radius \(radius)") }
        return parts.joined(separator: "; ")
    }

    static func sides(_ value: Any?) -> Sides {
        guard let map = value as? [String: Any] else { return Sides() }
        return Sides(top: number(map["top"]), right: number(map["right"]),
                     bottom: number(map["bottom"]), left: number(map["left"]))
    }

    static func number(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return 0
    }

    /// From the `details` message's body, or nil if it is none.
    public init?(body: [String: Any]) {
        guard let kind = body["kind"] as? String, kind == "details" else { return nil }
        tag = body["tag"] as? String ?? ""
        id = body["id"] as? String ?? ""
        classes = body["classes"] as? [String] ?? []
        width = Self.number(body["width"])
        height = Self.number(body["height"])
        x = Self.number(body["x"])
        y = Self.number(body["y"])
        margin = Self.sides(body["margin"])
        padding = Self.sides(body["padding"])
        border = Self.sides(body["border"])
        display = body["display"] as? String ?? ""
        if let gap = body["gap"] as? [String: Any] {
            rowGap = gap["row"] as? String ?? ""
            columnGap = gap["column"] as? String ?? ""
        }
        if let font = body["font"] as? [String: Any] {
            family = font["family"] as? String ?? ""
            size = font["size"] as? String ?? ""
            weight = font["weight"] as? String ?? ""
            lineHeight = font["lineHeight"] as? String ?? ""
            letterSpacing = font["letterSpacing"] as? String ?? ""
        }
        color = body["color"] as? String ?? ""
        background = body["background"] as? String ?? ""
        radius = body["radius"] as? String ?? ""
        name = body["name"] as? String ?? ""
        text = body["text"] as? String ?? ""
        ref = Int(Self.number(body["ref"]))
    }
}

extension MeasureDetails.Sides {
    /// "8px 16px" as CSS writes it, or "" when every side is 0.
    public var text: String {
        let sides = [top, right, bottom, left]
        if sides.allSatisfy({ $0 == 0 }) { return "" }
        let px = { (v: Double) in v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))px" : "\(v)px" }
        return sides.map(px).joined(separator: " ")
    }
}

/// The distance a `distance` message reports: between facing sides, or the
/// four insets when the element under the pointer holds the selected one.
public struct MeasureDistance: Sendable, Equatable {
    /// What the pointer is on.
    public var target = ""
    /// Set but empty of lines: ⌥ lifted.
    public var gone = false
    public var inside = false
    public var dx = 0.0
    public var dy = 0.0
    public var insets: MeasureDetails.Sides = MeasureDetails.Sides()

    public init() {}

    public init?(body: [String: Any]) {
        guard let kind = body["kind"] as? String, kind == "distance" else { return nil }
        gone = body["gone"] as? Bool ?? false
        target = body["target"] as? String ?? ""
        inside = body["inside"] as? Bool ?? false
        dx = MeasureDetails.number(body["dx"])
        dy = MeasureDetails.number(body["dy"])
        insets = MeasureDetails.sides(body["insets"])
    }
}

/// The guide and ruler settings measure.js takes as its `guides` argument
/// and `__egluMeasure.settings` takes again when the panel's fields change.
public struct MeasureGuides: Sendable, Equatable {
    public var columns = 12
    public var gutter = 24.0
    public var margin = 0.0
    public var row = 8.0
    public var rulers = true

    public init() {}

    public init(preferences: Preferences) {
        columns = preferences.measureColumns
        gutter = preferences.measureGutter
        margin = preferences.measureMargin
        row = preferences.measureRow
        rulers = preferences.measureRulers
    }

    /// As callAsyncJavaScript's `guides` argument.
    public var argument: [String: Any] {
        ["columns": columns, "gutter": gutter, "margin": margin, "row": row, "rulers": rulers]
    }

    /// The fields' values kept for the next run (Decided 6): the column
    /// guide's count, gutter and margin, the rows' step, the rulers.
    public func keep(in preferences: inout Preferences) {
        preferences.measureColumns = columns
        preferences.measureGutter = gutter
        preferences.measureMargin = margin
        preferences.measureRow = row
        preferences.measureRulers = rulers
    }
}

/// A colour the tool's picker came back with, shown as #hex and rgb().
public struct MeasureColour: Sendable, Equatable {
    public var red = 0
    public var green = 0
    public var blue = 0

    public init(red: Int, green: Int, blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var hex: String { String(format: "#%02x%02x%02x", red, green, blue) }
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }
}
