# macOS startup and viewport hotfix

The 1.0.6 installer was signed and notarized, but the release validation omitted an app launch. On a legacy installation, startup copied 8.2 GB of WebKit data synchronously before the first window. Interrupted attempts left a 1.9 GB staging directory and repeated workspace backup directories because directory checkpoints were saved only after the whole migration.

## Changes

- Present startup progress and actionable Retry before initializing Session, browser services or Settings.
- Copy legacy data on a worker, with atomic checkpoints per directory and atomic staged files. Resume previous staging, validating file contents before reusing them. Keep the legacy container intact.
- Preserve the current outside workspace. Copy missing WebKit stores without merging database sidecars into an existing store.
- Give the browser scene a stable identity and default value. Resume extension startup after migration, including after the application-finished-launching notification.
- Make the native WebKit holder follow its current bounds. Honor SwiftUI's proposed page size.

## Evidence

- The released PageHolder implementation fails the native host-bounds resizing fixture. The fixed production class passes seven native WebKit viewport/detachment checks in `Validation/mac-viewport.sh`.
- An isolated no-iCloud app with synthetic legacy data renders migration failure and Retry. Removing the injected failure and activating Retry opens the browser.
- A native local page reports 1022 CSS pixels with the sidebar, 1270 with it hidden, 922 after widening it, and 457 in each split pane. The page's right edge remains visible.
- Migration regressions cover legacy staging, canonical temporary paths, interrupted copies, checkpoint/journal failure, existing workspace preservation and missing-only WebKit stores. A further regression rejects staged bytes with a matching size and timestamp.

The production-signed app was not launched against real user data or CloudKit. Automatic approval rejected that test because iCloud entitlements can reach the real account even with an isolated home. Runtime checks used a separate test bundle ID and no iCloud entitlement. Existing remediation findings remain separate from this hotfix.

Core validation: all 495 XCTest tests and 84 Swift Testing tests pass. Signed packaging and public asset/feed verification are recorded in the release PR.
