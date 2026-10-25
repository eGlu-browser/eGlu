# Task 03: Grammar checking in other apps, on the Mac

| | |
|---|---|
| Needs first | Task 01 (`Engines`) and task 02 (`WritingChecker`, `WritingWords`, Settings › Writing) merged |
| Size | L (one to two months) |
| Platform | Mac only: iPadOS lets no app read another app's text |
| Pull requests | Two: (A) reading, underlining and the panel; (B) applying suggestions, the apps list, settings |

## Goal

With "Check in Other Apps" on, eGlu checks the English typed in other Mac apps' text fields (TextEdit, Mail, Notes, Messages, Slack and the apps the person picks) the way Harper Desktop does: problems underlined over the app's text, Harper Desktop's suggestion panel when the caret rests in a flagged word, a suggestion written back so the app's Undo works.

Another app's text can't be drawn on from outside, so here, unlike in eGlu's pages (task 02, where WebKit draws the underlines on the text), the underlines are in a window of eGlu's over the app. Harper Desktop's underlines can fall out of step with the text when it scrolls or moves; this task hides them while anything moves and draws them again once it is still (Decided 10). It needs the Accessibility permission, asked only when the person turns this on. It runs while eGlu is open.

## Context every task needs

This section is the same in every task in `Docs/Tasks/`. Read it once; the task's own sections follow it.

### eGlu

- A WebKit browser for iPad, iPhone and Mac, made for desktop web apps (Figma, whiteboards, project boards) used with a trackpad and a keyboard. Repository: `eGlu-dot-apps/eGlu`. The README says what it does from a user's side; `Docs/Requirements.md` says where each requirement lives in the code.
- **Spaces**: each has its own tabs, bookmarks and WebKit data store (cookies, sign-ins). **The command bar** is the address field and the command palette in one. **Handoff** gives the page on screen to an assistant app as a Markdown file through the share sheet. **On the Mac**, eGlu runs Chrome extensions (`WKWebExtension`), has Peek and little windows, as Arc does.
- It was called Safience up to 1.0.7. The bundle identifier `net.taehee.safience`, the folders `Application Support/Safience` and `Caches/Safience`, and the other names in CONTRIBUTING.md's table keep the old name. Never rename them.

### Where things are

| Folder | What |
|---|---|
| `App/Sources` | The iPhone and iPad app (UIKit and SwiftUI) |
| `Mac/Sources` | The Mac app (AppKit and SwiftUI) |
| `Shared/` | Code both apps compile (`Shared/PageShared.swift` is the half of `Page` they share) |
| `PadCore/Sources/PadCore` | Plain logic as a Swift package, no UIKit, AppKit or WebKit. Builds and tests on Linux too (`#if canImport(...)` where it must) |
| `PadCore/Sources/PadCore/Scripts` | The JavaScript and CSS that go into pages (`bridge.js`, `markdown.js`, and others) |
| `PadCore/Tests/PadCoreTests` | Unit tests, XCTest and Swift Testing, among them `ScriptAndPolicyTests.swift` (PolicyTests) |
| `Tests/` | Script tests in a browser (`node Tests/bridge.mjs`, Playwright), Handoff's fixtures (`Tests/handoff`) |
| `Validation/CHECKLIST.md` | Checks only a real device can show: numbered `## N. Title` sections of `- [ ]` items |
| `Docs/` | Design documents and these tasks |
| `Config/` | xcconfig files and entitlements |
| `Release/mac.sh` | The Mac's DMG: build, sign, notarize, Sparkle's appcast |
| `project.yml` | The Xcode project, made with XcodeGen. `eGlu.xcodeproj` is committed as generated |

Targets (`project.yml`): `eGlu` (iOS 17 and later; App/ and Shared/), `eGlu Mac` and `eGlu Mac Direct` (macOS 26 and later; Mac/ and Shared/; Direct adds Sparkle and the `DIRECT` condition). The Mac app is a Developer ID DMG, not on the Mac App Store, outside the App Sandbox, with the hardened runtime (`Config/eGluMac.entitlements`). So on the Mac, WebKit's private API may be used where a `responds(to:)` check guards it, as picture in picture does (`Mac/Sources/Page.swift:250-258`).

### The rules (CONTRIBUTING.md)

