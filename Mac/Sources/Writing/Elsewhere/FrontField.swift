import AppKit
import ApplicationServices
import PadCore

/// The app in front and the text field being typed in, as Accessibility
/// sees them (Docs/Tasks/03, Decided 2, 4, 5, 6).
///
/// What is read: the focused element of the frontmost app, only while it
/// is an AXTextArea or AXTextField. Never a secure field (its role is
/// another), never eGlu's own windows, never Harper Desktop's, and nothing
/// at all while Harper Desktop itself is running — eGlu leaves the fields
/// to it then.
@MainActor
final class FrontField: ObservableObject {
    static let shared = FrontField()

    /// What the checker hears about the field.
    enum Event {
        /// A different field (or app) is being watched now; nil ends watching.
        case field(AXUIElement?)
        /// The field's text changed.
        case text(String)
        /// The caret moved or the selection changed.
        case selection
        /// The window moved or resized: underlines are stale at once.
        case geometry
    }
    var onEvent: (Event) -> Void = { _ in }

    /// The field being watched and its app, when there is one.
    private(set) var field: AXUIElement?
    private(set) var app: NSRunningApplication?

    /// Every app eGlu has watched a field of since launch, by bundle id —
    /// the settings list shows these so the person can turn each off.
    @Published private(set) var seenApps: Set<String> = []
    var onSeenApp: (String) -> Void = { _ in }

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Apps accessibility was turned on for, and what it was before: it is
    /// put back when they leave the front.
    private var activated: [pid_t: Bool?] = [:]
    /// Chromium apps build their tree after the turn-on; reads start 3 s in.
    private var readyAt: [pid_t: TimeInterval] = [:]
    @Published private(set) var harperDesktopRunning = false

