import XCTest
@testable import PadCore

final class ExtensionCheckTests: XCTestCase {
    // MARK: The manifest

    func testAManifestWithCommentsReadsAsChromeReadsIt() throws {
        let json = """
        \u{FEFF}{
          // Chrome allows comments.
          "manifest_version": 2,
          "name": "Old one", /* and these */
          "version": "1.0",
          "permissions": ["storage", "tabs", "<all_urls>", "https://*.example.com/*", "webRequestBlocking"],
          "background": {"scripts": ["bg.js"]},
          "browser_action": {"default_popup": "popup.html"},
          "options_page": "options.html",
          "content_scripts": [{"matches": ["<all_urls>"], "js": ["a.js"], "all_frames": true}],
          "description": "A // that isn't a comment"
        }
        """
        let manifest = try ExtensionManifest(json: Data(json.utf8))
        XCTAssertEqual(manifest.manifestVersion, 2)
        XCTAssertEqual(manifest.permissions, ["storage", "tabs", "webRequestBlocking"])
        XCTAssertEqual(manifest.hostPermissions, ["<all_urls>", "https://*.example.com/*"], "Manifest V2's sites are among its permissions")
        XCTAssertEqual(manifest.background, .scripts(["bg.js"], persistent: true), "no persistent key is persistent")
        XCTAssertEqual(manifest.popup, "popup.html")
        XCTAssertEqual(manifest.optionsPage, "options.html")
        XCTAssertEqual(manifest.contentScripts.first?.allFrames, true)
        XCTAssertEqual(manifest.contentScripts.first?.world, "ISOLATED")
        XCTAssertEqual(manifest.files, ["bg.js", "a.js", "popup.html", "options.html"])
    }

    func testAManifestV3ExtensionsWorkerAndPages() throws {
        let json = """
        {"manifest_version": 3, "name": "New", "version": "2.1",
         "permissions": ["sidePanel", "offscreen", "identity"], "optional_permissions": ["bookmarks"],
         "host_permissions": ["<all_urls>"],
         "background": {"service_worker": "sw.js", "type": "module"},
         "action": {"default_popup": "p.html"}, "options_ui": {"page": "o.html"},
         "side_panel": {"default_path": "panel.html"}, "oauth2": {"client_id": "x"}}
        """
        let manifest = try ExtensionManifest(json: Data(json.utf8))
        XCTAssertEqual(manifest.background, .worker("sw.js", module: true))
        XCTAssertEqual(manifest.sidePanel, "panel.html")
        XCTAssertTrue(manifest.usesChromeSignIn)
        XCTAssertEqual(manifest.dropped(kept: ["identity"]), ["sidePanel", "offscreen", "bookmarks"],
                       "what WebKit didn't keep, optional ones included")
    }

