# Task 05: Asking about grammar checking at onboarding

| | |
|---|---|
| Needs first | Task 02 merged. Task 03 (other apps) and task 04 (iPad and iPhone) each add their part here when they are merged; see "Parts that wait" |
| Size | S (up to a week) |
| Platforms | Mac, iPad and iPhone |
| Pull requests | One, plus a small one for each part that waits |

## Goal

Grammar checking is off until the person says so (decided 2026-10-25). They are asked once:

- **New on iPad or iPhone:** a Writing step in the welcome sheet.
- **On the Mac,** which has no welcome sheet: a small sheet at the first launch with this version, for new and updating people alike.
- **Updating on iPad or iPhone** (their welcome is already done): the same small sheet, once.

Whatever they answer, Settings › Writing changes it later, and they are never asked again.

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

### The iOS welcome sheet (`App/Sources/Welcome.swift`)

- Steps: `enum Step: Int, CaseIterable { case hello, space, bookmarks, finish }` (`:20-22`). Only the session's `"welcome"` key is stored, never the step, so adding a step is safe.
- `go`/`advance` (`:92-100`; past `finish`, `done()`); the slide between steps (`:85-90`).
- Header (`:104-140`): the step dots, Back, "Skip Setup" (`done`, `:129`).
- Footer (`:142-167`): the main button, its words per step (`:169-180`) and action (`:182-185`); "Skip This Step" only on bookmarks (`:157-162`).
- `page` chooses the step's view (`:187-204`). Views: `hello` (`:222-248`, `Feature` rows `:406-428`), `yourSpace` (`:252-287`), `bookmarks` (`:297-318`), `finish` (`:322-374`). Helpers: `heading` (`:206-218`), `choice` (`:376-392`), `badge` (`:394-402`).
- When it shows: `Session`'s `"welcome"` key goes nil → `"pending"` only for a new workspace (`App/Sources/Session.swift:144-157`), → `"done"` in `finishWelcome()` after a durable save (`:159-166`); `needsWelcome` (`:148-150`). `Browser.resumeWelcomeIfNeeded()` (`App/Sources/Browser.swift:455-478`) presents it as a `.formSheet` of 520 by 680 with `isModalInPresentation`, from `viewDidAppear` (`:446`) and `sceneDidBecomeActive` (`App/Sources/AppDelegate.swift:75-78`); one window owns it (`:451`), and another takes it if that one goes (`:484-493`).

### The Mac

- No first-run interface. `Mac/Sources/EgluApp.swift:38-50` shows `LaunchProgressView` until `LaunchState.ready`, then the browser; `Mac/Sources/LaunchState.swift` only moves data out of an old sandbox.
- No "what's new" or "asked once" mechanism on either platform. The nearest: iOS's `"welcome"` key; the Mac's `Extensions.justInstalled` (`Mac/Sources/Extensions.swift:85-93`).

### Grammar checking (tasks 02 to 04)

- `Preferences.writing` (in pages), and from task 03 `Preferences.writingOtherApps` (other apps, the Mac only), with `AccessibilityAccess.ask()` (`Mac/Sources/Writing/Elsewhere/AccessibilityAccess.swift`).
- Settings › Writing on the Mac (`SettingsPane.writing`), and from task 04 on iOS (`SettingsGroup.writing`).

## Decided

1. **The question, in these words** (through the String Catalog):
   - Heading: "Check your English as you write?"
   - Text: "Harper, a grammar checker, underlines mistakes in what you type in pages and suggests fixes. It works on this device, in English only, and sends nothing anywhere."
   - Main button: "Check My Writing". Second button: "Not Now".
   - Under the text, on the Mac when task 03 is in: a checkbox "In other apps too, such as Mail and Notes", off; turning it on says under it "eGlu will ask for Accessibility, which lets it read the field you type in."
   - Below, small: "You can change this in Settings › Writing."
