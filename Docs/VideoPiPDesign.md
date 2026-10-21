# Video design: picture in picture and DRM, on the Mac

Status: researched on 21 October 2026, challenged by Gemini and corrected where the code bore its findings out. Mac only, decided the same day: on iPad and iPhone the call apps (Google Meet among them) have apps of their own. Built on 21 October: Document Picture-in-Picture for Google Meet, a page script and a floating window (section 2), tried end to end in a Debug build with `Tests/picture.html`, not yet on a real Meet call. Its code was reviewed by Gemini the same day; 7 of its 9 findings were fixed (splits, the kept frame, a window replaced while open, a quick switch back, pop-ups during the app's call, Back to Tab with no window open, a hidden button taking clicks), one was wrong (the spec fires `enter` after the promise resolves), and one was right only in part (a kept frame's size is Chrome's behaviour too). Not built: video PiP (section 3) and the FairPlay checks (section 4). WebKit facts were read in WebKit's source (`WebKit/WebKit`, `main`, 21 October 2026); facts about sites come from their help pages and public trackers, and are marked "reported" where only users say so.

Three questions:

1. Can Safience for Mac give Google Meet and other call apps the floating call window they have in Chrome? It uses the Document Picture-in-Picture API, which WebKit lacks.
2. Can it put a video in picture in picture (PiP)?
3. Can it play Widevine DRM?

| Question | Answer |
|---|---|
| Call windows | Yes, without changing WebKit: a script gives the page `documentPictureInPicture`, built on `window.open` of a blank page, and the app floats that window above every other. Built. Open question: whether Meet offers its PiP to a browser that isn't Chrome (section 2, "What is left") |
| Video PiP | Off today: WebKit turns it off for WKWebView on macOS, with only a private switch to turn it on. Planned |
| Widevine | No. WebKit's DRM on Apple platforms is FairPlay and Clear Key, fixed in its code. FairPlay is on already; whether each service accepts it from Safience needs testing |

## 1. What WebKit has

| Fact | Where, in WebKit's source |
|---|---|
| No Document Picture-in-Picture: no preference, no `documentPictureInPicture`. WebKit is set to oppose it: on 23 April 2026 a WebKit engineer proposed resolving its standards position as oppose ([#41](https://github.com/WebKit/standards-positions/issues/41)) | `Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml` |
| MediaSession's `setActionHandler('enterpictureinpicture', …)` throws a TypeError: the action sits behind `MediaSessionExtendedActionsEnabled`, a testing preference that is off | `Source/WebCore/Modules/mediasession/MediaSession.cpp`, `MediaSessionAction.idl` |
| A script the app runs (`evaluateJavaScript`, `callAsyncJavaScript`) counts as a click while it runs: WebKit grants the page a "forced activation" and revokes it when the script ends | `WKWebView.mm`, `ScriptController.cpp`, `UserGestureIndicator.cpp`, `LocalDOMWindow.cpp` |
| `window.open` is let through only during a click (or with `javaScriptCanOpenWindowsAutomatically`, off in Safience), and consumes the click | `LocalDOMWindow.cpp` (`allowPopUp`, `createWindow`) |
| Closing a web view unloads its page, firing `pagehide` | `WebPage.cpp` (`close`), `FrameLoader.cpp` (`detachFromParent`, `closeURL`) |
| On macOS a hidden page keeps its camera and microphone (unlike iOS, where they are interrupted) | `UnifiedWebPreferences.yaml` (`InterruptVideoOnPageVisibilityChangeEnabled`, `InterruptAudioOnPageVisibilityChangeEnabled`) |
| Video PiP is off for WKWebView on macOS (`AllowsPictureInPictureMediaPlayback` defaults to false there), and its switch is private: `WKPreferences._allowsPictureInPictureMediaPlayback`. With it off, `requestPictureInPicture()` rejects | `UnifiedWebPreferences.yaml`, `WKPreferencesPrivate.h`, `HTMLVideoElement.cpp`, `MediaElementSession.cpp` |
| The DRM systems registered on Apple platforms are Clear Key and FairPlay Streaming, in a fixed list; modern and legacy EME are on by default | `Source/WebCore/platform/graphics/avfoundation/CDMFairPlayStreaming.cpp`, `UnifiedWebPreferences.yaml` |

Search, the Mac browser Safience began from, floats video by lifting the whole web view into an always-on-top panel (`upstream/main:Sources/Search/Float.swift`). Its comment blames WebKit's click rule; more likely it is the macOS default of the PiP preference above, which Search never turns on.

## 2. Call windows: Document Picture-in-Picture, built

### How Chrome and Meet do it

- `documentPictureInPicture.requestWindow({ width, height, disallowReturnToOpener, preferInitialWindowPlacement })` opens an always-on-top window with a blank page and resolves with its `Window`. The site moves its own elements in and copies its own styles. It needs a click; one at a time; it can't be navigated; it never outlives its tab; `enter` fires on open, `pagehide` in the window on close (Chrome 116, Firefox 151; [Chrome](https://developer.chrome.com/docs/web-platform/document-picture-in-picture)).
- Automatic PiP (Chrome 120): a page that set a MediaSession handler for `enterpictureinpicture` and is using the camera or microphone has the handler called when its tab is left, with no click needed; the window closes when the tab shows again ([Chrome](https://developer.chrome.com/blog/automatic-picture-in-picture)).
- Meet uses both: its PiP window has camera, microphone, hand, chat, captions and leave ([Meet Help](https://support.google.com/meet/answer/13665919)), and has opened by itself on tab switch since late 2024 ([Workspace Updates](https://workspaceupdates.googleblog.com/2024/08/picture-in-picture-in-google-meet-will-open-when-switching-tabs.html)). Its help says PiP "is only available with Google Chrome on a computer".

### What Safience does

| Part | What | Where |
|---|---|---|
| Which sites | meet.google.com. A list, not every site: a site that finds `documentPictureInPicture` may take other Chrome-only paths with it. Never a hands-off host | `DocumentPicture.hosts`, `covers` |
| The script | In the page's own world at document start, main frame only: `documentPictureInPicture` (an `EventTarget` with `requestWindow`, `window`, `onenter`, the `enter` event), the `DocumentPictureInPicture` and `DocumentPictureInPictureEvent` classes, and a wrapper on `MediaSession.setActionHandler` that keeps an `enterpictureinpicture` handler instead of letting WebKit throw | `PadCore/Sources/PadCore/Scripts/picture.js`, installed in `Mac/Sources/Page.prepare` |
| Opening | `requestWindow` checks for a click (`navigator.userActivation`) and its sizes, closes the window already open (waiting for its `pagehide`, at most a second, before it resolves), and calls `window.open('about:blank#safience-picture', '_blank', 'popup,width=…,height=…')`, as it was before the site's scripts ran. `disallowReturnToOpener` and `preferInitialWindowPlacement` ride in the address (`&noreturn`, `&initial`). The blank page is same-origin and in the page's own process, so the site gets the real `Window` it expects | `picture.js` |
| Routing | `Page`'s `createWebViewWith` floats the window when the address is the marker, the request came from the page's main frame, and the page's site is listed; otherwise the same address is an ordinary pop-up, so a frame's ad can't float a window. It is decided in `Page` and not its window, so it works with the tab off screen | `Page.webView(_:createWebViewWith:…)`, `DocumentPicture.Request` |
| The window | An `NSPanel`: floating, non-activating (a click on it doesn't bring Safience in front of the app in use), on every Space and over full-screen apps; the site's host as its title; the size asked for, kept between 240 by 135 and 80% of the screen; first at the screen's lower right, then where it was last for that site. Its web view takes the first click, so a call's buttons work with Safience behind | `Mac/Sources/PictureWindow.swift`, `DocumentPicture.size`, `origin` |
| Back to Tab | In the page's top right corner while the pointer is over the window, as macOS's own PiP window shows its controls; none when the site sets `disallowReturnToOpener`. It brings the tab forward and closes the window. Not in the title bar, as Chrome has it: in Safience (Liquid Glass, macOS 27) the system's title bar covered anything added there, as an accessory, a subview, or a bar under a see-through title bar; AppKit laid each out and drew it, and the screen never showed it | `PictureWindow.backToTabButton`, `PictureContent` |
| The page in it | None of the app's scripts (an empty script controller), playback without a click (the moved videos play on), no navigation but `about:` (a link opens in a tab beside the opener) | `PictureWindow` |
| Closing | One way, `PictureWindow.finish`, whoever closes it: its close button, Back to Tab (which also brings the tab forward), the site (`pipWindow.close()`), the opener navigating to a new document, its process ending, its tab torn down, or a newer window. The web view goes, WebKit fires `pagehide` in its page, and the site takes its elements home | `PictureWindow.finish`, `Page.pictureDidClose`, `Page.didCommit`, `tearDown`, `processEnded` |
| Staying live | A tab with a window open never freezes (`mustStay`) | `Page.mustStay` |
| On tab switch | Leaving a tab that is using the camera or microphone on a listed site: the app calls the site's kept handler in the page's world, and waits for it (up to 3 seconds). The call counts as a click, so the window the handler opens is let through, and only that window: any other pop-up during the call is refused. A window opened this way closes when the tab is back on screen, as Chrome's does, and none opens if the tab is back before the site asks. Which pages left the screen is worked out once a switch has settled, so a page passing from the tab on screen to the one beside it in a split hasn't left | `Page.leftScreen`, `cameOnScreen`, `WindowModel.checkScreen` |

### What the test showed

`Tests/picture.html` stands in for Meet: a live video (a canvas's MediaStream) and a button, moved into the window on open and back on `pagehide`, and an `enterpictureinpicture` handler set at load. A Debug build runs it with no one at the keys: `-pictureHosts 127.0.0.1 -pictureTest <report>` presses the page's buttons from the app and writes what happened (`Page.testPictureIfAsked`). On macOS 27, 21 October:

| Step | Result |
|---|---|
| Opened by the page's button | Floating panel (window layer 3) at 360 by 260 as asked, titled "127.0.0.1"; the video moved in and played on (1.5 s of playback in 1.5 s); in a screenshot, Back to Tab in the corner beside the moving video |
| Closed by the site | `pagehide` fired, the call back in the page |
| Opened without Back to Tab | Opened, played on |
| Closed by the app (as its close button does) | `pagehide` fired, the call back |
| Opened on leaving the tab | The kept handler ran and opened the window, marked automatic; played on |
| Back on the tab | That window closed, the call back |
| Opened again while open | The old window's `pagehide` came first and the call went home, then into the new window, and played on |

Not tried by hand: clicking the close button, Back to Tab and the page in the window with a real pointer, and dragging and resizing the window. The test presses only what a script can.

Found on the way:

- An `about:blank#…` URL from WebKit (an NSURL) has no fragment, though Swift's own parser finds one, so the marker is read from the address's text (`DocumentPicture.Request`, with a test).
- The title bar, above. Seen only in screenshots of the screen itself: AppKit's own drawing of the window (`cacheDisplay`) showed what the screen did not.

### What is left

1. **A real Meet call.** The person signs in and joins; the app can't. Watch for: Meet's PiP button in the call's menu, the window opening, Meet's controls working in it, leaving the tab mid-call.
2. **If Meet hides its PiP from Safari's user agent** (its help says Chrome only): find what Meet reads and change only that, in `picture.js`, before reaching for Chrome's whole user agent, which would likely send Meet down Chrome-only paths WebKit lacks and break the call (decision 3).
3. **A click Meet makes after an `await`** would reach `window.open` with WebKit's click gone, and the pop-up rule would block it. If Meet does this, `requestWindow` can ask the app to open the window from a script of its own, which counts as a click.
4. **Other call apps**: Zoom's web client, Whereby, Teams, Slack huddles, Discord. Each tried, then added to `DocumentPicture.hosts` or left out (reported: Whereby and Zoom's web client use Document PiP; Teams, Slack and Discord don't).
5. **A setting** to turn the tab-switch window off, as Chrome and Meet both have (decision 2).
6. Chrome's window matches `@media (display-mode: picture-in-picture)`; this one can't. Sites that style by it get their normal styles.

## 3. Video picture in picture (planned)

| Part | How |
|---|---|
| Turn it on | `config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")` in `Page.configuration`, only when `responds(to: Selector(("_setAllowsPictureInPictureMediaPlayback:")))`. Without the leading underscore, so key-value coding finds the setter (with it, it throws). Private API: the DMG has no App Review; a macOS update could remove it, and then the fallback is Search's Float |
| Which video | A script in the app's world reports the page's videos as they change, each under an id; PadCore picks: playing and visible first, then the largest; "sound" means an audio track, not muted, volume above 0 |
| Starting it | One `callAsyncJavaScript` names the id and calls `requestPictureInPicture()` before any `await`, while the app's click lasts |
| Command and button | In the page's menu, the command bar and the menu bar, on an unused key; a media mark on the tab (sound, PiP), which the tab bars don't have yet |
| On tab switch | Leaving a tab whose chosen video plays with sound starts PiP, as Chrome does for media from Chrome 133; coming back ends it. A setting |
| Staying live | `mustStay` while a video is in PiP (`enterpictureinpicture` and `leavepictureinpicture` reach every world) |
| Sites that refuse | `disablePictureInPicture` respected (decision 4) |

## 4. Widevine and FairPlay

- **Widevine is out.** Adding a DRM system means Safience's own WebKit build, to rebuild and keep patched for every macOS release. Google licenses the Widevine CDM by agreement, with the browser's binary signed through its Verified Media Path on macOS; the browsers that ship it are Chromium-based, and Firefox, licensed since 2016 ([Mozilla](https://support.mozilla.org/en-US/kb/enable-drm), [castLabs EVS](https://pypi.org/project/castlabs-evs/)). The only way in would be a second engine (CEF, or castLabs' Electron) for some tabs. Not recommended.
- **FairPlay is on, and unproven.** It works in WKWebView on iOS and not in Mac Catalyst's ([WebKit bug 284841](https://bugs.webkit.org/show_bug.cgi?id=284841)); Safience for Mac is AppKit. Orion, another WebKit browser for the Mac, has a long thread of Netflix failures, working in some builds and not others, with the cause unclear to its moderators ([Orion feedback 2785](https://orionfeedback.org/d/2785-netflix-stream-error/115), reported).
- **Work:** a test sheet in `Validation/` (Netflix, Disney+, Prime Video, Max, Apple TV+, Spotify): plays, in PiP, full screen, after a tab switch, licence kept after a relaunch. Fix what is Safience's doing; report the rest; list Widevine-only sites in the README's Known limitations.

## 5. Plan

| Step | What | Done when |
|---|---|---|
| 1 | A real Meet call (section 2, "What is left" 1 to 3) | Meet's window opens from its button and on tab switch, its controls work, and it closes cleanly each way |
| 2 | A setting for the tab-switch window; then other call apps | Each listed app tried, in a table in `Validation/` |
| 3 | Video PiP (section 3) | PiP from the command, the button and a tab switch on YouTube and a FairPlay service |
| 4 | The FairPlay sheet (section 4) | Each service's result recorded |
| 5 | Words: README (features, Known limitations), `Docs/Requirements.md` rows | Checked against the code |

## 6. Risks, most likely first

1. **Meet checks the browser**, not only the API. Step 1 shows it.
2. **Meet changes how it uses the API**, and a site's update breaks the window. `Tests/picture.html` covers what the API promises; a regression on Meet itself is found by use.
3. **Services refuse FairPlay from Safience**, as some refuse Orion. Out of Safience's hands when the cause is theirs.
4. **The private PiP switch goes away in a macOS update.** Checked before use; Float as the fallback.
5. **A listed site's page can open the marker address itself** and get a floating window: only from its main frame and only on listed sites, which is what Document PiP grants anyway, with the same limits (a click, one window, the site's host on it, no navigation, gone with its tab).

## 7. Decisions for you

1. **Which call apps** after Meet: all that use Document PiP, or Meet only until each is tried.
2. **The tab-switch window**: on by default with a setting, as in Chrome (recommended), or off until turned on.
3. **If Meet hides its PiP from Safari**: change only what Meet reads (recommended), Chrome's whole user agent on meet.google.com, or no call window on Meet.
4. **Video PiP**: through the private switch (recommended) or Float only; and whether to respect `disablePictureInPicture` (recommended) or override it.

## Sources

WebKit source, `main` on 21 October 2026: `Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml`, `Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm`, `WKWebViewPrivate.h`, `WKPreferencesPrivate.h`, `Source/WebKit/Shared/Cocoa/DefaultWebBrowserChecks.mm`, `Source/WebKit/WebProcess/WebPage/WebPage.cpp`, `Source/WebCore/bindings/js/ScriptController.cpp`, `Source/WebCore/dom/UserGestureIndicator.cpp`, `Source/WebCore/page/LocalDOMWindow.cpp`, `Source/WebCore/loader/FrameLoader.cpp`, `Source/WebCore/html/HTMLVideoElement.cpp`, `Source/WebCore/html/MediaElementSession.cpp`, `Source/WebCore/Modules/pictureinpicture/HTMLVideoElementPictureInPicture.cpp`, `Source/WebCore/Modules/mediasession/MediaSession.cpp`, `MediaSessionAction.idl`, `Source/WebCore/platform/graphics/avfoundation/CDMFairPlayStreaming.cpp`.

Search: `upstream/main:Sources/Search/Float.swift`.

Web, read on 21 October 2026:

- Chrome, Document Picture-in-Picture: https://developer.chrome.com/docs/web-platform/document-picture-in-picture
- Chrome, automatic picture-in-picture: https://developer.chrome.com/blog/automatic-picture-in-picture
- WebKit standards position: https://github.com/WebKit/standards-positions/issues/41
- Google Meet Help, picture-in-picture: https://support.google.com/meet/answer/13665919
- Google Workspace Updates, automatic PiP in Meet: https://workspaceupdates.googleblog.com/2024/08/picture-in-picture-in-google-meet-will-open-when-switching-tabs.html
- WebKit bug 284841, FairPlay EME in Mac Catalyst's WKWebView: https://bugs.webkit.org/show_bug.cgi?id=284841
- Orion feedback, Netflix errors: https://orionfeedback.org/d/2785-netflix-stream-error/115
- Mozilla, DRM in Firefox: https://support.mozilla.org/en-US/kb/enable-drm
- castLabs EVS, Widevine VMP signing for Electron: https://pypi.org/project/castlabs-evs/
