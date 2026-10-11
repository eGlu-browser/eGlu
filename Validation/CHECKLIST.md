# Validating on a real iPad

What the tests in `Tests/` can't show: a real trackpad, a real keyboard, real sign-ins, real memory. Turn on the Diagnostics panel first (⌃⌥D, or Settings › Show diagnostics); most checks below read from it.

Last run: 2026-10-02, iPad Pro 13-inch (M5) on iPadOS 27.0, built with Xcode 27.0; Safari 27.0 on macOS 27.0. Results are under each section.

The panel's lines:

| Line | Reads |
|---|---|
| 1 | The site adapter, desktop or mobile pages, heavy or light |
| 2 | Page zoom, WebKit's scrolling, the scroll view's own pinch |
| 3 | Whether the page's `navigator.userAgent` is the Mac Safari string the app sends |
| 4 | Pinch steps, ⌘ zoom steps, wheel events bridged, and bridged events held back because WebKit sent its own |
| 5 | WebKit's own wheel events the page received, and the last bridged outcome |
| 6 | The wheel bridge mode, keys sent to the page, keys relayed, whether the focus is in a text field |
| 7 | Live and frozen tabs, and how many times this page's process ended |
| 8 | The cursor: the page's own picture (its size and hotspot), none, or the system's pointer |
| 9 | Ad blocking: on or off for this page, and the lists' rule count and dates |

## 1. Figma zooms on a synthetic ctrl+wheel (Mac Safari)

The pinch bridge rests on this, so check it first.

1. On a Mac, Safari › Settings › Advanced › Show features for web developers.
2. Open a Figma design file in Safari and click once on the canvas.
3. Develop › Show JavaScript Console, paste all of [figma-ctrl-wheel.js](figma-ctrl-wheel.js), press Return.

- [x] It prints `PASS: Figma zooms on a synthetic ctrl+wheel.` and the canvas zooms in, then back out.
- [ ] If it prints `LOOK:`, the zoom couldn't be read: the canvas should still zoom in and out.
- [x] Note `strength` and `pinchFactor`. Strength 1 means the zoom follows the pinch; `pinchFactor` is what Figma's adapter needs for it to (`Adapters.swift`).

Result: PASS. Figma took all 10 events and zoomed from 1.00 to 1.415: strength 0.50, pinchFactor 199. Measured one event at a time, Figma in Safari zooms by e^(−deltaY/200) for events up to 30, and less for bigger ones. The first version of the script asked for 1.5 and printed FAIL; it now passes at 1.1.

The same works inside the app: connect the iPad to the Mac, open the file in Safience, and pick its page under Safari's Develop › (your iPad). Every page in the app is inspectable.

## 2. Trackpad and keyboard in Figma

Open a design file in Safience, with a Magic Keyboard or a trackpad.

- [ ] Line 1 says Figma, desktop pages, heavy. Line 3 says Mac Safari.
- [ ] Hovering layers and frames highlights them; clicking selects; dragging moves.
- [ ] Pinching on the trackpad zooms the canvas around the pointer, not the whole page. Line 2 stays at zoom 1.00; line 4's pinch count goes up.
- [ ] ⌘ and two fingers zoom too.
- [ ] Two fingers pan the canvas. On line 5, if WebKit's own wheel events stay at 0, the bridge is doing the panning (line 4's bridged count goes up); if they go up, WebKit sends them itself and the bridge stands aside. Either way, note which.
- [ ] A quick two-finger flick keeps gliding for a moment, as on a Mac (only when the bridge does the panning).
- [ ] Figma's own cursors show, not the iPad's round pointer: its arrow on the canvas, and the frame, pen, comment and color picker tools' cursors, and the rotated arrows on a selection's corners and edges. Line 8 names the picture's size and hotspot. Over a panel's text or a field, the iPad's beam shows instead, as WebKit chooses.
- [ ] While dragging a layer, the cursor follows the pointer without jumping; after letting go, it doesn't blink to the iPad's pointer.
- [ ] With Settings › Show pages' own cursors off, the iPad's pointer is back everywhere.
- [ ] A secondary click (two-finger click) shows Figma's menu, and only Figma's.
- [ ] ⌘-click on a layer selects it and opens no tab.
- [ ] ⌘Z and ⇧⌘Z undo and redo in Figma. ⌘C, ⌘V copy and paste layers. ⌘F opens Figma's own find. ⌘D duplicates.
- [ ] Arrow keys nudge a selected layer; ⇧ and an arrow nudge by 10. Tab selects the next layer. If either doesn't reach Figma, turn on Settings › Tab and arrow keys › Send to the page first, and check again; note which setting works.
- [ ] Two fingers swiping sideways never goes back a page.
- [ ] Long-pressing a link or image with a finger shows no callout.
- [ ] Switch to another app and back, or click another Stage Manager window and back: typing a Figma shortcut works at once, without clicking the page first.
- [ ] On iPadOS 26, the menu bar shows the app's Go, Tabs, Spaces and Window menus, all on ⌃⌥, and none of the system's File, Edit, Format, View or Help. Hold ⌘: the shortcut list shows no ⌘ shortcut of the app's.