1. **The page gets the input.** A key or gesture the browser takes from a page is a bug. On iPad and iPhone the browser's own shortcuts are ⌃⌥ and a key (`PadCore/Sources/PadCore/Commands.swift`, `Shortcuts.chords`), except ⌘T, ⌘W, ⇧⌘T, ⌘N, ⇧⌘W, ⌃⇥, ⌃⇧⇥. The Mac's menu bar keeps Safari's ⌘ keys for what Safari has (⌘L, ⌘R, ⌘F…) and puts eGlu's own commands on ⌃⌥ (`Mac/Sources/Menus.swift`). A new command gets a ⌃⌥ key on both.
2. **Hands off Google's sign-in.** On a host in `HandsOff.swift` no script of eGlu's runs, no JavaScript is called, no cookie is read. Calls into pages (`evaluateJavaScript`, `callAsyncJavaScript`, `addUserScript`) are made only in `Mac/Sources/Page.swift`, `App/Sources/Page.swift` and `Shared/PageShared.swift`, and each such file checks `HandsOff.covers` first. `PolicyTests` (`ScriptAndPolicyTests.swift:156-276`) reads the source and fails otherwise; it also fails on any code that reads cookies.
3. **A site's needs go in its adapter** (`PadCore/Sources/PadCore/Adapters.swift`), not in the app.
4. **No dependencies beyond Apple's frameworks.** Two exceptions only: Sparkle (eGlu Mac Direct), and the Rust engines in `Engines/` (Harper and anydoc, task 01). Nothing else: no npm packages in the app, no other Swift packages, no other Rust crates.
5. **Nothing leaves the device** but the pages the person opens: no analytics, no telemetry, no server of eGlu's, no cloud API.
6. **Comments say why**, not what the next line does. Read a couple of files before adding one, and match their style. No force-unwraps on anything that can plausibly fail.
7. **No real key or token** anywhere. `gitleaks git --pre-commit --staged` catches most.
8. **A change that adds or fixes something adds its line** under `## Unreleased` in CHANGELOG.md, under `### Added` or `### Fixed`, in the user's words: "On the Mac, …". A fix says "Before, …".

Text people see goes through the String Catalog: `String(localized:)` in the apps (`Shared/Resources/Localizable.xcstrings`), `BrowserText.localized` in PadCore (`PadCore/Sources/PadCore/Resources/*/Localizable.strings`), a whole sentence at a time. English only for now.

### Building and testing

- Xcode 26 or later. A team ID goes in `Config/Local.xcconfig`, which git ignores.
- After adding or removing a file: `xcodegen` at the root, and commit the regenerated project with the change.
- `cd PadCore && swift test`: PadCore's tests, on macOS or Linux. Logic goes in PadCore when it can, so it is tested there.
- `node Tests/bridge.mjs`: the page scripts in a browser (needs Playwright).
- Builds clean: no warnings you introduced. Swift 5 language mode everywhere; the iOS target has strict concurrency and `MainActor` as its default isolation; PadCore has strict concurrency.
- What only a device shows goes in `Validation/CHECKLIST.md` as a new section of `- [ ]` items.

### Working on it

- One branch and one pull request per task, unless the task says it comes in parts. Never push to `main`.
- When you are done, hand back: what changed, the tests run and their results, what you could not verify (and why), the CHANGELOG line, the new CHECKLIST section, and anything this task's plan got wrong.
- Decisions listed under "Decided" are taken. Don't reopen them; if one turns out impossible, stop and say why.

## What there is to start from

### In eGlu, from tasks 01 and 02

- `Engines.Grammar` (task 01): lints text and answers ranges in UTF-16.
- `Shared/Writing/WritingChecker.swift` (task 02): `lint(_:) async -> [GrammarLint]` (English paragraphs only), `addWord`, `ignore`.
- Settings › Writing (`Mac/Sources/SettingsView.swift`, `WritingSettings`), preferences `writing`, `writingDialect`, `writingRules`, `writingOffSites` (`PadCore/Sources/PadCore/Preferences.swift`).
- ⌃⌥G is "Accept Writing Suggestion" (`Command.acceptWritingSuggestion`) as a menu key, which works only while eGlu is the active app.
- In pages, task 02's card is HTML in the page. Other apps need a native panel, which this task brings in.

### Harper Desktop's panel, to bring in

harperSwift's `harper-desktop/macos-popup` (Swift package `HarperPopup`, Apache-2.0 as the repository; swift-tools 6.0 in Swift 5 mode, macOS 13). Files in `Sources/HarperPopup/`:

