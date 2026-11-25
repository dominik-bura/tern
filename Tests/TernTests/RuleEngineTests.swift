import XCTest
@testable import Tern

final class RuleEngineTests: XCTestCase {
    func testHostBoundaryCasePortsAndSubdomains() throws {
        let matcher = URLMatcher(host: "example.com")
        for value in ["https://EXAMPLE.com:443/a", "http://one.two.example.com/a"] { XCTAssertTrue(matcher.matches(try XCTUnwrap(URL(string: value)))) }
        for value in ["https://badexample.com", "https://example.com.evil.test", "file://example.com/a"] { XCTAssertFalse(matcher.matches(try XCTUnwrap(URL(string: value)))) }
        XCTAssertFalse(URLMatcher(host: "example.com", includeSubdomains: false).matches(URL(string: "https://a.example.com")!))
    }
    func testPathsRespectSegmentsAndEncodingButIgnoreCase() {
        let matcher = URLMatcher(host: "example.com", pathPrefix: "/Team/")
        for path in ["/Team", "/Team/", "/team/docs?token=secret#fragment", "/TEAM"] { XCTAssertTrue(matcher.matches(URL(string: "https://example.com" + path)!)) }
        for path in ["/Teammate", "/Team%2Fprivate", "/%54eam"] { XCTAssertFalse(matcher.matches(URL(string: "https://example.com" + path)!)) }
    }
    func testFirstEnabledMatchWinsAndURLIsPreserved() {
        let first = RoutingRule(name: "First", matcher: URLMatcher(host: "example.com"), destination: .dia(.init(name: "Promptic")))
        var second = first; second.id = UUID(); second.name = "Second"
        var config = RoutingConfiguration(rules: [first, second])
        let url = URL(string: "https://example.com/a?token=a%2Bb#Section")!
        XCTAssertEqual(RuleEngine.decide(url, configuration: config).ruleName, "First")
        config.rules[0].enabled = false
        XCTAssertEqual(RuleEngine.decide(url, configuration: config).ruleName, "Second")
        XCTAssertEqual(IncomingURLRequest(url: url).url.absoluteString, "https://example.com/a?token=a%2Bb#Section")
        XCTAssertEqual(RuleEngine.decide(URL(string: "https://other.com")!, configuration: config).destination, .ask)
    }
    func testInvalidConditionsAndSelfDestinationsAreRejected() {
        for host in ["", ".com", "https://example.com", "a..com", "example.com/path", "-bad.com", "x.com:443"] { XCTAssertThrowsError(try URLMatcher(host: host).validate()) }
        XCTAssertThrowsError(try URLMatcher(host: "example.com", pathPrefix: "team").validate())
        XCTAssertThrowsError(try BrowserDestination.browser("com.dominikbura.tern.dev").validate())
    }
}

final class DomainInputTests: XCTestCase {
    func testPastedLinksBecomeHostAndPath() {
        let full = URLMatcher.parseDomainInput("https://github.com/statworx/")
        XCTAssertEqual(full?.host, "github.com"); XCTAssertEqual(full?.path, "/statworx"); XCTAssertEqual(full?.includeSubdomains, false)
        let bare = URLMatcher.parseDomainInput("https://GitHub.com")
        XCTAssertEqual(bare?.host, "github.com"); XCTAssertNil(bare?.path)
        let noScheme = URLMatcher.parseDomainInput("example.com/team/docs?x=1#y")
        XCTAssertEqual(noScheme?.host, "example.com"); XCTAssertEqual(noScheme?.path, "/team/docs")
        let wildcard = URLMatcher.parseDomainInput("*.notion.so")
        XCTAssertEqual(wildcard?.host, "notion.so"); XCTAssertEqual(wildcard?.includeSubdomains, true)
        XCTAssertEqual(URLMatcher.parseDomainInput("https://example.com:8443/a")?.host, "example.com")
    }

    func testPlainHostnamesAreLeftAlone() {
        XCTAssertNil(URLMatcher.parseDomainInput("example.com"))
        XCTAssertNil(URLMatcher.parseDomainInput("github"))
    }

    func testPastedLinkInPathFieldKeepsOnlyThePath() {
        XCTAssertEqual(URLMatcher.parsePathInput("https://github.com/statworx/repo/"), "/statworx/repo")
        XCTAssertEqual(URLMatcher.parsePathInput("/team"), "/team")
    }
}

final class MatcherKindTests: XCTestCase {
    private func url(_ s: String) -> URL { URL(string: s)! }

    func testWildcardPatterns() {
        let wiki = URLMatcher(kind: .wildcard, pattern: "*.atlassian.net/wiki/*")
        XCTAssertTrue(wiki.matches(url("https://statworx.atlassian.net/wiki/spaces/X")))
        XCTAssertFalse(wiki.matches(url("https://statworx.atlassian.net/jira/x")))
        let host = URLMatcher(kind: .wildcard, pattern: "*.notion.so")
        XCTAssertTrue(host.matches(url("https://www.notion.so/page")))
        XCTAssertTrue(host.matches(url("https://notion.so")))
        XCTAssertFalse(host.matches(url("https://notion.so.evil.com")))
        let docs = URLMatcher(kind: .wildcard, pattern: "https://Example.com/docs")
        XCTAssertTrue(docs.matches(url("https://example.com/docs/intro")))
        XCTAssertFalse(docs.matches(url("https://example.com/docsearch")))
        XCTAssertThrowsError(try URLMatcher(kind: .wildcard, pattern: "").validate())
    }

    func testRegex() throws {
        let matcher = URLMatcher(kind: .regex, pattern: "^https://github\\.com/statworx/")
        XCTAssertTrue(matcher.matches(url("https://GitHub.com/statworx/repo")))
        XCTAssertFalse(matcher.matches(url("https://github.com/other")))
        XCTAssertThrowsError(try URLMatcher(kind: .regex, pattern: "(").validate())
    }

