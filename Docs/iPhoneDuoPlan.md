# iPhone Duo: implementation plan

Status: planned on 21 October 2026 from `Docs/iPhoneDuoDesign.md` (commit b293e75), with the code at that commit and the iOS 27.1 SDK's headers; reviewed by Codex and Mercury (section 8). The same day, a review of the whole iPhone app was added (section 4): motion and interaction by Emil Kowalski's design engineering principles, the Swift by the write-swift guide, and every iPad-only feature checked for a reason to keep it off the iPhone. Nothing is built. Section numbers (§) are the design note's.

## 1. What the code and the SDK add to the design note

**This Mac can run step 0 now.** Xcode 27.1 (27A9275), the iOS 27.1 SDK and simulator runtime, and the iPhone Duo device type are installed.

**The APIs, as the SDK declares them** (`iPhoneSimulator27.1.sdk`, UIKit headers):

| API | Declared | Use here |
|---|---|---|
| `UITraitCollection.verticalBarEdge`: `.unspecified`, `.leading`, `.trailing` | iOS 27.1, `UIVerticalBarEdge.h` | Which layout; which side |
| `UITraitCollection.systemTraitsAffectingVerticalBarEdge` | iOS 27.1 | The traits to register for; `verticalBarEdge` is a property, not a trait of its own |
| `UIView.reservedRegions(kind: .division / .occlusion, options: [.includeInactive])` returning `frame` (margins included), `margins`, `isActive` | iOS 27.1, `UIView.h`, `UIViewReservedRegion.h:31-35` | The fold; the cameras |
| `UIView.LayoutRegion.bar(onEdge:extent:)` with `layoutGuide(for:)` | iOS 27.1 / 26.0, `UIViewLayoutRegion.h` | A custom strip's place, if the system's bar can't be used |
| `UIViewController.preferredVerticalBarBehavior`, `childForPreferredVerticalBarBehavior`, `setNeedsUpdateOfVerticalBarConfiguration()` | iOS 27.1 | The header says the vertical bar adds a leading or trailing safe area inset |
| `UIBarButtonItem.axisBehavior` (`.verticalPreferred`, `.horizontalOnly`) | iOS 27.1 | Strip items |
| `UIBarButtonItem.visibilityPriority` (`.low`, `.standard`, `.high`) | iOS 27.0 | Back and Tabs last to overflow |
| `UIBarButtonItem.badge` (`.count(_:)`) | iOS 26.0 | The tab count |
| `UINavigationItem.additionalOverflowItems` | iOS 16.0 | The page menu in the system's overflow |
| `UIWindowSceneActivationAction(alternate:)` | iOS 15.0 | New Window in UIKit menus; the alternate runs where windows can't be made, and its handler when the request fails |
| `UIWindowSceneDelegate.windowScene(_:didUpdateEffectiveGeometry:)` | iOS 26.0 | Called whenever the scene moves between screens |
| `UIHinge.status` (`.closed`, `.partiallyOpen`, `.fullyOpen`), `angle` | iOS 27.1, `UIHinge.h` | Fallback trigger only |

No SwiftUI API for the vertical bar was found; SwiftUI has only `ReservedRegion`.

**Corrections to the design note:**

| # | The note says | The code or SDK says | Effect on the plan |
|---|---|---|---|
| 1 | Register `verticalBarEdge` alongside the width class (`Browser.swift:325`) | Register `UITraitCollection.systemTraitsAffectingVerticalBarEdge` | Phase 2 |
| 2 | The page stops at the strip; `Page.obscure` covers only the bottom | The vertical bar adds a side safe area inset, and the stack is pinned to the safe area's sides (`Browser.swift:376-379`) | No `obscure` change with the system's bar; only the custom strip needs a constraint |
| 3 | `Browser` goes into a `UINavigationController` | `SceneDelegate.browser` casts the root to `Browser` (`AppDelegate.swift:32`): focus, state restoration, disconnect and links would all stop | Phase 2 keeps the `Browser` in a property |
| 4 | Read the fold in `Browser.updateConstraints()` | `Browser` is a view controller; `updateConstraints()` is `UIView`'s. Apple's re-run promise is for views | A root view of its own (`loadView`) overrides `updateConstraints()` |
| 5 | The sidebar's rows: check the `GeometryReader` at `SideTabs.swift:234` | That is the loading line. The width is fixed twice: `.frame(width: Self.width)` (`SideTabs.swift:90`) and the constraint (`Browser.swift:413`); the page's start is set by `card(_:)` (`Browser.swift:824`) | All three change together in Phase 3 |
| 6 | The command bar goes into one half (decision 6) | It is centred on the stack (`Browser.swift:553`), which already starts beside the sidebar | Comes free once the sidebar reaches the fold |
| 7 | Device checks follow the width class | `Device` is app-wide (static); menus are built once for the app; commands and settings are also filtered in suggestions (`Suggestions.swift:355`, `:360`), each by `Device.offers` | Phase 4 gives every list one per-window check |
| 8 | Narrow windows follow the width class | On iPad, a narrow window keeps the tab bar, focus page, Split View and site mode commands (`Menus.swift:34` tests the idiom) | iPad stays as it is; only the Duo changes |
| 9 | (not covered) | UIKit builds the main menu "on iPad and Mac only" (`Menus.swift:17`); the Duo's idiom is `.phone`. Whether it builds it, and passes ⌃⌥ keys, on the Duo is unknown | Step 0 checks with a hardware keyboard; Phase 4 has the fallback |
| 10 | Folding resizes the same scene, "typing and all" | A change of width class ends an address being typed and gives the keys back to the page (`Browser.swift:618-628`, `:728`) | Decision 8 |

