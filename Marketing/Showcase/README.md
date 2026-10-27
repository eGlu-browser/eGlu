# eGlu product showcase

[Watch the showcase](eGlu-showcase.mp4). A 93-second, captioned walkthrough of three everyday tasks in the actual iPad and iPhone app. This is a general product video, not an App Store preview. The existing App Store screenshots and previews are unchanged.

![Reviewing a design beside its notes](poster.png)

## Scenarios and evidence

| Time | Task | Visible outcome | Documentation and implementation |
| --- | --- | --- | --- |
| 00:03 to 00:20 | Review a design beside its notes | Open Forma's tab menu, choose Open in Split View, resize the divider and focus Margin. Both pages remain visible. | [Split view](../../README.md#split-view); [`Browser.swift`](../../App/Sources/Browser.swift), `split(with:)`, `dragDivider(to:)`, `dropDivider()`. |
| 00:20 to 00:52.5 | Move from Studio to a client project | Type Client in the command bar and choose the space result. The orange Client board and its tabs appear. Return to Studio, open a new tab and open Forma from its bookmarks. | [Spaces](../../README.md#spaces-each-signed-in-on-its-own), [command bar](../../README.md#the-command-bar), [bookmarks](../../README.md#bookmarks-on-every-new-tab); [`Browser.swift`](../../App/Sources/Browser.swift), `showSpace(_:)`, `.switchSpace` and bookmark actions; [`CommandBar.swift`](../../App/Sources/CommandBar.swift). |
| 00:52.5 to 01:30 | Use a desktop site on iPhone | Enter Trackpad View from the page menu, reopen gesture help and choose Continue, move the viewport with the minimap, change zoom and use Exit to restore normal browsing. | [Trackpad View](../../README.md#trackpad-view-on-iphone); [`DesktopPad.swift`](../../App/Sources/DesktopPad.swift); [`Browser.swift`](../../App/Sources/Browser.swift), `showDesktopPad()`, `showDesktopHelp()`, `leaveDesktopView()`. |

Each scenario follows a task rather than listing controls. Captions describe only observed actions and outcomes. Intro: 00:00 to 00:03. Closing slate: 01:30 to 01:33. The MP4 includes chapter markers for all five sections.

## Capture provenance

- Captured on 2026-10-27, Asia/Seoul, from main checkpoint [`0ac99c1`](https://github.com/eGlu-dot-app/eGlu/commit/0ac99c1593fe9fe23e31831f4c5de8505d128987).
- Native simulator recordings, not animated screenshots or recreated browser UI. All selected footage plays at its original speed. Cuts remove inspection pauses and redundant holds. The bookmarks ending uses the original take, which holds the clean grid longer than the retake. [The edit list](source/edits.json) records every source range; [the output timeline](source/timeline.json) records chapter and caption boundaries.
- iPad Pro 13-inch (M5), iPadOS 27.0, 2064 by 2752; Marketing iPhone 17 Pro Max, iOS 27.0, 1320 by 2868. Device identifiers and source hashes are in [the manifest](manifest.json).
- Separate Debug bundle `net.taehee.safience.MarketingQA`, with `EGLU_ISOLATED_QA=1` and `EGLU_DATA_ROOT` inside that QA container. No production app container, real workspace, signed-in site or Apple Account was used.
- Existing synthetic Forma, Margin, Lanes, Post and Week pages served on loopback port 8765. Sync, search suggestions, intelligence, content blocking and the developer-local bar were off. Onboarding and writing prompts were marked answered.
- Reused the existing separate capture build. Its temporary 27.1-only API guards allow the available 27.0 SDK/runtime and are not committed app-source changes. See [capture build constraints](../AppStore/source/README.md#capture-build).
- Existing SF Pro typography and straight, whole Apple device frames, consistent with the screenshot renderer. ABC Areal was unavailable. Licensed bezel source artwork remains ignored and is not redistributed separately.

## Limits

- Margin fits in the viewport, so notes scrolling could not be observed and is not claimed.
- The phone's help sheet is reopened through Help and Options. The edit does not claim it appears automatically on every entry.
- No live sign-in isolation, iCloud sync, Apple Intelligence, physical trackpad input, Mac or Duo coverage is demonstrated.
- Synthetic web pages illustrate browsing tasks. Their decorative editing controls are not presented as working editing functionality or as third-party products.
- No App Store Connect upload or PR merge.

## Reproduction

Follow the [isolated capture process](../AppStore/source/README.md), recording each scenario with `xcrun simctl io <device> recordVideo --codec=h264 <name>.mov`. The original native movies are local intermediates, not repository assets, matching the existing preview workflow. The manifest retains their hashes. Rebuilding this exact edit requires those source movies; a new recording requires updated edit ranges and hashes.

With FFmpeg, Pillow, the system SF Pro font, the existing brand files and locally licensed Apple bezel artwork available:

```sh
"$HOME/marketing-venv/bin/python3" Marketing/Showcase/source/render.py \
  Marketing/Showcase/source/edits.json /path/to/native-movies \
  /path/to/export --repo "$PWD"
```

The renderer produces the MP4 and timeline. Intermediates stay in the chosen export directory. Do not commit those movies or the bezel artwork.

## Validation

The three native task flows were exercised and recorded with annotations before editing. The final video was reviewed in full against its captions. Full decode, exact 1920 by 1080 dimensions, 30 fps, H.264 High/yuv420p, silent stereo AAC at 48 kHz, 93-second duration, MP4 fast-start and chapter timings were checked. The manifest records measured values and SHA-256 hashes. Python compilation, JSON parsing, edit ranges and `git diff --check` were also checked.
