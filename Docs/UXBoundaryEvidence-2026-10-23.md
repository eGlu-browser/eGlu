# UX boundary evidence, 2026-10-23

Scope: source changes and synthetic verification for the IDs below. Passing pure tests establish model policy and failure recovery. They do not establish live CloudKit behavior, real-site compatibility, assistive-technology usability or measured contrast.

## Trackpad View and phone controls

| ID | Implemented source | Evidence | Remaining manual check |
| --- | --- | --- | --- |
| P1 | `App/Sources/Browser.swift`: `showDesktopHelp`, first-use help; `DesktopPad.swift`: Help and Options | Gesture instructions include move, click, double click, drag, scroll, secondary click, zoom and minimap. iOS SDK build passes. | First-use and returning-use help on a physical phone. |
| P2 | `DesktopPad.swift`: persistent Exit, Zoom Out, Reset View, Zoom In, Keyboard and Options; `bridge.js`: context result; `Page.swift`: context feedback | Existing `Tests/bridge.mjs` passes in Chromium and WebKit, including synthetic context handling. | Single-pointer controls and real sites. Secondary click requires a site-provided menu; normal browsing provides native WebKit menus. |
| P3 | `PadCore/Sources/PadCore/DesktopView.swift`: `supportsTrackpad`; `Browser.swift`: accessibility status guard and normal-browsing fallback; `Page.swift`: trackpad accessibility exposure | Pure `DesktopViewTests` and iOS SDK build pass. | VoiceOver and Switch Control activation on device. Trackpad View explicitly falls back to normal browsing. |
| P4 | `App/Sources/BarBackdrop.swift`: opaque semantic system ground; phone controls use semantic ink | iOS SDK build; page-dependent translucent ground removed. | Measure contrast across light/dark, Increased Contrast and all warning icons. No numeric contrast claim. |
| P5 | `DesktopPad.swift`: saved `desktopMinimapCorner`, `desktopMinimapHidden`, position menu | Source and iOS SDK build; hidden minimap does not retain a gesture dead zone. | Re-entry, rotation, keyboard and relaunch placement. |
| P6 | `DesktopPad.swift`: `updateKeyboardButton`, `toggleKeyboard`; `Page.swift`: editing callback | Keyboard availability and accessibility hint follow actual editable focus; focused page input is required. Bridge tests pass. | Web-app editors, input-method composition and focus loss. |
| P7 | `Browser.swift`: Trackpad View explanation; `Bars.swift` and command labels distinguish Trackpad View from Request Desktop Site | Source and iOS SDK build. | Wide-phone menu comprehension. |
| P8 | `TabSheet.swift`, `PhoneBar.swift`, `TabOverview.swift`, `Browser.swift`: routine-action haptics removed | Source review and native SDK builds. | Physical-device haptic review. Deliberate drag/snap feedback remains. |
| P9 | `Browser.swift`: blocked sideways bar swipe gives “Use Tabs to switch in Trackpad View” feedback | Source and iOS SDK build. | Repeat swipe and accessible feedback on phone. |
| P10 | `Bars.swift`: optional shortcut suffix is composed only when keys exist | Source and iOS SDK build. | Phone without hardware keyboard. |

## Setup, Settings and destructive actions

