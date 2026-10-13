import XCTest
@testable import PadCore

final class ScriptedFilterTests: XCTestCase {
    private func action(_ line: String) -> ScriptedFilter.Action? {
        ScriptedFilter.parse(line).first?.action
    }

    func testAProceduralSelectorIsReadAsSteps() {
        XCTAssertEqual(action("news.test#?#div.card:has-text(Sponsored)"), .hide([.css("div.card"), .text("Sponsored")]))
        // Adblock Plus's names for the same things.
        XCTAssertEqual(action("news.test#?#.row:-abp-has(> header a:-abp-contains(/^\\s*Anzeige\\s*$/))"),
                       .hide([.css(".row"), .has([.css("> header a"), .text("/^\\s*Anzeige\\s*$/")])]))
        // CSS's own :has() with an operator inside it, and the CSS that goes on after one.
        XCTAssertEqual(action("shop.test#?#a[role=\"button\"]:has(p:has-text(Sponsored)) > span"),
                       .hide([.css("a[role=\"button\"]"), .has([.css("p"), .text("Sponsored")]), .css(" > span")]))
        XCTAssertEqual(action("shop.test##li:not(:has-text(Organic))"), .hide([.css("li"), .not([.text("Organic")])]))
        XCTAssertEqual(action("shop.test##.ad-label:upward(2)"), .hide([.css(".ad-label"), .upward("2")]))
        XCTAssertEqual(action("shop.test##span:has-text(Ad):upward(.card)"), .hide([.css("span"), .text("Ad"), .upward(".card")]))
        XCTAssertEqual(action("wiki.test##:xpath(//article/h1[not(./small)]/following-sibling::div[1])"),
                       .hide([.xpath("//article/h1[not(./small)]/following-sibling::div[1]")]))
        XCTAssertEqual(action("x.test##div:matches-css(position: fixed):min-text-length(40)"),
                       .hide([.css("div"), .style("position: fixed"), .length(40)]))
        // A bracket or a quote inside what is looked for doesn't end it.
        XCTAssertEqual(action("x.test#?#p:has-text(/\\(ad\\)/i)"), .hide([.css("p"), .text("/\\(ad\\)/i")]))
        XCTAssertEqual(action("x.test##a[title=\"a:has-text(b)\"]:has-text(c)"),
                       .hide([.css("a[title=\"a:has-text(b)\"]"), .text("c")]))
    }

    func testPlainSelectorsWebKitsRulesCouldntCarryAreHiddenByAStyleSheet() {
        XCTAssertEqual(action("shop.*##.promo"), .css(".promo"))
        XCTAssertEqual(action("x.test##div:has(> .a:has(.b))"), .css("div:has(> .a:has(.b))"), "CSS's own, left as it is")
        XCTAssertEqual(action("x.test##body[style=\"opacity: 0;\"]:style(opacity: 1 !important;)"),
                       .restyle([.css("body[style=\"opacity: 0;\"]")], "opacity: 1 !important;"))
        XCTAssertEqual(action("x.test##.gone:remove()"), .css(".gone"), "removed: hidden")
        XCTAssertNil(action("x.test##.a:style(color: red } body { display: none)"), "declarations only")
    }

    func testAHasAroundAPlainSelectorIsSaidInCSS() {
        // WebKit matches CSS's own ":has()" as the page changes, with no script looking again.
        XCTAssertEqual(action("shop.test#?#div.post:-abp-has(.ad-label)"), .css("div.post:has(.ad-label)"))
        XCTAssertEqual(action("shop.test#?#:-abp-has(> img[src*=\"gif\"])"), .css(":has(> img[src*=\"gif\"])"))
        XCTAssertEqual(action("shop.test#?#div:-abp-has(> ins) > span"), .css("div:has(> ins) > span"))
        XCTAssertEqual(action("shop.test#?#div:-abp-has(.ad):-abp-contains(Sponsored)"),
                       .hide([.css("div:has(.ad)"), .text("Sponsored")]))
        // Left as steps where joining would change what is meant: a list of
        // selectors on either side, or a ":has" inside, which CSS doesn't nest.
        XCTAssertEqual(action("shop.test#?#p, div:-abp-has(.ad)"), .hide([.css("p, div"), .has([.css(".ad")])]))
        XCTAssertEqual(action("shop.test#?#div:-abp-has(.ad) .a, .b"), .hide([.css("div:has(.ad)"), .css(" .a, .b")]))
        XCTAssertEqual(action("shop.test#?#div:-abp-has(.a:has(.b))"), .hide([.css("div"), .has([.css(".a:has(.b)")])]))
    }

