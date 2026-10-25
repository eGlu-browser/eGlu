# Task 08: Developer mode, as Arc's

| | |
|---|---|
| Needs first | Nothing |
| Unblocks | Task 10 (the measuring tool uses its bar and its element screenshots) |
| Size | M (two to four weeks) |
| Platforms | Mac; iPad and iPhone in part (no inspector in an iOS app, no local servers) |
| Pull requests | Four, in order: (1) when it is on, the bar, the inspector, reload from origin, the keys and Settings (Mac); (2) element screenshots and the JSON view (Mac and iOS scripts); (3) local servers and the phone and iPad sizes (Mac); (4) the iPad's and iPhone's bar |

## Goal

Arc turns developer mode on by itself on `localhost`, and on any site from its menu: the full address with its port across the top, buttons for the console, the network panel and the element inspector, a screenshot of the element under the pointer, and a JSON formatter. eGlu does the same, with WebKit's Web Inspector, and adds a list of the local servers running on the Mac in the command bar, reload without the cache, and a look at the page at a phone's or an iPad's size. The keys for the developer tools are ⌃⌥ (as eGlu's) or ⌥⌘ (as Chrome's), chosen in Settings.

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

### Addresses

- `PadCore/Sources/PadCore/Address.swift`: `enum Address` (`:6`, internal to PadCore; the apps reach it through `Destination` in `Commands.swift`: `editable(_:engine:)` `:294-296`, `pretty` `:306-308`, `editable(_:)` `:311-313`).
- The local-host test is a `let local` inside `url(from:)` (`:39-46`): `localhost`, `*.localhost`, `*.local`, `127.0.0.1`, `0.0.0.0`, `192.168.*`, `10.*`, and 172.16 to 172.31 (`privateRange`, `:52-56`); `[::1]` at `:31`. Local hosts get `http://` (`:47`). `reachable` (`:61-67`) turns `0.0.0.0` into `localhost`.
- The Mac's sidebar address, `AddressPill` (`Mac/Sources/Sidebar.swift:128-214`), shows the host only (`:208-213`), so no port; for `http` its icon is `exclamationmark.triangle.fill` (`:203`), so `localhost` shows a warning. The top tabs show `addressText()` (`Shared/AddressText.swift:8-21`; `Mac/Sources/TopTabBar.swift:291-302`): host only, no scheme, port or path. The whole address shows only in the command bar on ⌘L (`Mac/Sources/CommandBar.swift:47`).

### The Mac's page

- `Mac/Sources/Page.swift`: `decidePolicyFor navigationResponse` (`:937-956`): line 940 already casts to `HTTPURLResponse`; `mimeType` stored for the main frame at `:951` (declared `:111`); nothing keeps `statusCode`. The commit (`:973-991`). `WindowModel.refresh()` (`Mac/Sources/WindowModel.swift:281-294`) copies a page's state into the window's published values.
- `isInspectable = true` (`:269`): Safari › Develop › eGlu reaches every page. Nothing in eGlu opens the inspector; no `_WKInspector` use yet.
- The precedent for private API: `config.preferences.responds(to: Selector(("_setAllowsPictureInPictureMediaPlayback:")))` then `setValue(true, forKey:)` (`:256-258`).
- Reload: `reload(byHand:)` (`:364-377`), `WindowModel.reload()` (`WindowModel.swift:524-530`), the menu's "Reload Page" (`Mac/Sources/Menus.swift:102`). `reloadFromOrigin()` is used only by extensions (`Mac/Sources/ExtensionTabs.swift:230-231`).
- `takeSnapshot` only in `picture(pixels:)` (`:542-552`), with no rectangle.
- `pageZoom` (`:494-504`).
- The page's size: `PageHolder` (`Mac/Sources/PageHolder.swift:18-36`) sizes the web view to its bounds; `PageSurface` (`Mac/Sources/Window.swift:194-214`). Peek frames a page at a fixed size (`Mac/Sources/Peek.swift:178, 190`, `Peek.size`).
- Where a bar can go (`Mac/Sources/BrowserView.swift`): `body` (`:32-115`); the page's card (`PaneCard`, a `ZStack`, `:360-398`) holds `PageSurface` and the find bar (`:381-385`). A view in a `VStack` above `PageSurface` inside the card makes the page shorter; an overlay covers it.
- The Mac never sets `customUserAgent`; only `applicationNameForUserAgent` (`:244`). The iPhone's and iPad's user agents: `SiteMode.mobileUserAgent(…pad:)` (`PadCore/Sources/PadCore/SiteMode.swift:34-45`).

### iOS's page (`App/Sources/Page.swift`)

- `isInspectable = true` (`:293`): Safari on a Mac reaches an iPad's or iPhone's pages through Develop › (the device).
- `mimeType` (`:116`, set at `:1364-1368`).
- `takeSnapshot` with `configuration.rect` at `:918`, `:948`, `:1032`, `:1055`: the precedent for a rectangle.
- `reload(byHand:)` (`:391-402`).

### The command bar (Mac)

- `Suggestions` (`Mac/Sources/CommandBar.swift:17-194`): `candidates(for:)` (`:160-193`, cached per space in `Autocomplete.Index`, `:145-153`); `typed()` (`:57-81`) also asks the async sources; `show()` (`:118-143`) merges them through `Autocomplete.rows(...)`.
- Async sources (`Shared/SuggestionSources.swift`): each cancels its previous task, checks the query, stores `(query, rows)` and calls `changed()`; `recall` (`:106-114`) is the simplest to copy; `quiet()` and `end()` (`:51-72`).
- A new kind of row: a `Suggestion.Source` case (`PadCore/Sources/PadCore/Autocomplete.swift:7-26`), and every switch over it: `label` (`:28-42`), `isPage` (`:46-51`), `weight` (`:418-425`), `described` (`:676-687`), `kind` (`:898-910`), the Mac's `SuggestionRows.kind` (`CommandBar.swift:361-372`) and row icon (`:484-496`), and iOS's (`App/Sources/Suggestions.swift:289, 381, 440`).

### Commands and keys

- `Commands.swift`: `Command` (`:5-41`), `title` (`:43-79`), `keywords` (`:82-117`), `ShortcutGroup` (`:181-208`), `Shortcuts.chords` (`:211-245`). `CommandTests` (`:6-13`, `:50-54`): every command a ⌃⌥ chord unless reserved, unambiguous, in one group. A new command also needs its symbol in `App/Sources/Menus.swift:111-151` and `Mac/Sources/CommandBar.swift:196-232`, and a case in `App/Sources/Browser.swift:2064-2126` and `Mac/Sources/WindowModel.swift:886-920`.
- **The Mac** writes each key in `BrowserCommands` (`Mac/Sources/Menus.swift:7-285`) with `.keyboardShortcut`, Safari's ⌘ keys for what Safari has (⌘L, ⌘R, ⌘F, ⌘D, ⌘Y…), and `WindowModel.keys(for:)` (`:930-955`) says what each shows. In use with ⌥⌘ today: ↑, ↓, ←, →, `\`. Free with ⌥⌘: I, J, C, E, R.
- **iOS** makes its keys from the chords (`App/Sources/Menus.swift:166-208`, `keyCommand` `:264-268`), and already has a setting that changes their modifiers: `browserControlShortcuts` turns ⌃⌥ into ⌃ (`:155-161`, `:273`). Copy that pattern for the developer keys.
- Free ⌃⌥ chords (plain): C, E, G, I, J, M and others; shifted: R, V and others (taken shifted: N, P, D, C, M, S, I, A, L).

### Settings and preferences

- Preferences (`PadCore/Sources/PadCore/Preferences.swift`): three edits for each (`var` at `:23-102`, `CodingKeys` `:128-143`, decode `:145-174`); `PreferencesTests`.
- Mac panes: `SettingsPane` (`Mac/Sources/SettingsView.swift:100-136`), detail switch (`:40-47`).
- iOS: `SettingsGroup` and `SettingsAnchor` (`PadCore/Sources/PadCore/SettingsAnchor.swift`); `SettingsDetail` (`App/Sources/SettingsView.swift:67-406`); `SettingsRoutingTests.swift:22-26` counts the groups offered.

### Processes

Nothing reads processes or ports today. The Mac is outside the App Sandbox (`Config/eGluMac.entitlements`), so `libproc` works for the person's own processes. `Process` is used only for `/usr/bin/ditto` (`Mac/Sources/ExtensionUpdates.swift:250-260`).

## Decided

1. **On by itself** for local hosts (Address.swift's test, made public as `Address.isLocal(host:)` and used by `url(from:)`), unless turned off for that host; **on by hand** for any other site, from the page's menu or the command bar. Remembered per host.
2. **The bar** is per page, in the page's card above the page (the page is 28 points shorter), on the Mac and on iOS. It shows: the whole address (scheme, host, **port** in the accent colour, path and query), selectable; a click opens the command bar holding it; the response's HTTP status as a small label (2xx green, 3xx grey, 4xx orange, 5xx red); then buttons.
3. **Buttons (Mac):** Inspector, Console, Select Element, Element Screenshot, Reload from Origin, Size (Full, iPhone, iPad), and "Raw" when the page is JSON. **iOS:** Element Screenshot, Reload from Origin, Raw, and an info button saying how to inspect from Safari on a Mac.
4. **The inspector** through WebKit's private `_WKInspector`, behind `responds(to:)` checks (the picture in picture precedent). Where it is gone, the buttons say "Open it from Safari › Develop › eGlu."
5. **Keys**, with a setting "Developer Tools' Keys": ⌃⌥ (as it starts) or ⌥⌘ (as Chrome).

| Command | ⌃⌥ | ⌥⌘ |
|---|---|---|
| Show Web Inspector | ⌃⌥I | ⌥⌘I |
| Show JavaScript Console | ⌃⌥J | ⌥⌘J |
| Select an Element | ⌃⌥C | ⌥⌘C |
| Take a Picture of an Element | ⌃⌥E | ⌥⌘E |
| Reload from Origin | ⌃⌥⇧R | ⌥⌘R |
| Developer Mode for This Site (on or off) | ⌃⌥⇧V | ⌃⌥⇧V (the setting does not move it) |

   With ⌥⌘ chosen, those five keys are the browser's on every page, not only in developer mode: Settings says so under the choice ("Pages will no longer get these keys.").
6. **The JSON view** is on for every page whose main frame is JSON (`application/json` or `+json`), developer mode or not, with a setting "Format JSON" (on). It draws over the page in a closed shadow root; "Raw" hides it. Over 10 MB, raw only.
7. **An element's picture** covers the part of the element that is on screen, with 16 points around it, copied to the clipboard; a toast offers Save (Mac: `~/Downloads`; iOS: the share sheet).
8. **Local servers** (Mac): the TCP ports in the listening state on 127.0.0.1, ::1, 0.0.0.0 or :: of the person's own processes, that answer HTTP (a `HEAD /` with 300 ms to answer, no cookies, an ephemeral `URLSession`), with the process's name. In the command bar when the text typed is "local", "localhost", ":" or a port's first digits.
9. **Sizes** (Mac): iPhone (393 by 852 points, the iPhone's user agent) and iPad (820 by 1180, the iPad's), set on the page as `customUserAgent` and a fixed frame centred in the card, then a reload; Full puts both back. For that tab only, not saved. It is a size and a user agent, not an emulator: no touch events, no device pixel ratio.

## Pull request 1: when, the bar, the inspector, the keys (Mac)

### 1.1 PadCore

- `Address.isLocal(host: String) -> Bool` (public), with `url(from:)` using it; tests for each kind of host.
- `DeveloperMode.isOn(_ url: URL?, choices: [String: Bool], local: Bool) -> Bool`: the host's choice if there is one, else `local && Address.isLocal(host:)`. Tests.
- Preferences (three edits each, `PreferencesTests`):

```swift
/// Hosts where developer mode was turned on or off by hand (Docs/Tasks/08); local hosts are on unless here.
public var developerSites: [String: Bool] = [:]
/// Whether a JSON page is shown formatted.
public var formatJSON = true
/// The developer tools' keys: "controlOption" (⌃⌥) or "optionCommand" (⌥⌘).
public var developerKeys = "controlOption"
/// Whether local hosts are in developer mode by themselves.
public var developerLocal = true
```

- Commands (Decided 5's table), with titles, keywords ("developer", "devtools", "inspect", "console", "elements", "reload", "cache"), chords, one `ShortcutGroup` (a new "Developer" group or the page group, as `ShortcutGroup` reads), symbols (`hammer`, `terminal`, `cursorarrow.rays`, `camera.viewfinder`, `arrow.clockwise.circle`, `chevron.left.forwardslash.chevron.right`), and cases in both `perform` switches; iOS offers only Element Screenshot, Reload from Origin and Developer Mode for This Site (`Device.offers`).

### 1.2 The status and the address

- `Mac/Sources/Page.swift:951`: keep `statusCode` (an `Int?`) beside `mimeType`, for the main frame; `WindowModel.refresh()` publishes it.
- `AddressPill` (`Sidebar.swift:203, 208-213`) and `addressText()` (`Shared/AddressText.swift`): for a local host, the port after the host, and the symbol `chevron.left.forwardslash.chevron.right` in place of the warning triangle.

### 1.3 The bar

`Mac/Sources/DeveloperBar.swift`: a SwiftUI view, 28 points tall, in `PaneCard` (`BrowserView.swift:360-398`) in a `VStack` above `PageSurface`, shown when `DeveloperMode.isOn(page.url, choices: developerSites, local: developerLocal)`. Decided 2 and 3. Its buttons use the commands, so their keys show in their help tags.

### 1.4 The inspector

`Mac/Sources/WebInspector.swift`:

```swift
/// WebKit's Web Inspector, opened from eGlu. Private API: WKWebView's
/// `_inspector` (`_WKInspector`). A DMG has no App Review; a macOS that takes
/// it away leaves Safari's Develop menu, which the bar then points to.
enum WebInspector {
    enum Part { case inspector, console, elements }
    @discardableResult
    static func show(_ part: Part, for view: WKWebView) -> Bool
}
```

- `view.responds(to: Selector(("_inspector")))`, then the object it returns; on it, `show`, `showConsole` or `toggleElementSelection`, each after `responds(to:)`. Answer false where anything is missing.
- If `show` does nothing on a page, try WebKit's developer extras for that page's configuration with the picture in picture pattern (`_setDeveloperExtrasEnabled:` / `developerExtrasEnabled`), in `Page.configuration` (`Mac/Sources/Page.swift`, beside `:256-258`), and say in the hand-back whether it was needed.

### 1.5 The keys

- `BrowserCommands` (`Mac/Sources/Menus.swift`): a Developer menu, or a group in the View menu (`:101-135`), with the six commands; each item's `.keyboardShortcut` from `developerKeys` (Decided 5).
- `WindowModel.keys(for:)` (`:930-955`) returns the chosen keys.
- `WindowModel.perform` runs each: the inspector's parts, `reloadFromOrigin()` on the page, the site's switch (writes `developerSites`).
- The page's menu (`PageActions.swift`): "Developer Mode for This Site" with a check mark.

### 1.6 Settings › Developer (Mac)

`SettingsPane.developer` (title "Developer", symbol `hammer`): "Developer Mode on Local Sites" (`developerLocal`), the sites turned on or off by hand with Remove, "Format JSON", and the keys' choice with Decided 5's note.

## Pull request 2: element pictures and the JSON view (both apps)

### 2.1 An element's picture

1. `PadCore/Sources/PadCore/Scripts/element-pick.js`: a function run with `callAsyncJavaScript` in `Page.world` that returns a promise: it draws an outline (closed shadow root, `pointer-events: none`) round the element under the pointer (`mousemove`, capturing) or the finger, and resolves with that element's `getBoundingClientRect()` on a click or tap (capturing, `preventDefault`, `stopPropagation`), or with `null` on Esc. While it runs it takes the click and Esc from the page; nothing else.
2. In each `Page.swift`: `func pickElement() async -> CGRect?` (hands-off checked), and `func picture(of rect: CGRect) async -> NSImage?` / `UIImage?`: the rectangle times `pageZoom` (Mac) or as iOS's precedents compute it, with 16 points around it, clipped to the view, through `takeSnapshot(with:)` with `rect` set.
3. The result to the clipboard (PNG); `Shared/ActionToast.swift` shows "Picture copied" with Save.

### 2.2 The JSON view

1. `PadCore/Sources/PadCore/Scripts/json-view.js`: on a document whose body is one `<pre>` with JSON, parse it (under 10 MB), and draw over the page a tree: objects and arrays that fold and unfold, strings, numbers, booleans and null in their colours, light and dark by `prefers-color-scheme`, monospaced, with a "Raw" button that hides it. Never change the `<pre>`.
2. In each `Page.swift`'s `prepare`: add it at document end in `Page.world` when `formatJSON` is on and `mimeType` is JSON; the stamp includes that. As `mimeType` is known only at the response, call `prepare` again from the response handler (`Mac/Sources/Page.swift:951`; iOS `:1366` already does after redirects) when JSON-ness changes, before the document commits.
3. The bar's "Raw" (and a page without the bar: the view's own "Raw") toggles it.
4. Tests: `Tests/json-view.html` and `Tests/json-view.mjs` (Playwright, as `Tests/bridge.mjs`): an object, an array, nested, unicode, a 10 MB refusal, Raw.

## Pull request 3: local servers and sizes (Mac)

### 3.1 Local servers

`Mac/Sources/LocalServers.swift`:

1. `proc_listpids(PROC_ALL_PIDS, …)`; for each pid, `proc_pidinfo(pid, PROC_PIDLISTFDS, …)`; for each socket descriptor, `proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, …)`; keep `soi_kind == SOCKINFO_TCP` with `tcpsi_state == TSI_S_LISTEN` and a local address of 127.0.0.1, ::1, 0.0.0.0 or ::; the port from `insi_lport` (network byte order); the name from `proc_name`. Processes of other users are not readable and are skipped.
2. Probe each port (Decided 8) at the same time, at most 32.
3. Off the main actor, cached for 2 seconds.
4. A `Suggestion.Source.localServer` case and every switch it needs (listed above); an async source in `Shared/SuggestionSources.swift` after `recall`'s pattern, asked when the text typed matches Decided 8, its rows "localhost:5173" with the detail "vite (node)", opening `http://localhost:<port>/`. iOS never makes these rows, but its switches handle the case.

### 3.2 Sizes

The bar's Size menu (Decided 9): sets `view.customUserAgent` to `SiteMode.mobileUserAgent(…pad:)`'s iPhone or iPad string and frames `PageSurface` at that size, centred, the card's colour round it (Peek's sizing is the pattern); Full sets `customUserAgent = nil` and the full frame; each reloads.

## Pull request 4: iPad and iPhone

1. The bar of Decided 2 and 3 at the top of the page's area: find where `Browser` lays the page out (`Browser.layoutPanes`) and put it there, the page 28 points shorter; on a phone-width window, 24 points, with the address and the status only, and the buttons in the page's menu instead.
2. The page menu (`MenuEntry`, `App/Sources/Bars.swift:343-444`): "Developer Mode for This Site", Element Screenshot, Reload from Origin, when on.
3. Settings › Developer on iOS: a `SettingsAnchor.developer` in a new `SettingsGroup.developer` (or in the group with `.diagnostics` if `SettingsGroup` puts those together), with the same rows but the keys' choice only when a hardware keyboard is used (as Shortcuts is); update `SettingsRoutingTests` to the new count.
4. The keys' choice on iOS changes the modifier flags of the developer commands' `UIKeyCommand`s, as `browserControlShortcuts` does (`App/Sources/Menus.swift:155-161, 273`).

## Tests

- `cd PadCore && swift test`: `Address.isLocal`, `DeveloperMode.isOn`, preferences, commands.
- `node Tests/json-view.mjs`; `node Tests/bridge.mjs` still passes.
- By hand, a new section in `Validation/CHECKLIST.md`, "Developer mode", on a Mac and an iPad:
  - `npx vite` (or `python3 -m http.server 8000`) running: typing "local" in the command bar lists it with its process; opening it shows the bar with the port and 200; a missing path shows 404.
  - Inspector, Console and Select Element open WebKit's inspector at that part; Reload from Origin; the keys in both settings.
  - "Developer Mode for This Site" on `https://example.com`, then off again; off for `localhost:8000`, then on.
  - An element's picture of a card on a page, pasted into Preview.
  - `https://api.github.com/repos/eGlu-dot-apps/eGlu`: formatted, folded, Raw.
  - iPhone and iPad sizes on a responsive site: the layout changes, the site sees the user agent.
  - On the iPad: the bar, an element's picture, the JSON view; Safari on a Mac inspects the iPad's page.

## Done when

- [ ] All four pull requests merged; tests pass; no new warnings.
- [ ] The CHECKLIST section run once on a Mac and an iPad, results written under it.
- [ ] CHANGELOG under `### Added`: "Developer mode, as Arc's: on by itself for localhost and on for any site from its menu, with the whole address and its port, the response's status, buttons for WebKit's Web Inspector (Mac), a picture of an element, reload from origin, the page at a phone's or an iPad's size (Mac), and the local servers on your Mac in the command bar. JSON pages are shown formatted."
- [ ] README: a "Developer mode" section under Features, and the keys in the Keyboard shortcuts table, with the ⌥⌘ setting.

## Out of scope

- Arc's Boosts (a site's own CSS and JavaScript): Chrome extensions do that on the Mac.
- A console or network panel of eGlu's own: WebKit's inspector has them.
- The measuring tool: task 10.
