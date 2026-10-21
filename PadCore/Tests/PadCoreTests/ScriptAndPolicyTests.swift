import XCTest
@testable import PadCore

final class PreferencesTests: XCTestCase {
    func testMissingFieldsTakeTheirDefaults() throws {
        let saved = Data(#"{"address":"always","limits":{"heavy":1,"lightOffScreen":0}}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: saved)
        XCTAssertEqual(preferences.address, .always)
        XCTAssertEqual(preferences.limits.lightOffScreen, 0)
        XCTAssertTrue(preferences.tabBar)
        XCTAssertNil(preferences.wheel)
        XCTAssertEqual(preferences.keys, .site)
        XCTAssertEqual(preferences.engine, "google")
    }

    func testUnknownValuesFallBackRatherThanFail() throws {
        let saved = Data(#"{"address":"sometimes","wheel":"sideways","tabBar":false}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: saved)
        XCTAssertEqual(preferences.address, .always)
        XCTAssertNil(preferences.wheel)
        XCTAssertFalse(preferences.tabBar)
    }

    func testAdsAreBlockedUnlessTurnedOffForASite() throws {
        var preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"address":"automatic"}"#.utf8))
        XCTAssertTrue(preferences.blocksContent, "settings saved before blocking came keep it on")
        XCTAssertTrue(preferences.blocksContent(onHost: "www.news.test"))
        preferences.setBlocksContent(false, onHost: "www.news.test")
        XCTAssertEqual(preferences.unblockedSites, ["news.test"])
        XCTAssertFalse(preferences.blocksContent(onHost: "news.test"), "www. or not, the same site")
        XCTAssertTrue(preferences.blocksContent(onHost: "other.test"))
        let saved = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(saved.unblockedSites, ["news.test"])
        preferences.setBlocksContent(true, onHost: "news.test")
        XCTAssertEqual(preferences.unblockedSites, [])
        preferences.blocksContent = false
        XCTAssertFalse(preferences.blocksContent(onHost: "other.test"))
    }

    func testTheTabBarIsCompactByDefault() throws {
        XCTAssertEqual(Preferences().layout, .compact)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(#"{"address":"automatic"}"#.utf8)).layout, .compact)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data(#"{"layout":"separate"}"#.utf8)).layout, .separate)
    }

    func testTheAddressBarStaysByDefault() throws {
        XCTAssertEqual(Preferences().address, .always)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).address, .always)
    }

    func testRoundTrip() throws {
        var preferences = Preferences()
        preferences.wheel = .always
        preferences.keys = .on
        preferences.diagnostics = true
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data), preferences)
    }

    func testTabReachesEveryPageFirst() {
        // iPadOS 26's focus system keeps Tab from a page otherwise.
        XCTAssertEqual(Bridges().keys, [.tab])
        XCTAssertEqual(Adapters.standard.bridges.keys, [.tab])
        XCTAssertEqual(Adapters.figma.bridges.keys, [.tab])
        XCTAssertEqual(Preferences().bridges(for: Adapters.standard).keys, [.tab])
    }

    func testSettingsLayOverTheAdaptersBridges() {
        var preferences = Preferences()
        XCTAssertEqual(preferences.bridges(for: Adapters.figma), Adapters.figma.bridges)
        preferences.wheel = .off
        preferences.keys = .on
        let bridges = preferences.bridges(for: Adapters.figma)
        XCTAssertEqual(bridges.wheel, .off)
        XCTAssertEqual(bridges.keys, [.tab, .arrows])
        XCTAssertTrue(bridges.pinch)
        preferences.keys = .off
        XCTAssertEqual(preferences.bridges(for: Adapters.figma).keys, [])
    }
}

final class ScriptsTests: XCTestCase {
    func testTheResourcesShip() {
        XCTAssertTrue(Scripts.bridge.contains("__safience"))
        XCTAssertTrue(Scripts.style.contains("touch-action: manipulation"))
    }

    func testCalloutsAreOffOnlyWhereTheSiteKeepsItsOwnMenus() {
        let anywhere = Scripts.ours(for: Adapters.standard, bridges: Adapters.standard.bridges)
        let kept = Scripts.ours(for: Adapters.standard, bridges: Adapters.standard.bridges, ownMenus: true)
        XCTAssertFalse(anywhere.contains("-webkit-touch-callout"), "or WebKit never asks the app for a link's menu")
        XCTAssertTrue(anywhere.contains("touch-action"))
        XCTAssertTrue(kept.contains("-webkit-touch-callout: none"), "the site's own context menu is the only one there")
    }

