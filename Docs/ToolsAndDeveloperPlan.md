# Plan: writing, in-app tools and developer features

Seven ideas for eGlu, each judged for how feasible it is and planned. Mac first; where the iPad gets it too, the section says so. Written 2026-10-25 from the projects' own pages and eGlu's code at Build 38.

Sizes are rough, for one developer: **S** up to a week, **M** two to four weeks, **L** one to two months, **XL** three months or more.

## Summary

| # | Idea | Feasible | Size | Recommendation |
|---|---|---|---|---|
| 1 | Harper grammar checking in the browser | Yes | L | Build it, with the engine as a Swift package shared with harperSwift |
| 1b | Harper outside the browser | Yes | S | Leave it to Harper Desktop, and have the two apps agree on who checks eGlu |
| 2 | In-app tools in HTML5, UI from Toolcraft | Yes | M, then per tool | Build the tool platform once; use Toolcraft where a tool is a canvas |
| 2.1 | GenOffice as the PDF viewer and office tools | Poorly | XL, and a fork to keep | Not now. Native PDF mark-up and Quick Look for office files instead |
| 2.2 | Handoff for PDFs with pdf-inspector | Yes | M | Build it: today a PDF goes as its address only |
| 2.3 | Motion tool on HyperFrames | Yes, with a native renderer | L for a player and renderer, XL for an editor | Player and renderer first, editor later |
| 3.1 | Arc's developer mode for localhost | Yes | M | Build it |
| 3.2 | Mesurer | Yes | S as an extension, M built in | Try its Chrome extension now; build it in with developer mode |

## 0. What every idea runs into

eGlu's rules (CONTRIBUTING.md) decide more than the code does here.

| Rule | Which ideas break or bend it | Proposal |
|---|---|---|
| No dependencies beyond Apple's frameworks | All of them: Harper (Rust), Toolcraft (React), GenOffice, pdf-inspector (Rust), HyperFrames (TypeScript), Mesurer (React). Sparkle, in eGlu Mac Direct only, is the one exception so far | Amend it: "Apple's frameworks, plus open-source code that is pinned to a version, built from source in this repository or from a release with a checksum, credited in the README, and never loads anything from the network" |
| Nothing leaves the device | GenOffice's AI features (Genspark's servers or the person's own key) and its analytics, on by default in its official builds | Everything else here runs on the device. GenOffice's AI and analytics would have to go |
| The page gets the input | Harper's accept key, Mesurer's Option key, developer shortcuts | Browser keys stay on ⌃⌥. Free there today: C, E, G, I, J, M (Commands.swift:211). A tool that takes keys from the page does so only while the person has turned it on |
| Hands off Google's sign-in | Every script that goes into pages (Harper, Mesurer, element screenshots) | Each one checks HandsOff, as Page.call does |

The Mac app is a Developer ID DMG outside the App Sandbox (Config/eGluMac.entitlements), so it may use WebKit's private API where a `responds(to:)` check guards it, as picture in picture already does (Mac/Sources/Page.swift:250). Developer mode needs that.

## 1. Harper grammar checking

### What there is to start from