    private var preferences: () -> Preferences = { Preferences() }

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFront() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.harperChanged(note) }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.harperChanged(note) }
        })
        harperDesktopRunning = Self.harperDesktopIsRunning()
    }

    /// The preferences the checks read: set by the checker at start.
    func configure(preferences: @escaping () -> Preferences) {
        self.preferences = preferences
    }

    /// Begin watching the front app. Idempotent.
    func start() {
        refreshFront()
    }

    /// Harper Desktop coming or going changes whether eGlu checks at all.
    private func harperChanged(_ note: Notification) {
        let running = Self.harperDesktopIsRunning()
        guard running != harperDesktopRunning else { return }
        harperDesktopRunning = running
        if running {
            setField(nil)
        } else {
            refreshFront()
        }
    }

    static func harperDesktopIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.elijahpotter.harper-desktop").isEmpty
    }

    /// Read the front app and its focused field again: on activation, on an
    /// AX notification, and on the checker's 4 Hz timer (Decided 2 ends with
    /// the workspace notification; the timer catches what notifications miss).
    func refreshFront() {
        guard let app = frontApp() else {
            self.app = nil
            setField(nil)
            return
        }
        let pid = app.processIdentifier
        if observedPID != pid {
            observe(app: app)
        }
        self.app = app
        guard ready(at: pid) else { return }
        let element = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused else {
            setField(nil)
            return
        }
        // AX elements come back as AXUIElementRefs.
        let target = focused as! AXUIElement
        setField(Self.isField(target) ? target : nil)
    }

    /// The frontmost app that may be checked, else nil: not eGlu, not an
    /// app the settings leave off, and nothing while Harper Desktop runs.
    private func frontApp() -> NSRunningApplication? {
        guard !harperDesktopRunning else { return nil }
        // The system-wide element's focused application is the one with the
        // keyboard; the workspace's frontmost is the fallback.
        var app: NSRunningApplication?
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value) == .success,
           let element = value {
            var pid: pid_t = 0
            if AXUIElementGetPid(element as! AXUIElement, &pid) == .success {
                app = NSRunningApplication(processIdentifier: pid)
            }
        }
        if app == nil { app = NSWorkspace.shared.frontmostApplication }
        guard let app,
              let bundle = app.bundleIdentifier,
              bundle != Bundle.main.bundleIdentifier,
              !WritingApps.neverChecked.contains(bundle) else { return nil }
        let prefs = preferences()
        guard prefs.writing, prefs.writingOtherApps,
              WritingApps.isOn(bundle, choices: prefs.writingApps, newApps: prefs.writingNewApps)
        else { return nil }
        return app
    }

    /// A field eGlu reads: only these two roles, so secure fields and the
    /// rest are left alone.
    static func isField(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
              let role = value as? String else { return false }
        return role == kAXTextAreaRole || role == kAXTextFieldRole
    }

    /// Whether the app's accessibility tree may be read yet: Electron and
    /// Chromium apps (they carry a ChromeAXNodeId attribute) get 3 s after
    /// activation to build it.
    private func ready(at pid: pid_t) -> Bool {
        if let ready = readyAt[pid] { return ProcessInfo.processInfo.systemUptime >= ready }
        readyAt[pid] = .infinity
        let element = AXUIElementCreateApplication(pid)
        var names: CFArray?
        var isChromium = false
        if AXUIElementCopyAttributeNames(element, &names) == .success,
           let list = names as? [String] {
            isChromium = list.contains("ChromeAXNodeId")
        }
        readyAt[pid] = ProcessInfo.processInfo.systemUptime + (isChromium ? 3 : 0)
        activate(element: element, pid: pid)
        return !isChromium
    }

    /// Turn on the app's accessibility tree (Decided 2):
    /// AXEnhancedUserInterface, remembering the old value to put it back,
    /// and AXManualAccessibility where the first is unsupported.
    private func activate(element: AXUIElement, pid: pid_t) {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXEnhancedUserInterface" as CFString, &value) == .success {
            activated[pid] = value as? Bool
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString,
                                       kCFBooleanTrue as CFTypeRef)
        } else {
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString,
                                       kCFBooleanTrue as CFTypeRef)
            activated[pid] = nil
        }
    }

    /// The app's accessibility switches back to what it was.
    private func deactivate(pid: pid_t) {
        guard let previous = activated.removeValue(forKey: pid) else { return }
        let element = AXUIElementCreateApplication(pid)
        if let previous {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString,
                                         previous as CFTypeRef)
        } else {
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString,
                                       kCFBooleanFalse as CFTypeRef)
        }
    }

    /// Watch the app's notifications once per app.
    private func observe(app: NSRunningApplication) {
        if observedPID != 0 { deactivate(pid: observedPID) }
        let pid = app.processIdentifier
        observedPID = pid
        observer = nil

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, name, refcon in
            guard let refcon else { return }
            let field = Unmanaged<FrontField>.fromOpaque(refcon).takeUnretainedValue()
            let note = name as String
            Task { @MainActor in field.hear(note, element: element) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        self.observer = observer
        let element = AXUIElementCreateApplication(pid)
        for note in [kAXFocusedUIElementChangedNotification,
                     kAXValueChangedNotification,
                     kAXSelectedTextChangedNotification,
                     kAXWindowMovedNotification,
                     kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, element, note as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// An AX notification: work out which event it is.
    private func hear(_ name: String, element: AXUIElement) {
        switch name {
        case kAXFocusedUIElementChangedNotification:
            refreshFront()
        case kAXValueChangedNotification:
            onEvent(.text(readText() ?? ""))
        case kAXSelectedTextChangedNotification:
            onEvent(.selection)
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            onEvent(.geometry)
        default:
            break
        }
    }

    private func setField(_ element: AXUIElement?) {
        field = element
        if element != nil, let bundle = app?.bundleIdentifier, !seenApps.contains(bundle) {
            seenApps.insert(bundle)
            onSeenApp(bundle)
        }
        onEvent(.field(element))
    }

    // MARK: - Reads the checker shares

    /// The field's whole text, UTF-16-counted on our side.
    func readText() -> String? {
        guard let field else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    /// The caret's UTF-16 position, or nil for a selection or none.
    func readCaret() -> Int? {
        guard let field else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            field, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let rangeValue = value else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length == 0
        else { return nil }
        return range.location
    }

    /// The selection's UTF-16 range (a length over 0 means text is selected).
    func readSelection() -> CFRange? {
        guard let field else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            field, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let rangeValue = value else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }
}
