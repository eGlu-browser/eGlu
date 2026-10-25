import Foundation

/// Whether a page gets the developer bar and its tools. A site remembers
/// its own choice once made; before that, a local site has it on and any
/// other site has it off. `local` is the "Developer Mode on Local Sites"
/// setting: off, local sites no longer get it by themselves.
public enum DeveloperMode {
    public static func isOn(_ url: URL?, choices: [String: Bool], local: Bool) -> Bool {
        guard let url, let host = url.host() else { return false }
        if let key = SiteMode.siteKey(host), let choice = choices[key] { return choice }
        return local && Address.isLocal(host: host)
    }

    /// The key a site's choice is remembered under, as the rest of the
    /// site's choices are (SiteMode).
    public static func siteKey(_ url: URL?) -> String? {
        url?.host().flatMap { SiteMode.siteKey($0) }
    }

    /// Whether a response's MIME type is JSON (`application/json` or a
    /// `+json` kind, as `application/activity+json`): a page of it gets the
    /// JSON view while Settings formats JSON (Preferences.formatJSON).
    public static func isJSON(mimeType: String?) -> Bool {
        guard let type = mimeType?.lowercased(),
              let subtype = type.split(separator: "/").last else { return false }
        return subtype == "json" || subtype.hasSuffix("+json")
    }

    /// What the command bar's text asks of the Mac's local servers
    /// (Docs/Tasks/08, Decided 8): nil where it asks for none, "" for every
    /// one ("local", "localhost"), else the first digits of the ports it
    /// names (":51", "localhost:51" or "51").
    public static func localServerDigits(_ text: String) -> String? {
        let typed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if typed == "local" || typed == "localhost" { return "" }
        var digits = typed
        if typed.hasPrefix("localhost:") { digits = String(typed.dropFirst("localhost:".count)) }
        else if typed.hasPrefix(":") { digits = String(typed.dropFirst()) }
        else if typed.isEmpty { return nil }
        // ":" alone lists them all, as "local" does.
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.count <= 5 else { return nil }
        return digits
    }

    /// A point measure.js says (a tap for a colour), in the web view's
    /// points, by the same sum as pickedRect; nil off the view.
    public static func viewPoint(_ answer: Any?, view: CGSize) -> CGPoint? {
        guard var said = answer as? [String: Any] else { return nil }
        said["width"] = 0.0
        said["height"] = 0.0
        guard let spot = pickedRect(said, view: view, margin: 0.5) else { return nil }
        return CGPoint(x: spot.midX, y: spot.midY)
    }

    /// element-pick.js's answer as the rectangle of the web view it covers,
    /// in the view's points, with `margin` points round it, clipped to the
    /// view: nil for Escape or an element wholly off screen. The script
    /// measures in CSS pixels from the layout viewport; the visual viewport
    /// says where the part on screen starts and how many CSS pixels wide it
    /// is, so the view's width over it is the points a CSS pixel takes, the
    /// page's zoom, a desktop page scaled to fit and a pinch all in one
    /// (bridge.js's clientPoint, the other way).
    public static func pickedRect(_ answer: Any?, view: CGSize, margin: Double = 16) -> CGRect? {
        guard let said = answer as? [String: Any] else { return nil }
        func number(_ key: String) -> Double? {
            if let value = said[key] as? Double { return value }
            if let value = said[key] as? Int { return Double(value) }
            return (said[key] as? NSNumber)?.doubleValue
        }
        guard let x = number("x"), let y = number("y"), let width = number("width"), let height = number("height"),
              view.width > 0, view.height > 0
        else { return nil }
        let shown = number("viewportWidth").flatMap { $0 > 0 ? $0 : nil } ?? Double(view.width)
        let scale = Double(view.width) / shown
        let rect = CGRect(x: (x - (number("viewportX") ?? 0)) * scale, y: (y - (number("viewportY") ?? 0)) * scale,
                          width: width * scale, height: height * scale)
        let room = rect.insetBy(dx: -margin, dy: -margin).intersection(CGRect(origin: .zero, size: view))
        return room.isNull || room.isEmpty ? nil : room
    }
}
