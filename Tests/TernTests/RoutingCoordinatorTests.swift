import XCTest
@testable import Tern

@MainActor private final class FakeOpener: DestinationOpening {
    var requests: [IncomingURLRequest] = []
    var destinations: [BrowserDestination] = []
    var fails = false
    func open(_ request: IncomingURLRequest, in destination: BrowserDestination) async throws {
        requests.append(request); destinations.append(destination)
        await Task.yield()
        if fails { throw TernError.message("Permission denied") }
    }
}

@MainActor final class RoutingCoordinatorTests: XCTestCase {
    private func settle() async { for _ in 0..<50 { await Task.yield() } }
    func testFIFOEqualClicksAndSnapshot() async {
        let opener = FakeOpener(); let router = RoutingCoordinator(opener: opener)
        let url = URL(string: "https://example.com")!
        router.enqueue([url, url], configuration: RoutingConfiguration())
        XCTAssertEqual(router.current?.request.url, url)
        XCTAssertEqual(router.queuedCount, 1)
        let browser = BrowserDestination.browser("com.apple.Safari")
        router.choose(browser); await settle()
        XCTAssertEqual(opener.requests.count, 1)
        XCTAssertNotNil(router.current)
        router.choose(browser); await settle()
        XCTAssertEqual(opener.requests.count, 2)
        XCTAssertNotEqual(opener.requests[0].id, opener.requests[1].id)
        XCTAssertNil(router.current)
    }
    func testFailureStopsQueueAndRetryKeepsRequestID() async {
        let opener = FakeOpener(); opener.fails = true
        let router = RoutingCoordinator(opener: opener)
        let config = RoutingConfiguration(fallback: .dia(.init(name: "Promptic")))
        router.enqueue([URL(string: "https://example.com/a")!, URL(string: "https://example.com/b")!], configuration: config)
        await settle()
        XCTAssertEqual(router.queuedCount, 1)
        XCTAssertNotNil(router.current?.error)
        let id = opener.requests.first?.id
        opener.fails = false; router.retry(); await settle()
        XCTAssertEqual(opener.requests[1].id, id)
        XCTAssertEqual(opener.requests.count, 3)
        XCTAssertNil(router.current)
    }
    func testExplicitRedirectionUsesANewDeliveryID() async {
        let opener = FakeOpener(); opener.fails = true
        let router = RoutingCoordinator(opener: opener)
        router.enqueue([URL(string: "https://example.com")!], configuration: RoutingConfiguration(fallback: .dia(.init(name: "Promptic"))))
        await settle()
        let firstID = opener.requests.first?.id
        opener.fails = false
        router.choose(.dia(.init(name: "statworx"))); await settle()
        XCTAssertNotEqual(opener.requests.last?.id, firstID)
        XCTAssertEqual(opener.destinations.last, .dia(.init(name: "statworx")))
    }
    func testCancelAdvancesAndUnsupportedSchemeNeverDispatches() async {
        let opener = FakeOpener(); let router = RoutingCoordinator(opener: opener)
        router.enqueue([URL(string: "file:///tmp/x")!, URL(string: "https://example.com")!], configuration: RoutingConfiguration())
        router.cancel(); await settle()
        XCTAssertNil(router.current); XCTAssertTrue(opener.requests.isEmpty)
    }
}
