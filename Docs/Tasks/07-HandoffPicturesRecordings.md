# Task 07: Enhanced Handoff: pictures and recordings

| | |
|---|---|
| Needs first | Task 06's pull requests 1 and 2 merged (`HandoffSource`, `DocumentSource`, `FileFacts`, `HandoffDocument`, the format-told kinds, `HandoffFetch`) |
| Size | M (two to four weeks) |
| Platforms | Mac, iPad and iPhone |
| Pull requests | Three: (1) a picture as a file; (2) a page's pictures with no description; (3) recordings |

## Goal

Handoff, after task 06, gives an assistant pages, PDFs and documents. This task adds, all read on the device:

- **A picture** (in the tab, from a link, from Downloads, chosen, or in a ZIP): what text it holds (Vision), what it shows (Apple's on-device model, where it looks at pictures), and when and with what it was taken. Never where.
- **A page's large pictures that have no description**: a few of them read the same way, inside the time Handoff already takes, instead of being named as missing.
- **A recording** (an audio or video file in the tab, from a link, Downloads, or chosen): a transcript made on the device, its length and its title.

MarkItDown is the reference for what to keep of each (EXIF, text by OCR, a description, a transcript); eGlu uses none of its code, and nothing goes to a server.

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

### From task 06

- `Shared/HandoffSource.swift`: the `HandoffSource` protocol (`address`, `title`, `file`, `reading(limit:)`, `transcript(limit:)`, `picture(pixels:)`); `Page` and `DocumentSource` conform. `HandoffJob(source:mind:)`.
- `DocumentSource` (`Shared/HandoffDocumentSource.swift`): detects a file's format and reads it into a `PageReading` through `HandoffDocument.reading(markdown:facts:)` (PadCore).
- `FileFacts` and `FileFormat` (`PadCore/Sources/PadCore/HandoffDocument.swift`); `Handoff.document(..., file:)` writes "Kind of file" and the file's notes.
- `Shared/HandoffFetch.swift`: `fetch(_ url:, with view:, into folder:)` through the tab's web view (the space's sign-ins), not into Downloads.
- Vision for scanned PDF pages: `RecognizeDocumentsRequest` (macOS and iOS 26), `VNRecognizeTextRequest` before. Reuse that code for pictures.
- The entry points: the tab (by `mimeType`), "Hand Off Linked File" in a link's menu, "Hand Off" in Downloads, "Choose File…" and a drop on the Mac's Handoff panel; ZIP entries.

### Handoff today, for this task

- `HandoffJob` (`Shared/HandingOff.swift`): `draft` writes the first file; `organise` (`:214-256`) asks the on-device model and a site's transcript at once, with `patience` 8 s or `longPatience` 14 s (`:73-76`), then writes the file again unless it was given.
- **Pictures on a page with no description:** `markdown.js`'s `picture()` (`PadCore/Sources/PadCore/Scripts/markdown.js:936-975`) counts a picture with no `alt` of at least 200 by 150 pixels (`unnamed`, `unnamedTall`, `:961-970`) and writes it as `![](address)`; a picture with an empty `alt` inside a link is skipped (`:960`). The counts are reset at `:1535-1536` and given at `:2004-2007`. `Handoff.document` writes "N large pictures have no description…", and "Much of what this page says may be in them" for 3 or more, or 2 windows tall (`PadCore/Sources/PadCore/Handoff.swift:100-105`).
- **The on-device model** (`Shared/PageMind.swift`): `PageMinds.mind()` waits 1.5 s and gives nil in Low Power Mode or a hot device (`:56-64`, `:104-111`). `OnDevicePageMind.read` (`:139-167`) attaches a picture on macOS and iOS 27 when the model has the `.vision` capability (`:155`), through `Attachment(picture)` (`:175-179`, `:188-192`), with greedy sampling (`:172`). `Handoff.hardened` and `grounded` (`Handoff.swift:410-471`) make the model's words safe to put in the file.
- **Transcripts:** `Transcript` (`PadCore/Sources/PadCore/Transcript.swift:10-76`), `blocks(room:)` writes a "## Transcript" heading and paragraphs of about 600 characters (`:95-119`), `PageReading.adding(_:limit:)` adds it and sets `spoken` (`:142-153`). Today only a site's own reader gives one (YouTube's panel, `Shared/PageShared.swift:184-197`).
- **Kinds:** `PageKind` has `media` ("A video or a recording, and what the page says around it") for pages.
- **Permissions:** `App/Info.plist` has camera, adding to Photos and microphone strings (`:46-50`); `Mac/Info.plist` camera and microphone (`:77-80`). `PolicyTests` forbids, in `App/Info.plist`, `NSPhotoLibraryUsageDescription`, the location keys, HomeKit, Bluetooth and Health (`ScriptAndPolicyTests.swift:258-262`). `NSSpeechRecognitionUsageDescription` is allowed.