## 2. Decisions

The note's §8, taken as it recommends:

| # | Taken |
|---|---|
| 1 | The system's vertical bar; Safience's own strip only if the spike fails |
| 2 | Page menu in the system's overflow (`additionalOverflowItems`) |
| 3 | Back, Forward at the top; New Tab, Tabs, overflow at the bottom |
| 4 | Inner display in landscape: the iPad's bars along the top, beside the status bar's strip |
| 5 | iPad-only settings offered on the Duo closed and open |
| 6 | Command bar in the page's half (free, correction 6) |
| 7 | Split View dividing at the fold: later, not in this plan |

New, decided on 21 October 2026:

| # | Question | Taken |
|---|---|---|
| 8 | An address being typed when the Duo opens or closes | Carried over: the typed text and the cursor move to the other field (the bar at the bottom or the command bar), as Apple asks. Today's rule (typing ends) stays for an iPad window resized |
| 9 | A large iPhone held landscape (Pro Max, Plus, Air: regular width) | Keeps the iPad's bars, as today, and gets what that layout lacks there: Split View, Request Desktop or Mobile Site, the Window settings, Desktop View (Phase 4). The README's "an iPhone either way up" is corrected |

How the work runs:

| Topic | Decided |
|---|---|
| Posture testing | Turning any simulator works from the shell: `xcrun devicectl device orientation set landscapeLeft --device <id>`. Folding doesn't: Device Hub has no accessibility interface and no command reaches the Duo's hinge. You leave the Duo closed; fold and half-fold checks wait for you and are listed as not run |
| Syncing | Nothing related to syncing changes (`Shared/Sync.swift`, `HistoryCloud`, iCloud and its saves): it is being worked on in another session |
| Landing | Each phase on its own branch and its own pull request against main, for your review; nothing merges without you. Until the History pull request (taehee-pd/Safience#22) merges, a phase's pull request has `claude/history` as its base so its diff shows only its own work |
| Simulators | One at a time. The iPad Pro 11-inch (M5) simulator may be used and shut down for iPad checks |

## 3. Phases

Each phase is one pull request, except 0 and 1, which merge only their findings. Everything new is behind `#available(iOS 27.1, *)`; the deployment target stays iOS 17. iPhone and iPad must look and behave as before after every phase.

### Phase 0: Measure

- Add the Duo's values to the diagnostics overlay (`showDiagnostics`, Settings › Diagnostics), so they read on screen in any posture: window size, both size classes, `verticalBarEdge`, `layoutDirection`, safe area insets, each reserved region (kind, frame, margins, active), `UIHinge` status, `windowScene.screen.bounds`, idiom, `supportsMultipleScenes`.
- Build Debug with the 27.1 SDK for the iPhone Duo simulator. Measured first: closed, upright (the posture Device Hub is left in; 466 by 678 points, the status bar in a strip on the right, seen on 21 October). With you, by hand in Device Hub: closed and turned; open portrait and landscape; half folded like a book and like a laptop; open, as either app of a system Split View.
- Also find out:
  - Does `buildMenu` run, and do ⌃⌥ shortcuts fire, with a hardware keyboard (correction 9)?
  - Does `Session.openWindow` fail while closed, and what does `UIWindowSceneActivationAction` do then?
  - Does a fold without a change of window size re-run a view's `updateConstraints()`? (Needs you to fold.)
  - Answered: folding is by hand only (`simctl` has no posture command; Device Hub has no accessibility interface).

Done when: the closed posture's values replace the third parties' in §2 of the design note, the other postures are listed as waiting for you, and the questions that need no fold have answers.

Result (21 October): the closed Duo, upright, is measured in the design note's §2. Answers: UIKit builds the main menu on the Duo, so the ⌃⌥ keys should arrive through it (key delivery itself needs a hardware keyboard, not tried); New Window succeeds while closed in the simulator, the new window taking the old one's place, so Phase 4's failure handling stays as a safeguard for devices. Waiting for you: open, half-folded, Split View, and turned (the Duo resets `devicectl`'s orientation to portrait).

### Phase 1: Spike the system's vertical bar (throwaway branch)

Wrap `Browser` in a `UINavigationController` and try each variant; all three are tried, then the best is chosen.

| Variant | Navigation bar | Items | Pass if |
|---|---|---|---|
| A | Hidden | `toolbarItems`: Back, Forward, New Tab, Tabs; `additionalOverflowItems` | Back and Forward at the top and the others at the bottom, as decision 3; the overflow menu shows the extra items |
| B | Shown in the strip layout only (it is vertical there) | `navigationItem` leading: Back, Forward; toolbar: New Tab, Tabs; `additionalOverflowItems` | The same |
| C | None | A SwiftUI strip placed by `view.layoutGuide(for: .bar(onEdge:extent:))`, the page menu as a SwiftUI `Menu` at its foot | Clear of the status bar, the island and the cameras |

