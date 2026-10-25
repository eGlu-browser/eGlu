import AppKit
import ApplicationServices
import PadCore

/// The app in front and the text field being typed in, as Accessibility
/// sees them (Docs/Tasks/03, Decided 2, 4, 5, 6).
///
/// What is read: the focused element of the frontmost app, only while it
/// is an AXTextArea or AXTextField and not a password field (an
/// AXTextField whose subrole is AXSecureTextField). Never eGlu's own
/// windows, never Harper Desktop's, and nothing at all while Harper Desktop
/// itself is running — eGlu leaves the fields to it then. In an app the
/// settings leave off, only the focused element's role is read, to list
/// the app in Settings. Nothing is read until the checker starts it, and
/// nothing after it stops.
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

    /// What moves the text without changing it: the part of the text in
    /// view and the field's frame. Scrolling sends no notification, so the
    /// checker compares these on its beat (Decided 10).
    struct Looks: Equatable {
        var visible: NSRange?
        var frame: CGRect?
    }

    /// The field being watched and its app, when there is one.
    private(set) var field: AXUIElement?
    private(set) var app: NSRunningApplication?

    /// Every app eGlu has watched a field of since launch, by bundle id —
    /// the settings list shows these so the person can turn each off.
    @Published private(set) var seenApps: Set<String> = []
    @Published private(set) var harperDesktopRunning = false

    /// Electron and Chromium build their tree a moment after it is turned
    /// on: their fields are read this long after (accessibility_activation.rs).
    private static let chromiumSettle: TimeInterval = 3
    /// A turn-on that failed for a reason that may pass (Accessibility not
    /// allowed yet, the app busy) is tried again this much later, as
    /// Harper Desktop does.
    private static let retryInterval: TimeInterval = 10

    /// The AXObserver on the front app, with what it was told to watch, so
    /// it can be taken down again.
    private struct Observer {
        let pid: pid_t
        let observer: AXObserver
        let element: AXUIElement
        let notifications: [String]
    }

    /// The front app's accessibility as eGlu turned it on.
    private struct Activation {
        let pid: pid_t
        /// AXEnhancedUserInterface as it was, put back when the app leaves
        /// the front; nil when it couldn't be read, or when
        /// AXManualAccessibility took its place: that one stays on, as
        /// Harper Desktop leaves it, since turning it off throws away the
        /// tree the app just built.
        let restore: Bool?
        /// When a switch took, for the Chromium settle.
        let setAt: TimeInterval?
        /// When to try again after a failure that may pass.
        let retryAt: TimeInterval?
    }

    private var running = false
    private var observer: Observer?
    private var activation: Activation?
    /// Apps whose AXManualAccessibility eGlu turned on: it stays on, so
    /// coming back to one needs no wait for its tree.
    private var awake: Set<pid_t> = []
    private var refreshWork: DispatchWorkItem?
    /// When the pending refresh is due, so a later one doesn't push it back.
    private var refreshAt: TimeInterval = .infinity
    private var workspaceObservers: [NSObjectProtocol] = []
    private var preferences: () -> Preferences = { Preferences() }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFront() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.harperChanged() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.harperChanged() }
        })
        harperDesktopRunning = Self.harperDesktopIsRunning()
    }

    /// The preferences the checks read: set by the checker at start.
    func configure(preferences: @escaping () -> Preferences) {
        self.preferences = preferences
    }

    /// Begin watching the front app: the checker calls this once the
    /// settings are on and Accessibility is allowed.
    func start() {
        guard !running else { return }
        running = true
        AX.setTimeout()
        harperDesktopRunning = Self.harperDesktopIsRunning()
        refreshFront()
    }

    /// Stop reading: the observer taken down, the app's accessibility put
    /// back, no field.
    func stop() {
        guard running else { return }
        running = false
        refreshWork?.cancel()
        refreshWork = nil
        refreshAt = .infinity
        unobserve()
        release()
        app = nil
        setField(nil)
    }

    /// Harper Desktop coming or going changes whether eGlu checks at all.
    private func harperChanged() {
        let running = Self.harperDesktopIsRunning()
        guard running != harperDesktopRunning else { return }
        harperDesktopRunning = running
        if running {
            unobserve()
            release()
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
    /// AX notification, and on the checker's 4 Hz beat while a field is
    /// watched. The field is only reported when it is another one.
    func refreshFront() {
        guard running else { return }
        if refreshAt <= now { refreshAt = .infinity }
        guard !waitForHungApp(), let front = frontApp(), !waitForHungApp() else {
            if waitForHungApp() { return }
            unobserve()
            release()
            self.app = nil
            setField(nil)
            return
        }
        let app = front.app
        let isOn = front.isOn
        let pid = app.processIdentifier
        // An app turned off is still followed for its focus, so a text
        // field in it is listed in Settings, but its accessibility is left
        // as it was and its text never read. One listed already has
        // nothing more to tell.
        let listed = app.bundleIdentifier.map { seenApps.contains($0) || WritingApps.curated.contains($0) } ?? true
        if !isOn, listed {
            unobserve()
            release()
            self.app = app
            setField(nil)
            return
        }
        if !isOn {
            release()
        } else if activation?.pid != pid {
            release()
            activate(pid)
        } else if let retryAt = activation?.retryAt, now >= retryAt {
            activate(pid)
        }
        // After the wake-up: an app whose tree was asleep may take its
        // observer only now.
        if observer?.pid != pid { observe(pid) }
        // Each refresh asks again for what it still waits on, since an
        // earlier one may have taken the place of these.
        if observer == nil, isOn { scheduleRefresh(at: now + 1) }
        if let retryAt = activation?.retryAt { scheduleRefresh(at: retryAt) }
        if let setAt = activation?.setAt, now < setAt + Self.chromiumSettle {
            scheduleRefresh(at: setAt + Self.chromiumSettle)
        }
        self.app = app

        let focused = AX.element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
        let isField = focused.map(Self.isField) ?? false
        guard !waitForHungApp() else { return }
        guard let focused, isField else {
            setField(nil)
            return
        }
        // Seen with a text field, on or off: Settings lists it, so the
        // person can turn it on there (B3).
        if let bundle = app.bundleIdentifier, !seenApps.contains(bundle) {
            seenApps.insert(bundle)
        }
        guard isOn else {
            setField(nil)
            return
        }
        if let setAt = activation?.setAt, now < setAt + Self.chromiumSettle, Self.isChromium(focused) {
            setField(nil)
            scheduleRefresh(at: setAt + Self.chromiumSettle)
            return
        }
        guard !waitForHungApp() else { return }
        setField(focused)
    }

    /// A read just timed out: what is known stays as it is, and the front
    /// is looked at again once the pause is over.
    private func waitForHungApp() -> Bool {
        guard AX.isPaused else { return false }
        scheduleRefresh(at: AX.pausedUntil)
        return true
    }

    /// The frontmost app, and whether the settings have it checked; nil for
    /// eGlu itself and Harper Desktop, and while Harper Desktop runs.
    private func frontApp() -> (app: NSRunningApplication, isOn: Bool)? {
        guard !harperDesktopRunning else { return nil }
        // The system-wide element's focused application is the one with the
        // keyboard; the workspace's frontmost is the fallback.
        var app: NSRunningApplication?
        if let element = AX.element(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute) {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success {
                app = NSRunningApplication(processIdentifier: pid)
            }
        }
        if app == nil { app = NSWorkspace.shared.frontmostApplication }
        guard let app,
              let bundle = app.bundleIdentifier,
              bundle != Bundle.main.bundleIdentifier,
              !WritingApps.neverChecked.contains(bundle) else { return nil }
        let prefs = preferences()
        guard prefs.writing, prefs.writingOtherApps else { return nil }
        return (app, WritingApps.isOn(bundle, choices: prefs.writingApps, newApps: prefs.writingNewApps))
    }

    /// A field eGlu reads: only these two roles, and never a password
    /// field, which is a text field with its own subrole (Decided 4).
    static func isField(_ element: AXUIElement) -> Bool {
        guard let role = AX.string(element, kAXRoleAttribute),
              role == kAXTextAreaRole || role == kAXTextFieldRole else { return false }
        return AX.string(element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole
    }

    /// Whether the element is Chromium's (Chrome, Edge, Electron apps such
    /// as Slack): it carries a ChromeAXNodeId, as Harper Desktop checks on
    /// the field itself.
    static func isChromium(_ element: AXUIElement) -> Bool {
        AX.names(of: element).contains("ChromeAXNodeId")
    }

    // MARK: - Waking the app's accessibility

    /// Turn on the app's accessibility tree as Harper Desktop does
    /// (accessibility_activation.rs): AXEnhancedUserInterface, remembering
    /// what it was; where that can't be set, AXManualAccessibility, which
    /// Electron apps answer instead.
    private func activate(_ pid: pid_t) {
        let element = AXUIElementCreateApplication(pid)
        let before = AX.value(element, "AXEnhancedUserInterface") as? Bool
        var error = AX.set(element, "AXEnhancedUserInterface", to: true as CFTypeRef)
        let restore = error == .success ? before : nil
        // A tree already on needs no wait: one this app had, or one eGlu
        // woke before through AXManualAccessibility, which stays on.
        var wasAwake = error == .success && before == true
        if error != .success {
            let manual = AX.set(element, "AXManualAccessibility", to: true as CFTypeRef)
            if manual == .success {
                wasAwake = awake.contains(pid)
                awake.insert(pid)
                error = .success
            } else if Self.isUnsupported(error) {
                // Neither is there: whether to try again is the second's to say.
                error = manual
            }
        }
        switch error {
        case .success where wasAwake:
            activation = Activation(pid: pid, restore: restore, setAt: nil, retryAt: nil)
        case .success:
            activation = Activation(pid: pid, restore: restore, setAt: now, retryAt: nil)
            // A Chromium app's focused field may only appear once its tree is built.
            scheduleRefresh(at: now + Self.chromiumSettle)
        case _ where Self.isUnsupported(error):
            // Nothing to wake: the tree is read as the app keeps it.
            activation = Activation(pid: pid, restore: nil, setAt: nil, retryAt: nil)
        default:
            activation = Activation(pid: pid, restore: nil, setAt: nil, retryAt: now + Self.retryInterval)
            scheduleRefresh(at: now + Self.retryInterval)
        }
    }

    /// The app's AXEnhancedUserInterface back to what it was.
    private func release() {
        guard let activation else { return }
        self.activation = nil
        if let restore = activation.restore {
            AX.set(AXUIElementCreateApplication(activation.pid), "AXEnhancedUserInterface",
                   to: restore as CFTypeRef)
        }
    }

    /// The errors that mean an app has no such switch at all.
    private static func isUnsupported(_ error: AXError) -> Bool {
        error == .attributeUnsupported || error == .noValue || error == .notImplemented
    }

    /// One refresh at the earliest time asked for: each refresh asks again
    /// for whatever it still waits on, so a later wait is never lost.
    private func scheduleRefresh(at time: TimeInterval) {
        guard time < refreshAt || refreshAt <= now else { return }
        refreshWork?.cancel()
        refreshAt = time
        let work = DispatchWorkItem { [weak self] in self?.refreshFront() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, time - now), execute: work)
    }

    // MARK: - The app's notifications

    /// Watch the app's notifications, once per app. A create or add that
    /// fails leaves no observer, so the next refresh tries again.
    private func observe(_ pid: pid_t) {
        unobserve()
        var made: AXObserver?
        let callback: AXObserverCallback = { _, element, name, refcon in
            guard let refcon else { return }
            let front = Unmanaged<FrontField>.fromOpaque(refcon).takeUnretainedValue()
            let note = name as String
            // The source is on the main run loop, so this is the main thread.
            MainActor.assumeIsolated { front.hear(note, from: element) }
        }
        guard AXObserverCreate(pid, callback, &made) == .success, let made else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [kAXFocusedUIElementChangedNotification,
                             kAXValueChangedNotification,
                             kAXSelectedTextChangedNotification,
                             kAXWindowMovedNotification,
                             kAXWindowResizedNotification].filter {
            AX.add($0, to: made, on: element, refcon: refcon) == .success
        }
        // Without the focus notification nothing says another field is
        // typed in: try again on the next refresh.
        guard notifications.contains(kAXFocusedUIElementChangedNotification) else {
            for note in notifications { AXObserverRemoveNotification(made, element, note as CFString) }
            return
        }
        // Common modes, so notifications arrive while eGlu tracks a menu or a drag too.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .commonModes)
        observer = Observer(pid: pid, observer: made, element: element, notifications: notifications)
    }

    private func unobserve() {
        guard let observer else { return }
        self.observer = nil
        for note in observer.notifications {
            AXObserverRemoveNotification(observer.observer, observer.element, note as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .commonModes)
    }

    /// An AX notification: work out which event it is. Values and
    /// selections change all over an app; only the watched field's count.
    private func hear(_ name: String, from element: AXUIElement) {
        guard running else { return }
        switch name {
        case kAXFocusedUIElementChangedNotification:
            refreshFront()
        case kAXValueChangedNotification:
            guard let field, CFEqual(element, field), let text = readText() else { return }
            onEvent(.text(text))
        case kAXSelectedTextChangedNotification:
            guard let field, CFEqual(element, field) else { return }
            onEvent(.selection)
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard field != nil else { return }
            onEvent(.geometry)
        default:
            break
        }
    }

    private func setField(_ element: AXUIElement?) {
        switch (field, element) {
        case (nil, nil):
            return
        case let (old?, new?) where CFEqual(old, new):
            return
        default:
            break
        }
        field = element
        onEvent(.field(element))
    }

    // MARK: - Reads the checker shares

    /// The field's whole text, UTF-16-counted on our side.
    func readText() -> String? {
        guard let field else { return nil }
        return AX.string(field, kAXValueAttribute)
    }

    /// The caret's UTF-16 position, or nil for a selection or none.
    func readCaret() -> Int? {
        guard let field, let range = AX.range(field, kAXSelectedTextRangeAttribute),
              range.length == 0 else { return nil }
        return range.location
    }

    /// What the checker compares to tell a scroll or a move.
    func readLooks() -> Looks? {
        guard let field else { return nil }
        let visible = AX.range(field, kAXVisibleCharacterRangeAttribute)
            .map { NSRange(location: $0.location, length: $0.length) }
        return Looks(visible: visible, frame: FieldGeometry.frame(of: field))
    }
}

/// Reads of another app's elements. Each waits a quarter of a second at
/// most: the system's default is six, and every read runs on the main
/// actor, so a beachballing app would freeze eGlu with it. A read that
/// times out leaves the apps alone for two seconds, so a hung app costs
/// one short wait, not one per read.
@MainActor
enum AX {
    static let timeout: Float = 0.25
    static let pause: TimeInterval = 2
    private(set) static var pausedUntil: TimeInterval = 0

    static var isPaused: Bool { ProcessInfo.processInfo.systemUptime < pausedUntil }

    /// The wait for every element eGlu asks, set on the system-wide one.
    static func setTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeout)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard !isPaused else { return nil }
        var value: CFTypeRef?
        let error = timed { AXUIElementCopyAttributeValue(element, attribute as CFString, &value) }
        return error == .success ? value : nil
    }

    /// A parameterized attribute, such as the bounds of a range.
    static func value(_ element: AXUIElement, _ attribute: String, for parameter: CFTypeRef) -> CFTypeRef? {
        guard !isPaused else { return nil }
        var value: CFTypeRef?
        let error = timed {
            AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        }
        return error == .success ? value : nil
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, to value: CFTypeRef) -> AXError {
        guard !isPaused else { return .cannotComplete }
        return timed { AXUIElementSetAttributeValue(element, attribute as CFString, value) }
    }

    /// Whether the attribute can be set at all; nil when the app won't say.
    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard !isPaused else { return nil }
        var settable: DarwinBoolean = false
        guard timed({ AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) }) == .success
        else { return nil }
        return settable.boolValue
    }

    /// An observer's notification on an app, with the same short wait.
    static func add(_ notification: String, to observer: AXObserver, on element: AXUIElement,
                    refcon: UnsafeMutableRawPointer) -> AXError {
        guard !isPaused else { return .cannotComplete }
        return timed { AXObserverAddNotification(observer, element, notification as CFString, refcon) }
    }

    static func names(of element: AXUIElement) -> [String] {
        guard !isPaused else { return [] }
        var names: CFArray?
        guard timed({ AXUIElementCopyAttributeNames(element, &names) }) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // The type was checked just above, so the cast can't fail.
        return (value as! AXUIElement)
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        range(from: value(element, attribute))
    }

    static func rect(_ element: AXUIElement, _ attribute: String) -> CGRect? {
        rect(from: value(element, attribute))
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let axValue = axValue(value(element, attribute), .cgPoint) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let axValue = axValue(value(element, attribute), .cgSize) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    static func range(from value: CFTypeRef?) -> CFRange? {
        guard let axValue = axValue(value, .cfRange) else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    static func rect(from value: CFTypeRef?) -> CGRect? {
        guard let axValue = axValue(value, .cgRect) else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(axValue, .cgRect, &rect) ? rect : nil
    }

    /// `value` as an AXValue, when it is one holding `type`.
    private static func axValue(_ value: CFTypeRef?, _ type: AXValueType) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // The type was checked just above, so the cast can't fail.
        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    /// One call, timed: a `cannotComplete` that took the whole wait is an
    /// app not answering, where an immediate one is just a refusal.
    private static func timed(_ call: () -> AXError) -> AXError {
        let start = ProcessInfo.processInfo.systemUptime
        let error = call()
        let now = ProcessInfo.processInfo.systemUptime
        if error == .cannotComplete, now - start >= Double(timeout) * 0.9 {
            pausedUntil = now + pause
        }
        return error
    }
}