    func testAManifestWithoutAVersionIsRefused() {
        XCTAssertThrowsError(try ExtensionManifest(json: Data(#"{"name": "x"}"#.utf8)))
        XCTAssertThrowsError(try ExtensionManifest(json: Data("not json".utf8)))
    }

    // MARK: The table

    func testTheTableIsTheMacsWebKitWithTheShimsOnTop() {
        let table = ExtensionAPITable(
            webKit: ["tabs": ["query", "create"], "storage": ["local"]],
            shims: ["sidePanel": .shim, "identity": .part, "identity.getAuthToken": .refused,
                    "identity.launchWebAuthFlow": .shim, "contentSettings": .stub, "tabs": .shim]
        )
        XCTAssertEqual(table.answer(for: "tabs"), .native, "WebKit's own wins over a shim")
        XCTAssertEqual(table.answer(for: "tabs.query"), .native)
        XCTAssertNil(table.answer(for: "tabs.discard"), "a member WebKit's tabs lacks")
        XCTAssertEqual(table.answer(for: "sidePanel.open"), .shim)
        XCTAssertTrue(table.works("identity.launchWebAuthFlow"))
        XCTAssertFalse(table.works("identity.getAuthToken"))
        XCTAssertFalse(table.works("contentSettings.set"), "a stub does nothing")
        XCTAssertFalse(table.works("tabCapture"))
    }

    // MARK: Reading the code

    private let missing: Set<String> = ["tabCapture", "identity.getAuthToken", "history", "sidePanel"]

    func testAPlainUseIsFoundAndATestIsNot() {
        let code = """
        chrome.tabCapture.capture({audio: true}, s => {});
        if (chrome.sidePanel) { chrome.sidePanel.open({}); }
        """
        let uses = ExtensionScan.uses(in: code, file: "bg.js", of: missing)
        XCTAssertEqual(uses.map(\.path), ["tabCapture", "sidePanel", "sidePanel"])
        XCTAssertEqual(uses.first { $0.path == "tabCapture" }?.tested, false)
        XCTAssertTrue(uses.filter { $0.path == "sidePanel" }.allSatisfy(\.tested), "the test guards the use after it")
        XCTAssertEqual(uses.first?.line, 1)
    }

    func testTheWaysCodeTestsForAnAPI() {
        for code in [
            "typeof chrome.tabCapture !== 'undefined'",
            "e.tabCapture?.capture()",
            "const ok = !!t.tabCapture",
            "x.tabCapture && x.tabCapture.capture()",
            "if ('tabCapture' in chrome) {}",
            "while (chrome.tabCapture) {}",
            "chrome.tabCapture ? a() : b()",
            "typeof chrome['tabCapture']",
        ] {
            let uses = ExtensionScan.uses(in: code, file: "a.js", of: missing)
            XCTAssertFalse(uses.isEmpty, code)
            XCTAssertTrue(uses.allSatisfy(\.tested), code)
        }
    }

    func testMinifiedCodeIsReadUnderAnyName() {
        let uses = ExtensionScan.uses(in: "n.tabCapture.capture(o);e[\"sidePanel\"].open()", file: "min.js", of: missing)
        XCTAssertEqual(uses.map(\.path), ["tabCapture", "sidePanel"])
        XCTAssertTrue(uses.allSatisfy { !$0.tested })
    }

    func testStringsCommentsAndRegexAreNotCode() {
        let code = """
        // chrome.tabCapture.capture()
        /* chrome.tabCapture.capture() */
        const s = "chrome.tabCapture.capture()";
        const t = `chrome.tabCapture.capture()`;
        const r = /chrome.tabCapture.capture/g;
        """
        XCTAssertEqual(ExtensionScan.uses(in: code, file: "a.js", of: missing), [])
    }

    func testACommonNameCountsOnlyAsChromes() {
        // window.history is the web's; chrome.history and history.search are Chrome's.
        XCTAssertEqual(ExtensionScan.uses(in: "window.history.back(); location.history", file: "a.js", of: missing), [])
        XCTAssertEqual(ExtensionScan.uses(in: "chrome.history.search({text: ''})", file: "a.js", of: missing).map(\.path), ["history"])
        XCTAssertEqual(ExtensionScan.uses(in: "e.history.getVisits({url})", file: "a.js", of: missing).map(\.path), ["history"])
    }

    func testAMissingMemberOfANamespaceThatWorks() {
        let uses = ExtensionScan.uses(in: "chrome.identity.launchWebAuthFlow(o); chrome.identity.getAuthToken({interactive: true})",
                                      file: "a.js", of: missing)
        XCTAssertEqual(uses.map(\.path), ["identity.getAuthToken"])
        XCTAssertEqual(uses.first?.tested, false)
    }

    func testANameOnItsOwnIsntChromes() {
        XCTAssertEqual(ExtensionScan.uses(in: "const sidePanel = 1; sidePanel.open()", file: "a.js", of: missing), [])
    }

    func testAnArrayOfNamesIsntAUse() {
        XCTAssertEqual(ExtensionScan.uses(in: "const panels=[\"sidePanel\"];", file: "a.js", of: missing), [])
        XCTAssertEqual(ExtensionScan.uses(in: "f([\"tabCapture\", 1])", file: "a.js", of: missing), [])
    }

    func testNotOrVoidBeforeACallIsntATest() {
        for code in ["void chrome.sidePanel.open({});", "!chrome.sidePanel.open()", "typeof chrome.sidePanel.open"] {
            let uses = ExtensionScan.uses(in: code, file: "a.js", of: missing)
            XCTAssertEqual(uses.map(\.path), ["sidePanel"], code)
            XCTAssertEqual(uses.first?.tested, false, "the call throws all the same: \(code)")
        }
    }

    func testARegularExpressionAfterAConditionIsntCode() {
        XCTAssertEqual(ExtensionScan.uses(in: "if(ok)/chrome.sidePanel.open/.test(text);", file: "a.js", of: missing), [])
        XCTAssertEqual(ExtensionScan.uses(in: "while (x) /chrome.tabCapture/g.exec(s)", file: "a.js", of: missing), [])
        // A call's closing parenthesis still divides: f(x) / chrome.tabCapture.n
        XCTAssertEqual(ExtensionScan.uses(in: "f(x) / chrome.tabCapture.n", file: "a.js", of: missing).map(\.path), ["tabCapture"])
    }

    func testCodeInATemplateIsRead() {
        let uses = ExtensionScan.uses(in: "const text = `id: ${chrome.tabCapture.capture({a: {b: 1}})} and chrome.sidePanel`;", file: "a.js", of: missing)
        XCTAssertEqual(uses.map(\.path), ["tabCapture"], "the template's own text is not code")
        XCTAssertEqual(uses.first?.tested, false)
    }

    func testDivisionIsntARegularExpression() {
        let uses = ExtensionScan.uses(in: "const a = b / 2; chrome.tabCapture.capture(); const c = d / e;", file: "a.js", of: missing)
        XCTAssertEqual(uses.map(\.path), ["tabCapture"])
    }

    // MARK: Errors

    /// What nothing on this Mac answers, for the error tests.
    private let lacking: Set<String> = ["sidePanel", "notifications", "tabs.discard"]

    func testJavaScriptCoresWordingNamesTheAPI() {
        XCTAssertEqual(ExtensionError.problem(in: "TypeError: undefined is not an object (evaluating 'e.sidePanel.open')", missing: lacking),
                       ExtensionError.Problem(kind: .missing, api: "sidePanel"))
        XCTAssertEqual(ExtensionError.problem(in: "TypeError: chrome.tabs.discard is not a function. (In 'chrome.tabs.discard(1)', 'chrome.tabs.discard' is undefined)", missing: lacking),
                       ExtensionError.Problem(kind: .notAFunction, api: "tabs.discard"))
        XCTAssertEqual(ExtensionError.problem(in: "Invalid call to tabs.query(). The 'queryInfo' value is invalid.", missing: lacking),
                       ExtensionError.Problem(kind: .wrongArguments, api: "tabs.query"))
        XCTAssertEqual(ExtensionError.problem(in: "ReferenceError: Can't find variable: chrome", missing: lacking),
                       ExtensionError.Problem(kind: .missing, api: "chrome"))
    }

    func testAMinifiedNameCountsOnlyForWhatIsMissing() {
        XCTAssertEqual(ExtensionError.problem(in: "TypeError: e.tabs.discard is not a function. (In 'e.tabs.discard(1)', 'e.tabs.discard' is undefined)", missing: lacking),
                       ExtensionError.Problem(kind: .notAFunction, api: "tabs.discard"))
        // The extension's own state, whose field happens to be called tabs.
        XCTAssertNil(ExtensionError.problem(in: "TypeError: undefined is not an object (evaluating 'state.tabs.length')", missing: lacking))
        XCTAssertNil(ExtensionError.problem(in: "ReferenceError: Can't find variable: config", missing: lacking))
    }

    func testAnErrorAboutTheExtensionsOwnCodeIsntAProblem() {
        XCTAssertNil(ExtensionError.problem(in: "TypeError: undefined is not an object (evaluating 'state.user.name')", missing: lacking))
        XCTAssertNil(ExtensionError.problem(in: "Saved your settings", missing: lacking), "console.error used for good news")
        XCTAssertNil(ExtensionError.problem(in: "NetworkError: Load failed", missing: lacking))
    }

    func testTheErrorsPlaceIsThePathInsideTheExtension() throws {
        let place = try XCTUnwrap(ExtensionError.place(in: "Oops (webkit-extension://1234-abcd/js/background.js:12:5)"))
        XCTAssertEqual(place.file, "js/background.js")
        XCTAssertEqual(place.line, 12)
        XCTAssertEqual(ExtensionError.place(in: "Oops (popup.js:3:1)")?.file, "popup.js")
        XCTAssertNil(ExtensionError.place(in: "no place"))
    }

    // MARK: What the person reads

    private func started(_ change: (inout ExtensionEvidence) -> Void = { _ in }) -> ExtensionVerdict {
        var evidence = ExtensionEvidence()
        evidence.start = .started
        change(&evidence)
        return ExtensionVerdict(evidence)
    }

    func testStartingAndTheChecksPassingIsStartedFineAndNoMore() {
        let verdict = started { $0.testPage = .passed; $0.popup = .passed }
        XCTAssertEqual(verdict.status, .startedFine)
        XCTAssertEqual(verdict.title, "Started Fine")
        XCTAssertEqual(verdict.lines, ["Checked: starting up, a test page and its popup. Its features haven't all been tried."])
    }

    func testReadingAloneNeverChangesTheStatus() {
        let verdict = started { $0.popup = .passed; $0.mayNotWork = ["tabCapture"] }
        XCTAssertEqual(verdict.status, .startedFine)
        XCTAssertEqual(verdict.lines.last, "May not work: record a tab.")
    }

    func testAnErrorSeenIsSomeFeaturesDontWork() {
        let verdict = started {
            $0.popup = .passed
            $0.problems = [ExtensionError.Problem(kind: .missing, api: "sidePanel")]
            $0.unreachableApp = "Bitwarden"
        }
        XCTAssertEqual(verdict.status, .someFeaturesDontWork)
        XCTAssertEqual(verdict.lines, ["Can't open its side panel.", "Can't reach the Bitwarden app."])
    }

    func testNotStartingWinsOverEverything() {
        var evidence = ExtensionEvidence()
        evidence.start = .failed
        evidence.tried = .init(release: "2.3", works: true, what: "blocking on 20 sites")
        XCTAssertEqual(ExtensionVerdict(evidence).status, .couldntStart)
        XCTAssertEqual(ExtensionVerdict(evidence).lines.first, "Safience tried starting it again.")
    }

    func testOnlyUntriableChecksIsNotCheckedYet() {
        XCTAssertEqual(started { $0.testPage = .skipped }.status, .notCheckedYet)
        XCTAssertEqual(started { $0.popup = .timedOut }.status, .notCheckedYet)
        XCTAssertEqual(started { $0.testPage = .skipped; $0.popup = .passed }.status, .startedFine)
        XCTAssertEqual(started().status, .startedFine, "a background and nothing else: starting is all there is")
        XCTAssertEqual(started { $0.popup = .checking }.status, .checking)
    }

    func testOnlyTheTriedListSaysItWorks() {
        let verdict = started { $0.popup = .passed; $0.tried = .init(release: "2.3", works: true, what: "blocking on 20 sites") }
        XCTAssertEqual(verdict.status, .triedWorks)
        XCTAssertEqual(verdict.title, "Works")
        XCTAssertEqual(verdict.lines.first, "Tried by Safience on version 2.3: blocking on 20 sites.")
        // What this Mac saw still comes first.
        let failing = started { $0.tried = .init(release: "2.3", works: true, what: "x"); $0.problems = [.init(kind: .missing, api: "offscreen")] }
        XCTAssertEqual(failing.status, .someFeaturesDontWork)
    }

    func testCookiesKeptBackAreSaid() {
        XCTAssertEqual(started { $0.cookiesKeptBack = true }.lines.last, "Can't read cookies: kept from Google's sign-in.")
        var checking = ExtensionEvidence()
        checking.cookiesKeptBack = true
        XCTAssertEqual(ExtensionVerdict(checking).lines, [], "nothing under Checking…")
    }

    // MARK: Hands-off

    func testEveryExtensionIsKeptOffGooglesSignIn() throws {
        XCTAssertEqual(ExtensionPolicy.deniedSites, ["*://*.accounts.google.com/*"])
        XCTAssertTrue(ExtensionPolicy.deniedPermissions.contains("cookies"))
        XCTAssertFalse(ExtensionPolicy.grantsOnClick(try XCTUnwrap(URL(string: "https://accounts.google.com/signin"))))
        XCTAssertFalse(ExtensionPolicy.grantsOnClick(try XCTUnwrap(URL(string: "https://x.accounts.google.com/"))))
        XCTAssertTrue(ExtensionPolicy.grantsOnClick(try XCTUnwrap(URL(string: "https://mail.google.com/"))))
        XCTAssertFalse(ExtensionPolicy.mayTouchData(ofDomain: ".google.com"), "its cookies go to accounts.google.com")
        XCTAssertFalse(ExtensionPolicy.mayTouchData(ofDomain: "accounts.google.com"))
        XCTAssertTrue(ExtensionPolicy.mayTouchData(ofDomain: "mail.google.com"))
        XCTAssertTrue(ExtensionPolicy.mayTouchData(ofDomain: "figma.com"))
    }
}