    func testTheCalloutRuleGoesInByItselfSoAPageThatIsUpCanBeGivenIt() {
        let anywhere = Scripts.ours(for: Adapters.standard, bridges: Adapters.standard.bridges)
        let kept = Scripts.ours(for: Adapters.standard, bridges: Adapters.standard.bridges, ownMenus: true)
        XCTAssertTrue(anywhere.contains("\"callouts\":\"\""))
        XCTAssertTrue(kept.contains("\"callouts\":\"html, html * { -webkit-touch-callout: none !important; }\""))
        // Apart from the rest of the style, and changed by the app while the page is up (Page.settingsChanged).
        XCTAssertTrue(Scripts.bridge.contains("let ownMenus = addStyle(config.callouts);"))
        XCTAssertTrue(Scripts.bridge.contains("if (ownMenus) ownMenus.textContent = css || '';"))
        XCTAssertTrue(Scripts.bridge.contains("wheel, key, pointer, type, callouts,"))
    }

    func testTheBridgeSaysWhetherThePageKeptAContextMenu() {
        XCTAssertTrue(Scripts.bridge.contains("kind: 'context', kept: event.defaultPrevented"))
        XCTAssertTrue(Scripts.bridge.contains("if (!event.isTrusted) return;"))
    }

    func testTheBridgeSaysWhenASidewaysSwipeWentUnused() {
        // What a swipe back goes on (TrackpadSwipe): the page left the event, and nothing scrolled sideways.
        XCTAssertTrue(Scripts.bridge.contains("if (m.dx && !moved.x && !moved.keptX) return 'free';"))
        // overscroll-behavior keeps the swipe to the page: on a scroller, and on the page itself.
        XCTAssertTrue(Scripts.bridge.contains("if (leftX && !x && contains('x', style)) moved.keptX = true;"))
        XCTAssertTrue(Scripts.bridge.contains("getComputedStyle(doc.documentElement).overscrollBehaviorX"))
    }

