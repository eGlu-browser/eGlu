# Plan: grammar checking, PDF handoff and developer features

What eGlu will build from the ideas of 2026-10-25, how, and in what order. Mac first; the iPad gets what it can support. Written from the projects' own pages and source, and eGlu's code at Build 38.

Sizes are rough, for one developer: **S** up to a week, **M** two to four weeks, **L** one to two months, **XL** three months or more.

## Summary

| # | What | Size | Mac | iPad and iPhone |
|---|---|---|---|---|
| 1 | Harper's grammar checking in pages | L | Yes | Yes |
| 2 | Harper's grammar checking in other apps | L | Yes | No: iPadOS lets no app read another's text |
| 3 | Handoff for PDFs | M | Yes | Yes |
| 4 | Developer mode, as Arc's | M | Yes | In part: no inspector in the app, no local servers |
| 5 | A measuring tool, as Mesurer | S to try its extension, M built in | Yes | Built in only |

Not planned: GenOffice as the PDF viewer and office tools, the motion tool on HyperFrames, and Toolcraft, whose one good fit was the motion tool.

## 0. The rules

- **Apple's frameworks only, with one exception: Harper's engine, in Rust**, as Sparkle is the exception in eGlu Mac Direct. Harper's rules are Rust code (below), and a port to Swift would be about 45,000 lines to rewrite and every Harper release to port again by hand. Rust is kept for that reason, not for speed: Swift would check a field in milliseconds too.
- **pdf-inspector is Rust too** (MIT). Its default build is pure Rust (`lopdf`, `rayon`, `regex`, `ttf-parser`): no PDFium, no OCR models, no network code. Whether it joins the exception is the one decision left (section 3).
- **How the exception is built.** The Rust is compiled from source into one XCFramework (macOS arm64 and x86_64, iOS, the simulator) with a C interface and a Swift wrapper, published with a checksum and taken by eGlu as a pinned `binaryTarget`. Building eGlu still needs nothing but Xcode. If pdf-inspector joins, it goes in the same XCFramework, so there is one Rust build to keep.
- **Nothing leaves the device.** Everything here runs on it.
- **The page gets the input.** Browser keys stay on ⌃⌥, unless the person switches developer tools to ⌘ (section 4). Free on ⌃⌥ today: C, E, G, I, J, M (PadCore/Sources/PadCore/Commands.swift:211).
- **Hands off Google's sign-in.** Every script below checks HandsOff, as Page.call does.

The Mac app is a Developer ID DMG outside the App Sandbox (Config/eGluMac.entitlements), so it can ask for Accessibility and use WebKit's private API behind a `responds(to:)` check, as picture in picture does (Mac/Sources/Page.swift:250).

## 1 and 2. Harper's grammar checking

### What there is

