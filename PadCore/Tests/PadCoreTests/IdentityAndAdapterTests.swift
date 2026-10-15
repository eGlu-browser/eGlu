import XCTest
@testable import PadCore

final class IdentityTests: XCTestCase {
    func testApplicationNameIsSafaris() {
        XCTAssertEqual(Identity.applicationName(major: 18, minor: 6), "Version/18.6 Safari/605.1.15")
        XCTAssertEqual(Identity.applicationName(major: 26, minor: 0), "Version/26.0 Safari/605.1.15")
        XCTAssertEqual(Identity.applicationName(major: 17, minor: 4, patch: 1), "Version/17.4.1 Safari/605.1.15")
        let system = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        XCTAssertEqual(Identity.applicationName(for: system), "Version/26.1 Safari/605.1.15")
    }

    func testWholeUserAgentIsMacSafaris() {
        let name = Identity.applicationName(major: 18, minor: 6)
        XCTAssertEqual(
            Identity.macUserAgent(applicationName: name),
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
        )
    }
}

final class AdapterTests: XCTestCase {
    func testFigmaIsFirst() {
        XCTAssertEqual(Adapters.all.first?.id, "figma")
        XCTAssertEqual(Adapters.all.map(\.id), ["figma", "youtube", "greenhouse", "ashby", "workday"])
    }

    /// The tools most companies hire with: one job's page is a posting, by its address, and their boards' other pages are not.
    func testJobBoardsKnowTheirPostingsByAddress() {
        let postings = [
            ("https://job-boards.greenhouse.io/discord/jobs/8815116002", "greenhouse"),
            ("https://boards.greenhouse.io/anthropic/jobs/5183044008?gh_src=x", "greenhouse"),
            ("https://job-boards.eu.greenhouse.io/acme/jobs/4012345101", "greenhouse"),
            ("https://jobs.ashbyhq.com/openai/de06790a-7243-4e33-a6f1-e7bd34009588", "ashby"),
            ("https://jobs.ashbyhq.com/openai/de06790a-7243-4e33-a6f1-e7bd34009588/application", "ashby"),
            ("https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/Israel-Yokneam/Senior-AI-Systems-Engineer_JR2025271-1", "workday"),
            ("https://salesforce.wd12.myworkdayjobs.com/External_Career_Site/job/Sales-Strategy-Senior-Manager_JR363610", "workday"),
        ]
        for (address, id) in postings {
            let adapter = Adapters.adapter(for: URL(string: address))
            XCTAssertEqual(adapter.id, id, address)
            XCTAssertTrue(adapter.isPosting(URL(string: address)), address)
        }
        for address in ["https://job-boards.greenhouse.io/discord", "https://www.greenhouse.io/blog/jobs/1", "https://jobs.ashbyhq.com/openai",
                        "https://nvidia.wd5.myworkdayjobs.com/NVIDIAExternalCareerSite", "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/introduceYourself"] {
            XCTAssertFalse(Adapters.adapter(for: URL(string: address)).isPosting(URL(string: address)), address)
        }
        // Another site at a posting's path is not one.
        XCTAssertFalse(Adapters.adapter(for: URL(string: "https://example.com/discord/jobs/8815116002")).isPosting(URL(string: "https://example.com/discord/jobs/8815116002")))
        XCTAssertTrue(Adapters.greenhouse.bridges == .standard && Adapters.greenhouse.script.isEmpty && Adapters.workday.css.isEmpty)
    }

    func testFigmaCoversItsHostsOnly() {
        for address in ["https://www.figma.com/files", "https://figma.com/design/abc/Name", "https://embed.figma.com/x", "https://WWW.FIGMA.COM./x"] {
            XCTAssertEqual(Adapters.adapter(for: URL(string: address)).id, "figma", address)
        }
        for address in ["https://notfigma.com/", "https://figma.com.evil.example/", "https://example.com/figma.com"] {
            XCTAssertEqual(Adapters.adapter(for: URL(string: address)).id, "standard", address)
        }
        XCTAssertEqual(Adapters.adapter(for: nil).id, "standard")
    }