    func testAChainStartsFromASelectorOrAPath() {
        // A test alone would be asked of every element, the page itself among them.
        for line in ["x.test##:has-text(Ad)", "x.test##:upward(2)", "x.test#?#:-abp-has(p:-abp-contains(Ad))",
                     "x.test##:min-text-length(10)",
                     // In CSS this would be every element around an ad, up to the page: not said in CSS either.
                     "x.test#?#:-abp-has(.ad)", "x.test#?#:-abp-has(.ad) > span", "x.test#?#:-abp-has(+ .ad)"] {
            XCTAssertTrue(ScriptedFilter.parse(line).isEmpty, line)
        }
        XCTAssertEqual(action("x.test##:xpath(//div[@id=\"ad\"])"), .hide([.xpath("//div[@id=\"ad\"]")]))
    }

    func testWhatItCantDoIsLeftOut() {
        for line in ["##div:has-text(Ad)",                       // for every site
                     "x.test##:-abp-properties(base64)", "x.test#?#div:matches-attr(a=b)",
                     "x.test##^script:has-text(ads)", "x.test##div[class=\"unclosed", "x.test##div:has-text(open",
                     "x.test##+js(cookie-remover, sid)", "x.test##+js(set-cookie, a, 1)", "x.test##+js(nowebrtc)",
                     "x.test#$#.ad { display: none !important; }", "bücher.test##.wild:has-text(x)"] {
            XCTAssertTrue(ScriptedFilter.parse(line).isEmpty, line)
        }
    }

    func testScriptletsByEitherListsNames() {
        XCTAssertEqual(action("x.test##+js(set, adBlockDetected, false)"), .run("set-constant", ["adBlockDetected", "false"]))
        XCTAssertEqual(action("x.test##+js(acs, document.createElement, admiral)"),
                       .run("abort-current-script", ["document.createElement", "admiral"]))
        XCTAssertEqual(action("x.test##+js(rmnt, script, '\"data-adm-url\"')"), .run("remove-node-text", ["script", "\"data-adm-url\""]))
        XCTAssertEqual(action("x.test##+js(aost, HTMLElement.prototype.insertBefore, /[A-Z] .+chunks\\/\\d{4}\\./)"),
                       .run("abort-on-stack-trace", ["HTMLElement.prototype.insertBefore", "/[A-Z] .+chunks\\/\\d{4}\\./"]))
        XCTAssertEqual(action("x.test##+js(no-fetch-if.js, stella)"), .run("no-fetch-if", ["stella"]))
        XCTAssertEqual(action("x.test##+js(nostif, a\\,b, 300)"), .run("no-setTimeout-if", ["a,b", "300"]), "a comma of the word's own")
        // Adblock Plus's snippets, one or several to a line.
        let several = ScriptedFilter.parse("x.test,y.*#$#abort-on-property-read atob; abort-on-property-write Fingerprint2")
        XCTAssertEqual(several.map(\.action), [.run("abort-on-property-read", ["atob"]), .run("abort-on-property-write", ["Fingerprint2"])])
        XCTAssertEqual(several.first?.domains, ["x.test", "y.*"])
        XCTAssertTrue(ScriptedFilter.parse("x.test#$#abort-on-property-read atob; hide-if-contains ad").isEmpty,
                      "all of a line's or none")
    }

    func testAPageGetsItsOwnSitesFiltersAndNoOthers() {
        let table = ScriptedTable(FilterConverter.convert("""
        news.test#?#div:has-text(Sponsored)
        news.test,~live.news.test##+js(set, adBlock, false)
        shop.*##.promo
        other.test#?#p:has-text(Ad)
        """).scripted)
        XCTAssertEqual(table.count, 4)
        let news = table.rules(forHost: "www.news.test")
        XCTAssertEqual(news.hide, [[.css("div"), .text("Sponsored")]])
        XCTAssertEqual(news.run.map(\.name), ["set-constant"])
        XCTAssertTrue(news.hides)
        let live = table.rules(forHost: "live.news.test")
        XCTAssertEqual(live.hide.count, 1)
        XCTAssertTrue(live.run.isEmpty, "not on the part of the site the filter leaves out")
        XCTAssertEqual(table.rules(forHost: "shop.co.uk").css, [".promo"], "an entity: the name under any ending")
        XCTAssertEqual(table.rules(forHost: "m.shop.com").css, [".promo"])
        XCTAssertTrue(table.rules(forHost: "shopping.com").isEmpty)
        XCTAssertTrue(table.rules(forHost: "notnews.test").isEmpty)
        XCTAssertTrue(table.rules(forHost: "plain.test").isEmpty, "most sites: nothing, and so no script")
        XCTAssertTrue(table.rules(forHost: nil).isEmpty)
        XCTAssertEqual(ScriptedTable.keys(for: "a.shop.co.uk").prefix(3), ["a.shop.co.uk", "a.shop.co.*", "a.shop.*"])
    }