| ID | Implemented source | Evidence | Remaining manual check |
| --- | --- | --- | --- |
| O1, O7 | `Welcome.swift`, `SettingsView.swift`, `Shared/BookmarkImportStatusView.swift`, `WorkspaceBookmarkImport.swift` | Typed read/empty/archive/cancel/destination/save outcomes; retry and another-file actions. `BookmarkImportOutcomeTests`, `BookmarkFileTests` pass. Firefox and Safari ZIP are named. | Native file pickers with unreadable, malformed, duplicate and large real exports. |
| O2 | `Welcome.swift`: separate Skip Setup and Skip This Step | Source; iOS SDK build. | Complete, skipped and interrupted onboarding. Completion still requires the acknowledged workspace-save path. |
| O4 | `DefaultBrowser.swift`: active-scene refresh, old-system unknown state and version-specific instructions; Mac Settings active refresh | Source and native SDK builds. | iOS 17 through 18.3+ and actual default-browser transitions. Unknown status is not claimed to be “not default.” |
| O5 | `PadCore/Sources/PadCore/SyncStatus.swift`, `Shared/Sync.swift`: typed waiting/retrying/syncing/confirmation state, Retry Sync, account-scoped persisted last-confirmed date; Settings/onboarding share status | `SyncStatusTests` cover offline/send failure, no send-only completion, historical date after relaunch, pending changes and unrelated-zone fetches. History sync is disabled until the approved account and readable history metadata are validated. | Live offline, throttled-service, partial-failure and reconnect cycles. The date is historical; only a confirmed fetch without pending engine/history work records a new completion. |
| O6 | `SettingsView.swift`: native category destinations and dedicated Shortcuts page; `PadCore/Sources/PadCore/SettingsAnchor.swift`: shared category routing | `SettingsRoutingTests` pass. Settings > Spaces and iCloud > Spaces > New Space passed on isolated QA iPad Pro 13 and iPhone 17 Pro Max; native ledger B3 records both. | Keyboard connect/disconnect, direct command-search anchors, largest text and nested back navigation. |
| O8, D12 | `Dialogs.swift`: Create/Rename and trimmed-name validation; `Welcome.swift`, `Spaces.swift`, Mac Settings: visible blank-name explanation | Source, pure workspace behavior and native SDK builds. | Whitespace entry and keyboard submit on both platforms. |
| O9 | `Diagnostics.swift`: explicit Close; `SettingsView.swift`, `Browser.swift`, device/menu availability: developer diagnostics gate | Source and iOS SDK build. | DEBUG close control; Release command absence. |
| X3 | Settings scrolling, memory and cursor copy describes behavior; developer diagnostics is labelled as such | Source and native SDK builds. | Final language review across menus and contextual states. Command catalog/localization evidence is maintained separately. |
| X5 | `PadCore/Sources/PadCore/TabClosePlan.swift`: `SpaceRemovalCopy`; `Shared/Sync.swift`: effective current-account scope; App/Mac space deletion callers share it | `TabClosePlanTests` cover local, paused and approved-account scope, singular count, all named data and Mac extension data. | Online/offline two-device deletion and sign-in/store cleanup. |
| X8 | `Workspace.closeTab` preserves a pin's current record; App/Mac Session retains its live page. Explicit `resetPinnedTab` is confirmed in the owning window. | `PinnedAndSpaceTests`, `TabClosePlanTests`, native SDK builds. | Real unsaved editor when hiding/reopening a pin. Page retention cannot recover WebContent process death or application termination. |
| X9 | `TabClosePlan`; Browser/WindowModel bulk-close confirmations; reachable Reopen Closed Tab in page and phone Tabs menus | Unique existing ordinary tabs determine the destructive count; pins are excluded. Pure close, workspace and split tests pass. | Sidebar, overview, split and phone menu confirmation/cancel routes. Reopen restores saved addresses, not unsaved page content. |
| X14 | Settings anchor/header names align; Send to App replaces the ambiguous Handoff label; suggestions use From Other Devices | Source and `AutocompleteTests`. | Root-owned command catalog and localization pass, including dynamic labels. |

## Sync, account, import and request boundaries

