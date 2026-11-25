import XCTest
@testable import Tern

final class UpdateServiceTests: XCTestCase {
    func testOnlyProductionIdentityCanUpdate() {
        XCTAssertTrue(UpdateService.isAllowedBundleTransition(from: "com.dominikbura.tern", to: "com.dominikbura.tern"))
        for id in ["com.dominikbura.tern.dev", "com.dominikbura.sift", "com.dominikhait.devsweep"] {
            XCTAssertFalse(UpdateService.isAllowedBundleTransition(from: id, to: "com.dominikbura.tern"))
        }
        XCTAssertFalse(UpdateService.isSupportedCurrentApplicationName("Tern Dev.app"))
    }
    func testArchiveTraversalRejected() {
        XCTAssertTrue(UpdateService.safeArchiveEntries("Tern.app/\nTern.app/Contents/Info.plist\n"))
        for listing in ["../escape\n", "Tern.app/../escape\n", "/Tern.app/Contents/x", "Tern.app/Contents/x\nOther.app/file", "Tern.app/Contents/..\\escape"] { XCTAssertFalse(UpdateService.safeArchiveEntries(listing)) }
    }
    func testChecksumAndPackagedArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try UpdateService.sha256(of: url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertThrowsError(try UpdateService.validateArchive(url))
        if let archive = ProcessInfo.processInfo.environment["TERN_UPDATE_TEST_ARCHIVE"] {
            try UpdateService.validateArchive(URL(fileURLWithPath: archive))
        }
    }
    func testDownloadOrigins() {
        XCTAssertTrue(UpdateService.isAllowedDownloadURL(URL(string: "https://github.com/dominik-bura/tern/releases/download/v1/Tern.zip")!))
        XCTAssertFalse(UpdateService.isAllowedDownloadURL(URL(string: "https://evil.test/releases/download/v1/Tern.zip")!))
        XCTAssertFalse(UpdateService.isAllowedDownloadURL(URL(string: "http://github.com/a/releases/download/b")!))
    }
}