    func testOurScriptCarriesTheSitesSettings() {
        var bridges = Adapters.figma.bridges
        bridges.keys = [.arrows]
        let script = Scripts.ours(for: Adapters.figma, bridges: bridges, ownMenus: true)
        XCTAssertTrue(script.hasPrefix("window.__safienceConfig = {"))
        XCTAssertTrue(script.contains(#""adapter":"figma""#))
        XCTAssertTrue(script.contains(#""wheel":"auto""#))
        XCTAssertTrue(script.contains(#""keys":["arrows"]"#))
        XCTAssertTrue(script.contains(#""handsOff":["accounts.google.com"]"#))
        XCTAssertTrue(script.contains("-webkit-touch-callout"))
        XCTAssertTrue(script.contains(Scripts.bridge))
    }

    func testOnlyFigmaHasAPageWorldScript() {
        XCTAssertNotNil(Scripts.page(for: Adapters.figma))
        XCTAssertNil(Scripts.page(for: Adapters.standard))
    }

    func testAdapterScriptsCannotBreakTheBridge() {
        let adapter = SiteAdapter(id: "x", name: "X", domains: ["x.example"], script: "throw new Error('no')")
        let script = Scripts.ours(for: adapter, bridges: .standard)
        XCTAssertTrue(script.contains("try {\nthrow new Error('no')\n} catch (_) {}"))
    }
}

/// The rules about Google's sign-in, kept by reading the app's own source:
/// a cookie read or a script call anywhere else would break them without any
/// test of behaviour noticing.
final class PolicyTests: XCTestCase {
    /// The repository's root, where App/, Mac/ and PadCore/ are.
    var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PadCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // PadCore
            .deletingLastPathComponent()   // the root
    }

    func sources(in folder: String, ending: String) throws -> [(String, String)] {
        let start = root.appendingPathComponent(folder)
        guard let files = FileManager.default.enumerator(at: start, includingPropertiesForKeys: nil) else { return [] }
        return try files.compactMap { $0 as? URL }
            .filter { $0.path.hasSuffix(ending) }
            .map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    func testNothingReadsCookies() throws {
        let swift = try sources(in: "App", ending: ".swift") + sources(in: "Mac", ending: ".swift")
            + sources(in: "PadCore/Sources", ending: ".swift")
        XCTAssertFalse(swift.isEmpty)
        for (name, text) in swift {
            for banned in ["getAllCookies", "httpCookieStore", "HTTPCookieStorage", "document.cookie"] {
                XCTAssertFalse(text.contains(banned), "\(name) uses \(banned)")
            }
        }
        for (name, text) in try sources(in: "PadCore/Sources", ending: ".js") {
            XCTAssertFalse(text.contains("document.cookie"), "\(name) reads cookies")
        }
    }

    /// On the iPad (App/) and on the Mac (Mac/), each with a Page.swift of its own.
    /// SVGRaster.swift calls into a page of the app's own, where sites' SVG
    /// icons are drawn: it may, so long as that page is never a site's. So
    /// may the Mac's ExtensionBlankPage.swift, an empty page of the app's own
    /// at a removed extension's address, where what it kept is cleared; and
    /// its ExtensionPopup.swift, whose views (an extension's popup and side
    /// panel) only ever load that extension's own pages.
    func testOnlyPageSwiftCallsIntoPagesAndItAsksHandsOffFirst() throws {
        let ownPage = "SVGRaster.swift"
        let blank = "ExtensionBlankPage.swift"
        let surface = "ExtensionPopup.swift"
        for folder in ["App", "Mac"] {
            let swift = try sources(in: folder, ending: ".swift")
            if let page = swift.first(where: { $0.0 == blank })?.1 {
                XCTAssertTrue(page.contains("loadHTMLString(\"<!doctype html>\", baseURL: base)") && page.contains("base.scheme == Extensions.scheme"),
                              "\(blank)'s page must be an empty one at an extension's own address")
                for load in ["load(URLRequest", ".load(", "loadFileURL", "addUserScript", "evaluateJavaScript"] {
                    XCTAssertFalse(page.contains(load), "\(blank) must never load a site or add a script to one")
                }
            }
            if let page = swift.first(where: { $0.0 == surface })?.1 {
                XCTAssertTrue(page.contains("guard url.scheme == Extensions.scheme, url.host() == context.uniqueIdentifier"),
                              "\(surface)'s views must load only their extension's own pages")
                for load in ["loadHTMLString", "loadFileURL", "addUserScript"] {
                    XCTAssertFalse(page.contains(load), "\(surface) must never load a site or add a script to one")
                }
            }
            for (name, text) in swift where name != "Page.swift" && name != ownPage && name != blank && name != surface {
                for call in ["evaluateJavaScript", "callAsyncJavaScript", "addUserScript"] {
                    XCTAssertFalse(text.contains(call), "\(folder)/\(name) calls \(call); calls into pages go through Page.swift")
                }
            }
            if let raster = swift.first(where: { $0.0 == ownPage })?.1 {
                XCTAssertTrue(raster.contains("loadHTMLString(") && raster.contains("baseURL: nil"),
                              "\(ownPage)'s page must be the app's own, with no site for its origin")
                for load in ["load(URLRequest", ".load(", "loadFileURL", "addUserScript"] {
                    XCTAssertFalse(raster.contains(load), "\(ownPage) must never load a site or add a script to one")
                }
            }
            let page = try XCTUnwrap(swift.first { $0.0 == "Page.swift" }?.1, "\(folder) has no Page.swift")
            XCTAssertTrue(page.contains("HandsOff.covers"), "\(folder)/Page.swift doesn't ask HandsOff")
        }
    }

    /// What Apple's browser entitlement asks of the app
    /// (developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser).
    func testTheAppMeetsTheBrowserEntitlementsTerms() throws {
        let plist = try String(contentsOf: root.appendingPathComponent("App/Info.plist"), encoding: .utf8)
        for scheme in ["<string>http</string>", "<string>https</string>"] {
            XCTAssertTrue(plist.contains(scheme), "Info.plist must name \(scheme) as a URL scheme")
        }
        // Keys a browser with the entitlement is rejected for.
        for banned in ["NSPhotoLibraryUsageDescription", "NSLocationAlwaysUsageDescription",
                       "NSLocationAlwaysAndWhenInUseUsageDescription", "NSHomeKitUsageDescription",
                       "NSBluetoothAlwaysUsageDescription", "NSHealthShareUsageDescription",
                       "NSHealthUpdateUsageDescription"] {
            XCTAssertFalse(plist.contains(banned), "Info.plist has \(banned), which a browser may not use")
        }
        let swift = try sources(in: "App", ending: ".swift")
        for (name, text) in swift {
            XCTAssertFalse(text.contains("UIWebView"), "\(name) uses UIWebView")
        }
        let entitlements = try String(contentsOf: root.appendingPathComponent("Config/Safience.entitlements"), encoding: .utf8)
        XCTAssertTrue(entitlements.contains("<key>com.apple.developer.web-browser</key>"))
        // A browser may not claim Universal Links for its own domains.
        XCTAssertFalse(entitlements.contains("com.apple.developer.associated-domains"))
        let signing = try String(contentsOf: root.appendingPathComponent("Config/Signing.xcconfig"), encoding: .utf8)
        XCTAssertTrue(signing.contains("\nCODE_SIGN_ENTITLEMENTS = Config/Safience.entitlements"),
                      "the app is signed with the browser entitlement unless Local.xcconfig turns it off")
    }
}
