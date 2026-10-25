# Chrome extension compatibility evidence

Date: 25 October 2026. Scope: the Mesurer measuring extension (Chrome Web Store id `icmjafcffhpcnadkmmklegommbcekcac`, version 0.2.7) installed and tried by hand on eGlu for Mac (1.0.7, macOS 27.0.1). Trial pages: example.com. No account, login or content posting was used.

## What changed in eGlu for Mesurer

| Finding | Change | Evidence |
| --- | --- | --- |
| Mesurer injects its whole interface with `chrome.scripting.executeScript` and declares no `content_scripts`. Files injected that way run in the world a manifest entry's would have used, but with no entry declared nothing put eGlu's shim there: the toolbar's "Sample color" read `EyeDropper` as undefined and showed its own "Screen color picker unavailable." | `ExtensionPreparation.manifest(_:)` adds a shim-only `content_scripts` entry (js `_eglu/shim.js`, `run_at: document_start`) to any extension that has `scripting`, matched only to the hosts it already asked for in `host_permissions`. It requests nothing new. | `testAScriptingExtensionGetsTheShimWhereItInjects`; the colour tool now works on a live page. |
| WebKit has no `EyeDropper` (the web API Mesurer's colour tool calls). No web API of WebKit's samples a colour on screen. | The Mac's own sampler answers, `NSColorSampler`, reached as `native("eyeDropper.open")`. The shim defines `EyeDropper` only where the page lacks it; in a content script it relays through the extension's own background, the same way `i18n.detectLanguage` does. A cancel rejects with a `DOMException` named `AbortError`, as Chrome's picker does. | `ExtensionAnswers.swift` case `eyeDropper.open`; EyeDropper block in `Tests/extension-shim.mjs`; tried live, below. |
| Colour picking reached from a page is new power for a page script. | `eyeDropper.open` joins `__egluCall`'s short whitelist, beside `i18n.detectLanguage` and `tabs.getCurrent`: picking a colour reads nothing of the page's, so a content script may ask for it. Arbitrary `chrome.*` calls still go only to the extension's own pages. | EyeDropper block in `Tests/extension-shim.mjs`: the relay answers through the worker, and another extension's `__egluCall` cannot ask. |
| Install reading named nothing of `EyeDropper`: it is a web API no permission names, so the missing set never contained it. | `ExtensionScan` keeps a short list of web APIs nothing answers (`EyeDropper`) and reports bare uses of them (a `new EyeDropper()` or member read, not a declaration or object key). `missing(for:)` lists `EyeDropper` only when the built shim doesn't answer it, so the warning follows the shim for real. The verdict words read "pick a colour from the screen". | `testAWebAPIsNameIsFoundUsedAlone`; `Can't find variable: EyeDropper` cases in `testJavaScriptCoresWordingNamesTheAPI`. |

## Feature by feature, tried on a live page

Installed through `-installFromStore` on the debug app; the install sheet read "Started Fine" and "May not work: record a tab." Tried 25 October 2026 from the Extensions menu's "Toggle Mesurer", which fires the action click and puts Mesurer's toolbar on the page.

| Feature | What it calls | Where it runs | eGlu's answer, tried |
| --- | --- | --- | --- |
| Toolbar on the page | `action.onClicked` → `chrome.scripting.executeScript` | Content world | Works: the full toolbar appears and every button responds |
| Select & inspect (sizes, margins, type) | Page script | Content world | Works: element pick shows box size, font, weight, line height, tracking, margins |
| Annotate, notes | Page script | Content world | Toolbar of draw/text/undo tools opens; strokes not tried |
| X-ray (outlines every block) | Page script | Content world | Works: every block element outlined |
| Guides | Page script | Content world | Works: a guide drops where dragged and stays |
| Layout guides, Responsive | Page script | Content world | Buttons present; not tried |
| Sample colour | `new EyeDropper().open()` | Content world → worker → `native` | Works: the Mac's colour loupe opens and the picked hex, rgb and oklch are shown (`#eeeeee` off the page background). A cancel rejects with `AbortError` (covered by the shim test) |
| Screenshot | drag region; a captured bitmap comes back from the worker | Worker | Works: the selected region came back as a thumbnail; which capture call answered (`getDisplayMedia` or `tabs.captureVisibleTab`) was not traced |
| Screen record | `tabCapture.getMediaStreamId` → offscreen → MediaRecorder | Worker | Does not work: WebKit has no `tabCapture`, and the install sheet already says "May not work: record a tab". The button closed the menu with no visible effect |
| Comments | Page script | Content world | Button present; not tried |
| Distances between elements, gaps/padding | Page script | Content world | Not tried |

## Package inspection

Mesurer 0.2.7 asks for `activeTab`, `scripting`, `storage`, `clipboardWrite`, `tabCapture`, `offscreen`, and `http://*/*`/`https://*/*` hosts. It has no popup, options page or `content_scripts`; its background service worker injects its UI. On this Mac `tabCapture` is unsupported and unshimmed; `offscreen` is answered by eGlu's hidden-page shim; `clipboardWrite` (the copy path) was not tried.

## Validation

- `PadCore` tests: `ExtensionPreparationTests` 16/16, `ExtensionCheckTests` 40/40, zero failures. Full suite: one failure in `DocumentPictureTests.testTheMarkerIsReadFromWebKitsKindOfURLToo`, unrelated to these changes (it reads a WebKit URL marker; nothing here touches it).
- `node Tests/extension-shim.mjs`: all assertions pass, EyeDropper cases included.
- Re-ran `-installFromStore` after the changes: install sheet reads "Started Fine", "May not work: record a tab."
