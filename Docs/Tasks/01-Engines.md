# Task 01: The Rust engines: Harper and anydoc in one XCFramework

| | |
|---|---|
| Needs first | Nothing |
| Unblocks | 02, 03, 04 (grammar), 06, 07 (Handoff) |
| Size | M (two to four weeks) |
| Platforms | Mac and iOS (the library), used by both apps |
| Pull requests | One |

## Goal

Two Rust libraries, compiled from source into one XCFramework with a small C interface and a Swift wrapper, taken by every eGlu target as a pinned binary:

- **Harper**, the grammar checker: lint English text, with rules turned on and off, a dialect and a personal dictionary.
- **anydoc** (with Firecrawl's **pdf-inspector**, which anydoc already uses for PDFs): turn Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV and PDF bytes into Markdown, and say which PDF pages have no text and need reading from pictures.

Nothing in the app uses them yet: tasks 02 and 06 do. This task ends with the engines built, tested, licensed, wired into `project.yml`, and every target building with them.

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

## Why Rust here, and why only here

eGlu's rule is Apple's frameworks only. This task is its one exception, decided on 2026-10-25:

- Harper's rules are Rust code: in its core, 345 rule files with more than 31,000 lines besides their tests, 382 rules in its own rule language, an engine of about 15,000 lines, about 6,000 tests. A Swift port would be about 45,000 lines, and every Harper release would have to be ported again by hand. Rust is kept for that, not for speed.
- anydoc and pdf-inspector are Rust too, and take a large job (reading Office files and PDFs well) that Apple's frameworks don't do.

So the exception is exactly these crates and what they pull in. Nothing else may be added to `Engines/` without a new decision.

## The engines

### Harper

- Upstream: [Automattic/harper](https://github.com/Automattic/harper), Apache-2.0, "Copyright 2024 Automattic Inc." (root `LICENSE`). There is no NOTICE file.
- eGlu takes it from [taehee-pd/harperSwift](https://github.com/taehee-pd/harperSwift), the eGlu author's fork (same licence), at a tag. Its `harper-core` is the crate to use.
- Everything Harper needs at run time is compiled in (`include_str!` and `include_bytes!`): the dictionary and its annotations (`harper-core/src/spell/mutable_dictionary.rs:34-35`), `default_config.json` (`structured_config/mod.rs:21-29`), the part-of-speech tagger and chunker models (`harper-brill/src/lib.rs:9,24,39-40`), the rules in Harper's rule language (through `WEIR_RULE_DIR`, `harper-core/build.rs:151`). No files to ship.
- The dictionary's search structure is built the first time it is used (`fst_dictionary.rs:28-29`), which takes noticeable time: the wrapper needs a way to do it early, off the main thread.
- `harper-core` has a default feature `thesaurus` (`harper-core/Cargo.toml:57-59`) that eGlu does not need: turn default features off.
- The part-of-speech utilities use `burn` (a Rust machine-learning crate, CPU only, `harper-pos-utils/Cargo.toml`). It adds to the binary's size: measure it.

The API to wrap (paths in harperSwift's `harper-core/src`):

| What | Where |
|---|---|
| A document from text | `Document::new_plain_english_curated(text)` (`document.rs:91`), or `Document::new_markdown_default(text, &dict)` (`:152`) for Markdown |
| The text a document holds | `get_source() -> &[char]` (`:381`) |
| The rules | `LintGroup::new_curated(Arc<dict>, dialect)` (`linting/lint_group/mod.rs:582`), then `.with_lint_config(config)` (`:577`) |
| Linting | `organized_lints(&doc) -> BTreeMap<rule name, Vec<Lint>>` (`:1026`), or `Linter::lint` (`:1127`) |
| Rules on and off | `FlatConfig` (`lint_group/flat_config.rs:28-108`): a map from rule name to `Option<bool>`, `None` meaning the curated default; `set_rule_enabled`, `unset_rule_enabled`, `is_rule_enabled`, `fill_with_curated` |
| Rule names, labels, groups, defaults | `default_config.json` (Group and Bool entries with `name`, `state`, `label`); `all_descriptions` (`lint_group/mod.rs:541`) |
| Dialects | `Dialect` (`dict_word_metadata.rs:1129-1135`): American, Canadian, Australian, British, Indian |
| A lint | `Lint` (`linting/lint.rs:10-27`): `span: Span<char>`, `lint_kind: LintKind`, `suggestions: Vec<Suggestion>`, `message: String` (Markdown), `priority: u8` (lower matters more) |
| Kinds of lint | `LintKind` (`lint_kind.rs:10`), with `to_string_key` (`:89`) |
| A suggestion | `Suggestion` (`suggestion.rs:13-20`): `ReplaceWith(Vec<char>)`, `InsertAfter(Vec<char>)`, `Remove` |
| Spans | `Span<char>` (`span.rs:19-29`): end-exclusive indices into the document's `[char]` (Unicode scalars), **not UTF-16 and not bytes** |
| A personal dictionary | `MergedDictionary::new()` and `add_dictionary(...)` (`spell/merged_dictionary.rs:24,32`) over `FstDictionary::curated()` and a `MutableDictionary` (`extend_words`, `:72`). Adding words means building the `LintGroup` again |
| Ignoring one lint | `IgnoredLints` (`ignored_lints/mod.rs:14-55`): `ignore_hash`, `remove_ignored(&mut lints, &doc)`; the hash is `LintContext::from_lint(...).default_hash()` (`lint_context.rs:22,57`) |

**The model to copy** is `harper-wasm/src/lib.rs`: its `Linter` holds the lint group, the user dictionary, the curated dictionary, the ignored lints and the dialect (`:111-122`), rebuilds the merged dictionary when words change (`:152-178`), reads and writes the config as JSON (`:225-240`), lints (`:400-429`), and converts spans to UTF-16 (`:704-708`, `:753-758`). `harper-ls/src/pos_conv.rs:14-28` does the same conversion.

### anydoc

- [firecrawl/anydoc](https://github.com/firecrawl/anydoc), MIT, version 0.2.4 at the time of writing (`Cargo.toml`: edition 2024, Rust 1.88 or later). Formats: `.doc`, `.docx`, `.docm`; `.ppt`, `.pps`, `.pot`, `.pptx`, `.pptm`, `.ppsx`, `.ppsm`; `.xls`, `.xlsx`, `.xlsm`, `.xlsb`; `.odt`, `.ods`, `.odp`; RTF, EPUB, CSV, PDF.
- Output: GitHub-Flavored Markdown with headings, emphasis, links, lists, tables (merged cells, header rows), quotes, footnotes and endnotes, PowerPoint speaker notes, equations as LaTeX, pictures as their alt text.
- Its dependencies: `pdf-inspector` (1.14.2), `zip` (deflate only), `quick-xml`, `cfb`, `csv`, `flate2`, `encoding_rs`, `log`. No network crate, no features. Its README: the crate "never makes network calls". Firecrawl's hosted OCR exists only in its Node, Python and command-line wrappers, which eGlu does not use.
- API (`src/lib.rs`):
  - `Format` enum: `Doc`, `Docx`, `Odt`, `Pdf`, `Ppt`, `Pptx`, `Rtf`, `Epub`, `Excel`, `Ods`, `Odp`, `Csv`.
  - `Format::from_bytes(&[u8]) -> Option<Format>` (by content; `None` for CSV and the unknown), `Format::from_extension(&str)`.
  - `to_markdown_bytes(bytes: &[u8], format: impl Into<Option<Format>>) -> Result<String, ConvertError>`. CSV needs its format given.
  - `ConvertError`: `Unsupported`, `NeedsOcr`, `Malformed`, `Encrypted`, `ResourceLimit`, `MissingPart`, `Io`.

### pdf-inspector, for PDFs page by page

anydoc turns a scanned PDF into `NeedsOcr` as a whole. A PDF with some scanned pages and some with text needs the pages one by one, which pdf-inspector gives (`src/lib.rs`):

- `extract_pages_markdown_mem(buffer: &[u8], pages: Option<&[u32]>) -> Result<PagesExtractionResult, PdfError>`: each page's Markdown (`PageMarkdown { page (0-based), markdown, needs_ocr, ocr_reason }`), with `pages_needing_ocr`, `pages_with_tables`, `pages_with_columns`.
- `detect_pdf_mem(buffer) -> Result<PdfProcessResult, PdfError>`: `page_count`, `pdf_type`, `pages_needing_ocr` (**1-based** here), and the PDF's `title`, `author`, `subject`, `creation_date`.

Use pdf-inspector at the version anydoc resolves (1.14.2 at the time of writing), with default features off (its OCR, PDFium and model download are optional features, off by default), so Cargo builds one copy. Check that these two functions exist at that version; if one does not, take the oldest version that has them and that anydoc accepts, and say so in the hand-back.

## Decided

1. **Where:** `Engines/` at the repository's root: a Cargo workspace with one crate, `eglu-engines` (a `staticlib`), and a Swift package that wraps it. Everything to build it is in the repository.
2. **What it takes:** `harper-core` by git from harperSwift at a tag, `default-features = false`; `anydoc = "=0.2.4"`; `pdf-inspector` at the version anydoc resolves, `default-features = false`. Versions pinned exactly; `Cargo.lock` committed. The Rust version pinned in `Engines/rust-toolchain.toml`.
3. **The C interface carries JSON**: a handful of functions, strings in and out (UTF-8, NUL-terminated), every result `{"ok": …}` or `{"error": {"kind": "…", "message": "…"}}`. Small to keep and easy to test from both sides.
4. **Spans leave Rust in UTF-16**, the unit of Swift's `NSString`, JavaScript strings and the Accessibility API.
5. **No panic crosses the boundary:** each entry point runs in `std::panic::catch_unwind` and answers `{"error": {"kind": "panic"}}`. The release profile keeps `panic = "unwind"`.
6. **The XCFramework's slices:** macOS (arm64 and x86_64 in one), iOS (arm64), iOS Simulator (arm64 and x86_64).
7. **How eGlu takes it:** `Engines/Package.swift` declares a `binaryTarget(url:checksum:)` pointing at a release asset on `eGlu-dot-apps/eGlu` (tag `engines-<version>`), and a Swift target `Engines` that wraps it. With the environment variable `EGLU_ENGINES_LOCAL=1`, the manifest uses `binaryTarget(path: "build/EgluEngines.xcframework")` instead, for development. Building eGlu needs nothing but Xcode.
8. **PadCore does not depend on `Engines`**: PadCore must build and test on Linux, and an XCFramework has no Linux slice. Code that uses the engines is in `Shared/`, `Mac/` or `App/`.
9. **Licences:** listed in `Engines/LICENSES.md`, credited in the README, and shipped inside the apps (step 9).

## Steps

### 1. The workspace

Create:

```
Engines/
  Cargo.toml            workspace: members = ["eglu-engines"]; [profile.release] lto = "thin", strip = true, panic = "unwind", opt-level = "s"
  Cargo.lock            committed
  rust-toolchain.toml   channel pinned (1.88 or later, the newest stable at the time); targets listed below
  eglu-engines/
    Cargo.toml          [lib] crate-type = ["staticlib"]; the three dependencies above
    src/lib.rs          the C entry points (steps 2 and 3)
    src/harper.rs       the linter (step 2)
    src/documents.rs    anydoc and pdf-inspector (step 3)
    src/json.rs         ok/error envelopes, string in and out, catch_unwind
    tests/              Rust tests (step 5) and fixtures/
  include/
    eglu_engines.h      the C header, written by hand (step 4)
    module.modulemap    module EgluEnginesC { header "eglu_engines.h"; export * }
  build.sh              step 6
  Package.swift         step 7
  Sources/Engines/      the Swift wrapper (step 7)
  Tests/EnginesTests/   Swift tests (step 7)
  README.md             how to build, update and publish (step 8)
  LICENSES.md           step 9
```

`rust-toolchain.toml` targets: `aarch64-apple-darwin`, `x86_64-apple-darwin`, `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`.

### 2. Harper behind C

In `src/harper.rs`, a `Linter` modelled on harper-wasm's (`harper-wasm/src/lib.rs:111-178`): the lint group, the curated dictionary, the person's `MutableDictionary`, the merged dictionary, `IgnoredLints`, the dialect.

C functions (in `src/lib.rs`, `#[no_mangle] pub extern "C"`):

```c
typedef struct EgluHarper EgluHarper;

// settings: {"dialect":"American","rules":{"SpellCheck":false},"words":["eGlu","Figma"]}
// rules lists only differences from Harper's defaults; an unknown rule name is ignored.
EgluHarper *eglu_harper_new(const char *settings_json, char **error_json);
void        eglu_harper_free(EgluHarper *linter);

// Same settings shape; rebuilds the lint group and the merged dictionary.
char *eglu_harper_configure(EgluHarper *linter, const char *settings_json);

// Builds the dictionary's search structure and runs one lint, so the first real one is quick.
char *eglu_harper_warm_up(EgluHarper *linter);

// format: "plain" or "markdown".
char *eglu_harper_lint(EgluHarper *linter, const char *text, const char *format);

// Hides one lint from now on, by the context a lint carried.
char *eglu_harper_ignore(EgluHarper *linter, const char *context);

// Every rule: its group, name, label, description and default, from default_config.json.
char *eglu_harper_rules(void);

void eglu_free(char *string);
```

`eglu_harper_lint`'s answer:

```json
{"ok": {"lints": [
  {"start": 12, "end": 17, "rule": "SpellCheck", "kind": "Spelling",
   "message": "Did you mean “their”?", "priority": 63,
   "suggestions": [{"replace": "their"}, {"replace": "there"}],
   "context": "9b1f0c2a7d4e8f31"}
]}}
```

- `start` and `end` in UTF-16 code units of the text given. Convert from Harper's `Span<char>` with the document's `[char]`: a scalar above U+FFFF counts two.
- `kind` is `LintKind::to_string_key()`.
- `suggestions`: `{"replace": text}`, `{"insert": text}` (Harper's `InsertAfter`: inserted at `end`), `{"remove": true}`.
- `context` is the `u64` hash of `LintContext::from_lint(&lint, &doc).default_hash()`, as 16 hex digits, which `eglu_harper_ignore` takes back.
- Lints sorted by `start`, then `priority`.
- Ignored lints removed with `remove_ignored` before answering.
- Text of more than 200,000 UTF-16 units answers `{"error": {"kind": "tooLarge"}}`: the caller lints a paragraph or a field, never a book.

### 3. anydoc and pdf-inspector behind C

In `src/documents.rs`:

```c
// format: "" to detect from the bytes, or one of "doc","docx","odt","pdf","ppt","pptx","rtf","epub","excel","ods","odp","csv".
// {"ok":{"format":"docx","markdown":"…"}}
char *eglu_document_markdown(const uint8_t *bytes, size_t length, const char *format);

// {"ok":{"format":"docx"}} or {"ok":{"format":null}}
char *eglu_document_detect(const uint8_t *bytes, size_t length);

// pages: null for every page, or a JSON array of 0-based page numbers.
// {"ok":{"pageCount":12,"title":"…","author":"…","created":"…",
//        "pages":[{"page":0,"markdown":"…","needsOCR":false},{"page":3,"markdown":"","needsOCR":true,"reason":"…"}],
//        "withTables":[2],"withColumns":[5]}}
char *eglu_pdf_pages(const uint8_t *bytes, size_t length, const char *pages_json);
```

- Error kinds, from `ConvertError` and `PdfError`: `needsOCR`, `unsupported`, `malformed`, `encrypted`, `resourceLimit`, `missingPart`, `io`, and `panic`. `message` is the error's text, for logs only; the app shows its own words.
- `eglu_pdf_pages` takes `pages_needing_ocr` from `detect_pdf_mem` (1-based) and gives every page number 0-based. Say which in a comment where it is converted.
- More than 200 MB of bytes answers `{"error": {"kind": "tooLarge"}}` without reading them.

### 4. The header

`include/eglu_engines.h`: the declarations above, each with a comment on who frees what (every returned `char *` is freed with `eglu_free`; `eglu_harper_new` writes `*error_json` only on failure). `module.modulemap` makes it the Clang module `EgluEnginesC`.

### 5. Rust tests (`cargo test` in `Engines/`, on macOS or Linux)

- Harper: "I has a apple." gives at least an agreement and an article lint with suggestions; a turned-off rule gives none; a word added to the dictionary is no longer a spelling lint; an ignored context stays ignored; `rules` lists groups and rules with labels.
- UTF-16: a misspelling after "😀 " and after "한국어 " has the start and end JavaScript would give (`"😀 teh".indexOf("teh")` is 3).
- Panic: a test-only entry that panics answers `{"error":{"kind":"panic"}}`.
- Documents: small fixtures in `tests/fixtures/` (a `.docx` with a heading, a list and a table; an `.xlsx` with two sheets; a `.pptx` with speaker notes; a text PDF; a PDF of one page that is only a picture). Copy small ones from anydoc's own tests (MIT; say where they came from in `tests/fixtures/README.md`), or make them and say how. Check: the headings, the table's rows, the notes and both sheets are in the Markdown; the picture-only PDF's page has `needsOCR: true`; random bytes answer `unsupported` or `malformed`, never a crash.

### 6. `Engines/build.sh`

```sh
#!/bin/zsh
# Builds EgluEngines.xcframework from source into Engines/build/, zips it,
# and prints the checksum Package.swift needs.
set -euo pipefail
cd "$(dirname "$0")"
for t in aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  cargo build --release --target "$t" -p eglu-engines
done
# lipo the two macOS libraries, and the two simulator libraries, then:
# xcodebuild -create-xcframework -library <mac>.a -headers include \
#   -library <ios>.a -headers include -library <sim>.a -headers include \
#   -output build/EgluEngines.xcframework
# zip with `ditto -c -k --keepParent`, then: swift package compute-checksum build/EgluEngines.xcframework.zip
```

Write it out in full (the comments above say what each step is). Set `MACOSX_DEPLOYMENT_TARGET=26.0` and `IPHONEOS_DEPLOYMENT_TARGET=17.0` for the builds. Print the sizes of each slice at the end.

### 7. The Swift package

`Engines/Package.swift` (tools 5.9, platforms `.iOS(.v17)`, `.macOS(.v14)`):

- `binaryTarget` `EgluEnginesFFI`: by URL and checksum, or by path under `EGLU_ENGINES_LOCAL=1` (`Context.environment`).
- Target `Engines` (Swift), depending on it, with Swift 5 mode and strict concurrency as PadCore has.
- Test target `EnginesTests`.

The Swift API (`Sources/Engines/`):

```swift
public enum Dialect: String, Codable, Sendable, CaseIterable { case american = "American", british = "British", australian = "Australian", canadian = "Canadian", indian = "Indian" }

public struct GrammarSettings: Codable, Sendable, Equatable {
    public var dialect: Dialect
    public var rules: [String: Bool]      // differences from Harper's defaults
    public var words: [String]
}

public struct GrammarLint: Codable, Sendable, Equatable {
    public enum Suggestion: Codable, Sendable, Equatable { case replace(String), insert(String), remove }
    public let start: Int, end: Int       // UTF-16 code units
    public let rule: String, kind: String, message: String, priority: Int, context: String
    public let suggestions: [Suggestion]
}

public struct GrammarRule: Codable, Sendable, Identifiable { public let id: String /* name */; public let label: String; public let description: String; public let group: String; public let isOnByDefault: Bool }

public actor Grammar {
    public init(settings: GrammarSettings) throws
    public func configure(_ settings: GrammarSettings) throws
    public func warmUp() throws
    public func lint(_ text: String, markdown: Bool = false) throws -> [GrammarLint]
    public func ignore(context: String) throws
    public static func rules() throws -> [GrammarRule]
}

public enum DocumentFormat: String, Codable, Sendable { case doc, docx, odt, pdf, ppt, pptx, rtf, epub, excel, ods, odp, csv }

public struct EngineError: Error, Sendable, Equatable {
    public enum Kind: String, Sendable { case needsOCR, unsupported, malformed, encrypted, resourceLimit, missingPart, io, panic, tooLarge, unknown }
    public let kind: Kind; public let message: String
}

public enum Documents {
    public static func detect(_ data: Data) -> DocumentFormat?
    public static func markdown(_ data: Data, format: DocumentFormat? = nil) throws -> String
    public static func pdfPages(_ data: Data, pages: [Int]? = nil) throws -> PDFPages
}

public struct PDFPages: Codable, Sendable {
    public struct Page: Codable, Sendable { public let page: Int; public let markdown: String; public let needsOCR: Bool; public let reason: String? }
    public let pageCount: Int; public let title: String?; public let author: String?; public let created: String?
    public let pages: [Page]; public let withTables: [Int]; public let withColumns: [Int]
}
```

- `Grammar` owns the `EgluHarper *` and frees it in `deinit`. Being an actor, one call at a time reaches it.
- `Documents`' functions are synchronous and pure: callers run them off the main actor (task 06 does).
- One helper decodes every `{"ok"}`/`{"error"}` answer and frees the string with `eglu_free`.
- Tests (`swift test` in `Engines/` on a Mac, with `EGLU_ENGINES_LOCAL=1` after `build.sh`): the Rust tests' Harper cases through Swift; `NSString`'s ranges from `start` and `end` cover the misspelt word; `Documents.markdown` of the `.docx` fixture has its heading; the scanned PDF gives `needsOCR`.

### 8. Publishing and `Engines/README.md`

`Engines/README.md` says, in eGlu's plain style:

- What is in it and why it is the exception (the section above, short).
- How to build (`./build.sh`), test (`cargo test`, `swift test`), and use a local build (`EGLU_ENGINES_LOCAL=1`, with Xcode opened from a shell that has it, or set in the scheme's environment for package resolution).
- How to update Harper (a new harperSwift tag), anydoc or pdf-inspector: change the version, `cargo update -p …`, run the tests, build, publish.
- How to publish: create a GitHub release `engines-<version>` on `eGlu-dot-apps/eGlu` with `EgluEngines.xcframework.zip`, put the URL and checksum in `Package.swift`, commit.

Publishing the release needs the repository's owner. Prepare everything and the first release's notes; if you can't create the release, leave `Package.swift` pointing at the URL it will have, and say so in the hand-back.

### 9. Licences

- `Engines/LICENSES.md`: each crate built in (from `cargo metadata --format-version 1` in `Engines/`, release dependencies only): name, version, licence. Harper's Apache-2.0 text once, MIT's once, and any other licence that turns up. A short script that writes it (`Engines/licenses.sh`) so it is redone at each update.
- README.md › Credits (`README.md:507`): a line for Harper (Automattic, Apache-2.0, through harperSwift) and one for anydoc and pdf-inspector (Firecrawl, MIT).
- Inside the apps: `LICENSES.md`'s text as a resource of the `Engines` package (`resources: [.copy("Licenses.txt")]`), shown by a "Licences" button at the foot of Settings › General on the Mac (`Mac/Sources/SettingsView.swift`, `GeneralSettings`, `:182-286`) and at the foot of the iPad's and iPhone's Settings list (`App/Sources/SettingsView.swift:7-65`), opening a scrolling text view. Its title and button go through the String Catalog.

### 10. Into the project

1. `project.yml` › `packages`: `Engines: path: Engines`, beside PadCore (`project.yml:22-29`).
2. Add `- package: Engines` to the `eGlu` target's dependencies (`:67-68`) and to the `MacApp` template's (`:31-55`), so both Mac targets get it.
3. `xcodegen`, and commit `eGlu.xcodeproj`.
4. Build `eGlu` (an iPhone simulator and a device), `eGlu Mac` and `eGlu Mac Direct`. No warnings of yours.
5. A call that proves it links, in DEBUG builds only, nowhere people see: for example, in each app's launch, under `#if DEBUG`, `_ = try? Grammar.rules().count` logged with the app's logger. Remove it if tasks 02 or 06 have already merged a real use.

### 11. CONTRIBUTING.md

Change the rule "No dependencies beyond Apple's frameworks" to:

> **No dependencies beyond Apple's frameworks**, with two exceptions: Sparkle, in eGlu Mac Direct, to update the app; and the Rust engines in `Engines/` (Harper for grammar, anydoc and pdf-inspector for documents), built from source, pinned, and making no network call. Nothing else: no other Swift packages, Rust crates or npm packages in the app.

### 12. Measure, and put the numbers in the hand-back

- Each slice's size, and how much each app's download grows (an archive's `.app` before and after).
- Harper: time of `warmUp`, then of linting 1,000 and 10,000 characters, on an Apple Silicon Mac and an iPhone.
- anydoc: time and size of output for each fixture.

If the app grows by more than 25 MB, say what takes the room (the `burn` model is the likely part) before going on.

## Tests

- `cd Engines && cargo test`: all pass.
- `cd Engines && ./build.sh && EGLU_ENGINES_LOCAL=1 swift test`: all pass.
- `cd PadCore && swift test`: still passes, unchanged.
- The three app targets build, with no warnings of yours.

## Done when

- [ ] `Engines/` builds the XCFramework from source with one script, for macOS, iOS and the simulator.
- [ ] The C interface and the Swift API are as above; spans in UTF-16; no panic gets out.
- [ ] Rust and Swift tests pass.
- [ ] `project.yml` takes `Engines`; all three targets build; PadCore still tests on Linux.
- [ ] `Engines/README.md`, `Engines/LICENSES.md`, the README's Credits, CONTRIBUTING's rule and the Licences screen are done.
- [ ] The release is published, or ready for the owner to publish.
- [ ] The measurements are in the hand-back.

## Out of scope

- Using the engines in the app: tasks 02 to 07.
- OCR: Vision does it, in task 06.
- Harper Desktop's Clarity suggestions (Apple's model, not Harper's): not in these tasks.
