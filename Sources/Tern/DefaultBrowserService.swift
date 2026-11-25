import AppKit

@MainActor final class DefaultBrowserService {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var handlers: [String: String] {
        var values: [String: String] = [:]
        for scheme in ["http", "https"] {
            if let url = URL(string: "\(scheme)://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: url), let id = Bundle(url: app)?.bundleIdentifier { values[scheme] = id }
        }
        return values
    }
    var isDefault: Bool { Self.isDefault(handlers, identifier: Bundle.main.bundleIdentifier ?? "") }
    static func isDefault(_ handlers: [String: String], identifier: String) -> Bool {
        !identifier.isEmpty && ["http", "https"].allSatisfy { handlers[$0] == identifier }
    }
    /// The browser links would open in without Tern: the current default, or the one Tern replaced.
    var systemBrowserID: String? {
        if let id = handlers["https"], !BrowserRegistry.isTern(id) { return id }
        return (defaults.dictionary(forKey: "previousBrowserHandlers") as? [String: String])?["https"]
            .flatMap { BrowserRegistry.isTern($0) ? nil : $0 }
    }
    var canRestore: Bool { defaults.dictionary(forKey: "previousBrowserHandlers") != nil }
    func makeDefault() async throws {
        let current = handlers
        // Preserve the first pre-Tern handlers even if only one scheme was changed.
        if defaults.dictionary(forKey: "previousBrowserHandlers") == nil {
            guard current.count == 2, current.values.allSatisfy({ !BrowserRegistry.isTern($0) }) else {
                throw TernError.message("Set another browser as your default first so Tern can save a complete restore destination.")
            }
            defaults.set(current, forKey: "previousBrowserHandlers")
        }
        for scheme in ["http", "https"] { try await set(Bundle.main.bundleURL, scheme: scheme) }
        guard isDefault else { throw TernError.message("macOS did not assign both HTTP and HTTPS to Tern. Check Default Browser settings and retry.") }
    }
    func restore() async throws {
        guard let previous = defaults.dictionary(forKey: "previousBrowserHandlers") as? [String: String] else { return }
        for scheme in ["http", "https"] {
            guard let id = previous[scheme], !BrowserRegistry.isTern(id), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                throw TernError.message("Your previous browser is unavailable. Choose a default browser in System Settings.")
            }
            try await set(app, scheme: scheme)
        }
        guard handlers == previous else { throw TernError.message("The previous defaults were not fully restored. Check macOS settings.") }
        defaults.removeObject(forKey: "previousBrowserHandlers")
    }
    private func set(_ app: URL, scheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