For A and B also check, on the Duo, an iPhone 17 Pro and an iPad Pro: the status bar's style still comes from `Browser` (`applySiteColor`, `setNeedsStatusBarAppearanceUpdate`); presentations (Welcome, Settings, share, `TabSheet`); `Browser.keyCommands` (Escape, the suggestion arrows) still answer; nothing moves on iPhone or iPad, with both bars hidden there. A failure in any of these rules the variant out.

Done when: one variant is chosen and noted in the design note's §3.

Result (21 October): B, noted in the design note's §3. A puts every item at the strip's foot and shows no overflow; C works as a fallback. B's one cost is the navigation bar's 24-point top inset, which Phase 5 takes back for the page. Status bar style, presentations and keys are checked in Phase 2, where the navigation controller comes in for good.

### Phase 2: Groundwork (no visible change)

| File | Change |
|---|---|
| `AppDelegate.swift` | `SceneDelegate` keeps `browser` as a stored property; the window's root is the navigation controller only if Phase 1 chose A or B |
| `Browser.swift` | A root view of its own (`loadView`) whose `updateConstraints()` calls back into `Browser`, for Phase 3 |
| `Browser.swift` | `WindowModel.strip: Edge?` beside `phone`, set in `refreshChrome()` to the side `verticalBarEdge` names, only when the width is compact and the edge is `.leading` or `.trailing`. iPhone and iPad report `.unspecified`, so `strip` stays nil there. `registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge)` beside line 325 |
| `PadCore/Sources/PadCore/DuoLayout.swift` (new) | `sidebarWidth(sidebarStart:fold:rightToLeft:standard:minimum:)`, from the fold's frame (margins included), returning the sidebar's width and the page's start; plain `CGRect` and `CGFloat`, as `TabWidths` uses |
| `PadCore/Tests/PadCoreTests/DuoLayoutTests.swift` (new) | Book fold, laptop fold, none, inactive, right to left, a fold nearer the edge than the sidebar's minimum |
| `CloudAndSiteModeTests.swift:6-11` | The measured Duo sizes in place of the third parties' |

Done when: `swift test` passes in `PadCore`; the app builds; iPhone, iPad and the Duo look as before.

### Phase 3: The sidebar to the fold (§5)

- One function sets the sidebar's width (the constraint at `Browser.swift:413`, kept in a property) and `stackBeside.constant` together, from `DuoLayout`. `card(_:)` calls it instead of setting `stackBeside.constant = bezel` itself (`Browser.swift:824`), so neither undoes the other.
- The root view's `updateConstraints()` calls it while `sideShown`: for an active division region taller than wide, the width reaches the fold and the page starts past it; otherwise 248 and `Side.bezel`. Animated as the device folds (a spring, `layoutIfNeeded`).
- `SideTabs.swift:90`: `.frame(maxWidth: .infinity)` in place of the fixed width, so UIKit's constraint decides. Any row, pinned tile (`Shared/PinnedLook.swift`), Bookmarks row or `SideSpaces` that keeps a fixed width gets the same.
- Right to left: the sidebar on the right fills the right half (from `DuoLayout`).
- If Phase 0 found no re-run on fold: `UIHingeInteraction` status changes call `setNeedsUpdateConstraints()` on the root view.

Done when: folded like a book, the sidebar fills its half and the page card starts past the fold; like a laptop and fully open, 248; right to left mirrored; iPad unchanged.

### Phase 4: The iPad's features in every regular-width window (§4, decision 9)

The Duo open and a large iPhone held landscape are the same case: the phone idiom in a regular-width window, which shows the iPad's bars (`Browser.swift:615`) while the menus, settings and commands follow the idiom. On a small iPhone the window is never regular width, so it stays as it is.

One per-window check for every list of commands and settings:

