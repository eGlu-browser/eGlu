# Task 02: Grammar checking in pages, on the Mac

| | |
|---|---|
| Needs first | Task 01 (the `Engines` package with `Grammar`) merged |
| Unblocks | 03 (other apps), 04 (iPad and iPhone), 05 (onboarding) |
| Size | L (one to two months) |
| Platform | Mac |
| Pull requests | Two: (A) the panel, Settings › Writing, preferences, the dictionary; (B) the page script and checking in pages |

## Goal

In eGlu for Mac, with grammar checking turned on, English typed in a page's text fields is checked as it is typed, by Harper, on the Mac. Problems are underlined; putting the caret in an underlined word shows Harper Desktop's suggestion panel beside it; choosing a suggestion fixes the text so that the page's own Undo undoes it. ⌃⌥G accepts the first suggestion. Settings › Writing turns it on and off and holds the dialect, the rules, the personal dictionary and the sites where it is off. It is off until the person turns it on (task 05 asks at onboarding).

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

### The engine (task 01)

`import Engines` gives:

- `actor Grammar`: `init(settings:)`, `configure(_:)`, `warmUp()`, `lint(_ text:, markdown:) -> [GrammarLint]`, `ignore(context:)`, `static rules() -> [GrammarRule]`.
- `GrammarSettings { dialect: Dialect, rules: [String: Bool] (differences from the defaults), words: [String] }`.
- `GrammarLint { start, end (UTF-16), rule, kind, message (Markdown), priority, context, suggestions: [.replace(String) | .insert(String) | .remove] }`. `.insert` inserts at `end`.
- `GrammarRule { id, label, description, group, isOnByDefault }`.
- The first lint builds the dictionary's search structure, which takes noticeable time: call `warmUp()` off the main actor as soon as checking is on.

### Harper Desktop's UI, to bring in

