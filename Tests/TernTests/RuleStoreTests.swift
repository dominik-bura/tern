import XCTest
@testable import Tern

final class RuleStoreTests: XCTestCase {
    func testRoundTripAndAtomicReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuleStore(fileURL: root.appendingPathComponent("rules.json"))
        XCTAssertEqual(try store.load(), RoutingConfiguration())
        let config = RoutingConfiguration(rules: [.init(name: "Work", matcher: .init(host: "example.com"), destination: .dia(.init(name: "work \" & \\")))])
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
        var next = config; next.rules[0].name = "Updated"
        try store.save(next)
        XCTAssertEqual(try store.load(), next)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["rules.json"])
    }
    func testFutureSchemaAndCorruptionRemainUntouched() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RuleStore(fileURL: url)
        for content in [#"{"schemaVersion":999,"rules":[],"fallback":{"ask":{}}}"#, "not JSON"] {
            let data = Data(content.utf8); try data.write(to: url)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
    func testInvalidImportRejected() throws {
        let rule = RoutingRule(name: "x", matcher: .init(host: "example.com"))
        XCTAssertThrowsError(try RuleStore.encode(RoutingConfiguration(rules: [rule, rule])))
        var config = RoutingConfiguration(); config.fallback = .browser("com.dominikbura.tern")
        XCTAssertThrowsError(try RuleStore.encode(config))
    }
}
