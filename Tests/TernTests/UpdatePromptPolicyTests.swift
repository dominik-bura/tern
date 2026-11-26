import XCTest
@testable import Tern

final class UpdatePromptPolicyTests: XCTestCase {
    func testRemindersSkipsAndNewVersionsAreIndependentAndCodable() throws {
        var policy = UpdatePromptPolicy()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(policy.shouldPresent(version: "1.0.0", now: now))
        policy.presented("1.0.0")
        XCTAssertFalse(policy.shouldPresent(version: "1.0.0", now: now))
        policy.remindTomorrow("1.0.0", now: now)
        XCTAssertFalse(policy.allowsAutomaticUpdate(version: "1.0.0", now: now.addingTimeInterval(60)))
        XCTAssertTrue(policy.shouldPresent(version: "1.0.0", now: try XCTUnwrap(policy.remindAfter)))
        policy.skip("1.0.0")
        XCTAssertFalse(policy.shouldPresent(version: "1.0.0", now: now.addingTimeInterval(172_800)))
        XCTAssertTrue(policy.shouldPresent(version: "1.1.0", now: now))
        XCTAssertEqual(try JSONDecoder().decode(UpdatePromptPolicy.self, from: JSONEncoder().encode(policy)), policy)
    }
}
