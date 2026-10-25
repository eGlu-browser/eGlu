# Tasks: grammar checking, Enhanced Handoff and developer features

Ten tasks, each a file that can be handed to one engineer or agent as it is: each carries the context it needs (eGlu, its rules, how to build and test), what exists today with file and line, what is decided, the steps in order, the tests, and when it is done. Planned 2026-10-25 against Build 38.

Sizes are rough, for one developer: **S** up to a week, **M** two to four weeks, **L** one to two months.

## The tasks

| # | Task | Needs first | Size | Mac | iPad and iPhone |
|---|---|---|---|---|---|
| [01](01-Engines.md) | The Rust engines: Harper and anydoc in one XCFramework | Nothing | M | Yes | Yes |
| [02](02-GrammarInPagesMac.md) | Grammar checking in pages, on the Mac | 01 | L | Yes | |
| [03](03-GrammarInOtherAppsMac.md) | Grammar checking in other apps, on the Mac | 01, 02 | L | Yes | Not possible: iPadOS lets no app read another's text |
| [04](04-GrammarInPagesiPad.md) | Grammar checking in pages, on iPad and iPhone | 01, 02 | M | | Yes |
| [05](05-WritingOnboarding.md) | Asking about grammar checking at onboarding | 02 | S | Yes | Yes |
| [06](06-HandoffDocuments.md) | Enhanced Handoff: PDFs and documents | 01 | L | Yes | Yes |
| [07](07-HandoffPicturesRecordings.md) | Enhanced Handoff: pictures and recordings | 06, its step 1 | M | Yes | Yes |
| [08](08-DeveloperMode.md) | Developer mode, as Arc's | Nothing | M | Yes | In part |
| [09](09-MesurerExtension.md) | Mesurer's Chrome extension, tried and fixed | Nothing | S | Yes | |
| [10](10-MeasuringTool.md) | eGlu's own measuring tool | 08 | M | Yes | Yes |

## Order and what can run at once

```
01 Engines ──┬── 02 Grammar, Mac pages ──┬── 03 Grammar, other apps
             │                           ├── 04 Grammar, iPad pages
             │                           └── 05 Onboarding
             └── 06 Handoff, documents ───── 07 Handoff, pictures and recordings

08 Developer mode ───────────────────────── 10 Measuring tool

09 Mesurer's extension
```

- Right away, in parallel: **01**, **08**, **09**.
- After 01: **02** and **06**, in parallel.
- After 02: **03**, **04** and **05**, in parallel. 05 adds the "other apps" and iPad parts as 03 and 04 land.
- **07** starts once 06 has its step 1 (the converters' shape) merged.
- **10** after 08.

Two tasks that touch the same file (Settings, the command list, `Page.swift`) are kept apart where they can be; where not, each task says which part is its own.

## Decided on 2026-10-25

1. **Apple's frameworks only**, kept. The one new exception: two engines in Rust, in `Engines/`: **Harper** for grammar and **anydoc** for documents (with Firecrawl's pdf-inspector, which comes in with it). Harper stays Rust not for speed but because its rules are Rust code: a port to Swift would be about 45,000 lines to rewrite and every Harper release to port again by hand.
2. **Harper's rules and UI built into eGlu**: in pages, and in other apps on the Mac. The UI comes from harperSwift's `macos-popup` (Swift); the other-apps checker is rewritten from harperSwift's Rust in Swift.
3. **Grammar checking is off** until the person turns it on; onboarding asks.
4. **Developer tools' keys**: a setting chooses ⌃⌥ (as it starts) or ⌥⌘ (as Chrome).
5. **iPad and iPhone** get what they can support.
6. **Not planned**: GenOffice as the PDF viewer and office tools, a motion tool on HyperFrames, and Toolcraft.
7. **Handoff is extended** from pages to documents, pictures and recordings, with Microsoft's MarkItDown as the reference for what to read and keep; none of its code is used.

## Sources

- [Automattic/harper](https://github.com/Automattic/harper), [taehee-pd/harperSwift](https://github.com/taehee-pd/harperSwift)
- [firecrawl/anydoc](https://github.com/firecrawl/anydoc), [firecrawl/pdf-inspector](https://github.com/firecrawl/pdf-inspector), [microsoft/markitdown](https://github.com/microsoft/markitdown)
- [Arc's Developer Mode](https://resources.arc.net/hc/en-us/articles/20468488031511), [Drew Lyton on Arc for web development](https://www.drewlyton.com/story/this-is-the-best-browser-for-web-development-post/)
- [ibelick/mesurer](https://github.com/ibelick/mesurer), [Mesurer on the Chrome Web Store](https://www.chromeboard.com/extension/mesurer-icmjafcffhpcnadkmmklegommbcekcac)