- [Harper](https://github.com/Automattic/harper): an English grammar checker in Rust (`harper-core`), Apache-2.0, entirely offline. English only: US, UK, Australian and Canadian.
- [harperSwift](https://github.com/taehee-pd/harperSwift): Harper Desktop for macOS. Tauri hosts the app; Settings, setup and the editor are SwiftUI (`harper-desktop/macos-popup`), and the suggestion popup is a SwiftUI panel in Liquid Glass. It checks other apps' text through the Accessibility API, converts between Accessibility's UTF-16 offsets and Harper's character spans (`text_selection.rs`), and accepts a suggestion with ⌃⌘Y.
- [hippietrail/harper-swift](https://github.com/hippietrail/harper-swift): a minimal C bridge from `harper-core` to Swift (MIT). A proof that the bridge is small, not something to depend on.

### In the browser, as eGlu's own

1. **The engine, once, for both apps.** A Swift package, `HarperKit`, in the harperSwift repository: `harper-core` behind a C interface, built into an XCFramework (arm64 and x86_64 for the Mac, an iOS slice later), with a Swift wrapper (`lint(text:dialect:) -> [Lint]`). eGlu takes it as a `binaryTarget` with a URL and checksum, pinned as Sparkle is. Harper Desktop moves to the same package, so both apps check the same way.
2. **A script in eGlu's own world** (`writing.js`, in `Page.world`): it watches the field with the focus: `textarea`, text `input`s and `contenteditable`. Never a password or card field, a field with `spellcheck="false"`, a code editor (CodeMirror, Monaco, Ace, found by their classes), or a hands-off host.
3. **Checking.** After a pause in typing (about 300 ms), the field's text goes to the app through a message handler that answers (`WKScriptMessageHandlerWithReply`). Harper runs away from the main thread; lints come back as UTF-16 ranges, which is what JavaScript counts in. Paragraphs that are not English (NaturalLanguage's `NLLanguageRecognizer`) are skipped, so Korean is not flagged.
4. **Underlines.** Drawn in a closed shadow root over the page, never in the page's own text: placed with `Range.getClientRects()` in `contenteditable`, and with a mirror element for `textarea` and `input`. Placed again on scroll, resize and input.
5. **Suggestions.** A native panel at the underline, the one harperSwift already has (`macos-popup`), with the page keeping the focus. Choosing one selects the range and calls `document.execCommand("insertText")`, so the page's undo works and React, ProseMirror and Slate see an ordinary input. The key to accept the first suggestion is ⌃⌥G, not ⌃⌘Y.
6. **Settings › Writing.** On or off, the dialect, rules, a personal dictionary, a site's own switch (as Settings › Link menu has), and "Harper Desktop checks eGlu instead".
7. **Later.** Harper Desktop's Clarity suggestions use Apple's on-device model, which eGlu already uses (Shared/Intelligence.swift). The iPad can have the same script and engine.

**What will not work:** editors that draw their own text (Google Docs, Figma's canvas), and text in a frame from another site that the script is not let into. Hard but possible: rich editors that rebuild their DOM on every key (Notion, Slack); these are tested one by one, and a site that fights the overlay goes in the site list.

**macOS's own spell check** underlines in web views too. With Harper on, the two would underline the same word, so eGlu turns WebKit's continuous spell checking off in pages while Harper checks them (to be tried: `toggleContinuousSpellChecking:` on the web view).

### Outside the browser

| Option | How | Size | Verdict |
|---|---|---|---|
| A. Harper Desktop does it | eGlu's Settings points to Harper Desktop. Harper Desktop leaves eGlu (`net.taehee.safience`) alone while eGlu's own checking is on, so no field is underlined twice. One personal dictionary, in a place both read | S | **Recommended.** You keep both apps, so this is two small changes, one in each |
| B. eGlu carries a helper | Harper Desktop's highlighter as a login item inside eGlu.app (`SMAppService`), with its own Accessibility permission | L | No. Two copies of one app to keep, and a browser that asks for Accessibility is a large ask of trust |
| C. A system spelling service | Harper as an `NSSpellServer`, chosen in System Settings › Keyboard › Text Input › Spelling, which every Cocoa text view, WKWebView among them, asks | M, uncertain | A short trial only. macOS shows grammar as a plain underline and a menu item, and third-party spelling services are rare on recent macOS |

### Plan

| Phase | What | Size |
|---|---|---|
| 1 | `HarperKit` in harperSwift: C interface, XCFramework, Swift wrapper, tests; Harper Desktop moved to it | M |
| 2 | `writing.js` for `textarea` and `input`, underlines, panel, ⌃⌥G, Settings › Writing | M |
| 3 | `contenteditable`, the site list, tests on Gmail, Slack, Notion, Linear, GitHub | M |
| 4 | Harper Desktop and eGlu agree on who checks (option A), one dictionary | S |
| 5 | iPad; Clarity suggestions | M |

## 2. In-app tools in HTML5, with Toolcraft's UI

### What Toolcraft is

[Toolcraft](https://github.com/pixel-point/toolcraft), by Pixel Point, MIT: a starter kit for design apps, in TypeScript and React with TanStack Router, Tailwind and Base UI. It brings a canvas with pan and zoom, layers, timelines, and image and video export. It is not a package: `npx @pixel-point/toolcraft create` copies its source into a folder, to be changed as one likes. Young (24 commits, no releases yet).

### How a tool would live in eGlu

eGlu has no page of its own made in HTML today: no `WKURLSchemeHandler` anywhere. The platform is built once:

1. **An address of their own**, `eglu-tool://motion/`, served from the app's bundle by a scheme handler, which also sets the headers a tool needs (a Content-Security-Policy with no network, and COOP and COEP where a tool needs `SharedArrayBuffer`).
2. **A tool is a tab**, with its own data store, never a space's cookies, so a tool can't read a site's sign-in and a site can't read a tool.
3. **A narrow bridge**, in a content world of the tools' own: open a file (an open panel), save one (a save panel), the current tab's PDF, render a video natively (section 2.3), the share sheet. Nothing else.
4. **The source in the repository** (`Tools/`), built with npm, and the built files committed, as the filter lists are, so that building eGlu still needs nothing but Xcode. A check that the built files match the source.
5. **The look.** Toolcraft's Tailwind colours mapped to eGlu's (Design.swift) and the system font, so a tool reads as eGlu's. The window's bars stay SwiftUI; the HTML is only the tool's own area.

To try first: whether WebKit counts a custom scheme as a secure context (WASM, the clipboard and `crypto.subtle` need one).

### Where Toolcraft fits

| Tool | Fit | Why |
|---|---|---|
| Motion (2.3) | Good | It is a canvas with layers and a timeline, which Toolcraft has |
| PDF mark-up | Poor | PDFKit draws PDFs and their annotations natively (2.1) |
| Office (2.1) | None | GenOffice brings its own editors and UI |

### 2.1 GenOffice as the PDF viewer and office tools

[GenOffice](https://github.com/genspark-ai/genoffice), Apache-2.0 apart from `ee/` (an enterprise licence) and its names and logos (trademarks). Electron apps on TypeScript engines: Tiptap for documents, Univer for sheets, Konva for slides, pdf.js, pdf-lib and PDFium (through `@embedpdf/pdfium`) for PDFs, and a Rust sidecar for `.xlsx` (calamine, IronCalc). It edits locally; its AI needs a Genspark sign-in or the person's own key; its official builds send analytics by default. About 1,000 commits and in active development.

**Why embedding it costs so much:**

- It is an app, not a library: its editors would have to be taken out of Electron and given eGlu's bridge in place of Node's files and Electron's messages.
- The `.xlsx` sidecar is a separate Rust program: it would need building to WASM or into the app.
- Its AI and analytics would have to go, and its name and logo with them.
- Univer, PDFium and fonts make it tens of megabytes at least.
- Every upstream release would have to be merged into the fork, at the pace of a project with 30 open pull requests.

**"Default PDF viewer" is already WebKit's**, which draws a PDF in a tab natively, with selection, Look Up and VoiceOver. A web viewer in its place would be slower and lose those.

**Instead:**

| What | How | Size |
|---|---|---|
| Mark up a PDF | A Mark Up button on a PDF tab opens it in PDFKit's `PDFView`: highlight, notes, drawing, forms, a signature, Save and Save As. Optionally, eGlu can open PDFs from Finder (`com.adobe.pdf` in Mac/Info.plist) | M |
| Look at office files | `.docx`, `.xlsx` and `.pptx` from a link or a download shown in a tab with Quick Look (`QLPreviewView`), which WebKit on the Mac does not do | S |
| Edit office files | "Open in GenOffice" when it is installed, else in the app the Mac opens the file with | S |
| Embed GenOffice | Only if people ask to edit office files in the browser, and then its document editor alone first | XL |

### 2.2 Handoff for PDFs, with pdf-inspector

**Today a PDF goes as its address only.** `readingForHandoff` answers `.noReadableContent` for `application/pdf` (Shared/PageShared.swift:168), and the handoff becomes `.wordsOnly` (Shared/HandingOff.swift:162, PadCore/Sources/PadCore/HandoffStage.swift:27). For an assistant, a paper or a contract in a tab is the page it most needs the text of.

[pdf-inspector](https://github.com/firecrawl/pdf-inspector), by Firecrawl, MIT, in Rust: it tells whether a PDF has text or is scanned (by page, with the pages that need OCR listed), and turns text PDFs into Markdown with headings, lists, tables, columns in reading order, bold, italic and links, in under 200 ms. It comes as a crate, a CLI, Python and Node packages, and WebAssembly for browsers. Without OCR by default.

**How:**

1. **The PDF's bytes.** `WKWebView.startDownload(using:)` with the tab's address fetches it through the space's own store, with its cookies, into the handoff's folder; a `file:` PDF is read as it is.
2. **Reading it.** Three ways:

| Way | For | Against |
|---|---|---|
| A. WASM in an off-screen web view (as Unseen loads a page out of sight, Shared/PageShared.swift:24) | No native code and no Rust in the build; the iPad gets it too | Slower than native, still well under a second |
| B. The Rust crate in an XCFramework | Fastest | A native library to build and pin for each platform |
| C. PDFKit and Vision alone | No dependency at all | Its tables and reading order are unknown until measured |

   **A** first. Pages pdf-inspector names as scanned go to Vision's document recognition on the device (`RecognizeDocumentsRequest`, macOS and iOS 26), so a scan is read too and nothing leaves the Mac.
3. **The file.** The Markdown goes through HandoffCompose as a page's does, with what the file says of itself: how many pages there are, which pages are in it (a long PDF is cut at `Handoff.limit`, 100,000 characters), which were read by OCR, and tables that could not be read.
4. Apple Intelligence tells the kind and writes the summary as for any page; a PDF's kinds are new ones to add (paper, contract, invoice, manual, slides).

| Phase | What | Size |
|---|---|---|
| 1 | Bytes, pdf-inspector in WASM, Markdown into HandoffCompose, the file's notes, tests with PDFs in `Tests/handoff` | M |
| 2 | Vision for scanned pages; a PDF's kinds | S |
| 3 | The iPad | S |

### 2.3 A motion tool on HyperFrames

The X post linked could not be opened (X asks to sign in), so this section works from HyperFrames alone. What the post shows may change it.

[HyperFrames](https://github.com/heygen-com/hyperframes), by HeyGen, Apache-2.0: a video is an HTML file, with timing in data attributes, animated with GSAP, CSS, the Web Animations API, Lottie, Three.js or Anime.js through adapters that can seek. An `index.html` plays in a browser as it is. To make an MP4, its renderer seeks each frame in headless Chrome (Puppeteer) and encodes with FFmpeg, which needs Node 22. It has an embeddable player, a Studio editor ("available, evolving") and skills that teach coding agents to write compositions.

**Node, Chrome and FFmpeg can't go in the app, and needn't:** WebKit and AVFoundation do the same job.

1. **Open a composition**: a folder with an `index.html`, from Finder, a drop, or a file an assistant wrote. It plays in a tool tab (section 2) with a scrubber, using HyperFrames' runtime and adapters, which are browser code.
2. **Render it natively**: an off-screen web view at the composition's size; for each frame, seek through the runtime, wait for fonts, pictures and video to settle, `takeSnapshot`, and hand the picture to `AVAssetWriter` (H.264 or HEVC, ProRes 4444 for a clear background). Audio from the composition's audio and video elements, mixed with `AVMutableComposition`. About a minute for 30 seconds of 1080p at 30 frames a second, to be measured.
3. **Then an editor**, with Toolcraft's canvas, layers and timeline, writing HyperFrames' HTML, so a composition stays one an agent can read and change.

This fits Handoff the other way round: an assistant writes the composition (HyperFrames' skills), and eGlu plays it and renders it, on the Mac.

**Risks.** WebKit draws some things differently from Chrome (fonts, filters, shaders), so a composition made for HyperFrames' renderer can look different. Animation driven by `requestAnimationFrame` that can't seek renders wrong. Whether `takeSnapshot` includes WebGL needs a trial. A `<video>` element seeks slowly, frame by frame.

| Phase | What | Size |
|---|---|---|
| 1 | A trial: seek, snapshot and encode one GSAP composition and one with video; compare with HyperFrames' own render | S |
| 2 | The player, the renderer, audio, Render to MP4 | L |
| 3 | The editor, on Toolcraft | XL |

## 3. For developers

### 3.1 Arc's developer mode

Arc turns developer mode on by itself on localhost, and on any site from its menu. Then it shows the full address with its scheme, host, port and path across the top, buttons for DevTools' console, network and elements, a screenshot of the element under the pointer, and a JSON formatter it installs.

| Arc | eGlu today | How |
|---|---|---|
| On by itself for localhost | Address.swift already knows local hosts and opens them on `http:` (PadCore/Sources/PadCore/Address.swift:38) | On for `localhost`, `*.localhost`, `127.0.0.1`, `[::1]`, `*.local` and private addresses; "Turn On Developer Mode for This Site" in the site's menu and the command bar for any other |
| The full address across the top | The address shows the site | A slim bar over the page: the whole address to edit, the port standing out, the response's HTTP status |
| Console, Network, Elements buttons | Pages are inspectable (Mac/Sources/Page.swift:269), so Safari's Develop menu reaches them; nothing in eGlu opens the inspector | WebKit's private `_WKInspector` (`show`, `showConsole`, `toggleElementSelection`), behind a `responds(to:)` check. Where it is gone, the bar says to use Safari › Develop › eGlu |
| Screenshot of an element | None | The element under the pointer outlined by a script in eGlu's world; its rectangle, with some room round it, to `takeSnapshot(with:)`; to the clipboard or a file |
| A JSON formatter | None | When the main frame's type is `application/json` (Page.mimeType, Mac/Sources/Page.swift:951), a formatted, foldable view in its place, with Raw beside it. Built in, not an extension put in without asking |

eGlu's own, beyond Arc's:

- **Local servers in the command bar.** The ports this Mac listens on, with the program's name ("localhost:5173, vite"), read from the system's process list; the app is outside the sandbox, so it can. Typing "local" lists them.
- **Reload without the cache**: `reloadFromOrigin()`.
- **See it as a phone or an iPad**: the page at that size with that user agent (Identity.swift already has both).

**Keys.** ⌃⌥I the inspector, ⌃⌥J the console, ⌃⌥E an element's screenshot. Developers' hands know ⌥⌘I and ⌥⌘J; whether developer mode may take them from the page is a decision (below).

| Phase | What | Size |
|---|---|---|
| 1 | When it is on, the bar, the inspector's buttons, reload without the cache | S |
| 2 | Element screenshots, the JSON view, local servers | M |
| 3 | Phone and iPad sizes | S |

### 3.2 Mesurer

[Mesurer](https://github.com/ibelick/mesurer), by Julien Thibeaut (ibelick), MIT: measure an element's bounds, distances with Option held, gaps and padding, guides and rulers, notes and arrows, typography, colour sampling, X-ray, screenshots and short recordings, sizes side by side, and comments to copy for an agent. A React component (`npm install mesurer`), and a Chrome extension (Chrome Web Store `icmjafcffhpcnadkmmklegommbcekcac`, 0.0.8, 2026-04-16).

**A. The extension, now.** eGlu for Mac installs it from the Chrome Web Store, and its check at install (ExtensionCheck.swift) says what doesn't work. To expect: measuring, guides and notes work; colour sampling does not, since it uses Chromium's EyeDropper, which WebKit lacks; recording probably does not, since tab capture is among what nothing answers on this Mac (PadCore/Sources/PadCore/ExtensionCheck.swift:58). **S**: install it and file what fails.

**B. Built in, with developer mode.** The component built into one script, run in eGlu's world with its UI in a shadow root; turned on with a Measure button in the developer bar or ⌃⌥M, off with Esc.

- What it keeps goes to the app, not the site's `localStorage` (Mesurer takes a persistence adapter), so eGlu leaves nothing in the site's storage.
- Colour sampling with AppKit's `NSColorSampler`; screenshots with `takeSnapshot`; recordings with ScreenCaptureKit on the page's rectangle.
- While it is on, Option goes to Mesurer and not the page; that is the person's choice, for as long as they keep it on.
- The iPad can have it too, without the colour sampler.

**M.** Worth it if A shows people use it, or to have it on the iPad.

## Order

1. **Developer mode and Mesurer's extension** (3.1, 3.2 A). Mostly native, little risk, uses what eGlu already has.
2. **PDF handoff** (2.2). It fills a known gap in a feature that ships.
3. **The tool platform** (2). The motion tool needs it.
4. **Harper in the browser** (1). `HarperKit` can start at once, in harperSwift, beside 1 to 3.
5. **The motion tool's player and renderer** (2.3), after its one-week trial.
6. **PDF mark-up and Quick Look** (2.1). GenOffice only if people ask for office editing in the browser.

## Decisions

1. The rule on dependencies: amended as in section 0, or kept, with each item built natively (Harper and pdf-inspector can't be).
2. Harper outside the browser: option A (Harper Desktop), B or C.
3. Harper on by default, or off until turned on.
4. Developer mode's keys: ⌃⌥ only, or ⌥⌘I, ⌥⌘J and ⌥⌘C as well, in developer mode only.
5. The iPad: Harper, Mesurer and PDF handoff could go there too; developer mode's inspector can't (no Web Inspector in an iPad app).
6. What the X post shows, for section 2.3.

## Sources

- [Automattic/harper](https://github.com/Automattic/harper), [taehee-pd/harperSwift](https://github.com/taehee-pd/harperSwift) and its [pull request 4](https://github.com/taehee-pd/harperSwift/pull/4), [hippietrail/harper-swift](https://github.com/hippietrail/harper-swift)
- [pixel-point/toolcraft](https://github.com/pixel-point/toolcraft)
- [genspark-ai/genoffice](https://github.com/genspark-ai/genoffice)
- [firecrawl/pdf-inspector](https://github.com/firecrawl/pdf-inspector)
- [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes)
- [Arc's Developer Mode](https://resources.arc.net/hc/en-us/articles/20468488031511), [Drew Lyton on Arc for web development](https://www.drewlyton.com/story/this-is-the-best-browser-for-web-development-post/)
- [ibelick/mesurer](https://github.com/ibelick/mesurer), [Mesurer on the Chrome Web Store](https://www.chromeboard.com/extension/mesurer-icmjafcffhpcnadkmmklegommbcekcac)