## 3. Sign-in, for every tool you use

For each tool, sign in from a fresh space (Spaces › New Space…, so nothing is signed in yet) with each method it offers. The address bar should show on every sign-in page with the host in bold.

Edit the rows to your own list of tools.

| Tool | Google | Email and password | SSO | Address bar on sign-in | Notes |
|---|---|---|---|---|---|
| Figma | | | | | |
| Google Workspace (Drive, Docs) | | n/a | | | |
| Slack | | | | | |
| Notion | | | | | |
| Linear | | | | | |
| Miro | | | | | |
| Jira / Confluence | | | | | |

For each:

- [ ] A sign-in in a pop-up opens over the page as a sheet with its address on top, and closes by itself when done.
- [ ] On accounts.google.com, line 1 says hands-off, nothing injected, and line 3 says the user agent is not read there.
- [ ] If Google refuses ("This browser or app may not be secure", or Error 403: disallowed_useragent), a banner says so and points to email or SSO; Go Back returns to the tool's sign-in page.
- [ ] After signing in, quit the app (swipe it away) and open it again: still signed in.
- [ ] Two spaces signed in to two different accounts of the same tool stay apart.
- [ ] Passkey buttons are expected to fail: passkeys are out of scope (see README).

## 4. Memory, with a large Figma file

1. Open the heaviest Figma file you have (a design system, a file with many pages and images). Note how long it takes to become usable.
2. Open three more tabs: Slack, Notion, and a second Figma file.
3. Switch between them while watching line 7.

- [ ] The first file stays live while you visit Slack and come back (no reload, same view).
- [ ] Opening the second Figma file freezes the first: going back shows its picture at once, then the file loads again underneath.
- [ ] More than two light tabs off screen freeze, oldest first (Settings › Light tabs kept open changes the number).
- [ ] A tab with something typed but not sent (a message half written in Slack) doesn't freeze.
- [ ] If the file runs out of memory, the tab reloads by itself and line 7's process ends count goes up. After three in a minute, a banner offers Reload instead of reloading again.
- [ ] With Xcode's Instruments (Activity Monitor template, the iPad as target), note the peak memory of the `com.apple.WebKit.WebContent` process for the file. This is the number iPadOS limits, and no setting can raise it.

## 5. Windows

- [ ] ⌃⌥N opens a second window (Stage Manager or Split View). Each window shows its own tab; choosing a tab that the other window shows brings that window forward.
- [ ] A tab's menu (long press or secondary click on it) › Open in New Window moves it there.
- [ ] Close the app and open it again: each window comes back with its space and tab.

## 6. With Apple's browser entitlement

