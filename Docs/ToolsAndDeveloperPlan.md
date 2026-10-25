# Plan: grammar checking, Enhanced Handoff and developer features

What eGlu will build from the ideas of 2026-10-25, how, and in what order. Mac first; the iPad gets what it can support. Written from the projects' own pages and source, and eGlu's code at Build 38.

Sizes are rough, for one developer: **S** up to a week, **M** two to four weeks, **L** one to two months, **XL** three months or more.

## Summary

| # | What | Size | Mac | iPad and iPhone |
|---|---|---|---|---|
| 1 | Harper's grammar checking in pages | L | Yes | Yes |
| 2 | Harper's grammar checking in other apps | L | Yes | No: iPadOS lets no app read another's text |
| 3 | Enhanced Handoff: documents, pictures and recordings, after MarkItDown | L | Yes | Yes |
| 4 | Developer mode, as Arc's | M | Yes | In part: no inspector in the app, no local servers |
| 5 | A measuring tool, as Mesurer | S to try its extension, M built in | Yes | Built in only |

Not planned: GenOffice as the PDF viewer and office tools, the motion tool on HyperFrames, and Toolcraft, whose one good fit was the motion tool.

## 0. The rules

- **Apple's frameworks only, with one exception: two engines in Rust**, as Sparkle is the exception in eGlu Mac Direct.
  - **Harper**, for grammar (section 1). Its rules are Rust code, and a port to Swift would be about 45,000 lines to rewrite and every Harper release to port again by hand. Rust is kept for that reason, not for speed: Swift would check a field in milliseconds too.
  - **[anydoc](https://github.com/firecrawl/anydoc)**, for documents (section 3). Firecrawl's, MIT: Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV and PDF to Markdown, its PDFs read by Firecrawl's pdf-inspector, which comes in with it. The crate makes no network call and has no OCR: a scanned PDF fails with `NeedsOcr`, and eGlu reads it with Vision instead. Firecrawl's hosted OCR is in its Node, Python and command-line wrappers only, which eGlu does not take.
- **How the exception is built.** A Cargo workspace in `Engines/`, taking `harper-core` from a tag of harperSwift and anydoc at a pinned version from crates.io, with one C interface over both. A script compiles it from source into one XCFramework (macOS arm64 and x86_64, iOS, the simulator), published with a checksum and taken by eGlu as a pinned `binaryTarget`, with a Swift wrapper for each engine. Building eGlu still needs nothing but Xcode. A Rust panic is caught at the C interface and comes back as an error.
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
| Harper's rules and engine | `harper-core` | The Rust exception: in `Engines/`, with a Swift wrapper (`lint(text:dialect:) -> [Lint]`, rules on and off, the personal dictionary) |
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
| 1 | `Engines/`: the C interface over `harper-core`, the XCFramework for Mac and iOS, the Swift wrapper, tests; the binary's size measured | M |
| 2 | In pages on the Mac: `writing.js`, underlines, the panel, ⌃⌥G, Settings › Writing, the onboarding question | M |
| 3 | `contenteditable` and the site list, tested on Gmail, Slack, Notion, Linear, GitHub | M |
| 4 | In other apps: the Swift highlighter, Accessibility, the Apps list | L |
| 5 | iPad and iPhone in pages; Clarity suggestions (Shared/Intelligence.swift already uses the on-device model); the login helper | M |

## 3. Enhanced Handoff

Handoff gives an assistant the page on screen as a Markdown file (PadCore/Sources/PadCore/Handoff.swift). Enhanced, it gives it whatever the person is looking at in eGlu: a PDF, an Office document, a picture, a recording, an archive. [MarkItDown](https://github.com/microsoft/markitdown), Microsoft's, MIT, in Python, is the reference for which kinds of file to read and what to keep of each; eGlu takes none of its code.

### Today

- **A PDF goes as its address only.** `readingForHandoff` answers `.noReadableContent` for `application/pdf` and pictures (Shared/PageShared.swift:168), so the handoff is `.wordsOnly` (Shared/HandingOff.swift:162).
- **A document WebKit can't show** (`.docx`, `.xlsx`, `.pptx`) is downloaded and can't be handed off at all.
- **Pictures on a page with no description** are named as missing in the file, unread.
- **A page's recording** goes with its transcript only where the site has one to give (YouTube).

### What MarkItDown reads, and how eGlu does it

| Kind | MarkItDown | eGlu | Engine |
|---|---|---|---|
| PDF | Offline, or Azure for layout | Headings, lists, tables, columns in reading order, links | anydoc (its pdf-inspector) |
| Scanned PDF pages | Azure, or an LLM through a plugin | Pages rendered with PDFKit and read on the device: `RecognizeDocumentsRequest` (macOS and iOS 26), `VNRecognizeTextRequest` before | Vision |
| Word, PowerPoint, Excel | Each its own Python library | One model for all, with tables (merged cells kept), footnotes, a slide's speaker notes, equations as LaTeX; a sheet a table each | anydoc |
| OpenDocument, RTF, EPUB, CSV | EPUB and CSV | All four | anydoc |
| Pictures | EXIF, OCR, an LLM's caption | What the picture says (Vision), what it shows (Apple's on-device model, which looks at pictures from macOS and iOS 27), when and with what it was taken (ImageIO). Its location is left out | Vision, FoundationModels, ImageIO |
| Audio | Metadata, a transcript | A transcript made on the device: `SpeechAnalyzer` (macOS and iOS 26), `SFSpeechRecognizer` on the device before; its length and title (AVFoundation) | Speech, AVFoundation |
| Video | Azure only | A video file's sound, transcribed as audio is | Speech, AVFoundation |
| HTML | Its own converter | As now: markdown.js | eGlu |
| JSON, XML | As text | Formatted, in a code block; the JSON formatting is developer mode's (section 4) | eGlu |
| ZIP | Each file inside | Each file inside that eGlu reads, and a list of the rest. PadCore's ZipFile reads archives already, for Safari's bookmarks | eGlu |
| YouTube | Its transcript | As now: from the site's own panel | eGlu |
| Outlook messages | `.msg` | Not planned | |

Taken from MarkItDown's design as well:

- **A file's kind from its bytes, not its name.** anydoc tells its formats by their content (a PDF's header, an RTF's opening, a ZIP's mimetype), and ImageIO and AVFoundation tell pictures and recordings.
- **Each kind a converter, with one to fall back on**: anydoc's `NeedsOcr` goes to Vision; a picture the model can't describe still goes with its text.
- **One output for all**: every converter gives HandoffCompose what a page's reading gives it, so the file has the same two halves, what eGlu says about it and what the document says.
- **Untrusted input.** MarkItDown warns that it reads with the process's rights. anydoc reads bytes in memory, never a path, and stops with `ResourceLimit` on a file built to blow up; eGlu runs it away from the main thread with a time limit, and caps an archive's size and count of files as ZipFile does.