- [Harper](https://github.com/Automattic/harper), Apache-2.0: English only (US, UK, Australian, Canadian), offline. In [harperSwift](https://github.com/taehee-pd/harperSwift)'s copy of `harper-core`:

| Part | Size |
|---|---|
| Rules in Rust | 345 files, more than 31,000 lines besides their tests (294 phrase rules, 23 others, 17 folders) |
| Rules in Harper's own rule language (weir) | 382 |
| The engine: words, spelling, patterns, weir, parts of speech | about 15,000 lines |
| Data: the dictionary, the part-of-speech tagger and chunker | about 3 MB |
| Tests | about 6,000 |

- harperSwift's Mac app: SwiftUI windows over a Tauri process.
  - `harper-desktop/macos-popup` (HarperPopup): Swift, Apple's frameworks only, about 4,400 lines. The suggestion panel in Liquid Glass, Settings, the first-run setup, the editor, Clarity suggestions from Apple's on-device model.
  - `harper-desktop/src-tauri/src/mac_broker` and `highlighter`: Rust, about 6,000 lines. Reads other apps' text through the Accessibility API, draws the underlines, converts Accessibility's UTF-16 offsets to Harper's character spans (`text_selection.rs`), and writes a suggestion back by selecting the range and setting the selected text, so formatting, the caret and Undo stay.

### What goes into eGlu

| Part | From | Into eGlu as |
|---|---|---|
| Harper's rules and engine | `harper-core` | The Rust exception: `HarperKit`, the XCFramework and its Swift wrapper (`lint(text:dialect:) -> [Lint]`, rules on and off, the personal dictionary) |
| Harper's UI | HarperPopup | eGlu's own Swift, credited: the panel, the rule lists and the dictionary, in eGlu's Settings › Writing |
| Checking in other apps | `mac_broker` and `highlighter` | Rewritten in Swift with AppKit and the Accessibility API |
| Checking in pages | New | A script of eGlu's own and the panel |

Credits: Harper and harperSwift under Apache-2.0 in the README's Credits, with the NOTICE Apache asks for.

### 1. In pages

1. **A script in eGlu's own world** (`writing.js`, in `Page.world`) watches the field with the focus: `textarea`, text `input`s, `contenteditable`. Never a password or card field, a field with `spellcheck="false"`, a code editor (CodeMirror, Monaco, Ace), or a hands-off host.
2. **Checking.** After a pause in typing (about 300 ms), the field's text goes to the app through a message handler that answers. Harper runs away from the main thread; lints come back as UTF-16 ranges, which JavaScript counts in. Paragraphs that are not English (NaturalLanguage's `NLLanguageRecognizer`) are skipped, so Korean is not flagged.
3. **Underlines** in a closed shadow root over the page, never in its text: placed with `Range.getClientRects()` in `contenteditable` and a mirror element for `textarea` and `input`, and again on scroll, resize and input.
4. **Suggestions** in HarperPopup's panel at the underline, the page keeping the focus. Choosing one selects the range and calls `document.execCommand("insertText")`, so the page's undo works and React, ProseMirror and Slate see an ordinary input. ⌃⌥G accepts the first suggestion.
5. **macOS's own spell check** underlines in pages too: eGlu turns it off in pages while Harper checks them, so a word is not underlined twice (to try: `toggleContinuousSpellChecking:` on the web view).

