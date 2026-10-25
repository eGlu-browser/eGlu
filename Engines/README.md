# Engines

eGlu's engines: two Rust libraries compiled from source into one XCFramework
with a small C interface and a Swift wrapper, taken by every eGlu target as a
pinned binary.

- **Harper** ([harper-core](https://github.com/eGlu-dot-apps/harperSwift), our
  fork of Automattic's Harper): grammar linting, spell checking, dialects and
  a per-person dictionary. Apache-2.0.
- **anydoc + pdf-inspector** ([Firecrawl](https://firecrawl.dev)): Office,
  OpenDocument, RTF, EPUB and CSV documents to Markdown, and PDFs page by
  page with which pages need OCR. MIT.

eGlu's rule is no dependencies beyond Apple's frameworks. The engines are the
second exception (Sparkle is the first): they are built from source, pinned
exactly, and make no network call at runtime.

## Layout

- `eglu-engines/` — the Rust crate: `src/json.rs` (the `{"ok"}/{"error"}`
  envelope, `catch_unwind`, C string helpers), `src/harper.rs` (the linter),
  `src/documents.rs` (anydoc + pdf-inspector), `src/lib.rs` (the `extern "C"`
  entry points), `src/default_config.json` (Harper's rule config, kept in
  step by `tests/config.rs`), `tests/` + `tests/fixtures/`.
- `include/` — `eglu_engines.h` (who frees what) and `module.modulemap`
  (`EgluEnginesC`).
- `Sources/Engines/` — the Swift wrapper: `Grammar` (actor), `GrammarLint`,
  `GrammarRule`, `GrammarSettings`, `Dialect`, `Documents`, `PDFPages`,
  `DocumentFormat`, `EngineError`.
- `Tests/EnginesTests/` — the Swift tests.
- `build.sh` — builds `build/EgluEngines.xcframework` + `.zip` and prints the
  checksum. `licenses.sh` — writes `LICENSES.md` and
  `Sources/Engines/Licenses.txt`.
- `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml` — the workspace, the
  pinned dependency tree, the pinned toolchain (Rust 1.99.1, five Apple
  targets).

## Build and test

```sh
cd Engines
cargo test                          # the Rust tests (host target)
./build.sh                          # the XCFramework (five targets, ~5 min)
EGLU_ENGINES_LOCAL=1 swift test     # the Swift tests against the local build
```

`Package.swift` normally points at the `engines-<version>` release asset on
GitHub. `EGLU_ENGINES_LOCAL=1` switches it to `build/EgluEngines.xcframework`
for local work, and is also how Xcode builds eGlu until a release exists —
set it in your shell or in the Xcode scheme's environment.

## Updating an engine

1. Bump the pin in `eglu-engines/Cargo.toml` (`harper-core` tag,
   `anydoc`, `pdf-inspector`) and `rust-toolchain.toml` if needed.
2. `cargo update -p <crate>` so `Cargo.lock` moves; commit the lockfile.
3. If Harper's `default_config.json` changed, copy the new file over
   `eglu-engines/src/default_config.json` — `tests/config.rs` fails if the
   embedded copy drifts from the crate's curated config.
4. `cargo test`, then `./licenses.sh`, `./build.sh`, `swift test`.
5. Publish (below) with a new `engines-<version>`.

## Publishing

After `./build.sh`, `build/EgluEngines.xcframework.zip` and its printed
checksum are the release:

```sh
gh release create engines-<version> build/EgluEngines.xcframework.zip \
    --repo eGlu-dot-apps/eGlu --title "Engines <version>"
```

then put the new URL and checksum in `Package.swift`'s `url:`/`checksum:`.
CI and other developers pick the binary up from the release;
`EGLU_ENGINES_LOCAL=1` always builds against the local XCFramework.
