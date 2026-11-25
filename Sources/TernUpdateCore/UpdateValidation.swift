import Foundation
import Security

public enum InstallationError: LocalizedError {
    case invalidBundle, invalidSignature, invalidVersion, invalidLocation, timeout
    public var errorDescription: String? {
        switch self {
        case .invalidBundle: return "The update is not a production Tern application with the expected repository."
        case .invalidSignature: return "The update signature or signing team is invalid."
        case .invalidVersion: return "The staged update does not have the expected newer version."
        case .invalidLocation: return "The installation location is not writable or overlaps the staged application."
        case .timeout: return "Tern did not exit in time; the installed application was left in place."
        }
    }
}

public enum UpdateValidation {
    public static let identifier = "com.dominikbura.tern"
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
    public static func validVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil && value.split(separator: ".").allSatisfy { Int($0) != nil }
    }
    public static func productionBundle(_ url: URL) throws -> Bundle {
        guard url.lastPathComponent == "Tern.app", url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL,
              let bundle = Bundle(url: url), bundle.bundleIdentifier == identifier,
              bundle.object(forInfoDictionaryKey: "TernBuildChannel") as? String == "production",
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/Tern").path),
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/Helpers/TernUpdater").path) else { throw InstallationError.invalidBundle }
        return bundle
    }
    public static func validateCandidate(_ staged: URL, current: URL, expectedVersion: String) throws {
        let installed = try productionBundle(current)
        let candidate = try productionBundle(staged)
        guard validVersion(expectedVersion), candidate.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion,
              let oldVersion = installed.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              compare(expectedVersion, oldVersion) == .orderedDescending else { throw InstallationError.invalidVersion }
        guard let repository = installed.object(forInfoDictionaryKey: "TernUpdateRepository") as? String,
              !repository.isEmpty, candidate.object(forInfoDictionaryKey: "TernUpdateRepository") as? String == repository else { throw InstallationError.invalidBundle }
        try validateSignature(staged)
        if let team = signingTeam(current), signingTeam(staged) != team { throw InstallationError.invalidSignature }
    }
    public static func validateSignature(_ url: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { throw InstallationError.invalidSignature }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSRestrictSymlinks)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { throw InstallationError.invalidSignature }
    }
    private static func signingTeam(_ url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

public enum UpdateInstallation {
    /// The helper revalidates after the parent exits, immediately before replacement.
    public static func install(current: URL, staged: URL, expectedVersion: String, launch: (URL) throws -> Void) throws {
        let parent = current.deletingLastPathComponent()
        guard current.standardizedFileURL != staged.standardizedFileURL,
              !staged.standardizedFileURL.path.hasPrefix(current.standardizedFileURL.path + "/"),
              FileManager.default.isWritableFile(atPath: parent.path) else { throw InstallationError.invalidLocation }
        try UpdateValidation.validateCandidate(staged, current: current, expectedVersion: expectedVersion)
        let manager = FileManager.default
        let backup = parent.appendingPathComponent(".Tern-previous-\(UUID().uuidString).app")
        try manager.moveItem(at: current, to: backup)
        do {
            try manager.moveItem(at: staged, to: current)
            try launch(current)
        } catch {
            // Keep the backup if restoration itself fails; never remove the last good copy.
            if manager.fileExists(atPath: current.path) { try? manager.removeItem(at: current) }
            try manager.moveItem(at: backup, to: current)
            try? launch(current)
            throw error
        }
        try? manager.removeItem(at: backup)
    }
}
