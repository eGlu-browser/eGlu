# Crash report review, 23 October 2026

Reviewed all four supplied Xcode crash groups, containing ten unique reports plus three locally symbolicated copies. Changes are based on main at `1fe7617`. Raw reports and device identifiers are not included here.

| Group | Evidence | Disposition |
| --- | --- | --- |
| `CB5EHghqgbJqNw7dzx6j17` | Five reports in builds 31 and 36. WebKit's `CompletionHandlerCallChecker` aborts while a JavaScript confirmation callback is released by `UIAlertController` teardown. | Reproduced on current main and fixed in `App/Sources/Dialogs.swift`. |
| `CZTjvvTqE3P18ogcNMrAbr` | Builds 11 and 17. `TabOverviewController.configure` receives a synchronous page preview and applies a diffable snapshot inside the existing update. | Already addressed by `0f6fe40`, retained in current main. Added a simulator regression using a real cached WebKit preview. |
| `e_z6zv0MhqISnDs9LU0Xl` | Two build-16 reports. The same preview callback applies a snapshot while UIKit is dequeuing/configuring a cell, failing its dequeued-view assertion. | Same existing fix and cached-preview regression as above. |
| `Dh1z3Vy4-7etXk93_n4TVv` | Build 32. UIKit's compositional layout repeatedly invalidates visible cells and stops in `_UICollectionViewFeedbackLoopDebugger`. No app frame identifies the collection view or triggering action. | Not reproduced. The tab overview passed resizing, scrolling and selection stress tests, but that does not establish the reported trigger or prove this crash fixed. |

## Confirmed cause and fix

JavaScript alerts, confirmations, prompts and HTTP credential requests passed their completion closures directly into alert actions. A button tap answered the request; rejected presentation or dismissal without a button tap did not. WebKit requires a response before releasing the callback.

The baseline simulator test `testRejectedConfirmationRepliesFalse` terminated with:

```text
Completion handler passed to ... webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler: was not called (NSInternalInconsistencyException)
```

`DialogReply` now clears its callback before delivering a value and supplies a cancellation value on release if no action answered. Its isolated destructor runs on the main actor. `Dialogs` also refuses presentation on detached, dismissing or occupied presenters and answers immediately. Confirmations cancel with false, prompts and credentials with nil, and alerts acknowledge dismissal. Existing normal button behavior is preserved.

The real-WebKit dismissal test verifies that an alert shown on screen and then dismissed programmatically replies false. Additional tests verify discarded alerts, prompt/credential fallback, and prevention of duplicate replies.

## Existing tab-overview fix

The current `asking` marker in `TabOverviewController.configure` prevents a synchronous preview callback from applying another snapshot. The new test obtains a real WebKit thumbnail, makes the live view unavailable, verifies the cached callback delivers inline, then opens and lays out the actual overview. It exercises the path named by both older crash groups without changing the existing fix.

## Layout-loop investigation limits

The test creates 40 tabs and exercises widths 320, 393, 402, 852, 375, 600 and 320 points. At each width it scrolls to five positions and changes selection. No feedback-loop exception occurred. This is synthetic coverage, not reproduction of the reported incident. The report does not include UIKit's collected layout records or the user's preceding action. No speculative layout change is included.

## Validation results

All seven simulator regression tests passed on iOS 27.0. The complete PadCore suite passed: 503 XCTest tests and 84 Swift Testing tests, with no failures. The original implementation failed the real-WebKit rejected-presentation test with the same missing-completion exception as the crash reports.

## Running the simulator tests

The test specification extends the production XcodeGen specification. It generates a separate project and does not alter the production project or add test code to the shipping app.

```sh
xcodegen generate --spec Tests/Crashes/project.yml
xcodebuild -project Tests/Crashes/SafienceCrashTests.xcodeproj \
  -scheme CrashRegression \
  -destination 'platform=iOS Simulator,id=<dedicated-test-simulator-uuid>' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
swift test --package-path PadCore
```

Use a dedicated simulator: overview tests add and remove synthetic spaces in the app's test installation. No physical device, signed release or TestFlight build is part of this verification.