    func testSourceApps() throws {
        let slack = URLMatcher(sourceApps: ["com.tinyspeck.slackmacgap"])
        XCTAssertNoThrow(try slack.validate())
        XCTAssertTrue(slack.matches(url("https://any.com"), sourceApp: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(slack.matches(url("https://any.com"), sourceApp: "com.apple.mail"))
        XCTAssertFalse(slack.matches(url("https://any.com")))
        let scoped = URLMatcher(host: "github.com", sourceApps: ["com.apple.mail"])
        XCTAssertTrue(scoped.matches(url("https://github.com/x"), sourceApp: "com.apple.mail"))
        XCTAssertFalse(scoped.matches(url("https://gitlab.com/x"), sourceApp: "com.apple.mail"))
        XCTAssertThrowsError(try URLMatcher().validate())
    }

    func testOldConfigurationsStillDecode() throws {
        let json = """
        {"schemaVersion":1,"fallback":{"ask":{}},"rules":[{"id":"\(UUID().uuidString)","name":"x","enabled":true,
        "matcher":{"host":"example.com","includeSubdomains":true,"pathPrefix":""},"destination":{"ask":{}}}]}
        """
        let config = try RuleStore.decode(Data(json.utf8))
        XCTAssertEqual(config.rules.first?.matcher.kind, .domain)
        XCTAssertNil(config.rules.first?.group)
        XCTAssertTrue(config.unwrapLinks)
        XCTAssertTrue(config.removeTracking)
        XCTAssertFalse(config.resolveShortLinks)
    }

    func testGroupsStayTogetherInCheckOrder() {
        let a = RoutingRule(name: "a", matcher: .init(host: "a.com"), group: "Work")
        let b = RoutingRule(name: "b", matcher: .init(host: "b.com"))
        let c = RoutingRule(name: "c", matcher: .init(host: "c.com"), group: "Home")
        let d = RoutingRule(name: "d", matcher: .init(host: "d.com"), group: "Work")
        var config = RoutingConfiguration(rules: [a, b, c, d])
        config.normalizeGroups()
        XCTAssertEqual(config.rules.map(\.name), ["b", "a", "d", "c"])
        XCTAssertEqual(config.groups, ["Work", "Home"])
    }
}

final class LinkCleanerTests: XCTestCase {
    private func clean(_ s: String) -> String {
        LinkCleaner.cleanLocally(URL(string: s)!, unwrap: true, removeTracking: true).match.absoluteString
    }

    func testSecurityScannersStillOpenWrapped() {
        let safe = URL(string: "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Fa&data=x")!
        let result = LinkCleaner.cleanLocally(safe, unwrap: true, removeTracking: true)
        XCTAssertEqual(result.match.absoluteString, "https://example.com/a")
        XCTAssertEqual(result.open, safe)
        let google = URL(string: "https://www.google.com/url?q=https://example.com/b&sa=D")!
        let plain = LinkCleaner.cleanLocally(google, unwrap: true, removeTracking: true)
        XCTAssertEqual(plain.open, plain.match)
    }

    func testShortLinksStayLocalByDefault() async {
        XCTAssertFalse(RoutingConfiguration().resolveShortLinks)
        let short = URL(string: "https://t.co/abc")!
        let result = await LinkCleaner.clean(short, unwrap: true, resolveShortLinks: false, removeTracking: true)
        XCTAssertEqual(result.open, short)
    }

    func testUnwrapsKnownRedirects() {
        XCTAssertEqual(clean("https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Fstatworx&data=x&reserved=0"), "https://github.com/statworx")
        XCTAssertEqual(clean("https://www.google.com/url?q=https://example.com/a&sa=D"), "https://example.com/a")
        XCTAssertEqual(clean("https://slack-redir.net/link?url=https%3A%2F%2Fexample.com"), "https://example.com")
        XCTAssertEqual(clean("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fx&h=abc"), "https://example.com/x")
        XCTAssertEqual(clean("https://www.linkedin.com/safety/go?url=https%3A%2F%2Fexample.com"), "https://example.com")
        XCTAssertEqual(clean("https://urldefense.proofpoint.com/v2/url?u=https-3A__example.com_a&d=x"), "https://example.com/a")
    }

    func testIgnoresNonHTTPAndUnrelatedLinks() {
        XCTAssertEqual(clean("https://www.google.com/url?q=javascript:alert(1)"), "https://www.google.com/url?q=javascript:alert(1)")
        XCTAssertEqual(clean("https://www.google.com/search?q=https://example.com"), "https://www.google.com/search?q=https://example.com")
        XCTAssertEqual(clean("https://notgoogle.example.com/url?q=https://x.com"), "https://notgoogle.example.com/url?q=https://x.com")
    }

    func testRemovesTrackingOnly() {
        XCTAssertEqual(clean("https://example.com/a?utm_source=x&id=5&fbclid=y#top"), "https://example.com/a?id=5#top")
        XCTAssertEqual(clean("https://example.com/a?utm_medium=x"), "https://example.com/a")
        XCTAssertEqual(clean("https://example.com/a?b=%2B1"), "https://example.com/a?b=%2B1")
    }

    func testShortLinkHosts() {
        XCTAssertTrue(LinkCleaner.isShortLink(URL(string: "https://t.co/abc")!))
        XCTAssertTrue(LinkCleaner.isShortLink(URL(string: "https://www.bit.ly/abc")!))
        XCTAssertFalse(LinkCleaner.isShortLink(URL(string: "https://youtu.be/abc")!))
    }
}