2. **One flag, `"writingAsked"` in `UserDefaults.standard`**, set to the build number that asked, the moment either button is pressed. Nil means not asked. Never asked again once set.
3. **On iOS, new people:** a step `.writing` between `.bookmarks` and `.finish`. Pressing either button sets the flag; "Skip Setup" leaves it nil, so the small sheet asks later.
4. **On iOS, updating people:** when the welcome is `"done"` and the flag is nil, the small sheet shows once, presented as the welcome is (`resumeWelcomeIfNeeded`'s pattern), not over a welcome in progress, not while another sheet is up (try again at the next `sceneDidBecomeActive`).
5. **On the Mac:** a sheet on the first browser window, once `LaunchState.ready`, when the flag is nil.
6. **"Check My Writing"** sets `writing = true` (and `writingOtherApps = true` with the checkbox, then `AccessibilityAccess.ask()`). **"Not Now"** changes nothing.
7. **Where the device can't** (no engine for any reason): don't ask.

## Steps

### 1. The question as one view

`Shared/Writing/WritingQuestion.swift`: a SwiftUI view with Decided 1's words, two closures (`check(otherApps: Bool)`, `notNow()`), and a flag `offersOtherApps` (true on the Mac when task 03 is in, else false). It uses `heading`-like styling to match `Welcome.swift` on iOS and the Mac's settings forms on the Mac; look at both and keep it plain. A symbol at the top: `character.cursor.ibeam`.

`Shared/Writing/WritingAsked.swift`: `static var wasAsked: Bool`, `static func markAsked()` (writes the build number, `Bundle.main` `CFBundleVersion`).

### 2. The iOS welcome step

In `Welcome.swift`:

1. `case writing` between `bookmarks` and `finish`.
2. In `page`, `.writing` → `WritingQuestion(...)` laid out as the other steps (`heading`, then content).
3. Footer: on `.writing`, the main button is "Check My Writing" (sets `session.preferences.writing = true`, marks asked, advances), and a second button "Not Now" in the place of "Skip This Step" (marks asked, advances). Update `:157-162` and `:169-185` accordingly.
4. The step dots count it (`Step.allCases`).

### 3. The iOS small sheet

In `App/Sources/Browser.swift`, beside `resumeWelcomeIfNeeded()` (`:455-478`): `askAboutWritingIfNeeded()`: when `session.needsWelcome` is false, `WritingAsked.wasAsked` is false, nothing is presented, and this window owns the welcome's role (`:451`); present `UIHostingController(rootView: WritingQuestion(...))` as a `.formSheet` of 460 by 420, `isModalInPresentation = true`; both buttons dismiss it. Call it where `resumeWelcomeIfNeeded()` is called (`:446`, and `AppDelegate.swift:75-78`).

### 4. The Mac sheet

In the Mac's browser window view (`Mac/Sources/BrowserView.swift` or where `EgluApp.swift:38-50` shows the browser): `.sheet(isPresented:)` bound to a state set once `LaunchState.ready` when `WritingAsked.wasAsked` is false, only on the first window to appear (a static flag for the process). Content: `WritingQuestion(offersOtherApps: …)` with padding, 440 points wide.

### 5. Tests

- PadCore has nothing here; if `WritingAsked`'s decision (asked or not, given welcome state and flag) is a function, put it in PadCore and test its table:

| welcome | flag | shows |
|---|---|---|
| pending | nil | the welcome's step (not the sheet) |
| done | nil | the sheet |
| done | set | nothing |

- By hand, a section in `Validation/CHECKLIST.md`, "Asking about grammar checking": a new iPad (delete the app first): the step shows, both buttons do what they say; an iPad updated from a build without it: the sheet once, and never again after either button; "Skip Setup" then relaunch: the sheet; a Mac's first launch: the sheet on the first window only; the Mac's checkbox (with task 03) asks for Accessibility.

## Parts that wait

- **Task 03 merged:** set `offersOtherApps` true on the Mac, and wire the checkbox to `writingOtherApps` and `AccessibilityAccess.ask()`. Task 03's hand-back names this if 05 is already merged; if 05 merges after 03, do it here.
- **Task 04 merged:** the iOS parts above check `writing` on iOS. If task 04 is not merged when this task is done, leave the iOS parts out (the Mac's sheet alone) and add them in a follow-up pull request when it is.

## Done when

- [ ] Merged; tests pass; no new warnings.
- [ ] The CHECKLIST section run once on each platform present, results written under it.
- [ ] CHANGELOG under `### Added`: "eGlu asks once whether to check your English as you write, when you set it up or after this update. Settings › Writing changes it."
- [ ] The README's "First steps" (`README.md`, under Install) mentions the question on iPad and iPhone.

## Out of scope

- Any other "what's new" screen.
- Asking again later.
