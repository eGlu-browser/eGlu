# Task 02: Grammar checking in pages, on the Mac

| | |
|---|---|
| Needs first | Task 01 (the `Engines` package with `Grammar`) merged |
| Unblocks | 03 (other apps), 04 (iPad and iPhone), 05 (onboarding) |
| Size | L (one to two months) |
| Platform | Mac (the script is written for iOS too: task 04 uses it as it is) |
| Pull requests | Two: (A) preferences, the checker, the dictionary, Settings › Writing; (B) the page script: underlines, the card, applying, and its wiring |

## Goal

In eGlu for Mac, with grammar checking turned on, English typed in a page's text fields is checked as it is typed, by Harper, on the Mac. Problems are underlined **by WebKit itself, on the page's own text**, so the underlines never drift from the words as the page scrolls, wraps, zooms or changes. A card in the page, next to the word, offers the suggestions, as Harper's and Grammarly's browser extensions do; choosing one fixes the text so that the page's own Undo undoes it. ⌃⌥G accepts the first suggestion. Settings › Writing turns it on and holds the dialect, the rules, the personal dictionary and the sites where it is off. It is off until the person turns it on (task 05 asks at onboarding).

Harper Desktop draws its underlines in windows of its own above other apps, which can fall out of step with the text. Inside eGlu's pages there is no need: the page can draw them. (Task 03, for other apps, has no page to draw in and keeps windows.)

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

### Harper's own browser code: what to port