| File | What | For eGlu |
|---|---|---|
| `PopupModel.swift` | `PopupData` (snake_case JSON, `:8-84`), `PopupAction` (`:88-111`: 0 Close, 1 Apply(index), 2 Ignore, 3 AddToDict, 4 DisableRule, 5 DismissClarity, 6 TurnOffClarity) | Keep `PopupData` as a Swift struct made by eGlu (drop the JSON coding unless useful); keep actions 0 to 4 |
| `PopupView.swift` | The SwiftUI card, 320 points wide | Keep |
| `PopupPanel.swift` | A non-activating `NSPanel` that never becomes key, level `.popUpMenu` (`:8-33`); `PopupChrome`, Liquid Glass with `NSGlassEffectView`, corner radius 16 (`:42-92`); `PopupController`: show, update, hide, animation, VoiceOver, closes when another app is activated (`:107-386`) | Keep the panel and chrome; drop the `#if compiler`/`#available(macOS 26)` fallback (eGlu Mac needs macOS 26). Rework `PopupController` as `WritingPanel` (step A5), driven from Swift instead of Rust's per-frame action queue |
| `Placement.swift` | Geometry: where the card goes beside a word, from Accessibility's top-left screen coordinates | Keep |
| `AcceptShortcut.swift` | A Carbon hot key, ⌃⌘Y, registered only while the panel shows a suggestion | Use its pattern for ⌃⌥G (step B2) |
| `Bridge.swift`, `App/NativeBridge.swift`, `TextMetrics.swift`, `Clarity/*`, `Editor/*`, `Setup/*`, `App/*` | Rust's entry points, a text-width helper, Clarity, the editor, onboarding, windows | Not in this task |

Copy what is kept into `Mac/Sources/Writing/Panel/`, each file with a first comment: `// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.` Task 02 already brought `Settings/SettingsLists.swift`; don't bring it twice.

### Harper Desktop's highlighter, to rewrite in Swift

In [harperSwift](https://github.com/taehee-pd/harperSwift), `harper-desktop/src-tauri/src/` (Rust, Apache-2.0). It is a subprocess that redraws on every frame (no `AXObserver`). What it does, and where:

| Part | How it does it | Where |
|---|---|---|
| The app in front | `kAXFocusedApplicationAttribute` of the system-wide element, else `NSWorkspace.frontmostApplication` | `mac_broker/focused_window_pid.rs:13-45` |
| The field with the focus | `kAXFocusedUIElementAttribute`, remembered while its own overlay has the focus | `mac_broker/mod.rs:99-112, 318-320` |
| Waking an app's accessibility | Sets `AXEnhancedUserInterface`, else `AXManualAccessibility` (Chromium and Electron apps); waits 3 s for Chromium to settle | `accessibility_activation.rs:28, 90-104` |
| A window moving | Its frame from `CGWindowList`, settled after 150 ms | `window_stability.rs:17, 48` |
| Reading text | Only `AXTextArea` and `AXTextField`; `AXValue` | `accessibility_text.rs:162, 295-306`; tree walk `mac_broker/mod.rs:358-371` |
| Where a word is | `AXBoundsForRange` with a `CFRange`; for Chromium, `AXStaticText` children; else `AXFrame` and an estimate from text width | `accessibility_text.rs:57-139, 358-409`; `estimated_bounds.rs:31-80` |
| **A bug not to copy** | It passes character indices where Accessibility wants UTF-16, so underlines drift after an emoji | `accessibility_text.rs:183-188, 365, 387` |
| Drawing | A transparent, borderless, always-on-top window per screen that lets every click through; a faint fill (alpha 24 of 255) and a 2-point underline | `highlighter/window.rs:37-54`; `render_state/draw_highlight.rs:9-26` |
| When the panel shows | The caret settled 150 ms in a flagged range; typing hides it; reading pauses while the pointer rests on the panel, with 500 ms grace after typing | `mac_broker/caret_tracker.rs:18, 41-51, 89-121`; `native_popup/mod.rs:99-101, 176, 209-216, 314-333` |
| Writing a suggestion back | Checks `AXValue` still is what was read (else "text changed"), sets `AXSelectedTextRange` to the range, then `AXSelectedText` to the new text, then puts the selection back shifted; for Chromium (it has a `ChromeAXNodeId` attribute), types it with `CGEvent`s to the app's process in chunks of at most 20 UTF-16 units, no modifier keys; if the app refuses, sets the whole `AXValue` | `text_selection.rs:151-174, 189-260, 281-330`; `accessibility_text.rs:261-292` |
| UTF-16 and characters | `utf16_offset`, `char_index`, `caret_char_index` | `text_selection.rs:41-58, 105-109` |
| The accept key | ⌃⌘Y as a Carbon hot key (`RegisterEventHotKey`), registered only while the panel shows a suggestion | `macos-popup/Sources/HarperPopup/AcceptShortcut.swift:13, 23-38`; `PopupPanel.swift:189, 225-243` |
| Which apps | Curated: TextEdit, Mail, Messages, Notes, Slack, Discord, Day One; others off unless "new apps" is on; Harper Desktop's own id (`com.elijahpotter.harper-desktop`) always left out | `config/integration.rs:10-35`; `config/mod.rs:52, 80-97`; `mac_broker/mod.rs:61, 327-346` |
| The permission | Asks, then looks again every 2 s | `accessibility_watch.rs:20-38`; `macos-popup/.../App/AccessibilityAccess.swift` |

Read those files for the details; write eGlu's in Swift with AppKit and `ApplicationServices` (Apple's frameworks only).

