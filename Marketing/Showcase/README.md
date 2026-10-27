# eGlu feature showcase

[Watch the showcase](eGlu-showcase.mp4). A captioned feature overview of the native Mac, iPad and iPhone app. Feature names, controls and visible results replace the earlier task-based scenarios. This is not an App Store preview. Existing App Store screenshots and previews are unchanged.

![eGlu on Mac](poster.png)

## Feature chapters

| Feature | Footage | Visible demonstration |
| --- | --- | --- |
| Desktop web apps | Mac | Loaded desktop-layout synthetic web app. |
| Tab layouts | Mac | Compact tab row, pinned tabs and switching to the sidebar. |
| Split View | Mac and iPad | Two live pages and a divider that changes their widths. |
| Spaces | Mac | Switching changes the space colour and its tabs. No live sign-in comparison. |
| Command bar | Mac | A typed query finds a bookmark, followed by native selection. |
| Bookmarks | Mac | A new window opens on Studio's bookmark grid; opening a bookmark loads the page. |
| Little windows | Mac | A local link opens in a compact window; its loaded page scrolls. |
| History | Mac | Filter visited synthetic pages and reopen a result. |
| Developer tools | Mac | Address and HTTP status; Size changes the viewport. |
| Trackpad View | iPhone | Desktop page, native controls, minimap movement, zoom and Exit. |

The MP4 has a chapter marker for every feature. [The timeline](source/timeline.json) records chapter and caption boundaries. [The edit list](source/edits.json) records source ranges, devices and captions.

## Documentation and implementation

- [Feature documentation](../../README.md#features) and [requirements](../../Docs/Requirements.md) define the scope. Only observed native interactions appear in the video.
- Mac: [`BrowserView.swift`](../../Mac/Sources/BrowserView.swift), [`WindowModel.swift`](../../Mac/Sources/WindowModel.swift), [`Session.swift`](../../Mac/Sources/Session.swift), [`LittleWindow.swift`](../../Mac/Sources/LittleWindow.swift), [`CommandBar.swift`](../../Mac/Sources/CommandBar.swift) and [`DeveloperBar.swift`](../../Mac/Sources/DeveloperBar.swift).
- iPad: [`Browser.swift`](../../App/Sources/Browser.swift), `split(with:)`, `dragDivider(to:)`, `dropDivider()`, `showSpace(_:)` and command-bar actions.
- iPhone: [`DesktopPad.swift`](../../App/Sources/DesktopPad.swift), `showDesktopPad()`, `showDesktopHelp()` and `leaveDesktopView()` in the iOS browser.

## Provenance and safety

- Native app recordings, not recreated UI or animated screenshots. Actions play at original speed. Cuts remove pauses and repeated actions, not required outcome evidence. The recorder omitted static tail time in some Mac sources; the History and Developer clips use derivatives with a three-second hold on the actual final frame. No action is generated or interpolated.
- Product source checkpoint: [`0ac99c1`](https://github.com/eGlu-dot-app/eGlu/commit/0ac99c1593fe9fe23e31831f4c5de8505d128987). Dates, bundle identifiers, devices, isolation, source measurements and hashes are in [the manifest](manifest.json).
- Mac uses a separate MarketingQA bundle, defaults domain and data root. `EGLU_DATA_ROOT` also disables `canSync`. Simulators use `net.taehee.safience.MarketingQA`, `EGLU_ISOLATED_QA=1` and their own QA data roots.
- No production container, real workspace, signed-in site or Apple Account. Sync, suggestions and intelligence stay off. Developer mode is enabled only for its chapter, then restored off.
- Forma, Margin, Lanes, Post and Week are synthetic pages on loopback port 8765. Decorative editing controls are not presented as functional tools or third-party products.
- Mac footage shows the native window, not a fabricated hardware frame. Simulator footage retains the existing Apple artwork. SF Pro is retained because ABC Areal was unavailable. Licensed bezel source artwork stays ignored.
- Temporary iOS 27.1-only API guards stay in the separate capture build for the available 27.0 SDK/runtime, not repository app source. See [capture constraints](../AppStore/source/README.md#capture-build).

## Coverage limits

- Peek opened a blank overlay in the isolated Mac test, so it is excluded. Little windows were verified separately and do not imply Peek coverage.
- This covers verified features, not every documented capability. Chrome extensions, grammar checking, iCloud sync, Apple Intelligence, live sign-in isolation, physical iPad trackpad input and Duo are not demonstrated.
- Margin fits in the portrait iPad viewport, so notes scrolling there is not claimed. Scrolling in the Mac little window is a separate verified action.
- No App Store Connect upload or PR merge.

## Reproduction and validation

Follow the [isolated capture process](../AppStore/source/README.md). Simulator sources use `xcrun simctl io <device> recordVideo --codec=h264 <name>.mov`. Mac sources use native window-region screen recordings with the cursor. The manifest records their capture rectangle and hashes. Native movies are local intermediates, not repository assets. Exact reproduction requires those sources; new recordings require new ranges and hashes.

With FFmpeg, Pillow, system SF Pro, existing brand files and locally licensed Apple bezel artwork:

```sh
"$HOME/marketing-venv/bin/python3" Marketing/Showcase/source/render.py \
  Marketing/Showcase/source/edits.json /path/to/native-movies \
  /path/to/export --repo "$PWD"
```

The renderer produces the MP4 and timeline. Intermediates stay in the export directory. Do not commit source movies or bezel artwork. Native UI outcomes and the final edit are reviewed separately. Export checks cover full decode, 1920 by 1080, 30 fps, H.264 High/yuv420p, silent stereo AAC at 48 kHz, fast-start and chapter timings. The manifest records measured values and SHA-256 hashes. Python compilation, JSON parsing, source ranges, text bounds and `git diff --check` are also checked.