## Decided

1. **Two format-told kinds**, added as task 06 added its own: `PageKind.picture` and `PageKind.recording`; `FileFormat` gains `picture` (`public.image`: JPEG, PNG, HEIC, GIF, WebP, TIFF) and `audio`, `video` (`public.audio`, `public.movie`). Every part core.
2. **A picture's facts**: pixel size, when it was taken (EXIF `DateTimeOriginal`), the camera (TIFF `Make` and `Model`) and the lens (EXIF `LensModel`). **Never the GPS dictionary**: it is not read at all.
3. **Text in a picture**: Vision, as task 06 reads scanned pages, with automatic language detection (`automaticallyDetectsLanguage = true` before 26).
4. **What a picture shows**: only where the model looks at pictures (macOS and iOS 27, `.vision`), with these instructions: "Describe what this picture shows in two or three plain sentences, for someone who can't see it. Mention text only if it is large. Never say who a person is." Greedy sampling; the answer `hardened` to one line, at most 400 characters; written as the model's: "Described by the on-device model, which can be wrong: …". Without the model, the file has the text and the facts only.
5. **Big pictures** are read through a thumbnail of at most 4,096 pixels on the long side (`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`).
6. **A page's pictures**: the 4 largest with no description, at most, within the page's existing patience (8 s, or 14 s with a site's reader); their text first (all four at once), then descriptions while time is left. What is not done in time is not waited for. Their addresses are fetched through the tab's web view (`HandoffFetch`), from the site that showed them.
7. **Recordings**: transcribed on the device in the device's language where speech recognition supports it, else in English; the first 15 minutes, the rest named; the job waits at most 90 seconds for the transcript, showing its progress in the guide, and then writes what it has.
8. **Speech**: `SpeechAnalyzer` with `SpeechTranscriber` on macOS and iOS 26; `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` before 26, only where `supportsOnDeviceRecognition`, else no transcript ("Speech recognition on this device can't transcribe this language"). If it asks for permission, add `NSSpeechRecognitionUsageDescription` to `App/Info.plist` and `Mac/Info.plist`: "eGlu turns a recording you hand off into text, on this device." Ask only when a recording is first handed off. Where the system must download its speech model first, let it (it is Apple's model, as Apple Intelligence's is), showing "Getting the speech model" in the guide.

## Pull request 1: a picture as a file

1. `DocumentSource`, for `FileFormat.picture`:
   1. `CGImageSourceCreateWithData`; the facts of Decided 2 from `CGImageSourceCopyPropertiesAtIndex` (`kCGImagePropertyPixelWidth`/`Height`, `kCGImagePropertyExifDictionary` › `DateTimeOriginal`, `LensModel`, `kCGImagePropertyTIFFDictionary` › `Make`, `Model`). Leave `kCGImagePropertyGPSDictionary` untouched.
   2. The thumbnail of Decided 5; its text with Vision.
   3. Its description with the model (Decided 4), through a new `PageMind` method: `func describe(_ picture: CGImage) async -> String?`, in `Shared/PageMind.swift` beside `read`, nil where the model can't look.
   4. Markdown: `# <file name>`, then `![<description or nothing>](<file name>)`, then "Text in the picture:" and the text as paragraphs (or "No text in it." when Vision finds none).
2. `FileFacts` gains `width`, `height`, `taken`, `camera`, `lens`, `described: Bool`; `Handoff.document` with them says "Kind of file: picture, 4,032 by 3,024 pixels, taken 2026-10-02 with Apple iPhone 17 Pro" and, when described, "What it shows was described by the on-device model, which can be wrong." Never a place.
3. The tab: `readingForHandoff` (`Shared/PageShared.swift:168`) for `image/*` reads the picture as a `DocumentSource` would (fetched with `HandoffFetch`), instead of `.noReadableContent`.
4. A ZIP's pictures (task 06's walk) are read too.
5. Tests: PadCore, a fixture `photo` in `Tests/handoff/` (`photo.source.md`, `photo.file.json` with the facts, `photo.md`); a test that `FileFacts` coding has no field for a place.

## Pull request 2: a page's pictures with no description

