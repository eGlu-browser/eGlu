# Task 04: Grammar checking in pages, on iPad and iPhone

| | |
|---|---|
| Needs first | Task 01 (`Engines`, with its iOS slices) and task 02 (the Mac's checking in pages) merged |
| Size | M (two to four weeks) |
| Platforms | iPad and iPhone |
| Pull requests | One |

## Goal

What task 02 built for the Mac, on iPad and iPhone: with grammar checking on, the English typed in a page's fields is checked by Harper on the device, underlined, and a card beside the word offers the suggestions. The same script (`writing.js`) and the same checker (`WritingChecker`) as on the Mac; an iOS card instead of the Mac's panel; Settings › Writing on iOS. Checking in other apps is not possible on iOS and is not part of this.

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

### From tasks 01 and 02

- `Engines.Grammar` with iOS slices (task 01).
- `PadCore/Sources/PadCore/Scripts/writing.js` (task 02): finds the field, extracts its text with UTF-16 offsets, asks `window.webkit.messageHandlers.egluWriting.postMessage({kind: "lint", text})` and awaits the lints, draws the underlines in a closed shadow root, posts `{kind: "caret", index, rect}` and `{kind: "away"}`, and has `apply({start, end, expected, text})` and `clear()`.
- `Shared/Writing/WritingChecker.swift` and `Shared/Writing/WritingWords.swift` (task 02), compiled by both apps.
- `Mac/Sources/Writing/WritingHandler.swift` (task 02): the Mac's message handler with replies. Read it: this task writes the iOS one the same way.
- `Mac/Sources/Writing/PopupView.swift` (task 02, from harperSwift): the SwiftUI card.
- Preferences `writing`, `writingDialect`, `writingRules`, `writingOffSites`, and `WritingSites` (PadCore).
- `Command.acceptWritingSuggestion` (⌃⌥G), which on iOS does nothing yet and is not offered (`Device.offers`, `App/Sources/Menus.swift:58-67`).

### eGlu's page code on iOS (`App/Sources/Page.swift`)

- `Page.world` is `WKContentWorld.world(name: "eGlu")` (`:55`).
- `prepare` (`:437-472`) adds `Scripts.ours` (the config, `bridge.js` and the site's adapter) at document start in `Page.world` (`:465-466`), `Scripts.page(for:)` in the page's world (`:467-470`), then the filter scripts (`:471`). It rebuilds only when its stamp changes (`:458-462`). It is called at `:1216`, `:1248`, after a redirect (`:1366`), from `reload(as:)` (`:603`) and from `settingsChanged` (`:505-520`).
- One message handler today, `Relay`, named `"eglu"` (`:265`, `:1174-1184`), which switches on `body["kind"]` in `received(_:)` (`:1121-1149`) and is removed at `:371`. It does not reply.
- Calls into the page go through the private `call(_:_:done:)` (`:630-640`), which refuses a hands-off page.
- `mimeType` (`:116`, set at `:1364-1368`).
- On a phone-width window the page is a mobile site with touch scrolling and pinch zoom; on a wide one, a desktop site with WebKit's scrolling off and the zoom held at 1 (`Docs/Requirements.md`). **Desktop View** on iPhone (`App/Sources/DesktopPad.swift`) lays the page out at an iPad's size and drives it with a cursor.
- `PolicyTests` (`ScriptAndPolicyTests.swift:197-248`): the words `evaluateJavaScript`, `callAsyncJavaScript`, `addUserScript` only in `Page.swift`, `PageShared.swift` and three named files, comments included.

### iOS Settings, keys

- `SettingsView` lists the offered `SettingsGroup`s (`App/Sources/SettingsView.swift:7-65`); `SettingsDetail` (`:67-406`) is a series of `if group == .x { Section { … } header: { SettingsHeader("…", .anchor) } }`; `SettingsHeader` (`:417-437`).
- `SettingsAnchor` (`PadCore/Sources/PadCore/SettingsAnchor.swift`): 16 cases with title, detail, keywords and `isOffered` (`:7-117`), `SettingsGroup` (`:121-155`), each anchor's group (`:157-169`). The command bar finds them (`App/Sources/Suggestions.swift:213-218`) and opens Settings there (`App/Sources/Browser.swift:2847-2850`, `2940-2952`).
- `SettingsRoutingTests.swift:22-26` expects exactly 6 groups offered with diagnostics off; `AutocompleteTests.swift:169-186` expects unique titles and a detail and keywords for each.
- Keys: `Menus.build` (`App/Sources/Menus.swift:166-208`) makes a `UIKeyCommand` for each command from its chord (`keyCommand`, `:264-268`); with `browserControlShortcuts` on, ⌃⌥ becomes ⌃ (`:155-161`, `:273`). `Browser.perform` (`App/Sources/Browser.swift:2064-2126`).

## Decided

1. **The same script and checker** as the Mac. The iOS part is the message handler, the card, Settings, and the key.
2. **Not in Desktop View** on iPhone: its page is scaled and driven by a cursor; the script is not added there.
3. **The card is a view over the page, not a presented popover.** A presented controller would take the first responder from the web view and put the keyboard away. The card is a SwiftUI `PopupView` in a `UIHostingController`'s view, added as a subview over the page's view; its buttons do not take the first responder, so the keyboard and the caret stay in the field.
4. **Where the card goes:** below the word's line, clear of the iOS text menu (which shows above a selection), and inside the part of the page the keyboard leaves visible (`keyboardLayoutGuide`); above the word when there is no room below.
5. **iOS's own spell check stays.** It is the system's and the keyboard's; eGlu can't turn it off for pages. Harper's spelling lints show as well.
6. **Settings › Writing on iOS** is the Mac's first four sections (on/off, English, Rules, Dictionary) and Sites, without "In Other Apps" and without Harper Desktop's words.
7. **⌃⌥G** with a hardware keyboard accepts the first suggestion while the card shows.

## Steps

### 1. The card's view in Shared

Move `PopupView.swift` (and the types it needs, such as `PopupData`, and the kind colours) from `Mac/Sources/Writing/` to `Shared/Writing/`, so both apps compile it: replace AppKit types (`NSColor`, `NSFont`) with SwiftUI's or `#if os(macOS)` where nothing else will do. The Mac's panel keeps hosting it. Build the Mac targets to check nothing changed there.

### 2. The message handler

`App/Sources/WritingHandler.swift`: `NSObject, WKScriptMessageHandlerWithReply`, `static let name = "egluWriting"`, as the Mac's. Same checks (main frame, `Page.world`, not hands-off, `writing` on), same kinds (`lint`, `caret`, `away`), calling the iOS card instead of the panel.

In `App/Sources/Page.swift`:

1. In `setUp`, beside `Relay` (`:265`): `configuration.userContentController.addScriptMessageHandler(WritingHandler(page: self), contentWorld: Page.world, name: WritingHandler.name)`; removed where `Relay` is (`:371`).
2. In `prepare` (`:437-472`): add `Scripts.writing` at document end, `Page.world`, main frame only, when `writing` is on, the host is not hands-off and not `WritingSites.isOff`, `mimeType` is not PDF or a picture, and the page is not in Desktop View. Add these to the stamp (`:458-462`).
3. `func writingApply(start:end:expected:text:) async -> Bool` and `func writingClear()`, through `call` or with the same hands-off checks.

### 3. The card

`App/Sources/WritingCard.swift`, main actor:

- `show(lint: GrammarLint, word: String, rect: CGRect /* CSS pixels of the viewport */, over page: Page, actions:)`, `hide()`.
- From CSS pixels to the page view's points: on a desktop-width page the zoom is held at 1, so CSS pixels are points from the web view's top-left; on a mobile page, multiply by the scroll view's `zoomScale` and subtract its `contentOffset`. Then convert from the web view to the view the card is added to.
- Add the hosting controller as a child of the `Browser` that shows the page, its view over the page's container; place it by Decided 4; hide it when the page scrolls the word out of view, on typing, on another tab, on rotation.
- Actions as on the Mac: Apply, Ignore, Add to Dictionary, Turn Off This Rule, Close.
- VoiceOver: the card is an accessibility element group; when it shows, post `UIAccessibility.post(notification: .layoutChanged, argument: card)` only if VoiceOver is on and the person moved there (do not take VoiceOver's focus while typing).

### 4. ⌃⌥G

- `Device.offers(.acceptWritingSuggestion)` true when `writing` is on.
- `Browser.perform(.acceptWritingSuggestion)`: apply the card's first suggestion, if a card shows; else nothing.
- `validate`/`canPerformAction` (`App/Sources/Browser.swift:1909-1928`) enable it only while a card with a suggestion shows.

### 5. Settings › Writing on iOS

- `SettingsAnchor.writing` (title "Writing", detail "Grammar and spelling as you type, in English", keywords "grammar", "spelling", "harper", "writing", "check") and a new `SettingsGroup.writing`, with its anchor's group; `isOffered` true.
- In `SettingsDetail`, a `group == .writing` block with Decided 6's sections, bound to the same preferences; the rule list from `Grammar.rules()`; the dictionary list from `WritingWords`.
- Update `SettingsRoutingTests.swift:22-26` to the new count of groups, and the other tests the new anchor touches.

### 6. Where the dictionary lives on iOS

`WritingWords` (task 02) writes `Application Support/Safience/Writing/dictionary.txt`. On iOS, put it in the same base folder as the app's other files (find where `workspace.json` and `history.sqlite` are written, and use that folder's `Writing/`). If task 02 wrote the Mac's path in a way that can't serve iOS, change `WritingWords` to take its folder from each app.

### 7. Memory

Harper runs in the app's process. With `writing` on, measure the app's memory on an iPhone before and after the first check (Xcode's memory gauge), and the time of `warmUp()`. Put both in the hand-back. If the app grows by more than 100 MB, stop and say so.

## Tests

- `cd PadCore && swift test`: the settings and command tests with the new anchor, group and command.
- `node Tests/bridge.mjs` and `Tests/writing.mjs` (task 02's) still pass.
- By hand, a new section in `Validation/CHECKLIST.md`, "Grammar in pages (iPad and iPhone)":
  - On an iPad with a keyboard and on an iPhone: Gmail's compose, a Slack message, a GitHub comment, a plain `textarea`: underlines in the right place; tapping into a flagged word shows the card below it without putting the keyboard away; a suggestion applied, and undone (⌘Z on the iPad's keyboard; shake or three-finger swipe on the iPhone as iOS offers).
  - The card above the keyboard on the iPhone, below the word, clear of the text menu.
  - ⌃⌥G on the iPad.
  - Nothing in Desktop View, on `accounts.google.com`, in a password field, on Google Docs.
  - Korean not underlined.

## Done when

- [ ] Merged; tests pass; no new warnings.
- [ ] The CHECKLIST section run once on an iPad and an iPhone, results written under it.
- [ ] CHANGELOG under `### Added`: "On iPhone and iPad, eGlu can check the English you type in pages too, with Harper, on the device. Turn it on in Settings › Writing."
- [ ] README's grammar section (task 02's) covers iPhone and iPad, and its Install table's "Gets" column is still right.

## Out of scope

- Other apps: not possible on iOS.
- Desktop View on iPhone.
- Harper Desktop's Clarity suggestions.
