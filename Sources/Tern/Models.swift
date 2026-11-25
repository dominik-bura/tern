import Foundation

struct DiaProfileReference: Codable, Equatable, Hashable, Sendable {
    var name: String
}

enum BrowserDestination: Codable, Equatable, Hashable, Sendable {
    case ask
    case browser(String)
    case dia(DiaProfileReference)
    /// A profile of a Chromium browser (Chrome, Edge, Brave, …) or a Firefox browser (Firefox, Zen).
    case profile(ProfileReference)

    var label: String {
        switch self {
        case .ask: return "Ask Every Time"
        case .browser(let id): return id
        case .dia(let profile): return "Dia · \(profile.name)"
        case .profile(let profile): return profile.name
        }
    }
}

struct URLMatcher: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// A domain with optional subdomains and path prefix.
        case domain
        /// A pattern like `*.atlassian.net/wiki/*`.
        case wildcard
        /// A regular expression tested against the whole link.
        case regex
    }

    var kind: Kind = .domain
    var host = ""
    var includeSubdomains = true
    var pathPrefix = ""
    var pattern = ""
    /// Bundle identifiers of the apps a link must come from. Empty matches links from any app.
    var sourceApps: [String] = []

    init(kind: Kind = .domain, host: String = "", includeSubdomains: Bool = true, pathPrefix: String = "", pattern: String = "", sourceApps: [String] = []) {
        self.kind = kind; self.host = host; self.includeSubdomains = includeSubdomains
        self.pathPrefix = pathPrefix; self.pattern = pattern; self.sourceApps = sourceApps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .domain
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        includeSubdomains = try c.decodeIfPresent(Bool.self, forKey: .includeSubdomains) ?? true
        pathPrefix = try c.decodeIfPresent(String.self, forKey: .pathPrefix) ?? ""
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        sourceApps = try c.decodeIfPresent([String].self, forKey: .sourceApps) ?? []
    }

    func validate() throws {
        switch kind {
        case .domain:
            // A rule may match only on the source app ("everything from Slack").
            if host.isEmpty, pathPrefix.isEmpty, !sourceApps.isEmpty { break }
            let hostname = host.lowercased()
            guard !hostname.isEmpty, !hostname.hasPrefix("."), !hostname.hasSuffix("."),
                  !hostname.contains(".."), hostname.utf8.allSatisfy({
                      (97...122).contains($0) || (48...57).contains($0) || [45, 46].contains($0)
                  }), hostname.split(separator: ".").allSatisfy({ !$0.hasPrefix("-") && !$0.hasSuffix("-") }),
                  pathPrefix.isEmpty || (pathPrefix.hasPrefix("/") && !pathPrefix.contains("?") && !pathPrefix.contains("#")) else {
                throw TernError.message("Enter a hostname such as example.com and an optional path beginning with /. Use punycode for international domains.")
            }
        case .wildcard:
            let value = pattern.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !value.contains(" "), value != "*" || !sourceApps.isEmpty else {
                throw TernError.message("Enter a pattern such as *.atlassian.net/wiki/*.")
            }
        case .regex:
            guard !pattern.isEmpty, (try? NSRegularExpression(pattern: pattern)) != nil else {
                throw TernError.message("Enter a valid regular expression, for example ^https://github\\.com/statworx/.")
            }
        }
        guard sourceApps.allSatisfy({ !$0.isEmpty }) else { throw TernError.message("Choose an app to match.") }
    }

    /// Turns what people paste into the Domain field (a full link, "*.example.com", "example.com/team")
    /// into a hostname, a path prefix, and whether subdomains were requested. Plain hostnames return nil.
    static func parseDomainInput(_ raw: String) -> (host: String, path: String?, includeSubdomains: Bool)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var wildcard = false
        if text.hasPrefix("*.") { text.removeFirst(2); wildcard = true }
        guard wildcard || text.contains("/") || text.contains(":") || text != text.lowercased() || text.hasSuffix(".") else { return nil }
        let candidate = text.contains("://") ? text : "https://" + text
        guard let components = URLComponents(string: candidate), let host = components.host, !host.isEmpty else { return nil }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let cleanHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (cleanHost, path.isEmpty ? nil : path, wildcard)
    }

    /// Extracts the path when a full link was pasted into the Path field.
    static func parsePathInput(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("://"), let components = URLComponents(string: text) else { return text }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    func matches(_ url: URL, sourceApp: String? = nil) -> Bool {
        guard IncomingURLRequest.isSupported(url), let urlHost = url.host?.lowercased() else { return false }
        if !sourceApps.isEmpty {
            guard let sourceApp, sourceApps.contains(where: { $0.caseInsensitiveCompare(sourceApp) == .orderedSame }) else { return false }
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Match encoded paths so %2F cannot silently change account/path segment boundaries.
        let path = components?.percentEncodedPath ?? ""
        switch kind {
        case .domain:
            if host.isEmpty { return pathPrefix.isEmpty }
            let target = host.lowercased()
            guard urlHost == target || (includeSubdomains && urlHost.hasSuffix("." + target)) else { return false }
            // Paths compare case-insensitively: /STATWORX and /statworx are the same place on most sites.
            let prefix = (pathPrefix == "/" ? "" : pathPrefix.trimmingTrailingSlashes).lowercased()
            let lowered = path.lowercased()
            return prefix.isEmpty || lowered == prefix || lowered.hasPrefix(prefix + "/")
        case .wildcard:
            return Self.wildcardMatches(pattern, host: urlHost, path: path, query: components?.percentEncodedQuery)
        case .regex:
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            let text = url.absoluteString
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    /// `*` matches any run of characters. A pattern without "/" is tested against the host only;
    /// otherwise against host, path, and query. Matching ignores case and the scheme.
    static func wildcardMatches(_ rawPattern: String, host: String, path: String, query: String?) -> Bool {
        var pattern = rawPattern.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where pattern.hasPrefix(scheme) { pattern.removeFirst(scheme.count) }
        guard !pattern.isEmpty else { return false }
        var subject = host
        if pattern.contains("/") {
            subject += path.isEmpty ? "/" : path.lowercased()
            if let query, !query.isEmpty { subject += "?" + query.lowercased() }
        }
        // "*.example.com" also covers example.com itself, like the domain matcher.
        if pattern.hasPrefix("*."), !pattern.contains("/"), subject == String(pattern.dropFirst(2)) { return true }
        let expression = "^" + pattern.split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: ".*")
        // "example.com/docs*" should also match "example.com/docs/" and query strings.
        + (pattern.hasSuffix("*") || !pattern.contains("/") ? "$" : "(?:[/?#].*)?$")
        return subject.range(of: expression, options: .regularExpression) != nil
    }

    /// A short description for lists, e.g. "*.github.com/statworx".
    var summary: String {
        switch kind {
        case .domain:
            if host.isEmpty { return "Any link" }
            return "\(includeSubdomains ? "*." : "")\(host)\(pathPrefix)"
        case .wildcard: return pattern
        case .regex: return "/\(pattern)/"
        }
    }
}

private extension String {
    var trimmingTrailingSlashes: String {
        var value = self
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

struct RoutingRule: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var enabled = true
    var matcher = URLMatcher()
    var destination: BrowserDestination = .ask
    /// Optional group name; rules of a group are kept together.
    var group: String?

    init(id: UUID = UUID(), name: String = "", enabled: Bool = true, matcher: URLMatcher = URLMatcher(), destination: BrowserDestination = .ask, group: String? = nil) {
        self.id = id; self.name = name; self.enabled = enabled; self.matcher = matcher; self.destination = destination; self.group = group
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        matcher = try c.decode(URLMatcher.self, forKey: .matcher)
        destination = try c.decode(BrowserDestination.self, forKey: .destination)
        group = try c.decodeIfPresent(String.self, forKey: .group).flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct RoutingConfiguration: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var rules: [RoutingRule] = []
    var fallback: BrowserDestination = .ask
    /// Match the link inside redirect wrappers (Safe Links, Google, Slack). Done locally.
    var unwrapLinks = true
    /// Ask short-link services (t.co, bit.ly) where a link points. The only routing step that uses the network.
    var resolveShortLinks = false
    /// Remove tracking parameters such as utm_source and fbclid.
    var removeTracking = true

    init(schemaVersion: Int = 1, rules: [RoutingRule] = [], fallback: BrowserDestination = .ask, unwrapLinks: Bool = true, resolveShortLinks: Bool = false, removeTracking: Bool = true) {
        self.schemaVersion = schemaVersion; self.rules = rules; self.fallback = fallback
        self.unwrapLinks = unwrapLinks; self.resolveShortLinks = resolveShortLinks; self.removeTracking = removeTracking
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        rules = try c.decodeIfPresent([RoutingRule].self, forKey: .rules) ?? []
        fallback = try c.decodeIfPresent(BrowserDestination.self, forKey: .fallback) ?? .ask
        unwrapLinks = try c.decodeIfPresent(Bool.self, forKey: .unwrapLinks) ?? true
        resolveShortLinks = try c.decodeIfPresent(Bool.self, forKey: .resolveShortLinks) ?? false
        removeTracking = try c.decodeIfPresent(Bool.self, forKey: .removeTracking) ?? true
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw TernError.message("This configuration needs a different version of Tern. The original file has been preserved.") }
        guard Set(rules.map(\.id)).count == rules.count else { throw TernError.message("Rule identifiers must be unique.") }
        for rule in rules {
            try rule.matcher.validate()
            guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TernError.message("Give each rule a name.") }
            try rule.destination.validate()
        }
        try fallback.validate()
    }

    /// Group names in display order (order of first appearance).
    var groups: [String] {
        var seen = Set<String>()
        return rules.compactMap(\.group).filter { seen.insert($0).inserted }
    }

    /// Keeps each group's rules together so the list order is the order rules are checked.
    /// Ungrouped rules come first, then groups in order of first appearance.
    mutating func normalizeGroups() {
        let order = [nil] + groups.map(Optional.some)
        rules = order.flatMap { group in rules.filter { $0.group == group } }
    }
}

extension BrowserDestination {
    func validate() throws {
        switch self {
        case .ask: break
        case .browser(let id):
            guard !id.isEmpty, !BrowserRegistry.isTern(id) else { throw TernError.message("Choose another browser to avoid routing links back into Tern.") }
        case .dia(let profile):
            guard !profile.name.isEmpty else { throw TernError.message("Choose a named Dia profile.") }
        case .profile(let profile):
            guard BrowserProfiles.isValid(profile) else {
                throw TernError.message("Choose a valid browser profile.")
            }
        }
    }
}

struct IncomingURLRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    init(url: URL, id: UUID = UUID()) { self.url = url; self.id = id }
    static func isSupported(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }
}

struct RoutingDecision: Equatable, Sendable {
    let destination: BrowserDestination
    let ruleName: String?
    var ruleID: UUID? = nil
}

enum TernError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