1. `markdown.js`: alongside the counts, give the largest pictures with no description, at most 8, as `pictures: [{ address, width, height, block }]` (`address` absolute; `block` the index of the block that holds `![](address)`). Add it where the counts are given (`:2004-2007`), keeping their order by size.
2. `PageReading` (`PageReading.swift`): a field `pictures: [PagePicture]` read by the JSON init (`:211`), empty by default; `PagePicture { address: URL, width: Int, height: Int, block: Int }`.
3. Regenerate `Tests/handoff/*.reading.json` (`Tests/handoff.html?write=<name>` in Safari, through `python3 -m http.server 8642`, as `Tests/handoff.html:17-19` says; or the same page in Playwright's WebKit) and check every `.md` fixture is unchanged except where pictures are now listed.
4. In `HandoffJob.organise`, for a `Page` source: the first 4 of `reading.pictures` (Decided 6): fetch each with `HandoffFetch` into the job's folder; read their text with Vision at once; then, while patience lasts, describe them one at a time with `PageMind.describe`. For each picture done, change its block's text from `![](address)` to `![<description>](address)` and add a block after it, "Text in the picture: …", when it has text.
5. `Handoff.document`: "N large pictures have no description" becomes, when some were read, "N large pictures have no description of their own; eGlu read M of them on this device: the text in them, and what the on-device model saw, which can be wrong." Keep the "Much of what this page says may be in them" line for the ones not read.
6. Tests: a fixture page with three unnamed pictures, their reading with `pictures`, and the expected `.md` with two read (given texts and descriptions in the test, no Vision in PadCore).

## Pull request 3: recordings

1. `DocumentSource`, for `FileFormat.audio` and `.video`:
   1. `AVURLAsset` of the file in the job's folder: `load(.duration)`, `load(.commonMetadata)` for title, artist and album; for video, the size of its first video track.
   2. The transcript (Decided 7 and 8) of at most the first 15 minutes, into a `Transcript` (`Transcript.swift`), so `blocks(room:)` writes it as the YouTube transcript is written.
   3. Progress for the guide: the minutes done of the minutes to do.
2. `HandoffJob`: for a recording, a new stage between reading and ready, shown by the guide as "Transcribing the recording: 3 of 15 minutes" (`HandoffStage.swift`'s words, through the catalog); the 90-second limit; the share button works when the transcript is done or the time is up.
3. `FileFacts` gains `duration` (seconds), `transcribed` (seconds), `language`; `Handoff.document`: "Kind of file: recording, 23 minutes. Transcribed on this device, in English: the first 15 minutes; its words may be wrong in places." For a video: "video, 1920 by 1080, 4 minutes".
4. The tab: `audio/*` and `video/*` (WebKit plays these files directly) read as a `DocumentSource` (fetched with `HandoffFetch`), instead of the page's reading.
5. Not here: a video inside a web page (a site's player). YouTube keeps its own transcript.
6. Tests: a fixture `voice` (a `Transcript` given in the test, `FileFacts` of a 23-minute recording), and `HandoffStageTests` for the new stage.

## Tests, all pull requests

- `cd PadCore && swift test`: all pass; existing fixtures unchanged apart from pull request 2's listed pictures.
- By hand, a new section in `Validation/CHECKLIST.md`, "Enhanced Handoff: pictures and recordings", on a Mac and an iPhone:
  - A photo with location data in its EXIF: the file has its date and camera, and no place anywhere.
  - A screenshot of a chat: its text in the file.
  - On macOS or iOS 27 with Apple Intelligence: a description, marked as the model's.
  - A news article with large pictures without `alt`: up to four read, and the line about them.
  - In Low Power Mode: no descriptions, text only, as the model is not asked.
  - A 5-minute `.m4a` and a 20-minute `.mp4`: transcripts; the second says it was cut at 15 minutes; the guide's progress.
  - The first recording asks for speech recognition (if the system asks), and only then.

## Done when

- [ ] All three pull requests merged; tests pass; no new warnings.
- [ ] No place from a picture's metadata reaches the file.
- [ ] The CHECKLIST section run once on a Mac and an iPhone, results written under it.
- [ ] CHANGELOG under `### Added`: "Handoff reads pictures (the text in them, and on Apple Intelligence devices what they show) and recordings (a transcript made on your device), and the large pictures on a page that have no description."
- [ ] PRIVACY.md: a picture's place is never read; pictures and recordings are read on the device; a page's pictures are fetched again from the site that showed them; the speech model may be downloaded by the system.

## Out of scope

- Videos playing inside web pages.
- Faces, people's names, places.
- Pictures inside Office documents (anydoc gives their alt text; reading the pictures themselves is not in this task).