## Decided

1. **Swift, in eGlu's process.** No helper app, no subprocess. It runs while eGlu runs; checking when eGlu is closed (a login helper) is not in this task.
2. **Watching, not polling every frame:** an `AXObserver` on the front app for `kAXFocusedUIElementChangedNotification`, `kAXValueChangedNotification`, `kAXSelectedTextChangedNotification`, `kAXWindowMovedNotification`, `kAXWindowResizedNotification`, plus a timer at 4 Hz while a field is being checked, for scrolling (which sends nothing). `NSWorkspace.didActivateApplicationNotification` for the app in front.
3. **UTF-16 throughout**, as the Accessibility API and `NSString` count. No character indices.
4. **Only `AXTextArea` and `AXTextField`.** Never `AXSecureTextField`, never eGlu itself (`Bundle.main.bundleIdentifier`, its pages are task 02's), never Harper Desktop (`com.elijahpotter.harper-desktop`).
5. **If Harper Desktop is running**, eGlu does not check other apps, and Settings says so: "Harper Desktop is checking other apps, so eGlu leaves them to it." It starts again when Harper Desktop quits.
6. **Apps**: the curated list on by default; any other app off until the person turns it on; a switch "Check New Apps" (off).
7. **Long text**: up to 50,000 UTF-16 units, the whole field; beyond, the paragraph with the caret and the two on each side.
8. **The accept key** is ⌃⌥G, as in pages, registered as a global hot key only while the panel shows a suggestion over another app, and unregistered as soon as it hides, so ⌃⌥G belongs to the other app at all other times.
9. **Nothing typed is logged or kept.** Text lives in memory for as long as it is being checked.
10. **Underlines never lag behind the text.** They are hidden at once when anything that moves text happens: the field's text changes, its visible range or bounds change (the 4 Hz timer compares `kAXVisibleCharacterRangeAttribute` and the field's frame), its window moves or resizes, or the pointer scrolls over it (a `CGEvent` tap for scroll-wheel events is not used: the timer is enough). They are drawn again once nothing has changed for 150 ms, from rectangles read again then. Never drawn from rectangles read before the last change.

## Pull request A: reading, underlining, the panel

### A1. Pure logic in PadCore (tested on Linux)

`PadCore/Sources/PadCore/WritingElsewhere.swift`:

- `struct CaretSettle`: Harper Desktop's caret tracker as a value type: `mutating func moved(to caret: Int, at time: TimeInterval, textChanged: Bool) -> Event?` and `mutating func tick(at:) -> Event?`, events `.visit(lintIndex)`, `.leave`; settles after 0.15 s; text changing hides. Port `caret_tracker.rs:18-121` with its tests.
- `enum WritingApps`: `curated: Set<String>` (the bundle identifiers in `config/integration.rs:10-35`), `static func isOn(_ bundleID: String, choices: [String: Bool], newApps: Bool) -> Bool`, and `static let neverChecked: Set<String>` (Harper Desktop's identifier; eGlu's own is added at run time).
- `enum WritingSpan`: `clip(_ range:, toLength:)`, and the window of paragraphs for long text (Decided 7): `func region(of text: String, caret: Int, limit: Int) -> Range<Int>` in UTF-16 units.

