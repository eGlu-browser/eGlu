# Task 10: eGlu's own measuring tool

| | |
|---|---|
| Needs first | Task 08 (developer mode: its bar, `element-pick.js`, element pictures, the toast) merged |
| Size | M (two to four weeks) |
| Platforms | Mac, iPad and iPhone |
| Pull requests | Two: (1) measuring, guides, rulers, colour; (2) notes on elements, copied for an assistant |

## Goal

A measuring tool built into eGlu, for designers and developers looking at a live page: an element's size, the distances to the elements round it, its padding, margin and gaps, its type and colours; column and row guides and rulers; a colour picked from anywhere on the page; and, later, notes pinned to elements, copied as plain text an assistant can act on. It is modelled on what [Mesurer](https://github.com/ibelick/mesurer) does (MIT), written anew for eGlu: Mesurer is a React component, and eGlu takes no npm packages. Turned on from developer mode's bar or with ⌃⌥M; Esc ends it.

Task 09 is about Mesurer's own Chrome extension on the Mac; this task is eGlu's tool, on every platform, with no extension.

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

### From task 08

- `Mac/Sources/DeveloperBar.swift` and iOS's bar: the place for a Measure button.
- `PadCore/Sources/PadCore/Scripts/element-pick.js`: an outline round the element under the pointer, in a closed shadow root with `pointer-events: none`, resolving on a click: read it first; this task's script grows from it.
- Each `Page.swift`'s `picture(of rect:)` (a rectangle of the page through `takeSnapshot(with:)`), and the toast (`Shared/ActionToast.swift`).

### eGlu's rules for scripts (see the context above)

- Scripts are files in `PadCore/Sources/PadCore/Scripts/`, loaded in `Scripts.swift` with `load(name, "js")`, run in `Page.world`.
- Calls into the page only in `Mac/Sources/Page.swift`, `App/Sources/Page.swift`, `Shared/PageShared.swift`, after `HandsOff.covers` (PolicyTests).
- Message handlers registered in each `Page.setUp` with `controller.add(Handler(page: self), contentWorld: Page.world, name: Handler.name)` (Mac `Page.swift:288-292`; iOS beside `Relay`, `App/Sources/Page.swift:265`), checking the main frame and `Page.world` (`Mac/Sources/PasswordWatch.swift:49-55`).

### Mesurer, for what to build

From its README: click elements to measure their bounds; hold Option for distances; layout details with gap and padding; column, row and pixel grid guides; rulers on the top and left; typography; colour sampling; X-ray of the page's structure; comments pinned to elements, copied as feedback for agents; keyboard shortcuts; its state kept between visits.

## Decided