| ID | Implemented source | Evidence | Remaining manual check |
| --- | --- | --- | --- |
| N4 | `SyncPlan.apply` adds a fresh replacement space before returning every remote-deleted space for ordinary native cleanup; `Sync.joinWhenFetched` applies offline removals before joining | `SyncCRDTTests.testRemoteDeletionOfTheLastSpaceCreatesAFreshReplacementBeforeCleanup` and sync/workspace regressions pass. | Native cleanup of cookies, sign-ins, history, snapshots and Mac extension data after last-space deletion. |
| N6 | `SyncPlan.join` matches space cloud identity only; equal names remain separate | `SyncModelTests` cover same-name local/remote spaces, duplicates and replay. | Two-account/two-device fixtures with existing duplicate names. No automatic same-name merge is promised. |
| N7 | `SyncAccountConsent.swift`; `Sync.swift`: saved account choice, verified current user, durable identity detachment, generation guards and definite `.noAccount` revocation | Consent tests cover first choice, switch, sign-out/same account, stale action, malformed file, failed write, relaunch and identity-preserving detachment. Native SDK builds pass. | Real CloudKit sign-out, switch while running/offline, account change while app is stopped, consent-write failure and relaunch. Sync remains paused without an approved, saved choice. |
| N8 | `HistoryCloud` requires approved account permission; local clear requests capture an epoch/account; `HistoryStore.remove` commits account-bound pending clear intent with deletion | `HistoryFaultTests` cover rollback, storage lock, retry and account-A intent exclusion from account B. `HistoryAccountSessionTests` exercise unavailable SQLite at account-B approval, retained A metadata, reset/new-cutoff on retry and preserved account-bound local removals. The actual HistoryCloud gate uses this policy before queues or records are used. Stale work checks epoch/consent before direct backfill reads and after store awaits. | Delayed CloudKit/store callbacks across account changes and two-device history-clear replay. No live account data was accessed for this verification. |
| N9 | `Workspace.importBookmarks`; `WorkspaceBookmarkImport`; native import consumers; typed outcome and retained retry receipt | Destination deletion/replacement, rename, duplicate replay, read failure and failed-save tests pass. Retry validates the exact destination before and after saving and retains parsed bookmarks when it disappears. | Native delayed-save/delete race and real export fidelity. File contents are not discarded by import failure. |
| N14 | `Preferences.swift`: suggestions default off, legacy `true` lacks consent, named-provider choice; App Suggestions/Mac CommandBar check consent before request and after response | `AutocompleteTests` record generated request URLs for a growing private prefix before/after opt-in and revocation; local matches stay available. | Native URLSession interception and request cancellation timing. The fixture records request construction, not actual network traffic. After explicit opt-in, partial private names and the device IP can reach the named provider. |

## Verification records

All commands ran in the shared remediation worktree. No production app launch or live CloudKit verification was performed by this boundary review.

- `/private/tmp/safience-desktop-and-boundary-tests.log`: 112 pure tests passed during Trackpad View implementation.
- `/private/tmp/safience-desktop-bridge-chromium.log`: 142 browser checks passed.
- `/private/tmp/safience-desktop-bridge-webkit.log`: 142 browser checks passed.
- `/private/tmp/safience-settings-close-tests.log`: 86 focused routing/import/close tests passed.
- `/private/tmp/safience-boundary-held-tests.log`: 180 XCTest cases plus 5 Swift Testing history-fault tests passed, including exact delayed-storage/account-switch replay and O5 status policy.
- `/private/tmp/safience-boundary-status-ios-build.log` and `/private/tmp/safience-boundary-status-mac-build.log`: both native SDK builds passed after account validation and O5 status. Final builds after pending-history status notifications use `/private/tmp/safience-boundary-held-ios-build.log` and `/private/tmp/safience-boundary-held-mac-build.log`; both final builds passed.
- `/private/tmp/safience-settings-newspace-ipad-current.xcresult` and `/private/tmp/safience-settings-newspace-phone-current.xcresult`: isolated native category-route acceptance, reported by the native QA agent.

Focused replay command:

```sh
swift test --package-path PadCore --scratch-path /private/tmp/safience-import-tests \
  --filter 'HistoryAccountSessionTests|SyncStatusTests|SyncAccountConsentTests|SyncModelTests|SyncCRDTTests|BookmarkImportOutcomeTests|BookmarkFileTests|SettingsRoutingTests|TabClosePlanTests|PinnedAndSpaceTests|WorkspaceTests|SplitTests|AutocompleteTests|HistoryFaultTests|HistorySyncTests|DesktopViewTests'
```

Browser replay uses existing installed dependencies, with no package installation:

```sh
NODE=/Users/taehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node
PLAYWRIGHT=/Users/taehee/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs \
  "$NODE" Tests/bridge.mjs chromium
PLAYWRIGHT=/private/tmp/claude-501/-Users-taehee-Git-portfolio--claude-worktrees-import-codebase-figma-3db0a6/477b1983-ee2d-4922-be86-9b6175f50b80/scratchpad/cap/node_modules/playwright/index.mjs \
  "$NODE" Tests/bridge.mjs webkit
```