[harperSwift](https://github.com/taehee-pd/harperSwift)'s `harper-desktop/macos-popup` (Swift package `HarperPopup`, Apache-2.0 as the repository; swift-tools 6.0 in Swift 5 mode, macOS 13). Files in `Sources/HarperPopup/`:

| File | What | For eGlu |
|---|---|---|
| `PopupModel.swift` | `PopupData` (snake_case JSON, `:8-84`), `PopupAction` (`:88-111`: 0 Close, 1 Apply(index), 2 Ignore, 3 AddToDict, 4 DisableRule, 5 DismissClarity, 6 TurnOffClarity) | Keep `PopupData` as a Swift struct made by eGlu (drop the JSON coding unless useful); keep actions 0 to 4 |
| `PopupView.swift` | The SwiftUI card, 320 points wide | Keep |
| `PopupPanel.swift` | A non-activating `NSPanel` that never becomes key, level `.popUpMenu` (`:8-33`); `PopupChrome`, Liquid Glass with `NSGlassEffectView`, corner radius 16 (`:42-92`); `PopupController`: show, update, hide, animation, VoiceOver, closes when another app is activated (`:107-386`) | Keep the panel and chrome. Drop the `#if compiler`/`#available(macOS 26)` fallback: eGlu Mac needs macOS 26. Rework `PopupController` so eGlu drives it from Swift instead of Rust's per-frame action queue |
| `Placement.swift` | Geometry: where the card goes beside a word; takes Accessibility's top-left screen coordinates and flips them to AppKit's | Keep. Give it the word's rectangle in top-left screen coordinates (step B4) |
| `AcceptShortcut.swift` | A Carbon hot key, ⌃⌘Y | Not used here (task 03 may use the idea for other apps); eGlu's key is a menu command, ⌃⌥G |
| `Bridge.swift`, `App/NativeBridge.swift` | `@_cdecl` functions Rust calls | Drop |
| `Settings/SettingsLists.swift`, `SettingsView.swift`, `SettingsModel.swift` | Rules and dictionary lists; a JSON RPC model to Rust | Take the rule list and the dictionary list views; replace the model with one bound to eGlu's preferences |
| `TextMetrics.swift`, `Clarity/*`, `Editor/*`, `Setup/*`, `App/*` | A text-width helper for Rust, Apple-model sentence suggestions, an editor window, Harper Desktop's own onboarding and windows | Not in this task |

The lint colours by kind are in harperSwift's `harper-desktop/src-tauri/src/lint_kind_color.rs`: use the same.

Copy what is kept into `Mac/Sources/Writing/`, each file with a first comment: `// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.` Then make it read like eGlu's code (CONTRIBUTING: comments say why).

### eGlu's page code (Mac)

- **Scripts go in** in `Page.prepare(for:)` (`Mac/Sources/Page.swift:427-455`), for main-frame navigations (`:908-909`) and from `settingsChanged()` (`:468-470`). It rebuilds only when a stamp string changes (`installed`/`wanted`, `:105-106`, `:434-437`): **a new script must add what it depends on to the stamp**, or it is not put in again when that changes. It removes all scripts (`:438`), stops on a hands-off host (`:439`), and adds `PasswordWatch.script` at document end in `Page.world` (`:440-443`), the picture script, the filter scripts, the store script (`:451-454`). Every user script is main frame only.
- **PDFs are not skipped** by `prepare`: check `mimeType` (`Page.swift:111`, set at `:951`) yourself.
- **`Page.world`** is `WKContentWorld.world(name: "eGlu")` (`Page.swift:92`): eGlu's scripts share the page's DOM but not its JavaScript.
- **Message handlers**: `StoreButton` and `PasswordWatch` are registered in `setUp` with `controller.add(Handler(page: self), contentWorld: Page.world, name: Handler.name)` (`Page.swift:288-292`), never on extension pages. `PasswordWatch.swift` is the pattern: its script as a string in its own file (`:19-41`), its handler checking main frame and world (`:49-55`). No handler with replies exists yet: this task adds the first `WKScriptMessageHandlerWithReply`, registered with `controller.addScriptMessageHandler(_:contentWorld:name:)`.
- **PolicyTests is a text search.** In `App/`, `Mac/` and `Shared/`, the words `evaluateJavaScript`, `callAsyncJavaScript` and `addUserScript` may appear only in `Page.swift`, `PageShared.swift` and three named files (`ScriptAndPolicyTests.swift:197-248`), **comments included**. So every call into a page (applying a suggestion, clearing the underlines) is a method in `Mac/Sources/Page.swift`, which checks `HandsOff.covers` first, and the writing code calls that method.
- **Scripts as files**: `PadCore/Sources/PadCore/Scripts/*.js`, loaded by `public static let x = load("x", "js")` in `Scripts.swift` (pattern at `:64-68`, `:104`; `load` at `:118-123`). `PadCore/Package.swift:21` copies the folder, so a new file ships by itself. `isolated()` (`:114-116`) wraps a script in try and catch.
- **The page's zoom**: `pageZoom` (`Page.swift:494-504`), and the view's `magnification`.

### Preferences, Settings, commands (Mac)

- **Preferences** (`PadCore/Sources/PadCore/Preferences.swift`): one `Codable` struct saved as JSON in `UserDefaults` under `"preferences"` (`:207-213`). A new one takes three edits: a `var` with its default (`:23-102`), a `CodingKeys` case (`:128-143`), a decode line `(try? c.decodeIfPresent(...)) ?? default` (`:145-174`). A change saves, calls `settingsChanged()` on every live page (`Shared/SessionPreferences.swift:8-21`), and applies `Preferences.Changes` (`Preferences.swift:217-239`). Tests: `PreferencesTests` (`ScriptAndPolicyTests.swift:4-79`). Preferences stay on the device; they are not synced.
- **Mac Settings** (`Mac/Sources/SettingsView.swift`): `SettingsPane` (`:100-136`: general, iCloud, spaces, pinned, blocking, extensions, each with title, symbol and tint); the detail switch (`:40-47`); a pane is a `private struct XSettings: View { Form { Section { … } header: { … } footer: { … } } }` bound to `$session.preferences.x` (as at `:212`); `Note` for footers (`:622`).
- **Commands** (`PadCore/Sources/PadCore/Commands.swift`): `Command` (`:5-41`), `title` (`:43-79`), `keywords` (`:82-117`), `ShortcutGroup` (`:181-208`), `Shortcuts.chords` (`:211-245`). `CommandTests.swift` requires every command to have a ⌃⌥ chord unless reserved (`:6-13`), chords to be unambiguous, and each command to be in exactly one group (`:50-54`). A new command also needs its symbol in **both** `App/Sources/Menus.swift:111-151` and `Mac/Sources/CommandBar.swift:196-232`, and a case in **both** `perform` switches: `App/Sources/Browser.swift:2064-2126` and `Mac/Sources/WindowModel.swift:886-920`.
- **The Mac's keys are not read from `Shortcuts.chords`**: its menu bar is SwiftUI `BrowserCommands` (`Mac/Sources/Menus.swift:7-285`) with each `.keyboardShortcut` written out, and `WindowModel.keys(for:)` (`WindowModel.swift:930-955`) says which keys a command shows. Free on ⌃⌥: C, E, G, I, J, M (and others); ⌃⌥N and ⌃⌥O are taken on the Mac outside the table (`Menus.swift:23, 35`).
- **The page's menu** is the `PageActions` popover (`Mac/Sources/PageActions.swift:12-102`): tiles (`:20-40`), rows (`:42-60`, `:68-77`), `ActionRow(title, symbol:, keys:)` (`:159-194`).

## Decided

1. **Checked:** `textarea`; `input` of type `text`, `search` or none; the editing host of `contenteditable` (`true`, `""`, `plaintext-only`). **Never:** `input` of type password, email, url, tel, number; a field with `autocomplete` starting `cc-` or equal to `one-time-code`, `username`, `email`, `current-password`, `new-password`; a field that is read-only or disabled; anything with `spellcheck="false"` on it or an ancestor (it inherits); anything inside `.CodeMirror`, `.cm-editor`, `.monaco-editor`, `.ace_editor`; a hands-off host; a PDF or a picture; an extension's page; a frame (eGlu's scripts are main frame only).
2. **English only.** A paragraph whose language Apple's `NLLanguageRecognizer` says is not English (dominant hypothesis not English with probability at least 0.6, for 20 characters or more) is not sent. A paragraph is text between line breaks.
3. **When:** 300 ms after typing stops in a field, and when a checked field gains focus. Only the field with the focus is checked.
4. **The panel shows** when the caret comes to rest (150 ms) inside an underlined range, as in harperSwift's caret tracker, and never while typing. It hides when the caret leaves the range, on typing, on scroll beyond the word, on another tab, window or app.
5. **Applying:** the script selects the range and calls `document.execCommand("insertText", false, text)`, so the page's Undo undoes it and React, ProseMirror and Slate see an ordinary input. If the field's text in that range is no longer what was checked, nothing is changed and the field is checked again. If `execCommand` returns false in a `textarea` or `input`, set the value through the element's prototype setter and dispatch `input` with `inputType: "insertReplacementText"`.
6. **Underlines** are drawn in a closed shadow root under `document.documentElement`, fixed, with `pointer-events: none`: never in the page's text, never catching a click. A click on an underlined word goes to the page, which puts the caret there, which shows the panel.
7. **Keys:** ⌃⌥G, "Accept Writing Suggestion", accepts the panel's first suggestion. Nothing else is taken from the page.
8. **The personal dictionary** is a file, `Application Support/Safience/Writing/dictionary.txt`, one word per line, sorted: Harper Desktop's format. Rules turned off and sites turned off are preferences.
9. **Ignore** hides that lint for as long as the app runs (`Grammar.ignore(context:)`); it is not saved.
10. **macOS's own spell check** is turned off in eGlu's pages while Harper checks them, so a word is not underlined twice, and put back as it was when Harper is turned off.

