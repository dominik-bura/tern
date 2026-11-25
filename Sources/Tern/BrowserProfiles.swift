import AppKit

/// A browser profile. For Chromium browsers `directory` is the profile folder (e.g. "Profile 1");
/// for Firefox browsers it is the profile's path from profiles.ini and `name` is passed to `-P`.
struct ProfileReference: Codable, Equatable, Hashable, Sendable {
    var browserID: String
    var directory: String
    var name: String
}

/// Display and routing metadata for one browser profile, read from the browser's own files.
struct BrowserProfileInfo: Codable, Equatable, Hashable, Sendable {
    var directory: String
    var name: String
    /// sRGB color as 0xRRGGBB, when the browser stores one.
    var color: UInt32?
    /// The account picture the browser saved for this profile, if any.
    var pictureURL: URL?
}

/// A profile as shown in the interface, for any browser that supports profiles.
struct ProfileItem: Identifiable, Hashable {
    let destination: BrowserDestination
    let name: String
    let color: UInt32?
    let pictureURL: URL?
    /// Whether Tern can switch an existing window to this profile (Dia only).
    let canSwitch: Bool
    var id: BrowserDestination { destination }
}

/// Reads profile lists from browsers' own files. Discovery never launches or scripts a browser.
enum BrowserProfiles {
    enum Family: Equatable { case chromium, firefox }

    struct Support { let path: String; let family: Family }

    /// Profile data folders under ~/Library/Application Support, by bundle identifier.
    static let supported: [String: Support] = {
        var map: [String: Support] = [:]
        let chromium: [String: String] = [
            "com.google.Chrome": "Google/Chrome",
            "com.google.Chrome.beta": "Google/Chrome Beta",
            "com.google.Chrome.dev": "Google/Chrome Dev",
            "com.google.Chrome.canary": "Google/Chrome Canary",
            "com.microsoft.edgemac": "Microsoft Edge",
            "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
            "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
            "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
            "com.brave.Browser": "BraveSoftware/Brave-Browser",
            "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
            "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
            "com.vivaldi.Vivaldi": "Vivaldi",
            "com.operasoftware.Opera": "com.operasoftware.Opera",
            "com.operasoftware.OperaGX": "com.operasoftware.OperaGX",
            "org.chromium.Chromium": "Chromium",
            "org.chromium.Thorium": "Thorium",
            "ai.perplexity.comet": "Comet",
            "net.imput.helium": "net.imput.helium",
            BrowserRegistry.diaID: "Dia/User Data",
        ]
        let firefox: [String: String] = [
            "org.mozilla.firefox": "Firefox",
            "org.mozilla.firefoxdeveloperedition": "Firefox",
            "org.mozilla.nightly": "Firefox",
            "app.zen-browser.zen": "zen",
        ]
        for (id, path) in chromium { map[id] = Support(path: path, family: .chromium) }
        for (id, path) in firefox { map[id] = Support(path: path, family: .firefox) }
        return map
    }()

    static func family(of browserID: String) -> Family? { supported[browserID]?.family }

    /// Browsers Tern opens in a profile via launch arguments. Dia uses AppleScript instead.
    static func supportsLaunchArguments(_ browserID: String) -> Bool {
        browserID != BrowserRegistry.diaID && supported[browserID] != nil
    }

    static func dataDirectory(for browserID: String) -> URL? {
        guard let path = supported[browserID]?.path,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent(path, isDirectory: true)
    }

    /// The file that lists the profiles: "Local State" or "profiles.ini".
    static func listFileName(for browserID: String) -> String {
        family(of: browserID) == .firefox ? "profiles.ini" : "Local State"
    }

    enum Discovery: Equatable {
        case profiles([BrowserProfileInfo])
        /// The browser keeps its files private (Chrome, Edge, Firefox on recent macOS).
        /// Holds the profile folders Tern could detect without reading them, with placeholder names.
        case restricted(detected: [BrowserProfileInfo])
    }

    static func discover(for browserID: String) -> Discovery {
        guard let dataDirectory = dataDirectory(for: browserID) else { return .profiles([]) }
        let file = dataDirectory.appendingPathComponent(listFileName(for: browserID))
        do {
            return .profiles(try parse(file: file, browserID: browserID))
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .restricted(detected: family(of: browserID) == .chromium ? detectChromiumFolders(in: dataDirectory) : [])
        } catch {
            return .profiles([])
        }
    }

    static func parse(file: URL, browserID: String) throws -> [BrowserProfileInfo] {
        let data = try Data(contentsOf: file)
        let folder = file.deletingLastPathComponent()
        switch family(of: browserID) {
        case .firefox: return parse(profilesINI: String(decoding: data, as: UTF8.self))
        default: return parse(localState: data, userData: folder)
        }
    }