Tests for each, including text with emoji and Korean.

### A2. Preferences

In `Preferences.swift` (three edits each, and `PreferencesTests`):

```swift
/// Whether Harper checks the English typed in other apps too (Docs/Tasks/03). Off until turned on.
public var writingOtherApps = false
/// Apps turned on or off by the person, by bundle identifier: only the differences from WritingApps.curated.
public var writingApps: [String: Bool] = [:]
/// Whether an app not yet chosen is checked.
public var writingNewApps = false
```

### A3. The watcher (Mac)

`Mac/Sources/Writing/Elsewhere/`:

- `AccessibilityAccess.swift`: `isTrusted` (`AXIsProcessTrusted()`), `ask()` (`AXIsProcessTrustedWithOptions` with the prompt option), and a 2-second check until trusted (as `accessibility_watch.rs:20-38`), published so Settings can show it.
- `FrontField.swift`: follows the app in front and its focused element (Decided 2); for a new app, sets `AXEnhancedUserInterface` to true, or `AXManualAccessibility` when that fails (`accessibility_activation.rs:90-104`), and waits 3 s for an Electron or Chromium app (it has a `ChromeAXNodeId` attribute); reads `kAXRoleAttribute`, `kAXValueAttribute`, `kAXSelectedTextRangeAttribute`; ignores the roles and apps of Decided 4 and 6, and everything while Harper Desktop runs (Decided 5: `NSRunningApplication.runningApplications(withBundleIdentifier:)`, and `NSWorkspace` launch and quit notifications).
- `FieldGeometry.swift`: `rects(for range: NSRange, in element: AXUIElement) -> [CGRect]` with `kAXBoundsForRangeParameterizedAttribute` (a `CFRange` in UTF-16), one call per line (split the range where the bounds' height jumps); the Chromium fallback through `AXStaticText` children (`accessibility_text.rs:358-409`); the estimate from `AXFrame` and text width (`estimated_bounds.rs:31-80`, measured with `NSString.size(withAttributes:)` in the field's font where it says, else the system font at 13 points). Accessibility's rectangles are top-left screen coordinates.
- `ElsewhereChecker.swift` (main actor): when the field's text changes, waits 300 ms, lints with `WritingChecker` (the region of Decided 7), keeps the lints with the text they were for, and asks `Underlines` to draw; feeds `CaretSettle` from the selection; shows and hides `WritingPanel` on its events.

### A4. The underlines

`Mac/Sources/Writing/Elsewhere/Underlines.swift`: one `NSPanel` per screen, `styleMask: [.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `ignoresMouseEvents = true`, `level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, never key or main. A layer-backed view draws, for each lint's rectangles (converted from top-left to each screen's coordinates), a fill at alpha 0.1 and a 2-point line at the bottom in the kind's colour (task 02's colours). Follows Decided 10: hidden at once on any change, drawn again 150 ms after the last one, from fresh rectangles; cleared when the field loses focus or the app changes.

### A5. The panel over other apps

`WritingPanel` (main actor), the rework of `PopupController`:

