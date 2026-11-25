import XCTest
@testable import Tern

private actor FakeEvents: AppleEventClient {
    var calls: [[String]] = []
    func perform(_ arguments: [String]) async throws -> [String] { calls.append(arguments); return ["Promptic", "statworx"] }
    func recorded() -> [[String]] { calls }
}

@MainActor final class DiaServiceTests: XCTestCase {
    func testURLsAndNamesAreDataAndRetryIdentityIsStable() async throws {
        let client = FakeEvents(); let dia = DiaService(client: client)
        let profile = DiaProfileReference(name: "Work \" & do shell script")
        let request = IncomingURLRequest(url: URL(string: "https://example.com/?q=%22%5C#x")!)
        try await dia.open(request, profile: profile)
        try await dia.open(request, profile: profile)
        let calls = await client.recorded()
        XCTAssertEqual(calls[0], ["open", profile.name, request.id.uuidString, request.url.absoluteString])
        XCTAssertEqual(calls[0], calls[1])
    }
    func testDiscoveryAndSwitch() async throws {
        let client = FakeEvents(); let dia = DiaService(client: client)
        let profiles = try await dia.profiles()
        XCTAssertEqual(profiles.map(\.name), ["Promptic", "statworx"])
        try await dia.switchProfile(profiles[1])
        let calls = await client.recorded(); XCTAssertEqual(calls.last, ["switch", "statworx"])
    }
    func testDefaultRequiresBothSchemes() {
        let id = "com.dominikbura.tern.dev"
        XCTAssertFalse(DefaultBrowserService.isDefault(["http": id, "https": "com.apple.Safari"], identifier: id))
        XCTAssertTrue(DefaultBrowserService.isDefault(["http": id, "https": id], identifier: id))
    }
}