    /// Profile folders can be checked for existence even when their contents are private.
    /// Chromium numbers them "Default", "Profile 1", "Profile 2", …
    static func detectChromiumFolders(in userData: URL) -> [BrowserProfileInfo] {
        let candidates = ["Default"] + (1...40).map { "Profile \($0)" }
        return candidates.filter { exists(userData.appendingPathComponent($0)) }
            .map { BrowserProfileInfo(directory: $0, name: $0 == "Default" ? "Default Profile" : $0) }
    }

    private static func exists(_ url: URL) -> Bool {
        var info = stat()
        return stat(url.path, &info) == 0
    }

    /// True only when the profile folder is known to be missing. Private folders count as present.
    static func profileIsMissing(browserID: String, directory: String) -> Bool {
        guard let dataDirectory = dataDirectory(for: browserID) else { return true }
        if directory.hasPrefix("/") { return false }
        var info = stat()
        return stat(dataDirectory.appendingPathComponent(directory).path, &info) != 0 && errno == ENOENT
    }

    /// Parses `profile.info_cache` in the browser's display order.
    static func parse(localState: Data, userData: URL) -> [BrowserProfileInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: localState) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: [String: Any]] else { return [] }
        let order = (profile["profiles_order"] as? [String] ?? []).filter { cache[$0] != nil }
        let directories = order + cache.keys.filter { !order.contains($0) }.sorted()
        return directories.compactMap { directory in
            guard isValidDirectory(directory), let entry = cache[directory],
                  let name = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            var picture: URL?
            if let file = entry["gaia_picture_file_name"] as? String, !file.isEmpty, !file.contains("/") {
                let url = userData.appendingPathComponent(directory).appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: url.path) { picture = url }
            }
            return BrowserProfileInfo(directory: directory, name: name, color: color(from: entry), pictureURL: picture)
        }
    }

    /// Parses Firefox's profiles.ini: `[ProfileN]` sections with `Name` and `Path`, in N order.
    static func parse(profilesINI text: String) -> [BrowserProfileInfo] {
        var sections: [(index: Int, values: [String: String])] = []
        var currentIndex: Int?
        var values: [String: String] = [:]
        func flush() { if let currentIndex { sections.append((currentIndex, values)) }; values = [:] }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                flush()
                let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                currentIndex = title.hasPrefix("Profile") ? Int(title.dropFirst("Profile".count)) : nil
            } else if let equals = line.firstIndex(of: "="), currentIndex != nil {
                values[String(line[..<equals])] = String(line[line.index(after: equals)...])
            }
        }
        flush()
        return sections.sorted { $0.index < $1.index }.compactMap { section in
            guard let name = section.values["Name"]?.trimmingCharacters(in: .whitespaces), isValidFirefoxName(name),
                  let path = section.values["Path"], !path.isEmpty else { return nil }
            return BrowserProfileInfo(directory: path, name: name)
        }
    }

    /// Chromium stores colors as signed ARGB integers. Opaque black means "not set".
    private static func color(from entry: [String: Any]) -> UInt32? {
        for key in ["profile_color_seed", "profile_highlight_color"] {
            guard let value = (entry[key] as? NSNumber)?.int64Value else { continue }
            let argb = UInt32(truncatingIfNeeded: value)
            if argb != 0xFF00_0000, argb >> 24 != 0 { return argb & 0x00FF_FFFF }
        }
        return nil
    }

    /// Profile folders are plain names such as "Default" or "Profile 3", never paths or options.
    static func isValidDirectory(_ directory: String) -> Bool {
        !directory.isEmpty && !directory.hasPrefix("-") && !directory.hasPrefix(".") && !directory.contains("/")
    }

    static func isValidFirefoxName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("-") && !name.contains("\n")
    }

    static func isValid(_ profile: ProfileReference) -> Bool {
        guard supportsLaunchArguments(profile.browserID), !profile.name.isEmpty else { return false }
        switch family(of: profile.browserID) {
        case .firefox: return isValidFirefoxName(profile.name)
        default: return isValidDirectory(profile.directory)
        }
    }

    /// Arguments that make a running or newly started browser open the URL in the profile.
    static func launchArguments(for profile: ProfileReference, url: URL) -> [String] {
        switch family(of: profile.browserID) {
        case .firefox: return ["-P", profile.name, "-new-tab", url.absoluteString]
        default: return ["--profile-directory=\(profile.directory)", url.absoluteString]
        }
    }

    // MARK: Remembered lists for private browsers

    private static func cacheKey(_ browserID: String) -> String { "profileList." + browserID }

    /// Profiles read once from a file the user chose, for browsers that keep their files private.
    static func cachedProfiles(for browserID: String) -> [BrowserProfileInfo]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(browserID)) else { return nil }
        return try? JSONDecoder().decode([BrowserProfileInfo].self, from: data)
    }

    static func cache(_ profiles: [BrowserProfileInfo], for browserID: String) {
        // Pictures inside private folders can't be shown later, so only names and colors are kept.
        let stored = profiles.map { BrowserProfileInfo(directory: $0.directory, name: $0.name, color: $0.color) }
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: cacheKey(browserID)) }
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
