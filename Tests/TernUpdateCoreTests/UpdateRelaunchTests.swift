import XCTest
@testable import TernUpdateCore

final class UpdateRelaunchTests: XCTestCase {
    func testHelperOpensInBackgroundWithStartupIntentAsSeparateArguments() {
        let app = URL(fileURLWithPath: "/Applications/Test Folder/Tern.app")
        XCTAssertEqual(UpdateRelaunch.openArguments(for: app), ["-g", app.path, "--args", "--background-update-relaunch"])
        XCTAssertTrue(UpdateRelaunch.isRequested(arguments: ["Tern", UpdateRelaunch.argument]))
        XCTAssertFalse(UpdateRelaunch.isRequested(arguments: ["Tern"]))
        XCTAssertFalse(UpdateRelaunch.isRequested(arguments: ["Tern", "https://example.com/--background-update-relaunch"]))
    }
}
