# What Safience takes from Search's extensions

Safience's Chrome extension support is written fresh, shaped for spaces from the start (Docs/ExtensionsDesign.md, decided 21 October 2026). Search, the Mac browser Safience began as a fork of (github.com/driceroland/Search, MIT, on this repository's `upstream` remote), found most of what goes wrong with Chrome extensions on WebKit first. Each of its commits about extensions is read before the part of Safience it touches is written, and marked here:

- **Taken**: the fix is in Safience, as it was.
- **Taken, changed**: the fix is in Safience, changed for spaces or for Chromium's rules; how is said.
- **Not needed**: it doesn't apply, and why (Search's private tabs, its one window, its bench).
- **Not read yet**.

New upstream commits are added as they land: `git log upstream/main -i --grep=extension` and the commits touching Search's extension files.

Area is from the files a commit touched; "Elsewhere" means only Search's other files (its tabs, its browser, its README). Listed oldest first, 154 commits, as of `upstream/main` 6294b6a (18 October 2026).

| Date | Commit | What Search did | Area | In Safience |
| --- | --- | --- | --- | --- |
| 2026-09-23 | `226f6f4` | Test worlds of their own, and a test run that behaves as shipped | Controller | Not read yet |
| 2026-09-23 | `419c5a5` | 1.2 | Elsewhere | Not read yet |
| 2026-09-23 | `6e95b76` | Extensions: workers that stay alive, popups sized like Chrome's | Shims, Popup, Controller | Not read yet |
| 2026-09-23 | `7da5810` | Search with the engine you pick in Settings, Google by default (#49) | Shims | Not read yet |
| 2026-09-23 | `7ecd7ff` | Chrome extensions, on WebKit | Packages, Shims, Popup, Native messaging, Settings, Controller | Taken, changed: the CRX3 check (`CRXFile`) checks every proof, ECDSA ones too, and Google's for store installs, as Chromium does; the onMessage listeners gathered behind one that follows Chrome's answer rule, changed: to Chrome 148's (an empty answer is `null`, a throw or a rejection fails the sender's call, sent as a marked answer since WebKit drops failed ones), attached only while a page listens, as Search's later commits have it; 27.0.1's WebKit already waits for a later listener, so that part is for 26 (`Scripts/extension-shim.js`); the rest of this commit is not read yet |
| 2026-09-23 | `89a550f` | Shim takes the globals it needs at start, so a sandbox can't take them away | Shims | Taken in part: the shim holds `chrome` and `runtime` from its first line, and makes `chrome` and `browser` fixed accessors that keep a replacement only if it carries the APIs (`Scripts/extension-shim.js`); the rest not read yet |
| 2026-09-23 | `8e998a6` | Extensions: popups known as popups, measured before they show | Shims, Popup, Controller | Not read yet |
| 2026-09-23 | `989cb13` | Extension popups belong to the browser's window, as in Chrome | Shims, Popup, Controller | Not read yet |
| 2026-09-23 | `9c47858` | The Chrome Web Store says "Add to Search", and nothing about switching to Chrome | Store page, Settings, Controller | Not read yet |
| 2026-09-23 | `ace649a` | Extensions: far closer to Chrome, tested against 37 store extensions | Shims, Popup, Settings, Controller | Taken in part: the `chrome-extension` scheme registered before any context takes a base address in it (`Extensions.init`), without which WebKit raises an exception; and in the shim (`Scripts/extension-shim.js`), WebKit's wrapper objects kept alive, `lastError` for a callback whose message got no reply, and `InstallEvent.addRoutes`; the rest not read yet |
| 2026-09-23 | `af2b2a7` | 1.0.1, ready to ship: version, notes, changelog and roadmap | Elsewhere | Not read yet |
| 2026-09-23 | `b86993f` | An extension's panel inside a page no longer gets the page's process killed | Shims | Not read yet |
| 2026-09-23 | `bdc784a` | Spaces, off until turned on in Settings › Tabs | Elsewhere | Not read yet |
| 2026-09-23 | `bfdf0a3` | An extension's page can send its tab to a website | Elsewhere | Not read yet |
| 2026-09-23 | `fe0b47a` | Extensions behind a puzzle button, with pinning and Reload for unpacked ones | Settings, Controller | Not read yet |
| 2026-09-24 | `033f040` | The field leaves an extension's new tab page (#42) | Elsewhere | Not read yet |
| 2026-09-24 | `0a2a640` | Merge branch 'sec4-pr-201' into sec4 | Controller | Not read yet |
| 2026-09-24 | `183c2d8` | Extensions: the update check reads <updatecheck>, not the XML declaration | Controller | Not read yet |
| 2026-09-24 | `1ab7e61` | Roadmap: extensions per space, for later | Elsewhere | Not read yet |
| 2026-09-24 | `1de91a8` | Private tabs are shown to extensions only once they carry the controller | Controller | Not read yet |
| 2026-09-24 | `1f2ec2a` | Extensions: permissions.request takes only what the manifest names | Shims | Not read yet |
| 2026-09-24 | `2427820` | Extension popups open at their size, and their button closes them (#48) | Popup | Not read yet |
| 2026-09-24 | `245a261` | Extension settings and sign-ins ask for their permissions; camera wording | Shims | Not read yet |
| 2026-09-24 | `29851de` | Pin extensions to the toolbar from Settings (#50) | Settings | Not read yet |
| 2026-09-24 | `2e79b9e` | An extension's popup page is loaded from a copy beside it, so it hears its events | Shims, Popup, Controller | Not read yet |
| 2026-09-24 | `405c41f` | Bitwarden's offscreen storage answers at once, and extensions see their own contexts | Shims | Not read yet |
| 2026-09-24 | `473b860` | iCloud Passwords pairs on the first code, and stays paired (#217) | Shims, Native messaging, Sockets, Controller | Not read yet |
| 2026-09-24 | `48fcc2b` | Passkeys under the field, once a password manager offers them | Elsewhere | Not read yet |
| 2026-09-24 | `5b9bf02` | No "Add to Search" on the store before macOS 15.4 | Elsewhere | Not read yet |
| 2026-09-24 | `6396b38` | OAuth: only the tab that began the flow may finish it (#132) | Shims | Not read yet |
| 2026-09-24 | `7173fff` | Extension packages: refuse links, and never write through one (#129) | Packages, Shims | Not read yet |
| 2026-09-24 | `7296df1` | Merge branch 'sec4-pr-161' into sec4 | Controller | Not read yet |
| 2026-09-24 | `7637df9` | Vimium C's background starts: the Chrome layer runs before a module worker's imports (#170) | Shims | Not read yet |
| 2026-09-24 | `76cee56` | Extensions load after the window, and their shim is fitted off the main thread | Shims, Controller | Taken in part: extensions load once the app has finished launching (`Extensions.loadAll`); the shim's fitting, not built yet |
| 2026-09-24 | `87e9cad` | Extensions: hold the browsing APIs to what the manifest asked for (#128) | Shims | Not read yet |
| 2026-09-24 | `93fe1cf` | Proton Pass finds sign-in forms: requestIdleCallback for extensions (#146) | Shims | Taken: `requestIdleCallback` and `cancelIdleCallback` where WebKit has none (`Scripts/extension-shim.js`) |
| 2026-09-24 | `a868137` | Passkeys stay Search's under a password manager's page script | Shims | Not read yet |
| 2026-09-24 | `a87dfe5` | Pages see nothing of Search: its scripts run in a world of their own | Shims | Not read yet |
| 2026-09-24 | `b849335` | Session Buddy's button opens it: chrome.windows.onBoundsChanged exists | Shims | Not read yet |
| 2026-09-24 | `b91ed5d` | Extensions can be allowed on private tabs, off by default (#55) | Settings, Controller | Not read yet |
| 2026-09-24 | `cbd25bb` | Extension updates are compared on everything an extension may do | Shims, Controller | Not read yet |
| 2026-09-24 | `d95798f` | Extension files and links to other apps: tighter rules | Shims | Not read yet |
| 2026-09-24 | `ee0e445` | An extension's button closes its popup on the second click (#137) | Popup, Controller | Not read yet |
| 2026-09-24 | `f06f5bc` | 1Password works: sign-in, autofill and passkeys (#126) | Shims, Sockets, Controller | Not read yet |
| 2026-09-24 | `f4297e2` | Reloading an extension asks before it gets more access, and keeps the old version on no (#135) | Controller | Not read yet |
| 2026-09-24 | `f9c1941` | A new tab's page starts at once: one process pool for every tab | Elsewhere | Not read yet |
| 2026-09-26 | `f9bb5ef` | Bookmarks can be put at a place in a folder, not only at its end | Shims | Not read yet |
| 2026-09-27 | `028c4a3` | Extension popups stay anchored after switching tab layouts (#254) | Controller | Not read yet |
| 2026-09-27 | `0386648` | An extension whose worker WebKit kept a stale copy of starts again (#266) | Controller | Not read yet |
| 2026-09-27 | `05f1b70` | Tab groups for extensions: groupId, chrome.tabGroups, tabs.group | Shims | Not read yet |
| 2026-09-27 | `074b1f6` | Passkeys: carry the WebAuthn PRF extension through (#313) | Elsewhere | Not read yet |
| 2026-09-27 | `08b44be` | A site can be allowed to play sound by itself, from its site card | Elsewhere | Not read yet |
| 2026-09-27 | `0d82ae2` | Bitwarden signs in on WebKit without the disposal symbols (#343) | Shims | Taken: `Symbol.dispose` and `Symbol.asyncDispose`, before any extension code (`Scripts/extension-shim.js`) |
| 2026-09-27 | `0da6911` | Back, forward and reload can sit before the tabs, off unless turned on (#298) | Elsewhere | Not read yet |
| 2026-09-27 | `0e343a9` | An extension's button can ask for more access again (Figma) | Shims, Controller | Not read yet |
| 2026-09-27 | `0e953cc` | The sidebar can sit on the right, in Settings › Tabs (#340) | Elsewhere | Not read yet |
| 2026-09-27 | `1a62585` | Extensions with "tabs" see every tab's address, title and icon, and hear them change | Shims | Not read yet |
| 2026-09-27 | `1e8eb0c` | extensions hear what their background sends their pages | Shims | Not read yet |
| 2026-09-27 | `22426d3` | What's new after an update; ⌃Tab's switcher always on; no New tabs at the top | Shims, Controller | Not read yet |
| 2026-09-27 | `2ed2c52` | An extension's worker and its offscreen document hear each other, so ScriptCat's GM_xmlhttpRequest works (#319) | Shims | Not read yet |
| 2026-09-27 | `2f90ce5` | A tab no longer wears another site's icon (#216) | Elsewhere | Not read yet |
| 2026-09-27 | `3ac6791` | An extension that fails to install, update or reload keeps its working copy | Controller | Not read yet |
| 2026-09-27 | `411f828` | Extensions: downloads.open needs its permission and opens only the extension's own downloads | Shims | Not read yet |
| 2026-09-27 | `4433192` | the extension popup follows a width its page names, both ways | Popup | Not read yet |
| 2026-09-27 | `45d9592` | Several windows (2 to 4): ⌘N, menus and keys to the window in front, every window saved | Elsewhere | Not read yet |
| 2026-09-27 | `46d8e0d` | Extensions: search, notifications, idle, power and tts need their permission; search.query only searches | Shims | Not read yet |
| 2026-09-27 | `480a089` | Two builds: Apple Silicon and Intel, each with its own download and feed; built for size | Shims | Not read yet |
| 2026-09-27 | `4916b67` | Settings › Extensions brings extensions over from another browser (#261) | Settings | Not read yet |
| 2026-09-27 | `52e47a6` | Private tabs aren't pinned, tabs open in their own window's space, and a few edges tighten | Elsewhere | Not read yet |
| 2026-09-27 | `559f97e` | Bring Things Over… in the File menu and in Settings › General | Elsewhere | Not read yet |
| 2026-09-27 | `5970529` | Extension commands keep to keys Search doesn't use | Elsewhere | Not read yet |
| 2026-09-27 | `5d59cc6` | Several windows (7): extensions see every window | Controller | Not read yet |
| 2026-09-27 | `6059f4f` | Native messaging hosts registered with Vivaldi or Opera are read too (#302) | Native messaging | Not read yet |
| 2026-09-27 | `62b8530` | Extensions: a popup's messages come with no tab; tabGroups.Color; pages asked for by path keep their query | Shims | Not read yet |
| 2026-09-27 | `6425906` | Extensions: tabs are never sent to javascript: or file: addresses | Controller | Not read yet |
| 2026-09-27 | `6977771` | ⌘F puts the keyboard in the find field every time (#172) | Elsewhere | Not read yet |
| 2026-09-27 | `6da963a` | Shortcuts, sign-in flows, AppleScript and installs: the last edges before 1.0.4 | Shims, Controller | Not read yet |
| 2026-09-27 | `70bb962` | Extensions can't open a private window | Controller | Not read yet |
| 2026-09-27 | `7bfa35e` | 1Password's popup hears the app; popups without a button open by the buttons | Shims, Popup, Controller | Not read yet |
| 2026-09-27 | `7c86931` | NordPass's sign-in returns to its extension page (#323) | Elsewhere | Not read yet |
| 2026-09-27 | `8176f3e` | A disabled or removed extension's offscreen page and keep-awake go with it | Controller | Not read yet |
| 2026-09-27 | `8417d53` | Extensions: Search's own message envelopes are taken from the extension itself only | Shims | Not read yet |
| 2026-09-27 | `85569fd` | One sheet for bringing things over, with profiles and counts | Controller | Not read yet |
| 2026-09-27 | `85a923f` | Tab groups: one place puts the row in the order it is shown | Elsewhere | Not read yet |
| 2026-09-27 | `950c336` | Tabs opened in the background can wait to load, off unless turned on (#196) | Elsewhere | Not read yet |
| 2026-09-27 | `9bd1966` | Extensions' keyboard shortcuts can be changed in Settings › Shortcuts (#189) | Controller | Not read yet |
| 2026-09-27 | `9e57023` | The open bookmarks list holds the folded column out (#89) | Elsewhere | Not read yet |
| 2026-09-27 | `a3aa279` | Extensions: site access never includes other extensions' pages | Controller | Not read yet |
| 2026-09-27 | `a4083d3` | Started hidden, extensions load before the restored page (Fixes #199) | Controller | Not read yet |
| 2026-09-27 | `b0f93c4` | windows.update can move and size a window | Controller | Not read yet |
| 2026-09-27 | `b319bce` | no offer to save a password typed into an extension's own page | Elsewhere | Not read yet |
| 2026-09-27 | `bb308b4` | Your own keyboard shortcuts, in Settings › Shortcuts (#36) | Elsewhere | Not read yet |
| 2026-09-27 | `bd09fb3` | Reload from origin on ⌥⌘R, as in Safari; ⌘R reloads normally (#179) | Controller | Not read yet |
| 2026-09-27 | `c3611a3` | Extensions: a popup's window.open and a sign-in flow keep to the same addresses as tabs.create | Shims, Popup | Not read yet |
| 2026-09-27 | `c5db6de` | Extensions' tab calls find the tab in its own window | Shims | Not read yet |
| 2026-09-27 | `c8031aa` | Downloads show while they happen: a circle in the chrome, the file's progress in the Finder and the Dock | Elsewhere | Not read yet |
| 2026-09-27 | `dbdc016` | A second click on an extension's button closes its popup (#248) | Popup | Not read yet |
| 2026-09-27 | `e10e5ec` | Extension popups load their own page again; storage changes reach them through the background | Shims, Popup, Controller | Not read yet |
| 2026-09-27 | `e4115b0` | Store pages: the extension installed is the one in the page's /detail/ path, on https only | Packages, Store page, Settings | Taken: `ExtensionStore.id(ofPage:)` |
| 2026-09-27 | `e57866c` | Extensions that watch their sign-in tab for the chromiumapp.org address get it (Figma) | Shims, Controller | Not read yet |
| 2026-09-27 | `e78066f` | Put back what 22426d3 undid: Shortcuts, sign-in flows, AppleScript, imports | Shims, Controller | Not read yet |
| 2026-09-27 | `f98e3bf` | Tab groups: quiet headings, and a group lasts as long as its tabs (#242) | Shims | Not read yet |
| 2026-09-27 | `ff1ac38` | Bringing things over reads files more carefully | Elsewhere | Not read yet |
| 2026-09-28 | `08a937d` | Split View: an extension can't move typing from one page of the pair to the other | Shims, Controller | Not read yet |
| 2026-09-28 | `1afc650` | Offscreen documents stay on the extension's own pages | Offscreen | Not read yet |
| 2026-09-28 | `2e198d4` | Recorders: test runs keep Search's question; websites get the pretend devices too | Capture | Not read yet |
| 2026-09-28 | `313c731` | The recording pill: an extension recording says so, with Stop | Elsewhere | Not read yet |
| 2026-09-28 | `31be81f` | A site's icon is kept by its host and port (#413) | Shims | Not read yet |
| 2026-09-28 | `3639a2e` | Fix SingleFile worker and background downloads | Shims | Taken in part: SingleFile's own `browser` getter is left alone (`Scripts/extension-shim.js`); its worker and downloads fixes not read yet |
| 2026-09-28 | `3674374` | Pictures, popup windows and drops: tighter checks | Controller | Not read yet |
| 2026-09-28 | `3d2c1bc` | Camera and microphone questions from an extension's pages are the extension's own | Popup | Not read yet |
| 2026-09-28 | `41fccbc` | Extension rules WebKit's patterns can't hold are written so they can | Shims | Not read yet |
| 2026-09-28 | `46b4b7b` | Recorders: the pill shows what the broker sees; a refusal holds for the session | Capture | Not read yet |
| 2026-09-28 | `605ecff` | Recorders: the extension's button counts for a minute; a tab sharing its screen gets the pill | Capture, Controller | Not read yet |
| 2026-09-28 | `6167f92` | An extension's popup window answers windows.getCurrent for itself (#408) | Shims | Not read yet |
| 2026-09-28 | `686cf03` | Recorders: every screen recording through Search's question; offscreen recorders (phase 2) | Shims, Popup, Offscreen, Capture, Controller | Not read yet |
| 2026-09-28 | `7a76796` | Extension site access and page questions: tighter checks | Shims, Controller | Not read yet |
| 2026-09-28 | `7b48160` | Extensions, sign-in flows, icons and test runs: more checks | Shims, Controller | Not read yet |
| 2026-09-28 | `99d6e50` | Relayed extension messages pair with WebKit's own copies by count | Shims | Not read yet |
| 2026-09-28 | `9bd5be5` | An extension's popup window is a small window of its page | Controller | Not read yet |
| 2026-09-28 | `a352b40` | Recorders: a site's Stop ends its screen share only, not its call | Capture | Not read yet |
| 2026-09-28 | `b32cf82` | Offscreen documents: one per extension, loaded before use, never shown (#192) | Shims, Offscreen, Controller | Not read yet |
| 2026-09-28 | `b942d34` | Relayed messages pair only with the extension's own, on their whole text | Shims | Not read yet |
| 2026-09-28 | `ba34243` | Fix function script injection from embedded extension pages | Shims | Not read yet |
| 2026-09-28 | `c0d57c9` | Extensions can record the screen: the broker, the channel and the shim (work in progress) | Shims, Capture, Settings, Controller | Not read yet |
| 2026-09-29 | `8ccacae` | Apps on this Mac answer only an extension that asks for them itself | Controller | Not read yet |
| 2026-09-29 | `ca0c0f0` | An extension's items show once in a page's right-click menu (#456) | Controller | Not read yet |
| 2026-10-08 | `122b57d` | An extension's downloads never go through a private tab | Shims | Not read yet |
| 2026-10-08 | `3a2c633` | A worker that is a link to a file of its own package gets the shim (#481) | Shims | Not read yet |
| 2026-10-08 | `6586825` | Settings pages open at their top, and an extension's actions in a … menu (#479) | Settings | Not read yet |
| 2026-10-08 | `85d8cb9` | Popovers keep their rounded corners before macOS 26 | Controller | Not read yet |
| 2026-10-08 | `865c0b2` | Extensions from a folder keep only the links that lead inside them | Controller | Not read yet |
| 2026-10-08 | `8cb1709` | Extensions: files on this Mac are never among the sites given | Shims, Controller | Not read yet |
| 2026-10-08 | `a1c846b` | Pinned extensions give way in the column's bottom row (#535) | Controller | Not read yet |
| 2026-10-08 | `ad177b3` | A website an extension lists can message it, as in Chrome (#496) | Elsewhere | Not read yet |
| 2026-10-08 | `bd3d78a` | Extensions loaded from a folder get Chrome's id from their path (#440) | Packages, Shims, Controller | Taken: `ExtensionID.id(forUnpackedPath:)`; resolving the real path is the caller's |
| 2026-10-09 | `fa5ecab` | Content scripts' ports stay unwrapped for extension workers (#506) | Shims | Not read yet |
| 2026-10-15 | `c9f283b` | A bookmark opens in a tab of its own, never in place of a pin | Elsewhere | Not read yet |
| 2026-10-16 | `21143e8` | A native host's connection ends when its output closes, not when it exits (#483) | Native messaging | Not read yet |
| 2026-10-16 | `27b15f6` | Ports hear once when an extension's worker is really restarted (#453) | Shims, Recovery, Controller | Not read yet |
| 2026-10-16 | `2fd21ac` | An extension's side panel, beside the page (idea 261) | Shims, Side panel, Controller | Not read yet |
| 2026-10-16 | `5f1038c` | Claude in Chrome signs in; its tab groups work with groups off | Shims | Not read yet |
| 2026-10-16 | `6f40bd2` | Shortcuts on non-Latin keyboard layouts (#568) | Elsewhere | Not read yet |
| 2026-10-16 | `79c2f4b` | ⌘T can raise the field over the page, as in Arc (#601) | Elsewhere | Not read yet |
| 2026-10-16 | `92f7c3a` | Settings > General > Home page, while an extension offers a page (#472) | Settings, Controller | Not read yet |
| 2026-10-16 | `aea9871` | Affinity Pathfinder's sign-in works from its panel on a website (#612) | Shims | Not read yet |
| 2026-10-16 | `b2d8314` | Discover extension-only profiles and ego lite (#507) | Elsewhere | Not read yet |
| 2026-10-16 | `ca55c12` | Keep the browser folder pick in memory, bound import reads, say when macOS refuses (#415) | Elsewhere | Not read yet |
| 2026-10-16 | `cff4850` | Extensions keep checking for updates while Search stays open (#589) | Controller | Not read yet |
| 2026-10-16 | `d3acea6` | Test what an extension's panel is sent of a site's cookies | Elsewhere | Not read yet |
| 2026-10-16 | `ef889cd` | Panel cookies: a relaunch changes nothing; claude.ai's session is Lax | Elsewhere | Not read yet |
| 2026-10-16 | `f14347a` | AdBlock's background starts: webRequest listeners leave out the types WebKit doesn't know (#600) | Shims | Not read yet |
| 2026-10-18 | `6294b6a` | A quiet sign-in flow's page can ask for nothing and send nothing elsewhere | Shims | Not read yet |
| 2026-10-18 | `b16caeb` | Non-interactive launchWebAuthFlow runs out of sight, as in Chrome | Shims | Not read yet |