On a build signed with it (README › With Apple's browser entitlement).

- [ ] Safience's Settings › Default browser › Make Safience the Default Browser opens Settings › Apps › Default Apps; choose Browser App › Safience. Back in Safience's Settings, it says Safience is your default browser.
- [ ] A link tapped in Mail, Notes or Slack opens in Safience, in a new tab after the one on screen, which stays as it was.
- [ ] On a site that offers passkeys (Google, GitHub, Figma if offered), signing in with a passkey shows the system's passkey sheet and signs in.
- [ ] Creating a passkey on a site saves it in the Passwords app.
- [ ] The key button above the keyboard lists the site's own passwords without searching, and a verification code field offers the code.
- [ ] Share Page (⌃⌥S, or the tab's menu) shows the share sheet with Add to Home Screen; the icon it adds opens the page.
- [ ] A site with a service worker (an offline-capable web app) registers it: Diagnostics or the site itself says so.

## 7. Compact tabs, pinned tabs, bookmarks, spaces

- [ ] One row: the space's button in its colour, back and forward, pinned icons, tabs at one width, + and ⌘. The tab on screen shows a close button, its host with the name that matters in bold, the key badge on a sign-in page, the star and reload; it alone is in Liquid Glass.
- [ ] Clicking another tab only goes to it: no tab changes width. Going to a pinned tab keeps it an icon, unless its page is a sign-in page.
- [ ] Clicking the tab on screen: its host turns into the address, selected, in place, then the field widens over the other tabs without moving them; typing replaces it; Return goes; a click on the page or Escape takes the field back into the tab the same way, and the tab is as it was.
- [ ] Settings › The tab you are on shows › Its title: the tab shows the page's title, and its host on a sign-in page.
- [ ] With Settings › Show the tab bar off, the row still shows on a sign-in page and on a new tab.
- [ ] Split: a tab's menu › Open in Split View puts it beside the tab on screen, both as one tab in the row; a click in either pane moves the keys, the glass half and the coloured line to it; the divider drags and a double tap centres it; the + button's menu › New Tab in Split View opens a new tab beside, typed into; closing a pane leaves the other full width; the split comes back the same after relaunch.
- [ ] With the Korean keyboard, typing github.com in the palette shows Open github.com before any other key, and Return goes there; the same in the address field.
- [ ] Pin a tab from its menu: it becomes an icon at the front. Go elsewhere in it, then close it (⌃⌥W): it stays, and opening it shows its pinned page again. Unpin puts it back among the others.
- [ ] Import Chrome's export, then Safari's ZIP (Settings › Apps › Safari › Export › Bookmarks), into one space: the grid on a new tab shows them, the second import of the same file adds nothing, and another space's grid stays empty.
- [ ] The star adds and takes away the page; a bookmark's menu opens it in a new tab or deletes it; ⌃⌥K finds bookmarks by name.
- [ ] Space Settings changes the name, colour and icon at once in the bar; Settings › Spaces › Edit reorders, and ⌃⌥↑ ⌃⌥↓ follow the new order.

- [ ] Settings › App icon: choosing Diazo changes the Home Screen icon after the system's notice; choosing Safience puts the app's own back.

## 8. iPhone, iPhone Duo, iCloud

- [ ] On an iPhone, the bars are at the bottom: back and forward, the address, the tabs (with their count), the space, + and the menu. Tapping the address types a new one, the address selected, with the bar above the keyboard; Return goes.
- [ ] A site's mobile version loads (the page names an iPhone); it scrolls and pinches with a finger. Menu › Request Desktop Site loads the desktop version, and the site keeps it next time.
- [ ] The tabs button shows the space's tabs as a grid; a tap goes to one, × closes one, + opens a new tab.
- [ ] Turned sideways, an iPhone keeps the bars at the bottom (a Pro Max turns to the iPad's row) and keeps mobile sites.
- [ ] On an iPhone Duo: folded, the bars are at the bottom and sites are mobile; unfolded, the iPad's row comes back and sites load as desktop on the next page. Folding mid-typing leaves the address as it was.
- [ ] Settings › iCloud › Sync Spaces and Bookmarks on two devices with the same account: a space of the same name joins with both devices' bookmarks; a bookmark added on one shows on the other within a minute; a space removed on one goes on the other; tabs and sign-ins don't move.
- [ ] Signed out of iCloud, Settings says to sign in.

## 9. ⌘-click

On any site with links (a news site, GitHub), with the trackpad:

- [ ] ⌘-click on a link opens it in a new tab after the one on screen, which stays as it was. Two more ⌘-clicks put their tabs after the first, in order.
- [ ] ⌘⇧-click on a link opens it and goes to it.
- [ ] With a mouse, the middle button opens the link behind.
- [ ] A link that opens a new window by itself (Slack's, Notion's) opens behind with ⌘ and in front without it.
- [ ] ⌘-click on a search button (Google's, Wikipedia's) opens the results in a new tab; ⌘-click on a form that sends something (a comment's Post) sends it once, in place.
- [ ] A plain click on a link still goes there in place.

## 10. Ads and trackers

- [ ] A news site with ads (a newspaper's home page) shows no ad slots, and loads no Google Tag Manager or Analytics (Web Inspector's Network tab, or line 9 of Diagnostics says "on here").
- [ ] Menu › Allow Ads on This Site loads it again with its ads; Block Ads on This Site takes them away again; the choice stays for the site after a relaunch.
- [ ] accounts.google.com: line 9 says "off here", and line 1 "hands-off, nothing injected".
- [ ] Settings › Ads and trackers off: ads come back on every site from the next page; on again, they go.
- [ ] After four days with the app opened, Settings shows lists dated within the last week.

## 11. Address bar suggestions

In a space with a few tabs, a pinned tab and bookmarks, on iPad in each layout (Settings › Window › Tabs) and on an iPhone:

- [ ] Typing "fig" with figma.com open in a tab shows it first, "fig" plain and "ma.com…" in bold, its title under it and "Open Tab" at the end; Return goes to that tab rather than loading the page again.
- [ ] A pinned tab says "Pinned Tab", a bookmark "Bookmark", and "new" offers New Tab and New Space as "Command", with their keys on iPad; choosing New Tab opens one, its address field open.
- [ ] After a moment, Google's suggestions show under the first row, marked "Google"; choosing one searches for it. With Settings › Search engine set to DuckDuckGo or Bing they come from it and say so; with Kagi there are none.
- [ ] ↓ from the field chooses the first row, ↑ from it goes back to the field, and Return with no row chosen sends what was typed, as before. A tap or a click on a row takes it.
- [ ] Korean: typing 피그마 shows Google's suggestions while the last syllable is still being composed, and Return sends the whole word.
- [ ] Typing figma.com/ sends nothing to Google (Web Inspector's Network tab on the app shows no suggestqueries request), and Settings › Search engine suggestions off sends nothing at all while tabs and bookmarks still show.
- [ ] Escape, Cancel, a tap on the page, or going to another tab takes the rows away with the field. On iPhone the rows sit just above the bar and scroll when the keyboard leaves them little room.
- [ ] With Apple Intelligence on (iOS or iPadOS 26): "put this on my home screen" offers Share Page…, "탭 고정" Pin or Unpin Tab, "광고 차단" Block or Allow Ads on This Site, and a few words about a tab's subject that share no word with its title (a Figma file's topic) offer that tab, each a moment after typing stops, with sparkles beside its source. Two letters, or figma.com, never wait on the model.
- [ ] With Settings › Search engine suggestions off and Apple Intelligence on, searches marked Apple Intelligence show instead of Google's; with Airplane Mode on, they still do.
- [ ] Settings › Suggest with Apple Intelligence off: no sparkles. With Apple Intelligence off in the Settings app, Safience's Settings says to turn it on; on iOS 18 or a device without it, the switch isn't there and the app starts as before.

## 12. The phone bar's swipe, and a link's menu

On an iPhone, in a space with three tabs or more:

- [ ] A drag to the left on the bar brings the next tab in from the right, its page and its address both following the finger; letting go past halfway, or with a flick, goes to it, and short of that springs back.
- [ ] At the last tab a drag to the left moves a little and springs back; at the first, a drag to the right.
- [ ] A swipe up on the bar still shows the tabs, and while an address is typed a sideways drag only moves the text's caret.
- [ ] In Desktop View a sideways drag on the bar does nothing.
- [ ] A long press on a link lifts it with a menu under its address: Open in New Tab goes to it in a new tab, Open in Background adds a tab (the count goes up, with a tap felt) and stays, Copy Link puts the address on the clipboard, Share… opens the share sheet. A tap on the lifted link goes there in the same tab.
- [ ] On iPad at full width, a long press with a finger on a link on a plain page (a Wikipedia article) shows the same menu, and so does a secondary click with the trackpad, a moment after the click.
- [ ] On iPad, a secondary click on a link in a page with a context menu of its own (a file in Figma's file browser, a message in a web mail app, a row in GitHub's file list where the site has none) shows only the page's menu where it has one, never both.
- [ ] In Figma, on the canvas and in the file browser, a long press with a finger and a secondary click show only Figma's own menus.
- [ ] On accounts.google.com a long press on a link shows no menu of the app's.

## 13. Sites with their own menus, pictures, swipes, find

Sites with their own menus:

- [ ] Settings › Link menu › Sites with their own menus lists the built-in sites, each with a switch, and Add takes an address (`https://www.example.com/app` becomes example.com) and refuses a word that isn't one.
- [ ] On a plain page, the page's menu has Use This Site's Own Menus; after it, a long press on a link there shows nothing, the site is under Your sites in Settings, and the menu says Show Link Menu on This Site, which undoes it.
- [ ] With Figma's switch off in Settings, a long press on a link in Figma's file browser shows the app's menu; with it on again, only Figma's.
- [ ] In Google Docs, Notion, Linear and Slack, a secondary click and a long press show only the app's own menus; on google.com's results a link still has the link menu.

Pictures:

- [ ] A long press on a picture that isn't a link lifts it with Share…, Save to Photos, Copy and the rest; Save to Photos asks once to add to Photos and the picture is there afterwards.
- [ ] A long press on a picture that is a link shows the link's menu with Save to Photos at the bottom.
- [ ] On iPad, a secondary click with the trackpad on a picture in a page with its own context menu shows only the page's menu. (Not checked in the simulator, which has no pointer to click with.)

Back and forward by a swipe:

- [ ] On iPhone, a finger dragged in from the left edge slides the page before in, and from the right edge the page after.
- [ ] On iPad, on a desktop page with a page to go back to, a finger dragged in from the page's left edge brings an arrow in; letting go once it has filled goes back, and before that does nothing. With nowhere to go back to, no arrow shows and the page gets the drag.
- [ ] On iPad with a trackpad, on a plain page (a Wikipedia article reached from another), two fingers to the right bring the arrow in from the left and go back; two fingers to the left go forward.
- [ ] In Figma, on the canvas, two fingers sideways pan the canvas and never go back, however far and however often. The same in Miro, Google Sheets and a map.
- [ ] On a page with a row that scrolls sideways (a carousel, a wide table), two fingers sideways over the row scroll it, and a swipe that reaches the row's end doesn't go back. A new swipe begun at the row's end does, as in Safari on a Mac, and so does one away from the row.
- [ ] In a split view, each pane goes back by a drag from its own left edge.
- [ ] ⌘ with two fingers still zooms, and ⇧ with a mouse wheel scrolls sideways without going back.

The cursor at the page's top and bottom, in the iPhone's Desktop View:

- [ ] One finger down moves the cursor to the bottom of the page, and what the finger moves after that scrolls the page down; the cursor stays at the bottom. The same upward: at the top, the page scrolls up.
- [ ] With the cursor already at the bottom, a flick down scrolls and glides on, and a touch stops it. A flick that only gets the cursor to the bottom doesn't glide.
- [ ] Sideways along the bottom, and back up from it, scroll nothing.
- [ ] Zoomed in with a pinch, the view follows the cursor to the desktop's bottom first, and only then does the page scroll.
- [ ] Touch and hold, then drag past the top or the bottom: the page scrolls while the button is held.
- [ ] In Figma, the cursor pushed against the top or the bottom pans the canvas, as two fingers do.

Pull to load again, and find:

- [ ] On iPhone, at the top of a page, a pull down shows the spinner and loads the page again; the spinner goes when the page is back.
- [ ] On iPad, on a desktop page, and in the iPhone's Desktop View, a drag down does nothing of the kind.
- [ ] Find on Page (⌃⌥F, or the page's menu) shows the find bar; a word typed is counted and marked, and the arrows go from one to the next. After the bar is closed, ⌘F in Figma is Figma's again.

## 14. Links for other apps

- [ ] A `tel:` or `mailto:` link, and a link with an app's own scheme, opens that app at once when tapped.
- [ ] On a site with an "Open in app" button (instagram.com or youtube.com on an iPhone, with the app installed): the button asks "Open in Another App?", naming the site; Open goes to the app, and coming back, no empty tab has been left behind.
- [ ] Cancel, then the button again: it asks again. A second Cancel, and it asks no more until the page is loaded again.
- [ ] A link to Instagram or YouTube in a search's results opens the app, as in Safari (a universal link, which WebKit opens itself).
- [ ] With the app not installed, Open says that nothing on the device opens the link.
- [ ] A page that tries another app by itself as it loads (an ad's redirect to the App Store) only asks; nothing opens without Open.

## 15. The phone bar in the page's colour

On an iPhone, with the system in Dark Mode and again in Light Mode:

- [ ] Over a white page the bar fades to white and its controls are dark; over a dark page it fades to dark and they are light. Neither depends on the system's appearance.
- [ ] Over a page with a coloured ground (a navy footer, a yellow banner) the bar takes that colour.
- [ ] Scrolling from a light part of a page to a dark one turns the bar over as the dark part comes under it, eased and without a flash, and scrolling stays smooth.
- [ ] A new tab's start page has the system's own ground: dark in Dark Mode.
- [ ] In Desktop View the bar goes by the page under it in the same way.
- [ ] On iPad the bars still take the colour along the page's top, as before.