## Pull request A: the panel, Settings › Writing, preferences, the dictionary

### A1. Preferences (PadCore)

In `Preferences.swift`, with their three edits each and a line in `PreferencesTests` for the defaults and for decoding a blob without them:

```swift
/// Whether Harper checks the English typed in pages (Docs/Tasks/02). Off until the person turns it on.
public var writing = false
/// Harper's English: "American", "British", "Australian", "Canadian" or "Indian".
public var writingDialect = "American"
/// Harper's rules the person changed, by name: only the differences from its defaults.
public var writingRules: [String: Bool] = [:]
/// Sites where pages are not checked, by host (Hosts.normal).
public var writingOffSites: [String] = []
```

And in PadCore, `WritingSites` (`PadCore/Sources/PadCore/WritingSites.swift`): `static func isOff(_ url: URL?, sites: [String]) -> Bool`, matching a host and its subdomains as `HandsOff.covers` does (`HandsOff.swift:17-33`, `Hosts.host(_:isWithin:)`), plus a built-in list where checking never runs because the text is drawn, not typed: `docs.google.com`. Tests for both.

### A2. The checker (Shared)

`Shared/Writing/WritingChecker.swift` (the iPad will use it too, task 04):

- `@MainActor final class WritingChecker` (one for the app), holding a `Grammar` when `preferences.writing` is on and nil otherwise.
- `func preferencesChanged(_ p: Preferences)`: builds or configures the `Grammar` from `GrammarSettings(dialect: Dialect(rawValue: p.writingDialect) ?? .american, rules: p.writingRules, words: WritingWords.load())`, then `warmUp()` in a task off the main actor. Call it from where the session handles a preferences change (`Shared/SessionPreferences.swift`).
- `func lint(_ text: String) async -> [GrammarLint]`: splits into paragraphs at line breaks, skips the ones that are not English (Decided 2), lints the rest, shifts each lint's `start` and `end` by its paragraph's UTF-16 offset, and returns them sorted. On any `EngineError`, logs it (`os.Logger`, subsystem as the app's other loggers) and returns `[]`.
- `func addWord(_ word: String)`, `func ignore(_ lint: GrammarLint)`.

`Shared/Writing/WritingWords.swift`: `load() -> [String]`, `save(_:)`, `add(_:)`, `remove(_:)` for `dictionary.txt` (create the folder if needed; write atomically). And `harperDesktopWords() -> [String]?`, reading `~/Library/Application Support/harper-desktop/dictionary.txt` where it exists (the Mac only, `#if os(macOS)`).

### A3. The panel (Mac)

1. Copy the kept files of `HarperPopup` into `Mac/Sources/Writing/` (see the table above), with the first comment, and remove what eGlu does not use.
2. `WritingPanel` (rework of `PopupController`), main actor:
   - `show(lint: GrammarLint, word: String, at rect: CGRect /* screen, top-left origin */, in window: NSWindow, actions: (PopupAction) -> Void)`
   - `hide()`
   - It never becomes key, so the page keeps the keyboard; it hides when the window resigns key or another app is activated.
   - `PopupData` from the lint: the message (Markdown: render with `AttributedString(markdown:)`), the kind and its colour, up to five suggestions as buttons ("Remove" for `.remove`, the text for `.replace`, "Insert “x”" for `.insert`), and Ignore, Add to Dictionary (only for spelling lints), Turn Off This Rule.
3. Its words go through the String Catalog.

### A4. Settings › Writing (Mac)

A new `SettingsPane.writing` (title "Writing", symbol `character.cursor.ibeam`, a tint like the others) and `WritingSettings: View`:

| Section | Holds |
|---|---|
| (first) | Toggle "Check Grammar and Spelling in Pages" bound to `writing`. Footer: "English only. Harper checks it on this Mac; nothing you type is sent anywhere." |
| English | Picker of the five dialects, bound to `writingDialect` |
| Rules | `Grammar.rules()` by group, a toggle for each; a rule's toggle writes to `writingRules` only when it differs from `isOnByDefault`, and removes the entry when it is put back. "Restore Defaults" empties `writingRules`. Reuse `SettingsLists.swift`'s rule list |
| Dictionary | The words in `dictionary.txt`, with Add and Remove; "Add Harper Desktop's Words" only when `harperDesktopWords()` is not nil |
| Sites | `writingOffSites`, each with a Remove button; footer: "Turn checking off for a site from the page's menu." |

Sections other than the first are disabled while `writing` is off.

### A5. Pull request A done when

- [ ] PadCore tests pass with the new preferences and `WritingSites`.
- [ ] Settings › Writing shows, saves, and survives a relaunch.
- [ ] A DEBUG-only menu item (in `Mac/Sources/Menus.swift`, under `#if DEBUG`) shows the panel for a sample lint at the mouse, to check the panel's look in light and dark, with Reduce Transparency on and off. Remove it in pull request B.

## Pull request B: checking in pages

### B1. `writing.js`

`PadCore/Sources/PadCore/Scripts/writing.js`, loaded as `Scripts.writing` (`Scripts.swift`), run in `Page.world`. Plain JavaScript, no build step, in the style of the other scripts (read `bridge.js` and `markdown.js` first). Structure:

1. **State:** the field being checked, its text as last sent, a sequence number, the lints for that text, the overlay.
2. **Which fields:** `checkable(element)` by Decided 1. For `contenteditable`, the editing host: the nearest ancestor (or self) whose `isContentEditable` is true and whose parent's is not.
3. **Focus:** `focusin` on `document` (capturing) → if `checkable`, attach and check at once; `focusout` → after 200 ms, if the focus is not back in the field, detach and clear.
4. **Text and offsets:**
   - `textarea`/`input`: `value`.
   - `contenteditable`: walk the host's nodes in order, appending text nodes' data, `"\n"` for `<br>` and at the end of each block element (`display` block, list-item, table-row, or `P`, `DIV`, `LI`, `H1` to `H6`, `BLOCKQUOTE`, `PRE`), and record for each text node its start in the string. `rangeFor(start, end)` turns UTF-16 offsets back into a DOM `Range`.
5. **Checking:** on `input` in the field, wait 300 ms without input, then `const seq = ++sent; const lints = await window.webkit.messageHandlers.egluWriting.postMessage({ kind: "lint", text })`. Drop the answer if `seq !== sent` or the field's text changed meanwhile. Keep the lints and draw them.
6. **Drawing:**
   - The overlay: one `div` appended to `document.documentElement`, `attachShadow({ mode: "closed" })`, `position: fixed; inset: 0; pointer-events: none; z-index: 2147483647`.
   - Rectangles: `contenteditable` → `rangeFor(...).getClientRects()`. `textarea`/`input` → a mirror `div` with the field's computed font, size, letter spacing, line height, padding, border widths, box sizing, width, `white-space: pre-wrap` (`pre` for `input`), `overflow-wrap: break-word`, placed at the field's rectangle and scrolled by the field's `scrollTop`/`scrollLeft`, with the field's text; a `Range` over its text node gives the rectangles. Clip each rectangle to the field's visible rectangle.
   - Each rectangle: a 2-pixel line under it in the lint's kind's colour (Harper Desktop's colours), with a faint fill as Harper Desktop has (alpha about 0.1).
   - Drawn again, at most once a frame (`requestAnimationFrame`), on `scroll` (document, capturing), `resize`, `input`, and a `MutationObserver` on the editing host.
7. **The caret:** on `selectionchange`, if the selection is collapsed in the field and inside a lint's `start`…`end` (inclusive), after 150 ms with no typing and no further movement, post `{ kind: "caret", index, rect }` where `rect` is the word's first rectangle in viewport pixels; otherwise post `{ kind: "away" }` once.
8. **Applying**, as `apply({ start, end, expected, text })`, called from Swift: check the field's text from `start` to `end` equals `expected`; select it (`setSelectionRange` for fields, a `Range` in the selection for `contenteditable`); `document.execCommand("insertText", false, text)`, with Decided 5's fallback; then check again. Return whether it was applied.
9. **Clearing:** `clear()` removes the overlay and forgets the field.
10. Wrap the whole in `isolated()`'s try and catch, as the other scripts.

### B2. In `Mac/Sources/Page.swift`

1. In `prepare(for:)`, after the password watch: add `Scripts.writing` at document end, in `Page.world`, main frame only, when all hold: `Session.shared.preferences.writing`, not an extension page, not `WritingSites.isOff(url, sites:)`, and `mimeType` neither `application/pdf` nor `image/*`. Add these to the stamp (`wanted`).
2. In `setUp`, beside `StoreButton` and `PasswordWatch` (`:288-292`), not on extension pages: `controller.addScriptMessageHandler(WritingHandler(page: self), contentWorld: Page.world, name: WritingHandler.name)`.
3. `func writingApply(start: Int, end: Int, expected: String, text: String) async -> Bool` and `func writingClear()`: check `HandsOff.covers(view.url)` and `HandsOff.covers(committed)` first, then `callAsyncJavaScript` in `Page.world`.
4. Tell the writing code when the page navigates, goes behind another tab, or closes, so the panel hides.

### B3. `WritingHandler` (Mac)

`Mac/Sources/Writing/WritingHandler.swift`: `NSObject, WKScriptMessageHandlerWithReply`, `static let name = "egluWriting"`, a weak page. In `userContentController(_:didReceive:replyHandler:)` (nonisolated, then `MainActor.assumeIsolated` or a `Task { @MainActor in }` as `StoreButton.swift:24-39` does):

- Accept only `message.frameInfo.isMainFrame`, `message.world == Page.world`, a page that is not hands-off, and `writing` on; else reply `nil`.
- `kind: "lint"`: reply with `checker.lint(text)` as an array of plain dictionaries (`start`, `end`, `kind`, `rule`, `index`), keeping the full lints in the handler for this page.
- `kind: "caret"`: convert `rect` to screen coordinates (B4) and `WritingPanel.show(...)`; actions: Apply(i) → `page.writingApply(...)` with the lint's range, the text it covered, and the suggestion's new text (for `.insert`, `start = end` and `expected = ""`); Ignore → `checker.ignore`, then ask the page to check again; Add to Dictionary → `checker.addWord(word)`; Turn Off This Rule → `writingRules[rule] = false`; Close → hide.
- `kind: "away"`: hide.

### B4. From the page's pixels to the screen

`rect` is in CSS pixels of the viewport. On screen: multiply by `pageZoom` and by the view's `magnification`; that is the rectangle in the web view's own coordinates (WKWebView on the Mac is flipped: y down from its top). `view.convert(rect, to: nil)` into the window, `window.convertToScreen(_:)` onto the screen (bottom-left origin); `Placement.swift` wants top-left, so `y = screenFrame.maxY - rect.maxY` of the screen holding the window. Check it with the page zoomed (⌘+) and in a window on a second display.

### B5. ⌃⌥G

1. `Command.acceptWritingSuggestion` in `Commands.swift`: title "Accept Writing Suggestion", keywords "grammar", "spelling", "harper", "suggestion"; chord `Chord(.character("g"))`; in the `ShortcutGroup` that holds page commands.
2. Its symbol (`character.cursor.ibeam`) in `App/Sources/Menus.swift:111-151` and `Mac/Sources/CommandBar.swift:196-232`.
3. Mac: in `BrowserCommands` (`Mac/Sources/Menus.swift`), an item with `.keyboardShortcut("g", modifiers: [.control, .option])`, disabled unless the panel shows a suggestion; `WindowModel.perform` (`:886-920`) applies the first suggestion; `keys(for:)` (`:930-955`) returns its keys.
4. iPad: in `Browser.perform` (`App/Sources/Browser.swift:2064-2126`), the case does nothing until task 04, with a comment saying so; `Device.offers` (`App/Sources/Menus.swift:58-67`) returns false for it until then, so it is never shown there.

### B6. A site's switch

In `PageActions` (`Mac/Sources/PageActions.swift`), a row "Check Grammar on This Site" with a check mark, shown only while `writing` is on: it adds or removes the page's host (`Hosts.normal`) in `writingOffSites`. Not a command: no key.

### B7. macOS's spell check

WebKit's continuous spell checking draws its own red underlines. While `writing` is on:

1. Find how eGlu's web views can have it off: try `NSApp.sendAction(Selector(("toggleContinuousSpellChecking:")), to: view, from: nil)` when `view.responds(to: Selector(("isContinuousSpellCheckingEnabled")))` and that reports true; WebKit keeps it in the app's defaults (`WebContinuousSpellCheckingEnabled`), so one change covers every page.
2. Remember what it was before (a `UserDefaults` key of eGlu's), and put it back when `writing` is turned off.
3. If neither works, leave it, and say so in the hand-back with what was tried.

## Tests

- **PadCore** (`cd PadCore && swift test`): preferences; `WritingSites`; `CommandTests` with the new command.
- **The script in a browser**: `Tests/writing.html` and `Tests/writing.mjs`, run by Playwright in WebKit (and Chromium) as `Tests/bridge.mjs` is. `writing.html` loads `writing.js` with a stand-in `window.webkit.messageHandlers.egluWriting.postMessage` that answers set lints. Cases:
  - checkable: a `textarea`, an `input`, a `contenteditable` yes; a password field, `spellcheck="false"` on a parent, a field in `.cm-editor`, a read-only field no;
  - the text of a `contenteditable` with `<b>`, `<br>`, two `<p>` and an emoji, and `rangeFor` of a lint after the emoji covering the right word;
  - one rectangle per lint on a single line; two for a lint across a line break in a narrow `textarea`;
  - `apply` replaces the word, fires `input`, and `document.execCommand("undo")` brings the word back;
  - `apply` with an `expected` that no longer matches changes nothing;
  - an answer for an older sequence number is dropped.
- **The Mac** (by hand, `Validation/CHECKLIST.md`, a new section "Grammar in pages (Mac)"): Gmail's compose box, a Slack message, a Notion page, a Linear issue's description, a GitHub comment, a plain `textarea` on a test page: underlines, the panel at the word, a suggestion applied and undone with ⌘Z, ⌃⌥G, Add to Dictionary, Turn Off This Rule, a site turned off from the page's menu. Nothing on `accounts.google.com`, a PDF, Google Docs, a password field. Korean text not underlined. The panel at the right place with the page zoomed and on a second display.

## Done when

- [ ] Both pull requests merged; every test above passes; no new warnings.
- [ ] Off by default; on, it checks the fields of Decided 1 and nothing else.
- [ ] The CHECKLIST section run once on a Mac, its results written under it.
- [ ] CHANGELOG, under `### Added`: "On the Mac, eGlu can check the English you type in pages, with Harper, on your Mac: problems are underlined, and a suggestion beside the word fixes it (⌃⌥G takes the first). Turn it on in Settings › Writing."
- [ ] README: a short section under Features, "Grammar checking on the Mac", in the README's style, and the shortcut in the Keyboard shortcuts table.

## Out of scope

- Other apps (task 03), the iPad and iPhone (task 04), onboarding (task 05).
- Frames, and editors that draw their own text.
- Harper Desktop's Clarity suggestions, its editor window and its onboarding.
