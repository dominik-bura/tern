import XCTest
@testable import TernUpdateCore

final class UpdateValidationTests: XCTestCase {
    func testVersions() {
        XCTAssertEqual(UpdateValidation.compare("0.1.10", "0.1.9"), .orderedDescending)
        XCTAssertEqual(UpdateValidation.compare("1.0.0", "1.0.0"), .orderedSame)
        XCTAssertFalse(UpdateValidation.validVersion("v1.2.3"))
        XCTAssertFalse(UpdateValidation.validVersion("1.2.beta"))
        XCTAssertTrue(UpdateValidation.validVersion("0.1.1"))
    }
    func testWrongIdentityOrSymlinkRejectedBeforeInstallation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Tern.app")
        XCTAssertThrowsError(try UpdateValidation.productionBundle(url))
        XCTAssertThrowsError(try UpdateInstallation.install(current: url, staged: url, expectedVersion: "0.1.1", launch: { _ in XCTFail("Must not launch") }))
    }
}