Will not work: editors that draw their own text (Google Docs, Figma's canvas), and frames from another site the script is not let into. Rich editors that rebuild their DOM at every key (Notion, Slack) are tested one by one; a site that fights the overlay goes in a list, with a switch for each site in Settings.

### 2. In other apps (Mac)

1. eGlu watches the focused text field of the apps the person turned on (HarperPopup's Apps list), with an `AXObserver`.
2. It reads the field's text, lints it, finds each lint's rectangle (`kAXBoundsForRangeParameterizedAttribute`), and draws underlines in a window of its own over the field that lets clicks through.
3. The panel opens when the caret enters a flagged word, as in harperSwift. A suggestion is written back by selecting the range and setting `kAXSelectedTextAttribute`; the whole value is set only where an app refuses that, and nothing is written if the field changed since it was read.
4. eGlu's own pages are left to section 1.
5. It needs Accessibility, asked only when the person turns this on.
6. It checks while eGlu is open. Later: a helper inside eGlu.app, started at login (`SMAppService`, as harperSwift's LoginItem.swift), so it goes on when eGlu is closed.
7. Where Harper Desktop is installed too, Settings › Writing says so, since both would underline the same field.

### Off until asked: onboarding

- **iPad and iPhone:** a Writing step in the welcome sheet (App/Sources/Welcome.swift, between bookmarks and finish): "Check my English as I write?", off unless chosen.
- **Mac:** there is no welcome sheet today. A first-run sheet asks the same, with "In other apps too", which goes on to the Accessibility request.
- **People updating** from a build without it see the question once.
- Settings › Writing changes it later: in pages, in other apps, the dialect, rules, the personal dictionary, sites.

### Plan

| Phase | What | Size |
|---|---|---|
| 1 | `HarperKit`: the C interface over `harper-core`, the XCFramework for Mac and iOS, the Swift wrapper, tests; the binary's size measured | M |
| 2 | In pages on the Mac: `writing.js`, underlines, the panel, ⌃⌥G, Settings › Writing, the onboarding question | M |
| 3 | `contenteditable` and the site list, tested on Gmail, Slack, Notion, Linear, GitHub | M |
| 4 | In other apps: the Swift highlighter, Accessibility, the Apps list | L |
| 5 | iPad and iPhone in pages; Clarity suggestions (Shared/Intelligence.swift already uses the on-device model); the login helper | M |

## 3. Handoff for PDFs

**Today a PDF goes as its address only.** `readingForHandoff` answers `.noReadableContent` for `application/pdf` (Shared/PageShared.swift:168), so the handoff is `.wordsOnly` (Shared/HandingOff.swift:162). For an assistant, a paper or a contract in a tab is the page it most needs the text of.

[pdf-inspector](https://github.com/firecrawl/pdf-inspector), by Firecrawl, MIT: it tells, page by page, whether a PDF has text or is a scan, and turns text into Markdown with headings, lists, tables, columns in reading order, bold, italic and links, in under 200 ms.

1. **The PDF's bytes.** `WKWebView.startDownload(using:)` with the tab's address, through the space's own store and cookies, into the handoff's folder. A `file:` PDF is read as it is.
2. **Reading it.** One of two ways, the decision left:

| Way | For | Against |
|---|---|---|
| **pdf-inspector in Rust**, in the same XCFramework as Harper | Its tables, columns and headings, measured on 200 PDFs; fast | A second Rust project under the exception |
| **PDFKit and Vision alone** | No exception: the rule as it stands | Headings, columns and tables to work out from PDFKit's characters and fonts; quality unknown until measured against pdf-inspector |

   Either way, pages with no text go to Vision's document recognition on the device (`RecognizeDocumentsRequest`, macOS and iOS 26; the older `VNRecognizeTextRequest` before 26), so a scan is read too.
3. **The file.** The Markdown goes through HandoffCompose as a page's does, and says of itself how many pages there are, which are in it (a long PDF is cut at `Handoff.limit`, 100,000 characters), which were read from pictures, and which tables could not be read.
4. Apple Intelligence tells the kind and writes the summary as for any page, with kinds of PDF added: paper, contract, invoice, manual, slides.

| Phase | What | Size |
|---|---|---|
| 1 | The bytes, the reader, the file and its notes, tests with PDFs in `Tests/handoff` | M |
| 2 | Scanned pages through Vision; kinds of PDF | S |
| 3 | iPad and iPhone | S |

## 4. Developer mode

Arc turns developer mode on by itself on localhost, and on any site from its menu: the full address across the top, buttons for the console, network and elements, a screenshot of the element under the pointer, and a JSON formatter.

| Arc | eGlu today | How | iPad |
|---|---|---|---|
| On by itself for localhost | Address.swift knows local hosts (PadCore/Sources/PadCore/Address.swift:38) | On for `localhost`, `*.localhost`, `127.0.0.1`, `[::1]`, `*.local` and private addresses; "Turn On Developer Mode for This Site" in the site's menu and the command bar | Yes |
| The full address across the top | The address shows the site | A slim bar over the page: the whole address to edit, the port standing out, the response's HTTP status | Yes |
| Console, Network, Elements | Pages are inspectable (Mac/Sources/Page.swift:269), so Safari's Develop menu reaches them; nothing in eGlu opens the inspector | WebKit's private `_WKInspector` (`show`, `showConsole`, `toggleElementSelection`) behind a `responds(to:)` check; where it is gone, the bar says to use Safari › Develop › eGlu | No: iPadOS has no Web Inspector in an app. Safari on a Mac reaches the iPad's pages (App/Sources/Page.swift:293) |
| Screenshot of an element | None | The element under the pointer outlined by a script in eGlu's world; its rectangle, with some room round it, to `takeSnapshot(with:)`; to the clipboard or a file | Yes |
| JSON formatter | None | When the main frame is `application/json` (Page.mimeType, Mac/Sources/Page.swift:951), a formatted view that folds, with Raw beside it | Yes |

Beyond Arc's:

- **Local servers in the command bar**: the ports this Mac listens on, with the program's name ("localhost:5173, vite"), read from the process list. Mac only.
- **Reload without the cache**: `reloadFromOrigin()`.
- **See it as a phone or an iPad**: the page at that size with that user agent (Identity.swift has both).

### Keys: ⌃ or ⌘

Settings › Shortcuts gets a choice for developer tools' keys:

| | ⌃⌥ (as it starts) | ⌥⌘ (as Chrome) |
|---|---|---|
| The inspector | ⌃⌥I | ⌥⌘I |
| The console | ⌃⌥J | ⌥⌘J |
| Choose an element | ⌃⌥C | ⌥⌘C |
| Element screenshot | ⌃⌥E | ⌥⌘E |

With ⌥⌘ chosen, these keys are the browser's on every page, not only in developer mode, so the choice says that the page no longer gets them. The other browser shortcuts stay on ⌃⌥.

| Phase | What | Size |
|---|---|---|
| 1 | When it is on, the bar, the inspector, reload without the cache, the keys and their setting | S |
| 2 | Element screenshots, the JSON view, local servers | M |
| 3 | Phone and iPad sizes; the iPad's part | S |

## 5. A measuring tool

[Mesurer](https://github.com/ibelick/mesurer), by Julien Thibeaut, MIT: an element's bounds, distances with Option held, gaps and padding, guides and rulers, notes and arrows, typography, colour sampling, X-ray, screenshots and recordings, and comments to copy for an agent. A React component, and a Chrome extension (Chrome Web Store `icmjafcffhpcnadkmmklegommbcekcac`).

**A. Its extension, now, on the Mac.** The person installs it from the Chrome Web Store, and eGlu's check at install (ExtensionCheck.swift) says what doesn't work. To expect: measuring, guides and notes work; colour sampling doesn't (Chromium's EyeDropper, which WebKit lacks); recording probably doesn't (tab capture, PadCore/Sources/PadCore/ExtensionCheck.swift:58). Installed by the person, it is not something eGlu ships, so the rule is not touched. **S**: try it and fix what an extension shim can.

**B. eGlu's own, built in.** Mesurer is React, which the rule keeps out, so eGlu's is written anew: a script of eGlu's own for what is under the pointer, and the overlay in Swift. A Measure button in the developer bar, or ⌃⌥M; Esc ends it.

- First: bounds, distances with ⌥, padding and gaps, guides and rulers, colour (`NSColorSampler` on the Mac; the page's snapshot on the iPad), screenshots (section 4's).
- Later: notes on elements, copied as structured text for an assistant, which goes with Handoff.
- While it is on, Option goes to it and not the page, for as long as the person keeps it on.
- What it keeps stays in the app, not in the site's storage.

**M.** On the iPad too.

## Order

1. **Developer mode** (4) and **trying Mesurer's extension** (5 A): native, little risk, built on what eGlu has.
2. **`HarperKit` and checking in pages** (1, phases 1 to 3), with the onboarding question.
3. **PDF handoff** (3), once its reader is decided.
4. **Checking in other apps** (2).
5. **The measuring tool built in** (5 B).
6. **iPad and iPhone**: checking in pages, PDF handoff, developer mode's part, the measuring tool.

## Decisions

Taken on 2026-10-25:

1. Apple's frameworks only, kept, with Harper's Rust engine the one exception.
2. Harper's rules and UI built into eGlu, in pages and in other apps.
3. Off by default, asked at onboarding.
4. A setting for developer tools' keys, ⌃⌥ or ⌥⌘.
5. The iPad gets what it can support.
6. GenOffice and the motion tool not planned.

Left:

1. pdf-inspector: under the Rust exception, or PDFKit and Vision alone (section 3).

## Sources

- [Automattic/harper](https://github.com/Automattic/harper), [taehee-pd/harperSwift](https://github.com/taehee-pd/harperSwift) and its [pull request 4](https://github.com/taehee-pd/harperSwift/pull/4); measured in its source at the time of writing
- [firecrawl/pdf-inspector](https://github.com/firecrawl/pdf-inspector) and its [Cargo.toml](https://github.com/firecrawl/pdf-inspector/blob/main/Cargo.toml)
- [Arc's Developer Mode](https://resources.arc.net/hc/en-us/articles/20468488031511), [Drew Lyton on Arc for web development](https://www.drewlyton.com/story/this-is-the-best-browser-for-web-development-post/)
- [ibelick/mesurer](https://github.com/ibelick/mesurer), [Mesurer on the Chrome Web Store](https://www.chromeboard.com/extension/mesurer-icmjafcffhpcnadkmmklegommbcekcac)
