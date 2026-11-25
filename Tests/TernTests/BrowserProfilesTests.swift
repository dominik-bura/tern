import XCTest
@testable import Tern

final class BrowserProfilesTests: XCTestCase {
    func testParsesNamesOrderColorsAndPictures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
        try Data([0]).write(to: root.appendingPathComponent("Profile 1/Picture.png"))
        let json = """
        {"profile": {"profiles_order": ["Profile 1", "Default"], "info_cache": {
          "Default": {"name": "Personal", "profile_color_seed": -16741687},
          "Profile 1": {"name": "Work", "profile_color_seed": -16777216, "profile_highlight_color": -2917493, "gaia_picture_file_name": "Picture.png"},
          "Profile 2": {"name": "Unordered"},
          "../escape": {"name": "Bad"},
          "Profile 3": {"name": "  "}
        }}}
        """
        let profiles = BrowserProfiles.parse(localState: Data(json.utf8), userData: root)
        XCTAssertEqual(profiles.map(\.directory), ["Profile 1", "Default", "Profile 2"])
        XCTAssertEqual(profiles.map(\.name), ["Work", "Personal", "Unordered"])
        XCTAssertEqual(profiles[0].color, 0xD37B8B, "Opaque black seed falls back to the highlight color")
        XCTAssertEqual(profiles[1].color, 0x008AC9)
        XCTAssertNil(profiles[2].color)
        XCTAssertEqual(profiles[0].pictureURL?.lastPathComponent, "Picture.png")
        XCTAssertNil(profiles[1].pictureURL)
    }

    func testCorruptLocalStateYieldsNoProfiles() {
        XCTAssertEqual(BrowserProfiles.parse(localState: Data("not json".utf8), userData: URL(fileURLWithPath: "/tmp")), [])
    }

    func testDirectoryIsNeverAPathOrOption() {
        XCTAssertTrue(BrowserProfiles.isValidDirectory("Profile 1"))
        for bad in ["", "-flag", "--profile-directory=x", "../x", "a/b", ".hidden"] {
            XCTAssertFalse(BrowserProfiles.isValidDirectory(bad), bad)
        }
    }

    func testLaunchArgumentsKeepTheURLUnchanged() {
        let url = URL(string: "https://example.com/a?b=%22c%22#d")!
        XCTAssertEqual(BrowserProfiles.launchArguments(for: .init(browserID: "com.google.Chrome", directory: "Profile 2", name: "Work"), url: url),
                       ["--profile-directory=Profile 2", "https://example.com/a?b=%22c%22#d"])
        XCTAssertEqual(BrowserProfiles.launchArguments(for: .init(browserID: "org.mozilla.firefox", directory: "Profiles/x.work", name: "Work"), url: url),
                       ["-P", "Work", "-new-tab", "https://example.com/a?b=%22c%22#d"])
    }

    func testProfileDestinationRoundTripsAndValidates() throws {
        let destination = BrowserDestination.profile(.init(browserID: "com.google.Chrome", directory: "Profile 1", name: "Work"))
        let config = RoutingConfiguration(rules: [.init(name: "Work", matcher: .init(host: "example.com"), destination: destination)])
        XCTAssertEqual(try RuleStore.decode(RuleStore.encode(config)), config)
        XCTAssertThrowsError(try BrowserDestination.profile(.init(browserID: "com.google.Chrome", directory: "../x", name: "x")).validate())
        XCTAssertThrowsError(try BrowserDestination.profile(.init(browserID: "com.apple.Safari", directory: "Default", name: "x")).validate())
        XCTAssertThrowsError(try BrowserDestination.profile(.init(browserID: BrowserRegistry.diaID, directory: "Default", name: "x")).validate())
    }

    func testFirefoxProfilesINI() {
        let ini = """
        [Install6ED35B3CA1B5D3AF]
        Default=Profiles/b.default-release

        [Profile1]
        Name=Work
        IsRelative=1
        Path=Profiles/a.work

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/b.default-release
        Default=1

        [Profile2]
        Name=-bad
        Path=Profiles/c

        [General]
        Version=2
        """
        XCTAssertEqual(BrowserProfiles.parse(profilesINI: ini).map(\.name), ["default-release", "Work"])
        XCTAssertEqual(BrowserProfiles.parse(profilesINI: ini).last?.directory, "Profiles/a.work")
        XCTAssertNoThrow(try BrowserDestination.profile(.init(browserID: "app.zen-browser.zen", directory: "Profiles/a.work", name: "Work")).validate())
    }
}