    func testAnExceptionTakesAFilterBack() {
        let table = ScriptedTable(FilterConverter.convert("""
        a.test,b.test#?#div:has-text(Sponsored)
        b.test#@?#div:has-text(Sponsored)
        a.test##+js(set, x, true)
        #@#+js(set, x, true)
        """).scripted)
        XCTAssertEqual(table.rules(forHost: "a.test").hide.count, 1)
        XCTAssertTrue(table.rules(forHost: "b.test").isEmpty, "taken back on that site")
        XCTAssertTrue(table.rules(forHost: "a.test").run.isEmpty, "and everywhere, with no site named")
    }

    func testTheTableIsKeptOnDiskAndReadBack() throws {
        let table = ScriptedTable(FilterConverter.convert("""
        news.test#?#div:has-text(Sponsored):upward(2)
        news.test##body:style(opacity: 1 !important)
        news.test##+js(acs, document.createElement, admiral)
        shop.*##.promo
        """).scripted)
        let read = try JSONDecoder().decode(ScriptedTable.self, from: JSONEncoder().encode(table))
        XCTAssertEqual(read, table)
        XCTAssertEqual(read.rules(forHost: "news.test"), table.rules(forHost: "news.test"))
    }

    func testThePagesScriptsCarryTheRulesAsData() throws {
        var rules = PageRules()
        XCTAssertNil(Scripts.blocker(for: rules))
        XCTAssertNil(Scripts.scriptlets(for: rules))
        rules.css = [".promo"]
        rules.hide = [[.css("div"), .has([.css("> p"), .text("</script> \" \u{2028}")])]]
        rules.restyle = [([.css("body")], "opacity: 1 !important")]
        rules.run = [("set-constant", ["a.b", "false"])]
        let hiding = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rules.hidingJSON.utf8)) as? [String: Any])
        XCTAssertEqual(hiding["css"] as? [String], [".promo"])
        XCTAssertEqual((hiding["hide"] as? [[Any]])?.first?.count, 2)
        XCTAssertEqual(((hiding["style"] as? [[String: Any]])?.first?["css"]) as? String, "opacity: 1 !important")
        XCTAssertFalse(rules.hidingJSON.contains("\u{2028}"), "a line end JSON allows and a script doesn't")
        XCTAssertEqual(rules.scriptletsJSON, #"[["set-constant","a.b","false"]]"#)
        let blocker = try XCTUnwrap(Scripts.blocker(for: rules))
        XCTAssertTrue(blocker.hasSuffix("})(\(rules.hidingJSON));\n"))
        XCTAssertFalse(blocker.contains(Scripts.rulesMark))
        let scriptlets = try XCTUnwrap(Scripts.scriptlets(for: rules))
        XCTAssertTrue(scriptlets.hasSuffix("})(\(rules.scriptletsJSON));\n"))
        // A page's scripts are known by their rules: other rules, other scripts (Page.prepare).
        var other = rules
        other.run = []
        XCTAssertNotEqual(other.stamp, rules.stamp)
        XCTAssertNil(Scripts.scriptlets(for: other))
        XCTAssertNotNil(Scripts.blocker(for: other))
    }

    func testEveryScriptletTheListsMayNameIsInTheScript() {
        for name in Set(ScriptedFilter.scriptlets.values) {
            XCTAssertTrue(Scripts.scriptlets.contains("'\(name)'("), "\(name) has no code")
            XCTAssertFalse(name.contains("cookie"))
        }
        // The scripts are whole and have a place for their rules.
        XCTAssertTrue(Scripts.blocker.contains(Scripts.rulesMark))
        XCTAssertTrue(Scripts.scriptlets.contains(Scripts.rulesMark))
    }

    func testTheShippedListsFiltersForScripts() throws {
        let easylist = try XCTUnwrap(ContentBlocking.lists.first { $0.id == "easylist" })
        let scripted = FilterConverter.convert(try XCTUnwrap(ContentBlocking.bundled(easylist))).scripted
        XCTAssertGreaterThan(scripted.count, 400)
        XCTAssertTrue(scripted.allSatisfy { !$0.domains.isEmpty }, "each for the sites it names, none for every site")
        let table = ScriptedTable(scripted)
        XCTAssertTrue(table.rules(forHost: "example.com").isEmpty)
    }
}