    func testYouTubeIsAnAdapterForHandoffAlone() throws {
        let youtube = Adapters.adapter(for: URL(string: "https://m.youtube.com/watch?v=SAekvy5Mn_U"))
        XCTAssertEqual(youtube.id, "youtube")
        for address in ["https://www.youtube.com/", "https://youtu.be/SAekvy5Mn_U", "https://music.youtube.com/watch?v=x"] {
            XCTAssertEqual(Adapters.adapter(for: URL(string: address)).id, "youtube", address)
        }
        for address in ["https://notyoutube.com/", "https://youtube.com.evil.example/", "https://www.youtube-nocookie.com/embed/x"] {
            XCTAssertEqual(Adapters.adapter(for: URL(string: address)).id, "standard", address)
        }
        // Every bridge as on any other site, and nothing put into its pages: what goes in is the bridge, told the site's name.
        XCTAssertEqual(youtube.bridges, .standard)
        XCTAssertTrue(youtube.css.isEmpty && youtube.script.isEmpty && youtube.pageScript.isEmpty && youtube.heavyPaths.isEmpty)
        XCTAssertNil(youtube.userAgent)
        XCTAssertNil(Scripts.page(for: youtube))
        XCTAssertEqual(Scripts.ours(for: youtube, bridges: .standard).replacingOccurrences(of: "\"adapter\":\"youtube\"", with: "\"adapter\":\"standard\""),
                       Scripts.ours(for: Adapters.standard, bridges: .standard))
        // Its reader ships as one function, which the app names and calls when Handoff is asked for.
        let reader = youtube.reader.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(reader.hasSuffix("})"), "youtube.js must end with the function, not a call or a semicolon")
        XCTAssertTrue(reader.contains("(async function (limit, patience, address) {"))
        XCTAssertEqual(Scripts.readerCall(for: youtube)?.hasPrefix("const run = // "), true)
        XCTAssertEqual(Scripts.readerCall(for: youtube)?.hasSuffix("})\n;\nreturn await run(limit, patience);"), true)
        XCTAssertNil(Scripts.readerCall(for: Adapters.standard))
        XCTAssertNil(Scripts.readerCall(for: Adapters.figma))
        // It asks the site for nothing itself: the site's own button is pressed, and the page does the asking.
        for banned in ["fetch(", "XMLHttpRequest", "timedtext?", "youtubei/", "document.cookie", "sendBeacon"] {
            XCTAssertFalse(reader.contains(banned), "youtube.js uses \(banned)")
        }
    }

    func testAYouTubeVideoIsToldFromItsAddressAndHasADesktopPage() throws {
        for address in ["https://www.youtube.com/watch?v=SAekvy5Mn_U", "https://m.youtube.com/watch?v=SAekvy5Mn_U&t=42s&list=PL1&si=abc",
                        "https://youtube.com/watch?feature=share&v=SAekvy5Mn_U", "https://youtu.be/SAekvy5Mn_U?si=abc",
                        "https://www.youtube.com/shorts/SAekvy5Mn_U", "https://M.YouTube.com/live/SAekvy5Mn_U?feature=share"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertEqual(YouTube.video(at: url), "SAekvy5Mn_U", address)
            // The page a computer is served, with nothing of the address it was reached by.
            XCTAssertEqual(YouTube.desktopPage(for: url)?.absoluteString, "https://www.youtube.com/watch?v=SAekvy5Mn_U", address)
            XCTAssertEqual(Adapters.youtube.readerPage(for: url)?.absoluteString, "https://www.youtube.com/watch?v=SAekvy5Mn_U", address)
        }
        // Not its other pages, its other sites, or an address that only looks like a video's.
        for address in ["https://www.youtube.com/", "https://www.youtube.com/watch", "https://www.youtube.com/watch?v=", "https://www.youtube.com/@harbour",
                        "https://www.youtube.com/results?search_query=SAekvy5Mn_U", "https://www.youtube.com/embed/SAekvy5Mn_U",
                        "https://www.youtube.com/watch/more?v=SAekvy5Mn_U", "https://music.youtube.com/watch?v=SAekvy5Mn_U",
                        "https://studio.youtube.com/video/SAekvy5Mn_U/edit", "https://notyoutube.com/watch?v=SAekvy5Mn_U",
                        "https://www.youtube.com/watch?v=%3Cscript%3E", "https://www.youtube.com/watch?v=abc", "https://youtu.be/",
                        "https://www.youtube.com/watch?v=SAekvy5Mn_U%26next%3Dhttps%3A%2F%2Fevil.example"] {
            XCTAssertNil(YouTube.video(at: URL(string: address)), address)
            XCTAssertNil(YouTube.desktopPage(for: URL(string: address)), address)
        }
        XCTAssertNil(YouTube.video(at: nil))
        // Another site's adapter has no such page, and neither has a site with none.
        let video = URL(string: "https://www.youtube.com/watch?v=SAekvy5Mn_U")
        XCTAssertNil(Adapters.figma.readerPage(for: URL(string: "https://www.figma.com/design/abc")))
        XCTAssertNil(Adapters.standard.readerPage(for: video))
        XCTAssertNil(Adapters.figma.readerPage(for: video))
    }