### Where a file comes from

| From | How |
|---|---|
| The tab | A PDF, a picture, a text, JSON or XML file, or a recording WebKit shows or plays. The bytes through `WKWebView.startDownload(using:)`, with the space's own store and cookies; a `file:` address read as it is |
| A link | "Hand Off Linked File" in a link's menu, for a document WebKit would download: fetched the same way, never opened |
| Downloads | Hand Off on a file in the downloads list |
| A drop | A file dropped on the Handoff sheet |
| The page's own pictures | The largest pictures with no description, read and described, a few at most, within the time the model has now (`HandoffJob.patience`, 8 seconds) |

### What the file says of itself

As a page's does now (Handoff.document), with what each kind adds:

- Its kind and size: 12 pages, 3 sheets, 24 slides, 4 minutes of sound.
- What is in it and what is not: a long document is cut at `Handoff.limit` (100,000 characters) and says where; a large sheet goes as its first rows and says how many there are.
- What was read from pictures and what was transcribed, so the assistant knows which words may be wrong.
- What could not be read: a table, an encrypted file, a part that was missing.
- A document's comments and tracked changes: whether anydoc gives them is to be checked; where it does, the file names them as such.

Apple Intelligence tells the kind and writes the summary as for a page, with kinds of document added: paper, contract, invoice, manual, slides, spreadsheet, photo, screenshot, recording.

### Plan

| Phase | What | Size |
|---|---|---|
| 1 | anydoc in `Engines/` beside Harper, its Swift wrapper; PDFs in the tab, with Vision for scanned pages | M |
| 2 | Linked and downloaded documents, a dropped file; Office, OpenDocument, RTF, EPUB, CSV | M |
| 3 | Pictures: a picture in the tab or a file, and a page's pictures with no description | M |
| 4 | Recordings: transcripts made on the device | M |
| 5 | JSON, XML, ZIP; kinds of document for the model | S |
| 6 | iPad and iPhone, which have every engine above | S |

Tests: a corpus of each kind in `Tests/handoff`, the files written compared with what they should be, as the page's are.

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
2. **`Engines/` and checking in pages** (1, phases 1 to 3), with the onboarding question.
3. **Enhanced Handoff** (3): anydoc goes into `Engines/` beside Harper, so it follows at once.
4. **Checking in other apps** (2).
5. **The measuring tool built in** (5 B).
6. **iPad and iPhone**: checking in pages, Enhanced Handoff, developer mode's part, the measuring tool.

## Decisions

Taken on 2026-10-25:

1. Apple's frameworks only, kept, with two engines in Rust the one exception: Harper, and anydoc (with its pdf-inspector).
2. Harper's rules and UI built into eGlu, in pages and in other apps.
3. Off by default, asked at onboarding.
4. A setting for developer tools' keys, ⌃⌥ or ⌥⌘.
5. The iPad gets what it can support.
6. GenOffice and the motion tool not planned.
7. Handoff extended to documents, pictures and recordings, with MarkItDown as the reference.

None left.

## Sources

- [Automattic/harper](https://github.com/Automattic/harper), [taehee-pd/harperSwift](https://github.com/taehee-pd/harperSwift) and its [pull request 4](https://github.com/taehee-pd/harperSwift/pull/4); measured in its source at the time of writing
- [firecrawl/anydoc](https://github.com/firecrawl/anydoc) and its [Cargo.toml](https://github.com/firecrawl/anydoc/blob/main/Cargo.toml); [firecrawl/pdf-inspector](https://github.com/firecrawl/pdf-inspector)
- [microsoft/markitdown](https://github.com/microsoft/markitdown)
- [Arc's Developer Mode](https://resources.arc.net/hc/en-us/articles/20468488031511), [Drew Lyton on Arc for web development](https://www.drewlyton.com/story/this-is-the-best-browser-for-web-development-post/)
- [ibelick/mesurer](https://github.com/ibelick/mesurer), [Mesurer on the Chrome Web Store](https://www.chromeboard.com/extension/mesurer-icmjafcffhpcnadkmmklegommbcekcac)
