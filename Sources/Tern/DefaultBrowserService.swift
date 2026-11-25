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
    private static let previousKey = "previousBrowserHandlers"

    /// Handlers the other Tern build (development or production) saved before it became the default.
    /// Lets one build take over from the other without losing your usual browser.
    private var siblingPrevious: [String: String]? {
        for id in ["com.dominikbura.tern", "com.dominikbura.tern.dev"] where id != Bundle.main.bundleIdentifier {
            if let saved = UserDefaults(suiteName: id)?.dictionary(forKey: Self.previousKey) as? [String: String],
               Self.isComplete(saved) { return saved }
        }
        return nil
    }

    private static func isComplete(_ handlers: [String: String]) -> Bool {
        handlers.count == 2 && handlers.values.allSatisfy { !BrowserRegistry.isTern($0) }
    }

    /// The browser links would open in without Tern: the current default, or the one a Tern build replaced.
    var systemBrowserID: String? {
        if let id = handlers["https"], !BrowserRegistry.isTern(id) { return id }
        if let saved = defaults.dictionary(forKey: Self.previousKey) as? [String: String], let id = saved["https"], !BrowserRegistry.isTern(id) { return id }
        return siblingPrevious?["https"]
    }
    var canRestore: Bool { defaults.dictionary(forKey: Self.previousKey) != nil }
    func makeDefault() async throws {
        let current = handlers
        // Preserve the first pre-Tern handlers even if only one scheme was changed. When the other
        // Tern build is the default, take over the browser it saved. Without either, Tern still
        // becomes the default; only Restore Previous is unavailable.
        if defaults.dictionary(forKey: Self.previousKey) == nil {
            if Self.isComplete(current) {
                defaults.set(current, forKey: Self.previousKey)
            } else if let saved = siblingPrevious {
                defaults.set(saved, forKey: Self.previousKey)
            }
        }
        for scheme in ["http", "https"] { try await set(Bundle.main.bundleURL, scheme: scheme) }
        guard isDefault else { throw TernError.message("macOS did not assign both HTTP and HTTPS to Tern. Check Default Browser settings and retry.") }
    }
    func restore() async throws {
        guard let previous = defaults.dictionary(forKey: Self.previousKey) as? [String: String] else { return }
        for scheme in ["http", "https"] {
            guard let id = previous[scheme], !BrowserRegistry.isTern(id), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                throw TernError.message("Your previous browser is unavailable. Choose a default browser in System Settings.")
            }
            try await set(app, scheme: scheme)
        }
        guard handlers == previous else { throw TernError.message("The previous defaults were not fully restored. Check macOS settings.") }
        defaults.removeObject(forKey: Self.previousKey)
    }
    private func set(_ app: URL, scheme: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