    func testHeavyPagesAreDocumentsNotTheFileBrowser() {
        let figma = Adapters.figma
        XCTAssertTrue(figma.isHeavy(URL(string: "https://www.figma.com/design/AbC123/Product?node-id=1-2")))
        XCTAssertTrue(figma.isHeavy(URL(string: "https://www.figma.com/board/AbC123/Workshop")))
        XCTAssertTrue(figma.isHeavy(URL(string: "https://www.figma.com/file/AbC123/Legacy")))
        XCTAssertFalse(figma.isHeavy(URL(string: "https://www.figma.com/files/recents-and-sharing")))
        XCTAssertFalse(figma.isHeavy(URL(string: "https://www.figma.com/")))
        XCTAssertFalse(figma.isHeavy(URL(string: "https://example.com/design/x")))
        XCTAssertFalse(Adapters.standard.isHeavy(URL(string: "https://example.com/design/x")))
    }

    func testEveryBridgeIsOnByDefaultAndOnlyTabIsTakenFromTheSystem() {
        let bridges = Adapters.standard.bridges
        XCTAssertTrue(bridges.pinch)
        XCTAssertTrue(bridges.commandZoom)
        XCTAssertEqual(bridges.wheel, .auto)
        XCTAssertEqual(bridges.keys, [.tab], "Tab reaches the page first; the arrows stay the system's")
        XCTAssertEqual(bridges.pinchFactor, 100)
    }

    func testFigmaFollowsThePinch() {
        // Measured in Safari on a Mac (Validation/figma-ctrl-wheel.js): each
        // ctrl+wheel event zooms Figma by e^(-deltaY / 200).
        let figmaZoom = { (deltaY: Double) in Foundation.exp(-deltaY / 200) }
        let delta = Pinch.wheelDelta(step: 2, factor: Adapters.figma.bridges.pinchFactor)
        XCTAssertEqual(figmaZoom(delta), 2, accuracy: 0.001)
    }

    func testFigmaHidesTouchPointsInThePagesOwnWorld() {
        XCTAssertTrue(Adapters.figma.pageScript.contains("maxTouchPoints"))
        XCTAssertTrue(Adapters.standard.pageScript.isEmpty)
    }
}

final class HandsOffTests: XCTestCase {
    func testGoogleSignInIsHandsOff() {
        XCTAssertTrue(HandsOff.covers(URL(string: "https://accounts.google.com/v3/signin/identifier?flowName=GlifWebSignIn")))
        XCTAssertTrue(HandsOff.covers(URL(string: "https://ACCOUNTS.GOOGLE.COM./o/oauth2/auth")))
        XCTAssertTrue(HandsOff.covers(host: "accounts.google.com"))
    }

    func testOtherGoogleHostsAreNot() {
        XCTAssertFalse(HandsOff.covers(URL(string: "https://mail.google.com/")))
        XCTAssertFalse(HandsOff.covers(URL(string: "https://google.com/")))
        XCTAssertFalse(HandsOff.covers(URL(string: "https://notaccounts.google.com/")))
        XCTAssertFalse(HandsOff.covers(URL(string: "https://accounts.google.com.evil.example/")))
        XCTAssertFalse(HandsOff.covers(nil))
    }

    func testCookiesSentToGoogleSignInAreHandsOff() {
        XCTAssertTrue(HandsOff.covers(cookieDomain: "accounts.google.com"))
        XCTAssertTrue(HandsOff.covers(cookieDomain: ".accounts.google.com"))
        XCTAssertTrue(HandsOff.covers(cookieDomain: ".google.com"))
        XCTAssertTrue(HandsOff.covers(cookieDomain: "google.com"))
        XCTAssertFalse(HandsOff.covers(cookieDomain: "mail.google.com"))
        XCTAssertFalse(HandsOff.covers(cookieDomain: ".figma.com"))
        XCTAssertFalse(HandsOff.covers(cookieDomain: "google.co.uk"))
    }

    func testNativeScrollingOnlyWhereNoBridgeCanRun() {
        XCTAssertTrue(Scrolling.isNative(url: URL(string: "https://accounts.google.com/x"), mimeType: "text/html"))
        XCTAssertTrue(Scrolling.isNative(url: URL(string: "https://example.com/report"), mimeType: "application/pdf"))
        XCTAssertTrue(Scrolling.isNative(url: URL(string: "https://example.com/report.pdf"), mimeType: nil))
        XCTAssertFalse(Scrolling.isNative(url: URL(string: "https://www.figma.com/design/x"), mimeType: "text/html"))
        XCTAssertFalse(Scrolling.isNative(url: URL(string: "https://example.com/report.pdf"), mimeType: "text/html"))
    }
}
