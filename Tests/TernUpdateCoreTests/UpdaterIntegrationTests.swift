import XCTest
@testable import TernUpdateCore

/// Opt in with TERN_UPDATE_TEST_APP pointing at a bundled production build.
/// Only disposable copies are changed, and no app is launched.
final class UpdaterIntegrationTests: XCTestCase {
    private func fixtures() throws -> (URL, URL, URL) {
        guard let path = ProcessInfo.processInfo.environment["TERN_UPDATE_TEST_APP"] else { throw XCTSkip("Requires an opt-in production bundle") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TernUpdaterTests-\(UUID().uuidString)")
        let current = root.appendingPathComponent("installed/Tern.app")
        let staged = root.appendingPathComponent("staged/Tern.app")
        for url in [current, staged] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
        }
        let plist = staged.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plist)
        var value = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        value["CFBundleShortVersionString"] = "99.0.0"
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: plist)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); process.arguments = ["--force", "--sign", "-", staged.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        return (root, current, staged)
    }
    func testReplacementAndRevalidation() throws {
        let (root, current, staged) = try fixtures()
        defer { try? FileManager.default.removeItem(at: root) }
        var launched = false
        try UpdateInstallation.install(current: current, staged: staged, expectedVersion: "99.0.0") { url in
            launched = true
            XCTAssertEqual(url, current)
            let plistData = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            let info = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
            XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "99.0.0")
        }
        XCTAssertTrue(launched)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        try UpdateValidation.validateSignature(current)
    }
    func testRollbackRetainsInstalledVersionWhenRelaunchFails() throws {
        let (root, current, staged) = try fixtures()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: current.appendingPathComponent("Contents/Info.plist"))
        var attempts = 0
        XCTAssertThrowsError(try UpdateInstallation.install(current: current, staged: staged, expectedVersion: "99.0.0") { _ in
            attempts += 1
            throw InstallationError.invalidBundle
        })
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("Contents/Info.plist")), original)
        try UpdateValidation.validateSignature(current)
    }
    func testTamperedCandidateNeverReplacesCurrentApp() throws {
        let (root, current, staged) = try fixtures()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("tampered".utf8).write(to: staged.appendingPathComponent("Contents/Resources/TernMark.svg"))
        XCTAssertThrowsError(try UpdateInstallation.install(current: current, staged: staged, expectedVersion: "99.0.0", launch: { _ in XCTFail("Tampered app must not launch") }))
        try UpdateValidation.validateSignature(current)
    }
}