- `show(lint: GrammarLint, word: String, at rect: CGRect /* screen, top-left origin */, actions: (PopupAction) -> Void)`, `hide()`.
- It never becomes key, so the other app keeps the keyboard; it hides when another app is activated, and with the underlines (Decided 10).
- `PopupData` from the lint: the message (Markdown, rendered with `AttributedString(markdown:)`), the kind and its colour (task 02's colours), up to five suggestions as buttons ("Remove" for `.remove`, the text for `.replace`, "Insert “x”" for `.insert`), and Ignore, Add to Dictionary (spelling lints only), Turn Off This Rule.
- Actions: Ignore → `WritingChecker.ignore`; Add to Dictionary → `addWord`; Turn Off This Rule → `writingRules[rule] = false`; Close → hide; Apply is pull request B, and until it lands Apply is not shown.
- Its words through the String Catalog.

### A6. Pull request A done when

- [ ] In TextEdit, Notes and Slack, a misspelt word is underlined in the right place, also after an emoji, and the panel shows when the caret rests in it.
- [ ] Scrolling a long note in Notes, typing above a flagged word, and moving the window: the underlines vanish while it moves and come back on the words, never drawn off them.
- [ ] Nothing in a password field, in eGlu's own windows, or while Harper Desktop runs.
- [ ] PadCore tests pass.

## Pull request B: applying suggestions, the apps list, settings

### B1. Writing a suggestion back

`Mac/Sources/Writing/Elsewhere/FieldWriter.swift`, `func replace(range: NSRange, expected: String, with text: String, in element: AXUIElement, app: NSRunningApplication) -> Outcome` (`.done`, `.changed`, `.refused`):

1. Read `AXValue`; if its text in `range` is not `expected`, answer `.changed` (the checker lints again).
2. For a Chromium or Electron app (`ChromeAXNodeId` present): set `AXSelectedTextRange` to `range`, then type `text` with `CGEvent(keyboardEventSource:virtualKey:keyDown:)` and `keyboardSetUnicodeString`, posted to the app's process (`postToPid`), in chunks of at most 20 UTF-16 units, no modifier flags (`text_selection.rs:281-330`); an empty `text` is a Delete key press.
3. Otherwise: set `AXSelectedTextRange` to `range`, then `AXSelectedText` to `text`; put the selection back where it was, moved by the change in length (`text_selection.rs:151-174, 240-248`).
4. If a set fails with an error that says the attribute can't be set, set the whole `AXValue` to the changed text, only if `AXValue` is still what was read, and put the selection back.
5. Lint again after writing.

### B2. ⌃⌥G over other apps

`Mac/Sources/Writing/Elsewhere/AcceptKey.swift`: `RegisterEventHotKey` for `kVK_ANSI_G` with `controlKey | optionKey` (Carbon), registered when the panel shows a suggestion over another app, unregistered when it hides (`AcceptShortcut.swift`'s pattern). Pressing it applies the first suggestion.

### B3. Settings › Writing › In Other Apps

A section in `WritingSettings` after the first:

| Row | Does |
|---|---|
| Toggle "Check in Other Apps" (`writingOtherApps`) | Turning it on asks for Accessibility when not trusted, and shows "Allow eGlu in System Settings › Privacy & Security › Accessibility" with a button that opens that pane (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`) until it is |
| The apps | Each app eGlu has seen with a text field since launch, and the curated ones, with its icon and name (`NSWorkspace`), and a switch writing to `writingApps` only when it differs from the default |
| Toggle "Check New Apps" (`writingNewApps`) | |
| A note when Harper Desktop runs | Decided 5's words |

Footer: "eGlu reads the text of the field you type in, while you type, to check it on this Mac. It keeps nothing and sends nothing."

### B4. Pull request B done when

- [ ] A suggestion applied in TextEdit, Notes, Mail and Slack, undone with ⌘Z in each (Slack: as far as it allows).
- [ ] ⌃⌥G works over another app only while the panel shows, and goes to the app otherwise.
- [ ] The settings above; the permission flow from "never asked" to "allowed" without a relaunch.

## Tests

- `cd PadCore && swift test`: `CaretSettle`, `WritingApps`, `WritingSpan`, preferences.
- By hand, a new section in `Validation/CHECKLIST.md`, "Grammar in other apps (Mac)": TextEdit (plain and rich text), Notes, Mail's compose window, Messages, Slack, Discord; a word after "😀" and after Korean text underlined in the right place; the panel beside the word on a second display; a suggestion applied and undone; a password field, eGlu's own window, and Harper Desktop running (nothing from eGlu); Accessibility turned off in System Settings while it runs (it stops, Settings says so).
- Note in the hand-back: a build signed only to run on this Mac asks for Accessibility again after each rebuild (as harperSwift's README says of its own).

## Done when

- [ ] Both pull requests merged; tests pass; no new warnings.
- [ ] CHECKLIST section run once, results written under it.
- [ ] CHANGELOG under `### Added`: "On the Mac, Harper can check what you type in other apps too, such as Mail, Notes and Slack: turn on Settings › Writing › Check in Other Apps and allow eGlu in Accessibility."
- [ ] If task 05 (onboarding) is merged: its Mac question offers "In other apps too" (`offersOtherApps` true, the checkbox wired to `writingOtherApps` and `AccessibilityAccess.ask()`), as task 05's "Parts that wait" says.
- [ ] README's grammar section (task 02's) says it, and PRIVACY.md says that, with this on, eGlu reads the field being typed in other apps, on the Mac only, keeping and sending nothing.

## Out of scope

- Checking while eGlu is closed (a login helper).
- Harper Desktop's Clarity suggestions and editor.
- The iPad and iPhone: not possible.