| Check | Today | Becomes |
|---|---|---|
| `Device.phone` (`Menus.swift:22`) | Idiom | Stays the idiom, for the hardware: user agent (`Page.swift:487`), `touchFirst` (`:682`), the context menu's wait (`:1553`), "View on iOS" (`Spaces.swift:231`), the welcome's text (`Welcome.swift:216`: no trackpad, so the iPhone's) |
| `Device.isDuo` (new) | | Idiom `.phone` with `supportsMultipleScenes`, if Phase 0 confirms it tells the Duo from an iPhone. Used only for decision 5 |
| `Device.offers(_:in:)` (new, replaces `offers(_:)`) | Idiom | iPad: as today. Phone idiom: by its window's width class (tab bar, focus page, Split View, site mode only when regular) |
| Main menu (`Menus.build`) | `Device.offers` | Where UIKit builds it for the phone idiom (Phase 0), every command is built and `Browser.validate(_:)` hides those `offers(_:in:)` refuses for its window. iPad unchanged |
| Suggestions (`Suggestions.swift:355`, `:360`, `:510`) | `Device.offers`, `Device.keys` | `offers(_:in:)` and the window's `model.phone`, so the command bar and the menus agree |
| `SettingsView.swift:28`, `Device.offers(anchor)` | Idiom | Passed in by the presenting `Browser`. Duo: both the iPhone's and the iPad's sections (decision 5). Large iPhone: by the presenting window's width (in landscape, Window and not Desktop View's cursor speed; upright, as today). `SettingsAnchor.isOffered(phone:)` becomes `isOffered(phoneLayout:padLayout:)`, with a test |
| Desktop View (`Browser.swift:690`, `:693`, `:1884`) | Phone width only; turning to landscape leaves it | Phone idiom at any width, kept across a turn; `DesktopPad`'s layout checked at 956 by 440 |
| A split made in landscape, seen upright | One pane shows, and nothing upright can separate it (`Browser.swift:1030`, `Menus.swift:34`) | Separate Tabs in the page menu (`PhoneBar.swift:216-232`) and the tab card menu (`TabOverview.swift:379-441`) while the tab is in a split |
| `README.md:165` | "an iPhone either way up" gets the bar at the bottom | Says which iPhones keep the iPad's bars in landscape |
| New Window (`Menus.swift:33`) and Open in New Window (`Bars.swift:211`, `SideTabs.swift:728`, `:779`) | `supportsMultipleScenes` | UIKit menus: `UIWindowSceneActivationAction`, with New Tab as its alternate. SwiftUI menus: shown on the Duo only while the window is regular width, re-checked in `windowScene(_:didUpdateEffectiveGeometry:)` |
| `.tabInNewWindow` (`Browser.swift:1762-1775`) | Separates the tab from its split and moves this window off it, then asks for a window | A failed request (`Session.openWindow`'s error handler) puts the tab back on screen in this window |

- **Keys on the phone idiom.** If Phase 0 finds UIKit builds no main menu for the phone idiom (as `Menus.swift:17` says), `Browser.keyCommands` (`Browser.swift:1368`) returns every command's chord (from `Shortcuts`) that `offers(_:in:)` allows, while a hardware keyboard is connected (`GCKeyboard.coalesced`). Today it has only Escape and the suggestion arrows. This also brings shortcuts to an iPhone with a keyboard (section 4.3).
- **Typing across a fold (decision 8):** when `model.phone` changes while an address is typed on the Duo, the text and the selection go to the other field and the keys go with them, in place of ending the typing (`Browser.swift:623-626`).
- The 600 by 500 desktop rule (`SiteMode.swift:12`) and the 728-point Split View rule (`Browser.swift:1021`) checked against Phase 0's sizes; changed only with a test.

Done when: open, the Duo has the iPad's menus, shortcuts, settings, command bar commands and Split View in landscape; closed, no New Window, and a failed one loses nothing; an address typed survives opening and closing; an iPhone 17 Pro Max turned to landscape has Split View, Request Desktop Site, the Window settings and Desktop View, and turned back upright can separate a split; a small iPhone and iPad as before.

### Phase 5: The outer display (§3)

When `model.phone` and `model.strip != nil` (the Duo closed, or in system Split View):

- `PhoneBar`: a one-row form, space button then the address (star, reload), 56 points (`PhoneBar.stripHeight`); `PhoneTools` and `PageMenu` not shown. Typing as now.
- `ComingAddress` (`PhoneBar.swift:96-106`), the next tab's row during a sideways swipe: drawn as the one-row form (space button, no ellipsis) in this layout, so the preview matches what lands.
- `Browser`: the bar's height (`Browser.swift:445`, `:675`), `phoneCovered` (`:1112`) and the start page's inset (`:1099`) use the current layout's height, not `PhoneBar.height`.
- The strip, by Phase 1's variant. A or B: `UIBarButtonItem`s with symbol and title, `axisBehavior = .verticalPreferred`; Back and Tabs `visibilityPriority = .high`; Tabs with `badge = .count(n)`, a tap for `showTabs`, a menu for New Tab and the closes (as `TabsButton`); enabled states from `WindowModel` through Combine. The page menu as UIKit elements for `additionalOverflowItems`: a `PageMenuElements` builder from the same `BarAction`s as `PageItems` and `AppItems` (SwiftUI today), so both menus come from one list. C: the `SideStrip` view with `PageMenu` at its foot, and the stack's side pinned to the strip's inner edge.
- The system's navigation bar and toolbar are hidden in every layout but this one. The phone bar itself stays as today wherever `model.phone` is true.

Done when: closed upright and turned, and as either app in Split View, the bar and strip as §3 says; typing, both swipes, the tab sheet and Desktop View as before; iPhone unchanged.

### Phase 6: Documents and screenshots (§6 step 5)

`Validation/CHECKLIST.md` §8, `Docs/Requirements.md`, the README's iPhone section, `CHANGELOG.md`; real Duo screenshots from the simulator in place of the composites (`Marketing/AppStore/iPhone-Duo-inner`, `iPhone-Duo-outer`). Uploading them to App Store Connect waits for your OK.

## 4. The iPhone review

Three read-only passes over the iPhone's code (motion and interaction by Emil Kowalski's principles; the Swift by the write-swift guide; every iPad feature against the iPhone), and the app run on an iPhone 17 Pro simulator (iOS 27.0): the welcome, the start page, typing an address, a page, the page menu, the tab sheet. "Line read" means the cited code was re-read and the finding holds; "Reported" means it comes from a pass and is re-read before it is changed.

### 4.1 Motion and interaction (Phase B)

