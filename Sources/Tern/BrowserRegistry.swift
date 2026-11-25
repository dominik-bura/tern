import AppKit

struct InstalledBrowser: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

enum BrowserRegistry {
    /// Browsers whose profiles Tern can discover and target.
    static let diaID = "company.thebrowser.dia"
    static func isTern(_ id: String) -> Bool {
        ["com.dominikbura.tern", "com.dominikbura.tern.dev"].contains(id)
    }
    private static func isBrowser(_ bundle: Bundle) -> Bool {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        return types.contains { type in
            let content = type["LSItemContentTypes"] as? [String] ?? []
            let extensions = type["CFBundleTypeExtensions"] as? [String] ?? []
            return content.contains("public.html") || content.contains("public.xhtml") || extensions.contains("html") || extensions.contains("htm")
        }
    }
    @MainActor static func installed() -> [InstalledBrowser] {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        var seen = Set<String>()
        return apps.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !isTern(id), isBrowser(bundle), seen.insert(id).inserted else { return nil }
            return InstalledBrowser(id: id, name: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent, url: url)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
