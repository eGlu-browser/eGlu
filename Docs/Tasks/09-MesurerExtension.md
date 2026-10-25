# Task 09: Mesurer's Chrome extension, tried and fixed

| | |
|---|---|
| Needs first | Nothing |
| Size | S (up to a week) |
| Platform | Mac only (iPhone and iPad have no extensions) |
| Pull requests | One |

## Goal

Mesurer, a Chrome extension for measuring a page's layout, installs from the Chrome Web Store into eGlu for Mac and works there as far as WebKit allows. Whatever does not work is said in its row in eGlu's words, and a shim makes it work where a shim can. What was found is written down, so eGlu can list Mesurer as tried.

This is not task 10 (eGlu's own measuring tool, built in). Here eGlu ships nothing of Mesurer's: the person installs it, as any extension.

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

## Mesurer

- [ibelick/mesurer](https://github.com/ibelick/mesurer), by Julien Thibeaut, MIT. Its page says: "Inspect, annotate, and give feedback on any live interface."
- Features: click an element to measure its bounds; hold Option (Alt) for distances to other elements; gaps and padding; column, row and pixel grid guides; rulers along the top and left; arrows, freehand strokes and text notes; typography inspection; colour sampling; X-ray of the page's structure; screenshots of a region; video recordings up to 60 seconds; the page at several screen sizes; comments pinned to elements, copied as structured feedback for an agent; undo and redo; its state kept between visits.
- Its README says colour sampling needs a Chromium browser (it uses `EyeDropper`, a web API WebKit does not have) and that video capture works best with the extension.
- Chrome Web Store id: `icmjafcffhpcnadkmmklegommbcekcac` (version 0.0.8 on 2026-04-16; take the current one).

## What exists in eGlu

### Installing from the store

- On `chromewebstore.google.com`, `Scripts.extensionStore` (`PadCore/Sources/PadCore/Scripts/extension-store.js`) puts an "Add to eGlu" button on the page, in eGlu's own world (`Mac/Sources/Page.swift:451-453`; its handler `egluStore` is registered at `Page.swift:288-289`).
- `Mac/Sources/StoreButton.swift:24-39` takes the click and calls `Extensions.shared.add(fromStorePage:in:space:)` (`Mac/Sources/Extensions.swift:1086-1089`), then `add(storeID:)` (`:1094-1108`): download (`:1139-1152`), `CRXFile.archive(of:id:fromStore: true)` checks Google's signature (`PadCore/Sources/PadCore/CRXFile.swift:156-174`), and `offer(...)` (`Extensions.swift:1156-1227`) shows the install sheet.
- `keep(...)` (`Extensions.swift:1231-1279`) writes the package to `Extensions/<id>/<version>.zip` in `Application Support/Safience`, and `load` (`:395-455`) prepares a copy with the shim and starts it. Each extension's context is inspectable (`:424`): Safari › Develop › eGlu reaches its worker and pages.

### Launch arguments for testing (DEBUG builds only, `Extensions.swift:1605-1769`)

| Argument | Does |
|---|---|
| `-installFromStore icmjafcffhpcnadkmmklegommbcekcac` | Downloads it from the store and installs it without the sheet, 3 seconds after launch |
| `-extensionSpaces 1` | Makes a "Test 1" space |
| `-extensionPages url,url` | Opens each page in each space |
| `-extensionWait` | Waits at least 11 seconds before the report |
| `-extensionReport /path/out.txt` | Writes what was found: installed, incompatible, the namespaces WebKit answers, and per space the verdict, its lines, the errors (`report()`, `:1734-1767`); progress in `out.txt.steps` |

### How eGlu tells whether an extension works

- **At install** (`firstLook`, `Extensions.swift:537-566`): what the manifest asks for that this Mac's WebKit does not answer (`missing(for:)`, `:572-582`, from `ExtensionAPITable`, `PadCore/Sources/PadCore/ExtensionManifest.swift:248-348`), and what its code uses that nothing answers (`ExtensionScan.uses`, `PadCore/Sources/PadCore/ExtensionScan.swift:1-49`).
- **In its first seconds**: its worker has 5 seconds to start (`Extensions.swift:741-760`); WebKit's errors for it are read (`errorsChanged`, `:796-827`, with `ExtensionError.problem`, `PadCore/Sources/PadCore/ExtensionCheck.swift:41-46, 74-106`).
- **On a copy, in a space that keeps nothing** (`Mac/Sources/ExtensionTrial.swift`): its popup and options page are opened for 5 seconds each, on `https://test.eglu.invalid/` (`:95-169`), 2 seconds after it loads (`checkCopy`, `Extensions.swift:658-712`).
- **The verdict** (`ExtensionVerdict`, `ExtensionCheck.swift:210-326`): Checking…, Started Fine, Some Features Don't Work, Couldn't Start, Not Checked Yet, Works, Doesn't Work; its lines say "Can't %@.", "May not work: %@." with words for each API (`:286-313`; tab capture is "record a tab", `:289`).
- **Records** of what failed, where and how often: `Extensions/records.json` (`PadCore/Sources/PadCore/ExtensionRecords.swift:10-119`). **Report a Problem…** shows them as text to copy (`Mac/Sources/ExtensionReport.swift:13-95`).
- **Works** is said only for an extension in `ExtensionTried.shipped` (`ExtensionRecords.swift:156`, empty today; an entry's fields are at `:126-146`: id, from and through version, works, the eGlu release, and what was tried).

Two gaps the research found, which this task fixes where Mesurer needs it:

1. **A missing web API is not noticed.** The error parser knows "Can't find variable:" only for `chrome` and `browser` (`ExtensionCheck.swift:96-98`), and `problem()` keeps only Chrome API paths (`:44`). So `EyeDropper` missing would say nothing.
2. **Content scripts get few shims.** `extension-shim.js` stops for content scripts at `:1005-1043`; what is defined after it (`define`, `sidePanel`) is the worker's and pages' only. A content script reaches a native answer through the worker relay `__egluCall` (`:756-774`), as `i18n.detectLanguage` does (`:987-1003`).

### How a shim is added (copy `i18n.detectLanguage`, the latest complete one)

1. JavaScript, in `PadCore/Sources/PadCore/Scripts/extension-shim.js`: a whole namespace with `define("ns", [methods], [events])` (`:1152`), one member with `put(...)` (`:102`). For content scripts, a branch in the `__egluCall` relay (`:756-774`).
2. Swift: a `case "ns.method":` in `Extensions.answer` (`Mac/Sources/ExtensionAnswers.swift:17-191`). It replies `{"value": …}` or `{"error": …}` (`Extensions.swift:1895-1913`).
3. The path in `ExtensionAPITable.shims` (`ExtensionManifest.swift:270-278`), or the checks keep calling it missing.
4. Words for the person in `ExtensionVerdict.features` (`ExtensionCheck.swift:286-313`), if new.
5. Tests: `node Tests/extension-shim.mjs` (the detectLanguage cases at `:93-122` are the pattern) and `PadCore/Tests/PadCoreTests/Extension*Tests.swift`.
6. A changed shim changes its stamp (`PadCore/Sources/PadCore/ExtensionPreparation.swift:308-317`), which prepares every extension again and drops the cached checks: expected, nothing to do.

## Decided

- eGlu does not ship or preinstall Mesurer. It is installed by the person, from the store.
- No shim is added for something WebKit can't do at all (recording a tab with `tabCapture`): the row says it can't, and that is the answer.
- A colour picker stand-in is added only if Mesurer calls `EyeDropper` from a place a shim can reach, and only with AppKit's own picker (`NSColorSampler`), so the rule on dependencies holds.
- Nothing about Mesurer goes in `Adapters.swift`: it is an extension, not a site.

## Steps

### 1. Install it and get the first report (half a day)

1. Build eGlu Mac (Debug) in Xcode.
2. Run it once by hand: open `https://chromewebstore.google.com/detail/icmjafcffhpcnadkmmklegommbcekcac`, press Add to eGlu, and read the install sheet: write down its Capabilities and Sites requested.
3. Run it again with launch arguments (Product › Scheme › Edit Scheme › Arguments), in a fresh test space:
   ```
   -installFromStore icmjafcffhpcnadkmmklegommbcekcac -extensionSpaces 1
   -extensionPages https://example.com -extensionWait -extensionReport /tmp/mesurer.txt
   ```
4. Keep `/tmp/mesurer.txt` and `/tmp/mesurer.txt.steps`.

### 2. Read the package (half a day)

1. Unzip `~/Library/Application Support/Safience/Extensions/icmjafcffhpcnadkmmklegommbcekcac/<version>.zip` into a new, empty folder in `/tmp` (it is untrusted: read it, don't run anything from it).
2. From `manifest.json`, note: `permissions`, `optional_permissions`, `host_permissions`, `background`, `content_scripts`, `action`, `side_panel`, `commands`, `web_accessible_resources`.
3. Search its scripts for, and note where each is used (worker, content script, popup, page):
   - `EyeDropper`, `chrome.tabs.captureVisibleTab`, `chrome.tabCapture`, `getDisplayMedia`, `MediaRecorder`, `chrome.offscreen`
   - `chrome.scripting.executeScript`, `chrome.storage`, `localStorage`
   - `chrome.sidePanel`, `chrome.commands`, `chrome.runtime.sendMessage`
4. Write the table: feature → API → where → what eGlu answers today (`ExtensionAPITable` and `ExtensionAnswers.swift`).

### 3. Try every feature (one day)

On `https://example.com`, a long article, and a web app (for example `https://linear.app` signed out), with Mesurer turned on from the puzzle button:

| Feature | How to try | Expected |
|---|---|---|
| Turning it on | Click its tile in the puzzle button | Its overlay or popup shows |
| Bounds | Inspect mode, click a heading | Its box and size |
| Distances | Hold Option over another element | Lines with distances |
| Gaps and padding | Click a flex container | Gap and padding shown |
| Guides and rulers | Guides mode | Grid guides; rulers top and left |
| Notes | Arrow, pen, text; move, resize, rotate | Drawn and editable |
| Typography | Click text | Font, size, weight, line height |
| Colour | Its colour tool | Fails today (`EyeDropper`) |
| X-ray | X-ray mode | The page's structure outlined |
| Screenshot | Capture a region | A picture saved or copied |
| Recording | Record 5 seconds | Probably fails (tab capture) |
| Screen sizes | Responsive preview | The page at several widths |
| Comments | Pin a comment, copy feedback | Text with element selectors |
| Undo, redo | ⌘Z, ⇧⌘Z while it is on | Its own undo |
| Kept state | Reload the page, open it again | Its settings stay |

For each, write: works, partly, or fails, with what Safari › Develop › eGlu › (Mesurer's worker or the page) shows in its console.

### 4. Make what can work, work (one to two days)

For each failure, in this order:

1. **A Chrome API eGlu could answer** (a missing one in `ExtensionAPITable` that a shim can stand in for): add a shim as in "How a shim is added".
2. **`EyeDropper`, if Mesurer calls it from a content script, its popup or a page:**
   - In `extension-shim.js`, where that context is set up (for content scripts, before the return at `:1005-1043`), define `globalThis.EyeDropper` only if it is missing: a class whose `open()` returns a promise for `{ sRGBHex: "#rrggbb" }`, reached through `__egluCall` (content scripts) or `native("eyeDropper.open", [])` (other contexts).
   - In `Mac/Sources/ExtensionAnswers.swift`, `case "eyeDropper.open":` shows `NSColorSampler().show { color in … }` on the main thread, converts the colour to sRGB and answers `"#rrggbb"`; when cancelled, answers the error `"AbortError"`, which the JavaScript turns into a rejected promise with a `DOMException` named `AbortError`, as Chrome's does.
   - Add `"EyeDropper"` to `ExtensionAPITable.shims` only if the table holds web APIs; otherwise leave the table and do step 3's scan change for it.
3. **A missing web API the checks don't notice**: in `ExtensionScan.uses` (`ExtensionScan.swift`), add `EyeDropper` (and nothing else not found in Mesurer) as a name that makes a "May not work: pick a colour from the screen" line, unless the shim answers it. Add its words to `ExtensionVerdict.features`.
4. **Tab capture and anything else WebKit can't do**: change nothing but making sure its row says so ("Can't record a tab."). If it does not, find why in the verdict and fix that.

Keep each change to what Mesurer needs.

### 5. Write it down (half a day)

1. A new file `Docs/ExtensionCompatibilityEvidence-<date>.md`, in the format of `Docs/ExtensionCompatibilityEvidence-2026-10-23.md`: the date and scope, "Findings and changes" (Finding | Change | Evidence), "Public package inspection" (Mesurer's store link and version | what the manifest asks | what was tried and its limits), "Validation" (the tests run, with counts).
2. If its main features work (bounds, distances, guides, notes), add it to `ExtensionTried.shipped` (`ExtensionRecords.swift:156`) with its id, the versions tried, `works: true` and a "what" naming what was tried; otherwise leave the list.
3. Update `Docs/ExtensionsDesign.md` section 4 (`:220-224`, what is expected of particular extensions) with a line for Mesurer.
4. A section in `Validation/CHECKLIST.md` with step 3's table as `- [ ]` items.
5. If a shim or a check changed: a line under `## Unreleased` › `### Added` or `### Fixed` in CHANGELOG.md, for example: "On the Mac, an extension that picks a colour from the screen (Mesurer) uses the Mac's own colour picker." Only if that is what was built.

## Tests

- `cd PadCore && swift test`: all pass, with new cases for any change to `ExtensionScan`, `ExtensionCheck` or `ExtensionAPITable`.
- `node Tests/extension-shim.mjs`: all pass, with new cases for an `EyeDropper` stand-in (open answers a colour; a cancel rejects with `AbortError`; an existing `EyeDropper` is left alone).
- The step 1 launch arguments run again after the changes: the report's verdict and lines are what step 3's table says.

## Done when

- [ ] Mesurer installs from the store's page with Add to eGlu.
- [ ] Step 3's table is filled for the current version, in the evidence file.
- [ ] Every feature that fails is said in its row in eGlu's words, or the evidence file says why it can't be.
- [ ] The colour picker works through the Mac's own, or the evidence file says why Mesurer's use of `EyeDropper` can't be reached.
- [ ] Tests pass; no new warnings.
- [ ] CHECKLIST section, and the CHANGELOG line if something changed for people.

## Out of scope

- Recording a tab: WebKit's extensions have no `tabCapture`.
- eGlu's own measuring tool: task 10.
- Mesurer on iPhone and iPad: no extensions there.