Harper's Chrome and Firefox extension draws in the page through `packages/lint-framework` ([harperSwift](https://github.com/taehee-pd/harperSwift)'s copy, Apache-2.0, about 3,500 lines of TypeScript in `packages/lint-framework/src/lint/`). It depends on npm packages (`virtual-dom`, Font Awesome, `colorjs.io`) and a build step, which eGlu does not take: **port its approach into plain JavaScript in eGlu's style, without its dependencies**, crediting it in a comment at the top of `writing.js`: `// Its approach and several parts follow Harper's lint-framework (Apache-2.0).`

| File | What it does | For eGlu |
|---|---|---|
| `Highlights.ts` | For text the page holds as DOM (`contenteditable`), registers ranges with the **CSS Custom Highlight API**: `CSS.highlights.set("harper-<kind>", new Highlight(...ranges))`, and one `<style>` per kind: `::highlight(harper-<kind>) { text-decoration: underline <colour> solid 2px; background-color: <colour>22 }` (`:43-60`, `:66-90`). WebKit paints these on the text itself. Otherwise draws boxes in a shadow root (`:92-224`), attached to the editor's "render target" (`computeRenderTarget`, `:228-262`). `supportsCustomHighlights()` (`:323-365`) probes the API | Port both paths; the probe without its webdriver test |
| `RenderBox.ts` | A `harper-render-box` element with a shadow root, put back if the editor removes it | Port without `virtual-dom`: build the boxes with `document.createElement` and reuse them |
| `TextFieldRange.ts` | A `Range` for `textarea` and `input`: a hidden mirror `div` with the field's text-layout styles (`:65-84`), placed over the field in document coordinates (`:124-137`), its text and scroll kept as the field's; its ranges give the rectangles, kept only where they overlap the field (`:155-178`) | Port |
| `computeLintBoxes/index.ts` | Lints to ranges and boxes; and **applying a suggestion per editor** (`replaceValue`, `:120-343`): form fields, Lexical, Draft, CodeMirror, Slate and CKEditor, any other `contenteditable` | Port the boxes; port applying as Decided 10 says |
| `editorUtils.ts` | Finds each editor's root: Draft `.public-DraftEditor-content`, ProseMirror `.ProseMirror`, CodeMirror `.cm-editor`, Slate `[data-slate-editor="true"]`, Lexical `[data-lexical-editor="true"]`, CKEditor `.ck-editor__editable`, Quill `.ql-container`, Gutenberg, Trix, Medium, P2, Shreddit, Notion (`:17-119`); the caret's position (`:121-159`) | Port the ones Decided 10 uses |
| `spanMapping.ts` | Moves lints over one edit made since they were computed (the common start and end of the old and new text), so underlines stay on their words between typing and the next lint; lints the edit touches are dropped | Port |
| `PopupHandler.ts` | Opens the card on a pointer down inside a lint's box (`onPointerDown`, about `:115-140`), or by a key; its host is a render box made a `popover="manual"` (the top layer) | Port the opening; not the activation key |
| `SuggestionBox.ts` | The card: suggestions, the message, actions; placed under the word, clamped to the viewport, above the word when there is no room below (`:84-99`); saves and restores the caret if the card takes the focus (`:14-60`) | Port the behaviour; the look is HarperPopup's (next section) |
| `lintKindColor.ts` | A colour for each kind of lint | Take as it is |
| `LintFramework.ts` | Events that cause a new render: on the field `focus`, `keyup`, `keydown`, `paste`, `change`, `scroll`, `input`; on the window `resize`, `scroll`, `keyup`, `keydown`, `input`, `compositionend`, `selectionchange` (`:33-42`); every scrolling ancestor's `scroll`; a render at most once a frame; a check every second for editors that miss events (`:96-103`) | Port |

### Harper Desktop's look, for the card

harperSwift's `harper-desktop/macos-popup/Sources/HarperPopup/PopupView.swift` (SwiftUI) and `PopupPanel.swift` (`PopupChrome`, `:42-92`: Liquid Glass, corner radius 16): a card 320 points wide with the kind's colour, the message, the suggestions as buttons, and Ignore, Add to Dictionary and Turn Off This Rule. eGlu's card is HTML and CSS in the page; make it look like this one. Its Settings lists (`Settings/SettingsLists.swift`: rules and the dictionary) are SwiftUI, and Settings › Writing reuses them (pull request A).

### eGlu's page code (Mac)

- **Scripts go in** in `Page.prepare(for:)` (`Mac/Sources/Page.swift:427-455`), for main-frame navigations (`:908-909`) and from `settingsChanged()` (`:468-470`). It rebuilds only when a stamp string changes (`installed`/`wanted`, `:105-106`, `:434-437`): **a new script must add what it depends on to the stamp**, or it is not put in again when that changes. It removes all scripts (`:438`), stops on a hands-off host (`:439`), and adds `PasswordWatch.script` at document end in `Page.world` (`:440-443`), the picture script, the filter scripts, the store script (`:451-454`). Every user script is main frame only.
- **PDFs are not skipped** by `prepare`: check `mimeType` (`Page.swift:111`, set at `:951`) yourself.
- **`Page.world`** is `WKContentWorld.world(name: "eGlu")` (`Page.swift:92`): eGlu's scripts share the page's DOM but not its JavaScript objects.
- **Message handlers**: `StoreButton` and `PasswordWatch` are registered in `setUp` with `controller.add(Handler(page: self), contentWorld: Page.world, name: Handler.name)` (`Page.swift:288-292`), never on extension pages. `PasswordWatch.swift` is the pattern: its script as a string in its own file (`:19-41`), its handler checking main frame and world (`:49-55`). No handler with replies exists yet: this task adds the first `WKScriptMessageHandlerWithReply`, registered with `controller.addScriptMessageHandler(_:contentWorld:name:)`.
- **PolicyTests is a text search.** In `App/`, `Mac/` and `Shared/`, the words `evaluateJavaScript`, `callAsyncJavaScript` and `addUserScript` may appear only in `Page.swift`, `PageShared.swift` and three named files (`ScriptAndPolicyTests.swift:197-248`), **comments included**. So every call into a page is a method in `Mac/Sources/Page.swift`, which checks `HandsOff.covers` first, and other code calls that method.
- **Scripts as files**: `PadCore/Sources/PadCore/Scripts/*.js`, loaded by `public static let x = load("x", "js")` in `Scripts.swift` (pattern at `:64-68`, `:104`; `load` at `:118-123`). `PadCore/Package.swift:21` copies the folder, so a new file ships by itself. `isolated()` (`:114-116`) wraps a script in try and catch.

### Preferences, Settings, commands (Mac)

- **Preferences** (`PadCore/Sources/PadCore/Preferences.swift`): one `Codable` struct saved as JSON in `UserDefaults` under `"preferences"` (`:207-213`). A new one takes three edits: a `var` with its default (`:23-102`), a `CodingKeys` case (`:128-143`), a decode line `(try? c.decodeIfPresent(...)) ?? default` (`:145-174`). A change saves, calls `settingsChanged()` on every live page (`Shared/SessionPreferences.swift:8-21`), and applies `Preferences.Changes` (`Preferences.swift:217-239`). Tests: `PreferencesTests` (`ScriptAndPolicyTests.swift:4-79`). Preferences stay on the device; they are not synced.
- **Mac Settings** (`Mac/Sources/SettingsView.swift`): `SettingsPane` (`:100-136`: general, iCloud, spaces, pinned, blocking, extensions, each with title, symbol and tint); the detail switch (`:40-47`); a pane is a `private struct XSettings: View { Form { Section { … } header: { … } footer: { … } } }` bound to `$session.preferences.x` (as at `:212`); `Note` for footers (`:622`).
- **Commands** (`PadCore/Sources/PadCore/Commands.swift`): `Command` (`:5-41`), `title` (`:43-79`), `keywords` (`:82-117`), `ShortcutGroup` (`:181-208`), `Shortcuts.chords` (`:211-245`). `CommandTests.swift` requires every command to have a ⌃⌥ chord unless reserved (`:6-13`), chords to be unambiguous, and each command to be in exactly one group (`:50-54`). A new command also needs its symbol in **both** `App/Sources/Menus.swift:111-151` and `Mac/Sources/CommandBar.swift:196-232`, and a case in **both** `perform` switches: `App/Sources/Browser.swift:2064-2126` and `Mac/Sources/WindowModel.swift:886-920`.
- **The Mac's keys are not read from `Shortcuts.chords`**: its menu bar is SwiftUI `BrowserCommands` (`Mac/Sources/Menus.swift:7-285`) with each `.keyboardShortcut` written out, and `WindowModel.keys(for:)` (`WindowModel.swift:930-955`) says which keys a command shows. ⌃⌥G is free.
- **The page's menu** is the `PageActions` popover (`Mac/Sources/PageActions.swift:12-102`): rows (`:42-60`, `:68-77`), `ActionRow(title, symbol:, keys:)` (`:159-194`).

## Decided

1. **Checked:** `textarea`; `input` of type `text`, `search` or none; the editing host of `contenteditable` (`true`, `""`, `plaintext-only`). **Never:** `input` of type password, email, url, tel, number; a field with `autocomplete` starting `cc-` or equal to `one-time-code`, `username`, `email`, `current-password`, `new-password`; a field that is read-only or disabled; anything with `spellcheck="false"` on it or an ancestor (it inherits); anything inside `.CodeMirror`, `.cm-editor`, `.monaco-editor`, `.ace_editor`; a hands-off host; a PDF or a picture; an extension's page; a frame (eGlu's scripts are main frame only).
2. **English only.** A paragraph whose language Apple's `NLLanguageRecognizer` says is not English (dominant hypothesis not English with probability at least 0.6, for 20 characters or more) is not sent. A paragraph is text between line breaks.
3. **When:** 300 ms after typing stops in a field, when a checked field gains focus, and once a second while it has focus if its text changed without an event (the 1-second check). Only the field with the focus is checked. Between typing and the next answer, lints are moved over the edit (`spanMapping`'s rule), so underlines stay on their words.
4. **Underlines in `contenteditable` are CSS Custom Highlights**: one `Highlight` per kind, registered as `eglu-<kind>` (lowercase); one `<style id="eglu-writing">` in the page's `<head>` with a `::highlight(eglu-<kind>)` rule per kind: `text-decoration: underline <colour> solid 2px; text-underline-offset: 3px; background-color: <colour>1f`. WebKit draws them on the text, so they need no positions and never drift. When the field loses focus, the ranges are cleared; when the script stops, the `<style>` is removed.
5. **Underlines in `textarea` and `input`** (whose text is not DOM): boxes from a mirror (`TextFieldRange`), drawn in a render host (an `eglu-writing` element with a closed shadow root) inside the field's nearest ancestor that is not editable, `position: absolute` in that ancestor's coordinates, so the page's and its containers' scrolling move them with the field in WebKit's own scrolling, with no JavaScript per frame. A box's `left` is `rect.left - container.left - container.clientLeft + container.scrollLeft` (and the same for `top`), divided by the container's scale (`getBoundingClientRect().width / offsetWidth`) where it is transformed. Boxes are placed again only on input, the field's own scroll, its size (`ResizeObserver`), `document.fonts.ready`, and the 1-second check.
6. **If highlights can't be used** (the probe says no, or the spike in step B0 shows WebKit does not paint highlights registered from `Page.world`): `contenteditable` uses boxes too, from `Range.getClientRects()`, placed as in Decided 5.
7. **The card is in the page**, as Harper's and Grammarly's are: an element with `popover="manual"` (WebKit's top layer: never clipped or covered by the page), inside the same closed shadow root as an invisible anchor box placed at the word (as Decided 5 places boxes). It is placed with **CSS anchor positioning**: the anchor box has `anchor-name: --eglu-word`, the card `position-anchor: --eglu-word; position-area: block-end span-inline-end; position-try-fallbacks: flip-block, flip-inline`, 6 pixels from the word. WebKit moves it with the word as the page scrolls. Where `CSS.supports("anchor-name: --a")` is false (iOS before 26, task 04), it is placed from the word's rectangle (`SuggestionBox`'s clamp) and placed again once a frame while the page scrolls.
8. **The card's look** is HarperPopup's (`PopupView.swift`): 320 pixels wide, corner radius 16, `backdrop-filter: blur(24px) saturate(180%)` over a translucent background (`rgb(255 255 255 / 0.72)`, dark `rgb(40 40 44 / 0.72)`), a hairline border (`rgb(0 0 0 / 0.08)`, dark `rgb(255 255 255 / 0.12)`), a soft shadow, `font: 13px/1.35 -apple-system, system-ui`, light or dark by `prefers-color-scheme`; a dot of the kind's colour and the kind's name; the message; up to five suggestions as buttons (the first filled); then Ignore, Add to Dictionary (spelling lints only), Turn Off This Rule. The host's styles are reset with `all: initial`, so the page's CSS can't reach it.
9. **The card never takes the focus.** `pointerdown` on it is `preventDefault`ed, so the field keeps its caret and selection; if the focus moves anyway, the caret is put back (`SuggestionBox`'s save and restore). It **opens** on a click or tap inside a lint's box (`PopupHandler`'s rule), or when the caret rests 150 ms inside a lint's range; it **closes** on Esc (only while it is open; the page does not get that Esc), a click outside it, typing, or the word leaving the screen.
10. **Applying a suggestion** checks first that the text in the lint's range is still what was linted (else lints again), then, by the editor the field belongs to:

| Field | How |
|---|---|
| `textarea`, `input` | focus, `setSelectionRange(start, end)`, `document.execCommand("insertText", false, text)`; if it returns false: the element's prototype `value` setter and an `input` event with `inputType: "insertReplacementText"` |
| Lexical (`[data-lexical-editor="true"]`) | `lint-framework`'s `replaceLexicalValue`: select, replace the text in the range, `input` event |
| Draft (`.public-DraftEditor-content`) | `replaceDraftValue`: `beforeinput` with `inputType: "insertText"`; if not prevented, replace; `input` |
| Slate (`[data-slate-editor="true"]`), CKEditor 5 (`.ck-editor__editable`) | `replaceRichTextEditorValue`: `beforeinput` with `inputType: "insertReplacementText"`, `data` and `targetRanges: [new StaticRange(range)]`; if not prevented, replace; `input` |
| ProseMirror, Quill, Notion, any other `contenteditable` | select the range; `document.execCommand("insertText", false, text)`, which keeps the page's Undo and reaches editors that listen to `beforeinput`; if it returns false, `replaceGenericContentEditable` |

11. **Keys:** ⌃⌥G, "Accept Writing Suggestion", applies the open card's first suggestion. Nothing else is taken from the page.
12. **The card's words** come from the app's String Catalog, given to the script in its configuration when it is put in (a JSON object at the top of the script's source). Harper's messages are English Markdown: shown as text, with only inline code and emphasis turned into `<code>` and `<em>` elements built with `createElement`, never `innerHTML`.
13. **The personal dictionary** is a file, `Application Support/Safience/Writing/dictionary.txt`, one word per line, sorted: Harper Desktop's format. Rules turned off and sites turned off are preferences.
14. **Ignore** hides that lint for as long as the app runs (`Grammar.ignore(context:)`); it is not saved.
15. **macOS's own spell check** is turned off in eGlu's pages while Harper checks them, so a word is not underlined twice, and put back as it was when Harper is turned off.
16. **What goes into the page's DOM**, and nothing else: the `<style id="eglu-writing">` in `<head>`; for text fields and the card, one `eglu-writing` element per field's container (closed shadow root, `pointer-events: none` except on the card); the mirror `div` for text fields, `visibility: hidden`, appended to `<body>`. All removed when the field loses focus for good or the script stops.

## Pull request A: preferences, the checker, the dictionary, Settings › Writing

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

And `WritingSites` (`PadCore/Sources/PadCore/WritingSites.swift`): `static func isOff(_ url: URL?, sites: [String]) -> Bool`, matching a host and its subdomains as `HandsOff.covers` does (`HandsOff.swift:17-33`, `Hosts.host(_:isWithin:)`), plus a built-in list where checking never runs because the text is drawn, not typed: `docs.google.com`. Tests for both.

### A2. The checker (Shared)

`Shared/Writing/WritingChecker.swift` (the iPad uses it too, task 04):

- `@MainActor final class WritingChecker` (one for the app), holding a `Grammar` when `preferences.writing` is on and nil otherwise.
- `func preferencesChanged(_ p: Preferences)`: builds or configures the `Grammar` from `GrammarSettings(dialect: Dialect(rawValue: p.writingDialect) ?? .american, rules: p.writingRules, words: WritingWords.load())`, then `warmUp()` in a task off the main actor. Call it where the session handles a preferences change (`Shared/SessionPreferences.swift`).
- `func lint(_ text: String) async -> [GrammarLint]`: splits into paragraphs at line breaks, skips those that are not English (Decided 2), lints the rest, shifts each lint's `start` and `end` by its paragraph's UTF-16 offset, and returns them sorted. On any `EngineError`, logs it (`os.Logger`, with the app's subsystem; never the text) and returns `[]`.
- `func addWord(_ word: String)`, `func ignore(_ lint: GrammarLint)`.

`Shared/Writing/WritingWords.swift`: `load() -> [String]`, `save(_:)`, `add(_:)`, `remove(_:)` for `dictionary.txt` (create the folder if needed; write atomically). And `harperDesktopWords() -> [String]?`, reading `~/Library/Application Support/harper-desktop/dictionary.txt` where it exists (`#if os(macOS)`).

### A3. Settings › Writing (Mac)

A new `SettingsPane.writing` (title "Writing", symbol `character.cursor.ibeam`, a tint like the others) and `WritingSettings: View`. Bring harperSwift's `Settings/SettingsLists.swift` (its rule list and dictionary list) into `Mac/Sources/Writing/`, first comment `// From harperSwift's harper-desktop/macos-popup (Apache-2.0), changed for eGlu.`, bound to eGlu's preferences and `WritingWords` instead of its JSON model.

| Section | Holds |
|---|---|
| (first) | Toggle "Check Grammar and Spelling in Pages" bound to `writing`. Footer: "English only. Harper checks it on this Mac; nothing you type is sent anywhere." |
| English | Picker of the five dialects, bound to `writingDialect` |
| Rules | `Grammar.rules()` by group, a toggle for each; a toggle writes to `writingRules` only when it differs from `isOnByDefault`, and removes the entry when put back. "Restore Defaults" empties `writingRules` |
| Dictionary | The words in `dictionary.txt`, with Add and Remove; "Add Harper Desktop's Words" only when `harperDesktopWords()` is not nil |
| Sites | `writingOffSites`, each with Remove; footer: "Turn checking off for a site from the page's menu." |

Sections other than the first are disabled while `writing` is off.

### A4. Pull request A done when

- [ ] PadCore tests pass with the new preferences and `WritingSites`.
- [ ] Settings › Writing shows, saves, and survives a relaunch; the rules list shows Harper's groups.

## Pull request B: the page script and its wiring

### B0. A spike first (half a day)

On a Mac, in a DEBUG build: in a test page with a `contenteditable`, run from `Page.world` (a temporary call in `Mac/Sources/Page.swift`) a script that registers a `Highlight` over one word and adds the `::highlight` `<style>`. Look:

- If WebKit paints it: Decided 4 holds.
- If not: Decided 6 applies (boxes for `contenteditable` too).

Do the same for anchor positioning: an anchor box and a `popover="manual"` card in one closed shadow root; scroll the page and a scrolling container, and see whether the card follows without script. If it does not, place it as Decided 7's fallback says. Write what you found in the pull request's description, and remove the temporary call.

### B1. `writing.js`

`PadCore/Sources/PadCore/Scripts/writing.js`, loaded as `Scripts.writing`, run in `Page.world`, plain JavaScript in the style of `bridge.js` and `markdown.js` (read them first), wrapped as `isolated()` does. Its first line: its configuration (Decided 12), filled in by Swift: `const config = /*__EGLU_WRITING__*/{};` with the card's words and the kind colours.

Parts, in this order in the file:

1. **Colours** from `lintKindColor.ts`, keyed by `GrammarLint.kind`.
2. **Which field:** `checkable(element)` by Decided 1; for `contenteditable`, the editing host (the nearest element whose `isContentEditable` is true and whose parent's is not). Which editor it belongs to (Decided 10's selectors).
3. **Text and offsets.** `textarea`/`input`: `value`. `contenteditable`: walk the host's nodes in order, appending text nodes' data, `"\n"` for `<br>` and at the end of each block element (computed `display` block, list-item or table-row), and record each text node's start; `rangeFor(start, end)` turns UTF-16 offsets back into a `Range`.
4. **Edits between lints:** `spanMapping`'s single-edit rule (common start and end of the old and new text) moves the current lints, dropping those the edit touches.
5. **Checking:** Decided 3. `const seq = ++sent; const lints = await window.webkit.messageHandlers.egluWriting.postMessage({ kind: "lint", text })`; drop the answer if `seq !== sent` or the text changed meanwhile (then map it over the edit, or ask again).
6. **Highlights** (Decided 4 and 6): the probe (`supportsCustomHighlights`, without the webdriver test); one `Highlight` per kind in `CSS.highlights`; the `<style id="eglu-writing">`.
7. **Boxes** (Decided 5): the mirror (`TextFieldRange`), the render host and its absolute boxes, placed again only on the events listed there.
8. **The card** (Decided 7 to 9): built once per field container, in the render host's shadow root, with its anchor box; its content made with `createElement`; `pointerdown` prevented; the open and close rules; `showPopover()` and `hidePopover()`.
9. **Events** (`LintFramework`'s lists, Decided 3's 1-second check), all with `{ capture: true, passive: true }` except the card's own.
10. **Applying** (Decided 10), as `apply(index, suggestionIndex)` from the card and `acceptFirst()` from Swift; then lint again.
11. **Actions** posted to the app: `{ kind: "ignore", context }`, `{ kind: "addWord", word }`, `{ kind: "disableRule", rule }`; then the lints for the field are dropped and asked again.
12. **Stopping:** `stop()` removes everything Decided 16 lists.

### B2. In `Mac/Sources/Page.swift`

1. In `prepare(for:)`, after the password watch: add `Scripts.writing` (with `/*__EGLU_WRITING__*/{}` replaced by the configuration's JSON) at document end, in `Page.world`, main frame only, when all hold: `preferences.writing`, not an extension page, not `WritingSites.isOff(url, sites:)`, and `mimeType` neither `application/pdf` nor `image/*`. Add these to the stamp (`wanted`).
2. In `setUp`, beside `StoreButton` and `PasswordWatch` (`:288-292`), not on extension pages: `controller.addScriptMessageHandler(WritingHandler(page: self), contentWorld: Page.world, name: WritingHandler.name)`.
3. `func writingAcceptFirst() async -> Bool` and `func writingStop()`: check `HandsOff.covers(view.url)` and `HandsOff.covers(committed)` first, then `callAsyncJavaScript` in `Page.world`.
4. `writingStop()` when the page navigates or `writing` is turned off.

### B3. `WritingHandler` (Mac)

`Mac/Sources/Writing/WritingHandler.swift`: `NSObject, WKScriptMessageHandlerWithReply`, `static let name = "egluWriting"`, a weak page. In `userContentController(_:didReceive:replyHandler:)` (nonisolated, then onto the main actor as `StoreButton.swift:24-39` does):

- Accept only `message.frameInfo.isMainFrame`, `message.world == Page.world`, a page that is not hands-off, and `writing` on; else reply `nil`.
- `lint`: reply with `checker.lint(text)` as an array of plain dictionaries: `start`, `end`, `kind`, `rule`, `message`, `context`, `suggestions` (each `{ replace }`, `{ insert }` or `{ remove: true }`), `word` (the text in the range).
- `ignore`: `checker.ignore`; `addWord`: `checker.addWord`; `disableRule`: `writingRules[rule] = false`; reply `true`.
- `opened` and `closed` (the script tells when its card opens and closes), so ⌃⌥G is enabled only while a card is open.

### B4. ⌃⌥G

1. `Command.acceptWritingSuggestion` in `Commands.swift`: title "Accept Writing Suggestion", keywords "grammar", "spelling", "harper", "suggestion"; chord `Chord(.character("g"))`; in the `ShortcutGroup` that holds page commands.
2. Its symbol (`character.cursor.ibeam`) in `App/Sources/Menus.swift:111-151` and `Mac/Sources/CommandBar.swift:196-232`.
3. Mac: in `BrowserCommands` (`Mac/Sources/Menus.swift`), an item with `.keyboardShortcut("g", modifiers: [.control, .option])`, disabled unless the page's card is open; `WindowModel.perform` (`:886-920`) calls `page.writingAcceptFirst()`; `keys(for:)` (`:930-955`) returns its keys.
4. iOS: in `Browser.perform` (`App/Sources/Browser.swift:2064-2126`), the case does nothing until task 04, with a comment saying why; `Device.offers` (`App/Sources/Menus.swift:58-67`) returns false for it until then.

### B5. A site's switch

In `PageActions` (`Mac/Sources/PageActions.swift`), a row "Check Grammar on This Site" with a check mark, shown only while `writing` is on: it adds or removes the page's host (`Hosts.normal`) in `writingOffSites`. Not a command: no key.

### B6. macOS's spell check

WebKit's continuous spell checking draws its own red underlines. While `writing` is on:

1. Try `NSApp.sendAction(Selector(("toggleContinuousSpellChecking:")), to: view, from: nil)` when `view.responds(to: Selector(("isContinuousSpellCheckingEnabled")))` and that reports true; WebKit keeps it in the app's defaults (`WebContinuousSpellCheckingEnabled`), so one change covers every page.
2. Remember what it was before (a `UserDefaults` key of eGlu's), and put it back when `writing` is turned off.
3. If neither works, leave it, and say so in the hand-back with what was tried.

## Tests

- **PadCore** (`cd PadCore && swift test`): preferences; `WritingSites`; `CommandTests` with the new command.
- **The script in a browser**: `Tests/writing.html` and `Tests/writing.mjs`, run by Playwright in WebKit (and Chromium) as `Tests/bridge.mjs` is. `writing.html` loads `writing.js` with a stand-in `window.webkit.messageHandlers.egluWriting.postMessage` that answers set lints. Cases:
  - `checkable`: a `textarea`, an `input`, a `contenteditable` yes; a password field, `spellcheck="false"` on a parent, a field in `.cm-editor`, a read-only field no.
  - Text of a `contenteditable` with `<b>`, `<br>`, two `<p>` and an emoji; `rangeFor` of a lint after the emoji covers the right word.
  - Highlights: after a lint answer, `CSS.highlights.get("eglu-spelling")` holds one range over the word; after blur, none.
  - Boxes in a `textarea` inside a scrolling `div`: the box's `getBoundingClientRect()` minus the field's is the same before and after scrolling the page and the `div`, with no script run in between (spy on `requestAnimationFrame`).
  - The card: a click in a lint's box opens it below the word; near the viewport's bottom, above; `document.activeElement` is still the field after a `pointerdown` on a suggestion; Esc closes it and the page's own `keydown` listener does not see that Esc.
  - Applying: a `textarea` (and `execCommand("undo")` brings the word back); a generic `contenteditable` (undo too); a stand-in Slate editor (`data-slate-editor`, handling `beforeinput` and preventing it) receives `insertReplacementText` with the right `targetRanges`; a stand-in Draft editor gets `insertText`.
  - A lint whose range changed is not applied; typing before a lint keeps its highlight on the word (the edit mapping).
  - An answer for an older sequence number is dropped.
- **The Mac** (by hand, `Validation/CHECKLIST.md`, a new section "Grammar in pages (Mac)"): Gmail's compose box, a Slack message, a Notion page, a Linear issue's description, a GitHub comment, a plain `textarea`: underlines on the words while scrolling quickly, while a long paragraph rewraps, and with the page zoomed (⌘+); the card at the word, following it as the page scrolls; a suggestion applied and undone with ⌘Z; ⌃⌥G; Add to Dictionary; Turn Off This Rule; a site turned off from the page's menu. Nothing on `accounts.google.com`, a PDF, Google Docs, a password field. Korean text not underlined. Dark mode: the card in dark.

## Done when

- [ ] Both pull requests merged; every test above passes; no new warnings.
- [ ] Off by default; on, it checks the fields of Decided 1 and nothing else, and adds to the page only what Decided 16 lists.
- [ ] The CHECKLIST section run once on a Mac, its results written under it.
- [ ] CHANGELOG, under `### Added`: "On the Mac, eGlu can check the English you type in pages, with Harper, on your Mac: problems are underlined on the words, and a card beside the word fixes them (⌃⌥G takes the first suggestion). Turn it on in Settings › Writing."
- [ ] README: a short section under Features, "Grammar checking", in the README's style, and the shortcut in the Keyboard shortcuts table. README › Credits: Harper's lint-framework and harperSwift's settings lists, Apache-2.0.

## Out of scope

- Other apps (task 03, which keeps windows over the apps), the iPad and iPhone (task 04), onboarding (task 05).
- Frames, and editors that draw their own text.
- Harper Desktop's Clarity suggestions, its editor window and its onboarding.