| # | Where | Before | After | Why | Checked |
|---|---|---|---|---|---|
| 1 | `Browser.swift:1432`, `:1542` | A sideways swipe is refused while the last slide's 0.4 s spring settles | Drop `!slideSettling`; a new swipe takes the stage's presentation transform, removes the running animation and carries on from there, finishing the last slide first if it was going through | Flipping through tabs is quick and repeated; the spring was chosen to be interruptible; a 400 ms lockout is over the 300 ms ceiling | Line read |
| 2 | `Browser.swift:1545-1551` | The page's spring starts at the finger's speed; the address row's SwiftUI spring starts from rest | `withAnimation(.interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: start))` | On every release the address lags the page, then catches up | Line read |
| 3 | `Bars.swift:333-338` | The address (host and path) truncated in the middle | On the phone, the host alone, truncated at the head | Middle truncation can cut out the registrable domain, the part that says who you are talking to | Line read |
| 4 | `TabSheet.swift:169`, `:231` | The tabs ignore touches until the spring is fully at rest, about 250 ms after the sheet looks open | Turn touches on where `landed` becomes true (progress 0.99) | Taps on a sheet that looks open are dropped, every time it opens | Line read |
| 5 | `Suggestions.swift:483` | Rows answer `.onTapGesture`, with no pressed state | A `Button` with a row style: `Color.primary.opacity(0.1)` while pressed, no animation in, 0.15 s ease-out out | A touch must show it registered | Line read |
| 6 | `Bars.swift:345-346`, `:410` | VoiceOver hears "Address, …" without "Not secure" | Add ", Not secure" when the icon warns | VoiceOver users miss the warning | Reported |
| 7 | `Design.swift:241-254` | `iconSwap` grows from 25% out of a 4 pt blur, also under Reduce Motion, for the star, reload and stop, and clear | Star and reload/stop: `.contentTransition(.symbolEffect(.replace))`; clear: `.opacity` | A quarter scale is close to "from nothing"; reload/stop swaps at every load; the system effect follows Reduce Motion | Line read |
| 8 | `PhoneBar.swift:42`, `:45` | Cancel and the page menu slide in from the trailing edge, also under Reduce Motion | `.opacity` when `accessibilityReduceMotion` | They move on every tap on the address; SwiftUI does not drop `.move` by itself | Line read |
| 9 | `Design.swift:262-268` | `PressScale` uses the 0.3 s `.bar` spring for press and release | Press: `.spring(duration: 0.12, bounce: 0)`; release: `.bar` | Press feedback belongs in 100 to 160 ms; a quick tap only gets 60% of the way to 0.96 | Line read |
| 10 | `Bars.swift:660-676` | The loading line animates `width`, vanishes in one frame when loading ends, drawn in `Palette.faint` | A full-width bar scaled from the leading edge; on finishing it reaches full width, then fades over 0.25 s after 0.15 s; `Palette.muted` | It never shows finishing; width is a layout change; faint is about 1.5:1 on a light page | Line read |
| 11 | `Browser.swift:464`, `TabSheet.swift:26`, `TabOverview.swift:530` | The bar swipe, the sheet's pan and a card's pan take any number of touches | `maximumNumberOfTouches = 1` | A second finger mid-drag makes it jump; `BackSwipe` and `DesktopPad` already limit theirs | Line read |
| 12 | `Bars.swift:561` | The clear button in `Palette.faint` | `Palette.muted` | An enabled control at about 1.5:1 | Reported |
| 13 | `Suggestions.swift:473`, `:536`, `:589`, `:635` | Secondary text at `Color.primary.opacity(0.5)` | 0.6 (the system secondary label's alpha) | 0.5 is about 4.0:1, under 4.5:1 for 11 to 12 point text, and less over glass | Line read |
| 14 | `Browser.swift:795-799`, `BarBackdrop.swift:25-29`, `:99-107` | The bar's ink flips light or dark in one frame while its wash eases over 0.25 s | No animation for the wash when the side flips | For 250 ms light ink sits on a light wash while scrolling | Reported |
| 15 | `Design.swift:35` | `muted = pair(0.55, 0.58)`: about 3.4:1 on white | `pair(0.46, 0.58)`: about 4.5:1 | Small dimmed text (the address's path, empty states, Skip) under 4.5:1 | Line read |
| 16 | `Bars.swift:765`, `Popup.swift:66` | The banner's dismiss is 28 points; the popup's close is 32 wide | 44 by 44 | Under the 44 point minimum | Line read |
| 17 | `Design.swift:100`, `StartPage.swift:156`, `:178` | The thumb's star, reload and clear are 40 wide; the start page's Back and New Folder 40 | 44 on the phone | The code's own rule for the thumb is 44 (`Design.swift:86-88`) | Line read |
| 18 | `Spaces.swift:94-115` | Ten 40 point colour dots in one row | Two rows of five, 44 points | Ten 44 point targets don't fit a phone's width | Reported |
| 19 | `DesktopPad.swift:516-517` | The keyboard button and the minimap move on the default curve | The keyboard notification's curve (`keyboardAnimationCurveUserInfoKey << 16`) | They drift off the keyboard's edge mid-move | Reported |
| 20 | `BackSwipe.swift:202`, `Welcome.swift:317-319` | White chevron on the space colour; the default-browser line in the space colour on white | `SpaceColor.ink` for the chevron; `Palette.ink` text with only the check in colour | Yellow is about 1.5:1 either way | Line read (`BackSwipe`) |
| 21 | `StartPage.swift:44`, `:48`, `:65` | Header after 0.16 s; tiles after 0.2 s plus 0.02 s each, up to 0.4 s | Header 0.04 s; tiles 0.06 s plus 0.03 s each, up to 0.12 s | The last tile lands about 0.7 s after the page; the cascade stays, shorter | Line read |
| 22 | `Browser.swift:1504-1507`, `:2314-2321` | A frozen tab's picture replaces its icon in one frame, mid-drag | Fade it in over 0.15 s, then remove the icon | An abrupt swap mid-gesture reads as a glitch | Reported |
| 23 | `Browser.swift:1370`, `:1409-1411` | Escape closes the tab sheet with its spring | `closeNow()` for the key | Keyboard actions don't animate | Line read |
| 24 | `DesktopPad.swift:402`, `PadCore/Sources/PadCore/DesktopView.swift:130` | Pinch zoom stops dead at both limits | Rubber-band past a limit while pinching; spring back on release | At a boundary motion slows down, it doesn't hit a wall | Reported |
| 25 | `Browser.swift:1489-1521` | The sideways slide gives no haptic at its commit line | A medium impact each time the line is crossed | The sheet, back swipe and card swipe all tick; same family of gesture | Reported |
| 26 | `Bars.swift:726` | Reload shows on a new tab with no page (seen in the simulator) | Only with `window.url`, as the star | A control that does nothing | Line read |
| 27 | `Bars.swift:808-809` | The empty space prints ⌘T and ⌃⌥K on every device | Keys only where they work (section 4.3) | Keys that do nothing on an iPhone without a keyboard | Line read |
| 28 | Suggestion rows (seen in the simulator) | Every search row repeats a "Google" tag | The engine named once, on the first search row | Four identical tags are noise | Seen |

Already right, and kept: the `.bar` spring for bar state (zero bounce, interruptible); the tab sheet (a per-frame spring a finger can catch, release by projected rest and flick, rubber band past open, closing faster than opening, a fade under Reduce Motion); the sideways slide's projected release and rubber band; `BackSwipe` (one touch, velocity, a tick at the line, a fade under Reduce Motion); card swipe-to-close; suggestions appearing and moving with no animation, as typing-driven UI should; disabled tools dimmed by opacity; the minimap's catch-and-throw; the bar waiting for the first keyboard.

### 4.2 Swift (Phases A, D, E)

| # | Where | Issue | Fix | Phase | Checked |
|---|---|---|---|---|---|
| 1 | `TabOverview.swift:604-609`, `:663-669` | A thrown card calls `self.closed` 0.35 s later; by then a scroll may have reused the cell for another tab | Take `closed` at the release; `prepareForReuse` removes animations and clears `closed` | A | Line read |
| 2 | `Session.swift:142-150` | The workspace is saved on the concurrent global queue 0.5 s after each change: writes can overlap and land out of order, and nothing saves on going to the background | One serial queue for writes; save on `didEnterBackground` inside a background task | A | Line read |
| 3 | `Browser.swift:195-200`, `:1422-1446` | The bar's gesture is four variables that can disagree: an upward swipe starts while a slide settles, a sideways one while the sheet sinks | `enum BarGesture { idle, tabs, sliding, settling }`, begun only from `idle` with no sheet (a new slide may take over `settling`, motion 1) | A | Line read |
| 4 | `TabSheet.swift:185`, `App/Info.plist` | The sheet asks for 120 Hz, but without `CADisableMinimumFrameDurationOnPhone` an iPhone holds it to 60 | Add the key | A | Line read |
| 5 | `Browser.swift:1500` | The incoming card is placed from `stage.frame` while the stage is translated | Place it from `stage.bounds` and `stage.center` | A | Line read |
| 6 | `TabSheet.swift:127` vs `:140` | `beginDrag` decides at 0.5, `drag` at 0.3 or 0.7 | One rule | A | Line read |
| 7 | `Browser.swift:855-858` | `asyncAfter(1.5)` can't be cancelled and sets the app-wide flag with no keyboard | A cancellable `Task` per turn at the field; that turn's flag only | A | Reported |
| 8 | `TabSheet.swift:336-351` | Finds the tabs' scroll view by searching for the largest one (O(n²)); the content is a collection view now | The content hands over its scroll view | A | Line read |
| 9 | `Browser.swift:1246-1281`, `:1231` | Every progress tick runs all of `pageDidChange` and sets the scene's title | Progress sets `model.load.fraction` alone; the title only when changed | D | Reported |
| 10 | `Browser.swift:574`, `:2349` | `layoutPanes()` runs twice a layout pass, once on stale bounds | `Stage.layoutSubviews` the only entry | D | Reported |
| 11 | `Browser.swift:35-95` | `WindowModel` is an `ObservableObject`: any change redraws every view that watches it | `@Observable` (iOS 17; `Shared/HandingOff.swift` already uses it) | D | Reported |
| 12 | `TabSheet`, `Browser`, `DesktopPad`, `TabOverview` | The throw projection is written four times, the rubber band twice; release decisions have no tests | `PadCore/Sources/PadCore/Gestures.swift` with tests, as `GestureTests.swift` | D | Reported |
| 13 | `Browser.swift:599-729` | `refreshChrome` decides and applies in 130 lines on every page step | A pure `ChromeState` in PadCore, tested; return early when unchanged | D | Reported |
| 14 | `Session.swift:297` | `NSLog` | `Logger` with explicit privacy | D | Reported |
| 15 | `TabOverview.swift:38-39`, `Browser.swift:268` and others | Implicitly unwrapped views; the `spaces[0]` invariant kept out of sight | `lazy let`; `Workspace.firstSpace` with a `precondition` | D | Reported |
| 16 | `Browser.swift:8`, `:108-112`, `:182-184` | Doc comments on the wrong declarations | Moved | D | Reported |
| 17 | `PhoneBar.swift:102-106` vs `:234-238` | The ellipsis disc styled twice | One `MoreDisc` view | D | Reported |
| 18 | `project.yml:15-17`, `PadCore/Package.swift` | Swift 5 mode, minimal checking; the comment says the app is main-thread only, but `Session`, `SiteIcons` and `Stores` work off it | Complete checking (warnings), then Approachable Concurrency, then main-actor by default for the app, one step per pull request; PadCore checked without main-actor by default | E | Reported |

### 4.3 iPad features the iPhone lacks, one by one

| Feature | Reason in the code or documents | Verdict | Plan |
|---|---|---|---|
| Reordering tabs by dragging (`TopTabs.swift:242-253`, `SideTabs.swift:357-362`) | None stated; the overview's comment lists its gestures without it (`TabOverview.swift:5-12`) | Port | Phase C: drag to reorder in the tab overview, alongside swipe-to-close and the card menu |
| Keyboard shortcuts: every command, Tab 1 to 9, Give Keys Back to the Page, keys beside command rows, Settings › Shortcuts and Known limitations, the keyboard half of Trackpad and keyboard | "UIKit builds the menus that carry them on iPad and Mac only" (`Menus.swift:16-18`): true of menus, not of `keyCommands`; an iPhone can have a keyboard | Port, shown while a keyboard is connected | Phase 4 (the keys, shared with the Duo), Phase C (labels, settings) |
| Request Desktop or Mobile Site | "On iPhone, Desktop View in the page's menu shows the desktop version" (`README.md:312`) | Keep off at phone width; offered in the iPad layout on large iPhones (decision 9) | Phase 4 |
| Split View | Two readable pages need 728 points (`Browser.swift:1018-1021`) | Keep off at phone width; by width on large iPhones | Phase 4 |
| Show or Hide Tab Bar; tabs along the top or in a sidebar; Settings › Window | "One bar at the bottom whatever the layout" (`SettingsView.swift:25-26`) | Keep off at phone width; by width on large iPhones | Phase 4 |
| New Window, Close Window, Open in New Window | "An iPhone has one window" (`Bars.swift:210`, `Menus.swift:16`) | Keep off | |
| Bookmarks bar; the sidebar's Bookmarks | "A phone, its bar alone" (`Browser.swift:656`); the start page shows the space's bookmarks | Keep off | |
| Pinch at the pointer, the page's cursors, secondary click | "No pointer reaches an iPhone's page" (`Page.swift:1552`) | Keep off | |
| iPadOS Settings… in the app menu | No menu bar; the default-browser row already opens the Settings app (`DefaultBrowser.swift:58`) | Keep off | |

The other way, what only the iPhone's layout has, matters now that the Duo open and large iPhones in landscape show the iPad's layout:

| Feature (iPhone only today) | Reason | Plan |
|---|---|---|
| Close Other Tabs; Arrange Tabs By; Copy Link and Share of a tab not on screen (`TabOverview.swift:382-433`) | None stated | Phase C: added to the iPad's tab menu (`SideTabs.swift:746-793`) |
| New Space…, Remove Space… in the space menu (`Bars.swift:208`, `:215`); the iPad layout has New Space only as a key and a command row | None stated | Phase C: added to the space buttons' menu (`SideTabs.swift:648-669`) |

### 4.4 iPhone phases

Like the Duo's, each is one pull request, and a small iPhone and iPad must behave as before after each one but for the change it makes.

| Phase | What | Done when |
|---|---|---|
| A: Correctness | Swift 1, 2 and 4 to 8; for 3, the two guards (no upward swipe while a slide settles, no sideways one while the tabs are out); motion 11 | A card thrown mid-scroll closes its own tab; a change made just before going to the background survives a kill and relaunch; no bar gesture starts while another settles; the sheet's spring runs at 120 Hz (Instruments' frame rate) |
| B: Motion and interaction | Section 4.1, rows 1 to 10 and 12 to 28, and Swift 3's `BarGesture` enum, which motion 1 rewrites the same code for | Each row checked in the simulator (screen recording and frame times, as in the simulator notes, for 1, 2, 4, 9 and 21); contrast computed for 10, 12, 13, 15 and 20; VoiceOver reads 6 |
| C: Parity | Section 4.3's ports | Tabs reorder by drag in the iPhone's overview; with a keyboard the iPhone shows keys, the Shortcuts section and Known limitations (named for iOS); the iPad layout's tab and space menus have the iPhone's extra items |
| D: Structure and performance | Swift 9 to 17 | A page load's main-thread time in Instruments before and after; `ChromeState` and `Gestures` tested in PadCore |
| E: Concurrency checking | Swift 18 | Each setting its own pull request with its warnings fixed, never with a refactor |

## 5. Order

| Phase | Needs | Size | Touches |
|---|---|---|---|
| 0 Measure | | S | Diagnostics overlay |
| 1 Spike | 0 | S | Throwaway branch |
| A Correctness | | S | `TabOverview`, `Session`, `Browser`'s bar gesture, `TabSheet`, `Info.plist` |
| 2 Groundwork | 0, 1 | S | `AppDelegate`, `Browser`'s root view, PadCore |
| 3 Fold sidebar | 2 | S | `Browser`'s layout, `card(_:)`, `SideTabs` |
| 4 Regular-width windows | 2 | M | `Menus`, `SettingsView`, `Suggestions`, `Session.openWindow`, `refreshChrome()` |
| B Motion | A | M | `PhoneBar`, `Bars`, `Design`, `Suggestions`, `TabSheet`, `StartPage`, `BackSwipe`, `DesktopPad` |
| C Parity | 4 | M | `TabOverview`, `SideTabs`' menus, `SettingsView` |
| 5 Outer display | 1, 2, B | L | `PhoneBar`, `Browser`'s bar, the strip |
| D Structure | 5 | M | `Browser`, `TabSheet`, PadCore |
| 6 Documents | 3, 4, 5, C | S | Documents, screenshots |
| E Concurrency | D | M | Build settings and what they flag |

Phase A needs nothing from the Duo and can land first. Phases 3 and 4 can run side by side; both edit `Browser.swift`, so they merge one after the other. B comes before 5 because both change `PhoneBar`; D comes after the features so its refactors don't collide with them.

## 6. Verification

- `swift test` in `PadCore` (Mac or Linux).
- `xcodebuild` for the iPhone Duo, an iPhone 17 Pro and an iPad Pro simulator; the iOS 17 deployment target still compiles.
- The Duo closed, upright and turned (`devicectl device orientation set`), in the simulator; the iPhone 17 Pro Max turned the same way for decision 9. Open and half-folded postures only when you set them in Device Hub; until then those checks are listed as not run.
- `Validation/CHECKLIST.md` §8 rows per phase.

## 7. Risks added to the note's §7

1. **UIKit may treat the Duo as an iPhone for menus and keys.** Phase 4's `keyCommands` route covers it.
2. **A navigation controller around `Browser`** can change status bar forwarding, presentations, safe areas and keys. Phase 1 rules a variant out on any of them.
3. **No API names the Duo.** `Device.isDuo` rests on `supportsMultipleScenes` with the phone idiom; if Phase 0 shows that fails, decision 5 falls back to the window's width.
4. **Two page menus** (SwiftUI and UIKit) can drift; one builder for both.
5. **The fold may not re-run layout** when the window's size doesn't change; the hinge fallback covers it.
6. **Moving typing between two fields** is what `refreshChrome()` avoided on purpose: the keys can be lost on the way. Phase 4 tests it with a hardware keyboard and the on-screen one.
7. **Folding needs your hands.** No command reaches the Duo's hinge, so open, half-folded and inner-display Split View checks wait for you.
8. **`@Observable` (Phase D) touches every view that reads `WindowModel`.** It goes alone, after the features, and is checked view by view.

## 8. Review

The iPhone review (section 4) came from three Claude subagents, each read only: one applied Emil Kowalski's design engineering principles to the iPhone's motion and interaction, one the write-swift guide to its Swift, one listed every action's entry points on iPad and iPhone with the reasons the code and documents give. Their findings were re-read at the cited lines where section 4 says so, and the app was run on an iPhone 17 Pro simulator.

Codex (GPT, `codex exec`, read only, with the repository and the SDK headers) and Mercury 3 (Inception Labs, adversarial reviewer, with the plan and code excerpts) reviewed the first draft of the Duo plan. Gemini was not used: its quota had run out. Each finding was checked against the code and headers before it was taken.

| Finding | From | Taken | Change |
|---|---|---|---|
| The SDK says a reserved region's frame includes its margins; the draft's correction said it was unstated | Codex | Yes | Correction removed; `DuoLayout` takes the frame only |
| Hiding commands in every compact window would take them from narrow iPad windows | Codex | Yes | Correction 8; only the Duo changes |
| Suggestions filter commands and settings apart from the menus | Codex | Yes | One `offers(_:in:)` for all |
| A failed new window leaves the tab separated and off screen | Codex | Yes | Phase 4 restores it |
| Prefer `UIWindowSceneActivationAction` over screen sizes | Codex | Yes | Phase 4 |
| Folding ends an address being typed, against Apple's guidance | Codex | Yes | Decision 8, Phase 4 |
| Variant C had no page menu; variant A's test didn't check grouping or overflow | Codex | Yes | Phase 1 |
| The `keyCommands` fallback had no phase | Codex | Yes | Phase 4 |
| The welcome would promise a trackpad the Duo doesn't have | Codex | Yes | The welcome stays on the idiom |
| The swipe's preview row would not match the one-row bar | Codex | Yes | Phase 5 |
| `card(_:)` resets `stackBeside.constant`, undoing the fold's width | Mercury | Yes | Phase 3: one function sets both |
| "Bars hidden in every other layout" could be read as the phone bar | Mercury | Yes | Reworded |
| The 600 by 500 and 728-point rules had no file named | Mercury | Yes | Named |
| Fixed-width sidebar parts had no fix | Mercury | Yes | Phase 3 |
| `strip` would be set on iPhone and iPad in compact windows | Mercury | No | `verticalBarEdge` is `.unspecified` there; wording made explicit |
| Building every command would change the iPhone's menus | Mercury | No | The draft limited it to iPad and the Duo; now the Duo only |
| The hinge fallback's timing could flicker | Mercury | No | Speculative; Phase 0 decides whether the fallback is needed at all |
