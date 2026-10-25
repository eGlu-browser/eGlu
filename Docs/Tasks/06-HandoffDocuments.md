# Task 06: Enhanced Handoff: PDFs and documents

| | |
|---|---|
| Needs first | Task 01 (`Engines`, with `Documents`) merged |
| Unblocks | Task 07 (pictures and recordings), after this task's step 1 is merged |
| Size | L (one to two months) |
| Platforms | Mac, iPad and iPhone |
| Pull requests | Four, in order: (1) sources and documents in PadCore; (2) PDFs in the tab; (3) links, downloads and a chosen file; (4) text, JSON, XML, CSV and ZIP |

## Goal

Handoff gives an assistant app the page on screen as a Markdown file. Today a PDF goes as its address only, and a Word file or a spreadsheet can't go at all. After this task, Handoff also gives:

- **a PDF** in the tab, with its headings, lists, tables and columns in reading order; pages that are only pictures read on the device by Vision;
- **a document** from a link, the Downloads list, or a file the person chooses or drops: Word, PowerPoint (with speaker notes), Excel (each sheet a table), OpenDocument, RTF, EPUB, CSV;
- **a text, JSON or XML file** in the tab, formatted;
- **a ZIP archive**: each file inside that eGlu reads, and a list of the rest.

Each file is the same kind of Handoff file as a page's, saying what eGlu read and what it could not. Microsoft's [MarkItDown](https://github.com/microsoft/markitdown) (MIT, Python) is the reference for which kinds of file to read and what to keep of each; eGlu uses none of its code.

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

### Handoff today

**The flow on the Mac.**
- Ways in: File › "Handoff Page…" (`Mac/Sources/Menus.swift:52-55`), the "Send to App" tile (`Mac/Sources/PageActions.swift:33-37`), the command bar (`Mac/Sources/CommandBar.swift:179`), `WindowModel.perform(.handoff)` (`Mac/Sources/WindowModel.swift:911`).
- `startHandoff()` (`WindowModel.swift:813-824`) checks `canHandoff` (`:805-808`), makes `HandoffJob`, and publishes it (`:103, 822`).
- `HandoffPanel` (`PageActions.swift:257-305`) wraps `HandoffGuide`, as an overlay at the bottom trailing corner (`Mac/Sources/BrowserView.swift:246-253`).
- `shareHandoff(from:)` (`WindowModel.swift:828-837`) gives `[job.file, job.prompt]` to an `NSSharingServicePicker` (`PageActions.swift:201-220`); an app picked calls `job.give()` then `endHandoff(taken: true)` (`:840-844`).
- In a DEBUG build, `-showing handoff` opens straight into it (`WindowModel.swift:165-167`).

**The flow on iOS.**
- ⌃⌥H from the Go menu (`App/Sources/Menus.swift:191, 243-246`), `perform(.handoff)` (`App/Sources/Browser.swift:2123`), or the page menu's "Send to App" (`App/Sources/Bars.swift:357-359`).
- `handoff()` (`Browser.swift:2606-2624`) needs `presentedViewController == nil` (also `explain`, `:2640`, and `share`, `:2679`): **a Handoff started from a presented sheet (Downloads) fails unless the sheet is dismissed first.**
- `explain()` (`:2639-2675`) presents `HandoffGuide` as a form sheet. Its button calls `share(job)` (`:2627-2634`), a `UIActivityViewController` with `[HandoffFile(job), prompt]` (`:2678-2703`).

**The job** (`Shared/HandingOff.swift:28-299`).
- `HandoffJob` (`init(page:url:title:mind:)`, `:83-102`) **is tied to `Page`**: `draft` calls `page.readingForHandoff`, and `organise` uses `page.adapter`, `page.transcript` and a picture of the page.
- Stages (PadCore `HandoffStage.swift:19-129`): `reading` → `organising(counted:)` → `ready(kind)`, or `wordsOnly`, `addressOnly`, `failed(.reading | .writing)`, `stopped`.
- `draft` (`:154-203`) maps the outcome (`:160-169`), tells the kind by counting (`Handoff.kind(of:url:)`), composes, writes the document and the file (`:171-173`), skips the model under 300 characters (`Handoff.leastToSum`, `:182`), and gives the model `patience` (8 s) or `longPatience` (14 s) (`:73-76`, `:195-202`).
- `organise` (`:214-256`) asks the model, and a site's transcript, at once; a picture of the page when there is little text (`:222-228`); then writes the file again unless it was already given (`:243-247`).
- The file: `temporaryDirectory/Handoff/<UUID>/<Handoff.fileName>.md` (`:66, 87-88`); older folders not in use are emptied (`:265-282`); `finish(taken:)` removes it if no app took it (`:126-139`).
- `HandoffGuide` (`:349-472`), with words that speak of a page (`:501-524`). `HandoffFile` (`:310-326`) gives the file only once an app is picked.
- Gating: `Preferences.handoff` (off by default, `PadCore/Sources/PadCore/Preferences.swift:74`); `Session.hasIntelligence` (Mac `Mac/Sources/Session.swift:31-34`; iOS `App/Sources/Session.swift:40-47`); `canHandoff` (iOS `Browser.swift:878`; Mac `WindowModel.swift:805-808`).

**What a page's reading is** (PadCore).
- `ReadOutcome` (`HandoffStage.swift:13-15`): `content(PageReading)`, `noReadableContent`, `protectedPage`, `failed`.
- `Shared/PageShared.swift:166-175`, `readingForHandoff`: **a PDF or a picture answers `.noReadableContent` (`:168`)**, which becomes `.wordsOnly`; otherwise `markdown.js` in `Page.world`.
- `PageReading` (`PageReading.swift:188-196`): `blocks`, `facts`, `things`, `focus`, `truncated`, `spoken`; public init at `:201`.
- `PageBlock` (`:18-54`, init at `:56`): kind, level, text, characters, plain, links, linked, hint, group, item, onScreen, selected, start, link, note, wide.
- `PageFacts` (`PageKind.swift:46-160`): filled by `markdown.js` today; nothing makes it from blocks.
- `PageKind` (`PageKind.swift:8-27`): article, landing, app, other, product, thread, listing, media, job.
- `HandoffCompose.swift`: `Role` (`:29-38`), `Composed` (`:96-125`), `role(of:kind:page:)` (`:317-352`), `compose` (`:417-611`).
- `Handoff.document(title:url:composed:reading:summary:read:)` (`Handoff.swift:75-174`) writes "About this file" and "From the page"; "Kind of page" (`:89`); `limit = 100_000` (`:19`); `prompt(url:)` (`:25-27`); `fileName` (`:606-627`), which for an address without a host names the file "Page".

**What a new source needs to reuse `compose` and `document`.** A `PageReading` from the public inits, with blocks. A `PageFacts` filled by hand, at least `characters` (it decides the 300-character and 1,500-character thresholds), `long`, `written`, `links`, `linked`, `headings`, and `description` and `titled` where known. `truncated`. A URL for "Source:" and the prompt. A `PageKind`.

**Tests.**
- `Tests/handoff/`: for 12 kinds of page (article, landing, app, product, thread, listing, media, job, selection, story, launch, casestudy), a `<name>.html`, its `<name>.reading.json`, and the expected `<name>.md`; also `media.transcript.md` and `landing.model.md`.
- `PadCore/Tests/PadCoreTests/HandoffComposeTests.swift` reads them through `#filePath` (`:1157-1176`) and compares with the `.md` files. `HANDOFF_WRITE=1` writes them again (`:1178-1193`). The read time is fixed at `1_791_936_753` (`:1169`).
- Also `HandoffTests.swift`, `HandoffStageTests.swift`, `HandoffFailureTests.swift`.

### Where files come from today

- **The tab's type:** `mimeType` (Mac `Mac/Sources/Page.swift:111`, set at `:951`; iOS `App/Sources/Page.swift:116`, set at `:1364-1368`). It is set before the download decision, so a response that became a download overwrites it too.
- **Downloads.** Engine: `Shared/DownloadActivity.swift`. Finished files: on the Mac in `~/Downloads` (`:168`); on iOS in `Session.folder/Downloads/Files/<id>/` (`:171`). Index: `Downloads/activity.json`. A record: `DownloadRecord` (`PadCore/Sources/PadCore/DownloadRecord.swift:4-40`). Lists: Mac `DownloadList` (`Mac/Sources/Downloads.swift:12-57`), whose finished row has only "Show in Finder" (`:36-37`); iOS `DownloadActivityView` (`App/Sources/Downloads.swift:34-82`), whose finished row has "Save to Files…" (`:54-57`).
- **A link's menu.** Mac: `PageView.willOpenMenu` (`Mac/Sources/Page.swift:28-79`) renames WebKit's items and inserts "Open Link in Peek" after "Open Link in New Tab" (`:51-57`). iOS: `contextMenuConfigurationForElement` (`App/Sources/Page.swift:1530-1561`) and `linkMenu(for:suggested:)` (`:1584-1611`).
- **Dropping files:** nowhere in the app.
- **Opening a file from Finder:** the Mac opens `.html` and `.xhtml` (`Mac/Info.plist:37-50`), with security-scoped access (`Mac/Sources/Session.swift:471-506`).
- **ZIP:** `PadCore/Sources/PadCore/ZipFile.swift`: `isArchive`, `names(in:)`, `file(in:matching:)` (first match only); stored and deflated entries, each up to 64 MiB, no encryption, no ZIP64; **no limit on the count of files or their total size**.

### The engines (task 01)

`import Engines`:
- `Documents.detect(_ data: Data) -> DocumentFormat?`
- `Documents.markdown(_ data: Data, format: DocumentFormat?) throws -> String`
- `Documents.pdfPages(_ data: Data, pages: [Int]?) throws -> PDFPages` (each page's Markdown and `needsOCR`, the page count, title, author, created, pages with tables and columns)
- `EngineError.kind`: `needsOCR`, `unsupported`, `malformed`, `encrypted`, `resourceLimit`, `missingPart`, `io`, `panic`, `tooLarge`

These are synchronous: call them off the main actor.

## Decided

1. **A file is a source like a page.** `HandoffJob` takes a source instead of a `Page`; the page is one kind of source, a document another. Everything after the reading (compose, document, the file, the model, the guide, the share sheet) stays one path.
2. **Documents become `PageReading`.** The engines' Markdown is turned into blocks and facts in PadCore, so `HandoffCompose` and `Handoff.document` work unchanged in what they do, and documents are tested on Linux like pages.
3. **New kinds of page**, told by the file's format, never counted and never asked of the model: `document` (Word, OpenDocument text, RTF, EPUB, PDF), `slides` (PowerPoint, OpenDocument presentation), `spreadsheet` (Excel, OpenDocument spreadsheet, CSV), `data` (JSON, XML), `archive` (ZIP). In `role(of:kind:page:)` every part of these is core, as for an article.
4. **"About this file" for a file** says "Kind of file" instead of "Kind of page", with the format's name and its size: "Word document, 12 pages", "Excel workbook, 3 sheets", "PowerPoint presentation, 24 slides", "PDF, 37 pages, 5 read from pictures of them".
5. **Fetching** a PDF in the tab or a linked file goes through the tab's own web view, `WKWebView.startDownload(using:)`, so the space's sign-ins come with it, into the job's folder, with a delegate of Handoff's own (not the Downloads list). Code never reads cookies (PolicyTests).
6. **Limits:** a file over 200 MB is not read ("Too large to read: 340 MB"); a PDF's first 300 pages at most; Vision for at most the first 30 pages that need it; an archive's first 20 files and 50 MB unpacked; the Handoff file cut at `Handoff.limit` at a page, sheet or slide boundary, saying where.
7. **OCR** is Vision's, on the device: `RecognizeDocumentsRequest` on macOS and iOS 26 (paragraphs, lists, tables), `VNRecognizeTextRequest` (accurate) before 26; a page drawn with PDFKit at 2× for it.
8. **The prompt for a local file** says `File: <name>` instead of `URL: <address>`; a fetched file keeps its URL.
9. **Text people see**: new strings through the String Catalog, in the guide's existing style.

## Pull request 1: sources and documents in PadCore, and the job

### 1.1 Markdown to a reading (PadCore)

`PadCore/Sources/PadCore/HandoffDocument.swift`:

```swift
public enum FileFormat: String, Sendable, CaseIterable {
    case pdf, word, openText, rtf, epub, powerPoint, openPresentation, excel, openSpreadsheet, csv, json, xml, text, zip
    public var kind: PageKind { ... }           // Decided 3
    public var name: String { ... }             // "PDF", "Word document", "Excel workbook", … (BrowserText.localized)
}

public struct FileFacts: Equatable, Sendable {
    public var format: FileFormat
    public var name: String                     // the file's name, without its folder
    public var bytes: Int
    public var pages: Int?                      // PDF, Word if known
    public var sheets: Int?
    public var slides: Int?
    public var readFromPictures: [Int] = []     // 1-based pages
    public var notRead: [Int] = []              // pages past the limits
    public var title: String?
    public var author: String?
    public var created: String?
    public var entries: [String] = []           // an archive's files, as named in it
    public var skipped: [String] = []           // an archive's files not read, with why
}

public enum HandoffDocument {
    /// The engines' Markdown as a reading: one block per paragraph, heading,
    /// list item, table row and code block, with the facts compose and
    /// document read.
    public static func reading(markdown: String, facts: FileFacts) -> PageReading
}
```

`reading(markdown:facts:)`:

- Splits GitHub-Flavored Markdown into blocks: `#`…`######` headings (kind heading, level), paragraphs, list items (with `group` and `item` as `markdown.js` sets them; read its `group`/`item` handling), table rows (one block per row, the header row first, `hint` none), fenced code blocks (kind code), quotes. Read how `markdown.js` fills `PageBlock` and match it, so compose treats a document's parts as a page's.
- Fills `PageFacts`: `characters` (all text), `headings`, `long` and `written` as `markdown.js` computes them for prose, `links` and `linked`, `titled` from the first heading or `facts.title`, `description` none.
- `truncated` when the text was cut.

Tests (`PadCore/Tests/PadCoreTests/HandoffDocumentTests.swift`, Swift Testing): headings and levels; a list's group and items; a table's rows; a code block kept whole; facts' `characters`.

### 1.2 New kinds, and what a file's document says (PadCore)

- `PageKind`: add `document`, `slides`, `spreadsheet`, `data`, `archive`. The compiler will point to each `switch` over it: in `HandoffStage` (its words per kind, `:84-128`), `HandoffCompose.role` (every part core for these, `:317-352`), `PageKind.name`, the briefs (`PageKind.swift:510-562`). These kinds are never in `builtKindsInUse` (`:371`) nor offered to the model.
- `Handoff.document(...)`: a new optional argument `file: FileFacts?`. With it, the first half says "Kind of file: <name>, <counts>" (Decided 4) instead of "Kind of page", and, where they apply: "Read from pictures of the pages, on this device: pages 3, 4 and 9. Their words may be wrong in places."; "Not in this file: pages 301 to 412."; "In the archive, not read: <names> (<why>)."; "From the file: its title …, by …, made …" under "From the page" (call it "From the file").
- `Handoff.prompt(file name:)`: `"File: <name>\nQuestion: "` (Decided 8).
- `Handoff.fileName` for a file: the file's own name without its extension, cleaned as now.

Tests: fixtures in `Tests/handoff/` of a new form, `<name>.source.md` (what the engine gives) with `<name>.file.json` (the `FileFacts`), and the expected `<name>.md`; `HandoffComposeTests` reads them like the pages' (`#filePath`, `HANDOFF_WRITE`). Make four: `report` (a Word document with headings, a list and a table), `deck` (slides with notes), `budget` (two sheets), `scan` (a PDF with two pages read from pictures and one past the limit). Write the `.source.md` by hand in the shape anydoc gives (headings, lists, GitHub tables, `$…$`), or from task 01's fixtures.

### 1.3 The source (Shared)

`Shared/HandoffSource.swift`:

```swift
@MainActor
protocol HandoffSource: AnyObject {
    var address: URL? { get }        // for "Source:" and the prompt; nil for a local file
    var title: String { get }
    var file: FileFacts? { get }     // nil for a page
    func reading(limit: Int) async -> Handoff.ReadOutcome
    func transcript(limit: Int) async -> Transcript?      // pages only; nil otherwise
    func picture(pixels: Int) async -> CGImage?           // the page's; nil for documents (task 07 adds pictures)
}
```

- `Page` (both apps) conforms with what `HandoffJob` calls on it today. Keep every call into the page in `Page.swift` / `PageShared.swift` (PolicyTests).
- `HandoffJob.init(source:mind:)` replaces `init(page:url:title:mind:)`; `draft` and `organise` use the source. The site's own reader (`adapter`) is asked only when the source is a `Page`.
- `DocumentSource` (`Shared/HandoffDocumentSource.swift`): made from `Data` or a file URL, a name, and optionally the address it came from. Its `reading(limit:)` detects the format (Decided 3 and the bytes: `Documents.detect`, else the name's extension for CSV, JSON, XML, text), converts off the main actor, builds `FileFacts`, and returns `.content(HandoffDocument.reading(...))`, or `.failed` with a reason the guide can say ("This file is protected by a password.", "eGlu can't read this kind of file.", "Too large to read: 340 MB.").

### 1.4 The guide's words

`HandoffGuide`'s step words (`HandingOff.swift:501-524`) say "page": give them a file's words when the source is a file ("Reading the document", "the document's text"). Keep the layout.

### 1.5 Pull request 1 done when

- [ ] Pages hand off exactly as before: every existing fixture passes unchanged.
- [ ] The four document fixtures pass.
- [ ] `HandoffJob` takes sources; both apps build.

## Pull request 2: a PDF in the tab

1. `Shared/HandoffFetch.swift`: `func fetch(_ url: URL, with view: WKWebView, into folder: URL) async throws -> URL`: `view.startDownload(using: URLRequest(url: url))`, a `WKDownloadDelegate` that names the file in `folder` (`decideDestinationUsing`), finishes or fails, and a 30-second limit. Not in the Downloads list. A `file:` URL is copied (on the Mac, with the security-scoped access `Mac/Sources/Session.swift:471-506` gives).
2. `PageShared.readingForHandoff` (`:166-175`): for `application/pdf`, instead of `.noReadableContent`, fetch the PDF into the job's folder and read it as a `DocumentSource` would (share the code), with the tab's address as `address`.
3. PDFs in `DocumentSource`:
   1. `Documents.pdfPages(data, pages: Array(0..<min(pageCount, 300)))`.
   2. Pages with `needsOCR`, at most 30: open the PDF with PDFKit (`PDFDocument(data:)`), draw each page at 2× into a `CGContext` (white background), and read it with Vision (Decided 7). From `RecognizeDocumentsRequest`'s document: paragraphs as paragraphs, lists as `- ` items, tables as GitHub tables. From `VNRecognizeTextRequest`: lines joined into paragraphs where they are close.
   3. The pages in order into one Markdown; `FileFacts` with `pages`, `readFromPictures`, `notRead`, `title`, `author`, `created`.
4. The time: a PDF's reading has its own limit of 20 seconds before the file is written with what is read by then (the rest named in "Not in this file"); the model's patience after it as now.
5. An encrypted PDF: "This PDF is protected by a password." and the address alone, as `wordsOnly` does today.

Tests: `DocumentSource` with task 01's PDF fixtures (text, and one picture page) in an app-hosted test or a DEBUG self-check (`-showing handoff` on a PDF page); the CHECKLIST items below.

## Pull request 3: links, Downloads, a chosen or dropped file

1. **A link's menu.**
   - Mac, in `willOpenMenu` (`Mac/Sources/Page.swift:28-79`), after "Open Link in Peek": "Hand Off Linked File", only when Handoff is available (`canHandoff`'s conditions) and the link's path ends in `.pdf`, `.doc`, `.docx`, `.docm`, `.ppt`, `.pptx`, `.xls`, `.xlsx`, `.xlsm`, `.odt`, `.ods`, `.odp`, `.rtf`, `.epub`, `.csv`, `.json`, `.xml`, `.txt` or `.zip`.
   - iOS, in `linkMenu(for:suggested:)` (`App/Sources/Page.swift:1584-1611`): the same item, under the same conditions.
   - It fetches the link with `HandoffFetch` through the tab's view, then starts a job with a `DocumentSource` (its `address` the link).
2. **Downloads.**
   - Mac `DownloadList` (`Mac/Sources/Downloads.swift:36-37`): a "Hand Off" button beside "Show in Finder" on a finished row whose file is a kind `DocumentSource` reads; it starts a job with the file.
   - iOS `DownloadActivityView` (`App/Sources/Downloads.swift:54-57`): the same beside "Save to Files…". It dismisses the Downloads sheet first, then starts the job (`handoff()` needs nothing presented, `Browser.swift:2606-2624`).
3. **A chosen or dropped file.**
   - The guide gets a "Choose File…" button when no job is reading: Mac `NSOpenPanel` for the kinds above; iOS `.fileImporter`.
   - Mac: `HandoffPanel` (`PageActions.swift:257-305`) takes a dropped file (`.onDrop(of: [.fileURL])`), and the panel shows on File › "Hand Off File…" (a menu item, no key) for that.
   - Either starts a job with a `DocumentSource` for the file (`address` nil, Decided 8).
4. The job's file names itself from the document (`Handoff.fileName`).

## Pull request 4: text, JSON, XML, CSV and ZIP

1. **In the tab:** for `text/plain`, `application/json` (and `+json`), `application/xml`, `text/xml` (and `+xml`), `text/csv`: read as a `DocumentSource` of the tab's text (fetched with `HandoffFetch` from the tab's address), not with `markdown.js`. JSON: parsed with `JSONSerialization` and written back with `.prettyPrinted` and `.sortedKeys` in a ```` ```json ```` block (raw if it does not parse); XML in a ```` ```xml ```` block as it is; CSV through `Documents.markdown(data, format: .csv)`; text as it is.
2. **ZIP** (from a link, a download or a chosen file): `ZipFile.names`; for each file (not folders, not links, not `__MACOSX/`), in order, up to 20 files and 50 MB unpacked in all (Decided 6): unpack it (`ZipFile.file(in:matching:)` with its exact name), read it as its kind, and add it under a heading with its name; the others go in `FileFacts.skipped` with why ("not a kind eGlu reads", "past the first 20 files", "too large"). Encrypted or ZIP64 archives: "eGlu can't open this archive."
3. Tests: PadCore tests for the JSON formatting and the ZIP walk (with small archives made in the test with `ZipFile`'s format, or committed fixtures), and fixtures for a JSON file and an archive in `Tests/handoff/`.

## Tests, all pull requests

- `cd PadCore && swift test`: all pass, the existing Handoff fixtures unchanged.
- By hand, a new section in `Validation/CHECKLIST.md`, "Enhanced Handoff: documents", on a Mac and an iPad:
  - A text PDF (a paper with two columns and a table) in the tab: headings, columns in order, the table.
  - A scanned PDF: its pages read, and the file says they were read from pictures.
  - A PDF behind a sign-in (for example a bank statement or a course's PDF): fetched with the sign-in.
  - Links to a `.docx`, an `.xlsx` and a `.pptx`: "Hand Off Linked File" in the link's menu; speaker notes and each sheet are in the file.
  - Downloads: "Hand Off" on a finished `.docx`.
  - A chosen file and, on the Mac, a dropped one.
  - A JSON address (`https://api.github.com/repos/eGlu-dot-apps/eGlu`): formatted.
  - A ZIP with a PDF, a `.docx` and a picture: the first two read, the picture named as not read (task 07 reads pictures).
  - A password-protected PDF and a 300 MB file: the guide says why, and the address goes alone.

## Done when

- [ ] All four pull requests merged; tests pass; no new warnings.
- [ ] Pages hand off exactly as before.
- [ ] The CHECKLIST section run once on a Mac and an iPad, results written under it.
- [ ] CHANGELOG under `### Added`: "Handoff gives an assistant PDFs, with pages that are pictures read on your device, and Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV, JSON and ZIP files: from the tab, a link's menu (Hand Off Linked File), Downloads, or a file you choose."
- [ ] README's Handoff paragraph (`README.md`, "And more") and PRIVACY.md's Handoff row (what the file holds, where it is kept) say it.

## Out of scope

- Pictures and recordings, and a page's pictures with no description: task 07.
- Outlook `.msg` files.
- Opening Office files in a tab to look at them.
- A keyboard shortcut for Handoff on the Mac (⌃⌥H is in the commands table but not bound on the Mac).
