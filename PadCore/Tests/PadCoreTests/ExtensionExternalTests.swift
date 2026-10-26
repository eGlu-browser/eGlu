import JavaScriptCore
@testable import PadCore
import XCTest

final class ExtensionExternalTests: XCTestCase {
    func testPatternsChromeTakesAndNoOthers() {
        for pattern in ["https://claude.ai/*", "*://*.example.com/*", "http://localhost:8080/*", "https://app.example.co.uk/path/*"] {
            XCTAssertTrue(ExtensionExternal.allowed(pattern), pattern)
        }
        for pattern in ["*://*/*", "<all_urls>", "https://*.com/*", "https://*/*", "https://a*.example.com/*",
                        "ftp://example.com/*", "https://example.com", "https://accounts.google.com/*", "https://*.google.com/*"] {
            XCTAssertFalse(ExtensionExternal.allowed(pattern), pattern)
        }
        let manifest: [String: Any] = ["externally_connectable": ["matches": ["https://claude.ai/*", "*://*/*", "https://claude.ai/*"]]]
        XCTAssertEqual(ExtensionExternal.listed(in: manifest), ["https://claude.ai/*"])
        XCTAssertNil(ExtensionExternal.script(listings: [:]))
        XCTAssertNil(ExtensionExternal.script(listings: ["a": []]))
    }

    /// The script in a page of its own: chrome.runtime only where an
    /// extension lists the page, and a message for one that doesn't list
    /// it, or isn't there, fails as Chrome's does.
    func testOnlyAListedPageGetsChromeAndReachesOnlyWhoListsIt() throws {
        let script = try XCTUnwrap(ExtensionExternal.script(listings: ["listing": ["https://claude.ai/*"], "elsewhere": ["https://other.example/*"]]))
        let listed = JSContext()!
        listed.evaluateScript("""
        var window = this, sent = [];
        var location = { protocol: 'https:', hostname: 'claude.ai', port: '', pathname: '/oauth', search: '?x=1' };
        window.browser = { runtime: { sendMessage: function (id, m) { sent.push(id); return Promise.resolve('answered ' + id); } } };
        """)
        listed.evaluateScript(script)
        XCTAssertEqual(listed.evaluateScript("typeof chrome === 'object' && typeof chrome.runtime.sendMessage")?.toString(), "function")
        listed.evaluateScript("""
        var results = [];
        chrome.runtime.sendMessage('listing', {}).then(function (r) { results.push(r); });
        chrome.runtime.sendMessage('elsewhere', {}).then(function () { results.push('wrong'); }, function (e) { results.push(e.message); });
        chrome.runtime.sendMessage('missing', {}, function (r) { results.push('callback ' + (chrome.runtime.lastError && chrome.runtime.lastError.message)); });
        """)
        // Promises settle once the evaluation's turn is over.
        listed.evaluateScript("0")
        XCTAssertEqual(listed.evaluateScript("JSON.stringify(sent)")?.toString(), "[\"listing\"]")
        let results = listed.evaluateScript("JSON.stringify(results.slice().sort())")?.toString() ?? ""
        XCTAssertTrue(results.contains("answered listing"), results)
        XCTAssertTrue(results.contains("Could not establish connection. Receiving end does not exist."), results)
        XCTAssertTrue(results.contains("callback Could not establish connection"), results)

        let unlisted = JSContext()!
        unlisted.evaluateScript("""
        var window = this;
        var location = { protocol: 'https:', hostname: 'news.example', port: '', pathname: '/', search: '' };
        window.browser = { runtime: { sendMessage: function () { return Promise.resolve(); } } };
        """)
        unlisted.evaluateScript(script)
        XCTAssertEqual(unlisted.evaluateScript("typeof chrome")?.toString(), "undefined")

        let own = JSContext()!
        own.evaluateScript("""
        var window = this; var chrome = { mine: true };
        var location = { protocol: 'https:', hostname: 'claude.ai', port: '', pathname: '/', search: '' };
        window.browser = { runtime: { sendMessage: function () { return Promise.resolve(); } } };
        """)
        own.evaluateScript(script)
        XCTAssertEqual(own.evaluateScript("chrome.mine === true && chrome.runtime === undefined")?.toBool(), true)
    }
}