1. **Script and native.** What is drawn on the page (boxes, distance lines, guides, rulers) is in a closed shadow root over the page; what is read (the selected element's details, settings, notes) is in a native panel: on the Mac at the window's bottom trailing corner, as the Handoff panel is (`Mac/Sources/BrowserView.swift:246-253`); on iOS a card at the bottom of the page.
2. **While it is on**, the page gets no clicks (they select), and Esc, ⌥ (held), G, R and X are the tool's. Nothing else is taken. It ends with Esc, the bar's button or ⌃⌥M.
3. **Units are CSS pixels**, as the page's own code counts them, whatever the page's zoom.
4. **Distances**: from the selected element to the element under the pointer with ⌥ held (Mac, iPad with a keyboard); on touch, the next element tapped.
5. **Colour**: on the Mac, AppKit's `NSColorSampler` (any pixel, the system's loupe); on iOS, the pixel under the finger from a 1-pixel `takeSnapshot`. Shown as hex and `rgb()`, copied on click.
6. **Settings kept** (preferences, not the site's storage): the column guide's count, gutter and margin, the row guide's height, whether rulers show.
7. **Notes** live with the tab and go when it navigates or closes. Nothing about them is saved.
8. **Command**: `Command.measure`, "Measure", ⌃⌥M, not moved by task 08's ⌥⌘ setting (⌥⌘M minimizes every window in macOS).

## Pull request 1: measuring, guides, rulers, colour

### 1.1 `measure.js`

`PadCore/Sources/PadCore/Scripts/measure.js`, started with `callAsyncJavaScript` in `Page.world` (it resolves when the tool ends). One overlay host under `document.documentElement` with a closed shadow root, `position: fixed; inset: 0; pointer-events: none; z-index: 2147483647`.

| Part | How |
|---|---|
| Hover | `mousemove` (capturing) and touch: the element under the point (`document.elementFromPoint`, skipping the overlay); its border box outlined, with its width and height in a label |
| Select | `click` (capturing, `preventDefault`, `stopPropagation`): the element selected; its margin (orange), border, padding (green) and content boxes drawn from `getComputedStyle`; for a flex or grid container, its gaps (purple) between children |
| Details | Posted to the app (1.2): tag, id, classes (first three), width and height, margin, padding, border widths, `display`, `gap`, font family (first), size, weight, line height, letter spacing, `color`, `background-color`, border radius |
| Distances | With ⌥ held (`keydown`/`keyup` of Alt) or on the next tap: lines from each side of the selected box to the nearest side of the other box, with the distance in pixels; if one contains the other, the four insets |
| Guides | G toggles. Columns: count, gutter and margin from the settings, drawn over the viewport's width; rows: lines every N pixels |
| Rulers | R toggles. Top and left, ticks every 10 pixels, numbers every 100, in viewport pixels from the page's left and top edge at the current scroll |
| X-ray | X toggles: every element's border box outlined thinly, so the structure shows |
| End | Esc, or `stop()` called from the app: remove everything, resolve |

Redraw at most once a frame on scroll (capturing), resize and DOM changes near the selection (a `MutationObserver` on the selected element's parent).

### 1.2 The app's side

- In each `Page.swift`: `startMeasuring() async` (hands-off checked), `stopMeasuring()`, and `sampleColour(at point:) async -> CGColor?` (iOS, 1-pixel snapshot).
- A message handler `MeasureHandler` (`egluMeasure`, no reply), registered with the others, taking `{kind: "details", …}`, `{kind: "distance", …}` and `{kind: "ended"}`.
- `Shared/Measure/MeasureModel.swift` (`@Observable`, main actor): the selected element's details, the last distances, the guide settings; `Shared/Measure/MeasurePanel.swift` (SwiftUI): the details as a compact table, with Copy buttons for size, colours and font; the guides' fields; Pick Colour; Stop.
- Mac: the panel in the browser view's overlay (Decided 1). iOS: a card at the bottom of the page's area.
- `Command.measure` (Decided 8) with title, keywords ("measure", "ruler", "guides", "spacing", "inspect"), chord `Chord(.character("m"))`, a group, symbols (`ruler`), both `perform` cases, the Mac's `BrowserCommands` item and `keys(for:)`; the bar's button.
- Preferences (three edits each, `PreferencesTests`): `measureColumns = 12`, `measureGutter = 24`, `measureMargin = 0`, `measureRow = 8`, `measureRulers = true`.

### 1.3 Tests

- `Tests/measure.html` and `Tests/measure.mjs` (Playwright, WebKit and Chromium, as `Tests/bridge.mjs`): a fixed layout (a 300 by 200 box with 16 px padding, a flex row with a 12 px gap, two boxes 40 px apart), with a stand-in message handler. Check: the details posted for the box; the gap; the distance 40 between the two; guides' columns at the right x for 12 columns at a known width; Esc ends and leaves no element behind; clicks do not reach the page while on.
- `cd PadCore && swift test`: commands and preferences.

## Pull request 2: notes, copied for an assistant

1. In the panel, with an element selected: "Add Note…" opens a text field; the note is pinned to the element (a numbered dot at its top left in the overlay).
2. The panel lists the notes; each can be edited or removed.
3. "Copy for an Assistant" puts this on the clipboard (built in PadCore, `MeasureNotes.text(page:viewport:notes:)`, tested on Linux):

```
Page: https://example.com/pricing
Window: 1440 by 900, at 100%

1. button.primary "Sign up", at 120, 340, 96 by 40
   Note: make the padding 12 pixels on each side
   Now: padding 8px 16px; Inter 15px/20px 600; #ffffff on #2563eb; radius 8px

2. …
```

   An element is named by a CSS selector: its `id` if it has one (`#id`), else up to four levels of `tag.class:nth-of-type(n)` from the nearest ancestor with an `id` or from `body`; the text is its first 40 characters of `innerText`. Never the page's other text.
4. Tests: `MeasureNotes` in PadCore; the selector in `Tests/measure.mjs`.

## Tests, both pull requests

By hand, a new section in `Validation/CHECKLIST.md`, "Measuring tool", on a Mac and an iPad:
- A marketing page and a web app: sizes, padding and gaps match what Safari's Web Inspector shows for the same elements.
- ⌥ distances on the Mac; tap-then-tap distances on the iPad.
- Guides at 12 columns, rulers; X-ray.
- A colour picked with the Mac's loupe, and by touch on the iPad.
- The page zoomed (⌘+): the numbers stay in CSS pixels.
- Notes on three elements, copied, pasted into a chat with an assistant.
- `accounts.google.com`: the tool does not start.

## Done when

- [ ] Both pull requests merged; tests pass; no new warnings.
- [ ] The CHECKLIST section run once on a Mac and an iPad, results written under it.
- [ ] CHANGELOG under `### Added`: "A measuring tool (⌃⌥M, or Measure in developer mode's bar): an element's size, padding, margin and gaps, the distances to others with ⌥, column guides and rulers, a colour from the page, and notes on elements to copy for an assistant."
- [ ] README: a paragraph in the developer mode section (task 08's), and ⌃⌥M in the Keyboard shortcuts table.

## Out of scope

- Screenshots and recordings of a region: task 08's element picture covers pictures; recordings are not planned.
- Mesurer's responsive previews: task 08's sizes on the Mac.
- Saving notes, or sharing them other than by copying.
