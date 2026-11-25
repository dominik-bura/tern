import Foundation

/// Finds the real destination behind redirect wrappers and short links, and removes tracking parameters.
enum LinkCleaner {
    /// Query parameters that only identify campaigns or clicks.
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "li_fat_id",
        "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "vero_conv", "oly_anon_id",
        "oly_enc_id", "rb_clickid", "s_cid", "wickedid", "srsltid", "_ga", "_gl", "ref_src", "ref_url",
    ]

    /// Hosts that only redirect, resolved with a request that doesn't follow the redirect.
    static let shortLinkHosts: Set<String> = [
        "t.co", "bit.ly", "lnkd.in", "buff.ly", "ow.ly", "tinyurl.com", "rebrand.ly", "is.gd", "tiny.cc",
        "shorturl.at", "dlvr.it", "trib.al", "bitly.com", "cutt.ly", "rb.gy", "t.ly", "s.id",
    ]

    /// Runs the enabled steps. Short links are resolved over the network; everything else is local.
    static func clean(_ url: URL, unwrap: Bool, removeTracking: Bool) async -> URL {
        var current = url
        if unwrap {
            for _ in 0..<5 {
                if let inner = unwrapped(current) { current = inner; continue }
                if isShortLink(current), let resolved = await resolveShortLink(current) { current = resolved; continue }
                break
            }
        }
        return removeTracking ? stripTracking(current) : current
    }

    /// The same steps without the network, for previews.
    static func cleanLocally(_ url: URL, unwrap: Bool, removeTracking: Bool) -> URL {
        var current = url
        if unwrap { for _ in 0..<5 { guard let inner = unwrapped(current) else { break }; current = inner } }
        return removeTracking ? stripTracking(current) : current
    }

    /// The link wrapped inside a known redirect service, or nil.
    static func unwrapped(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = components.host?.lowercased() else { return nil }
        let path = components.path.lowercased()
        func value(_ names: String...) -> String? {
            for name in names {
                if let item = components.queryItems?.first(where: { $0.name == name })?.value, !item.isEmpty { return item }
            }
            return nil
        }
        var candidate: String?
        if host.hasSuffix(".safelinks.protection.outlook.com") || host.hasSuffix(".safelinks.protection.office365.us") {
            candidate = value("url")
        } else if isGoogle(host), path == "/url" {
            candidate = value("q", "url")
        } else if host == "slack-redir.net", path == "/link" {
            candidate = value("url")
        } else if ["l.facebook.com", "lm.facebook.com", "l.messenger.com", "l.instagram.com", "l.threads.net"].contains(host) {
            candidate = value("u")
        } else if host.hasSuffix("linkedin.com"), path.hasPrefix("/safety/go") {
            candidate = value("url")
        } else if host.hasSuffix("youtube.com"), path == "/redirect" {
            candidate = value("q")
        } else if host == "steamcommunity.com", path.hasPrefix("/linkfilter") {
            candidate = value("u", "url")
        } else if host == "out.reddit.com" {
            candidate = value("url")
        } else if host == "href.li" {
            candidate = components.percentEncodedQuery.flatMap { $0.removingPercentEncoding }
        } else if host == "urldefense.proofpoint.com", path.hasPrefix("/v2/url") {
            // Proofpoint v2 encodes "%" as "-" and "/" as "_".
            candidate = value("u").map { $0.replacingOccurrences(of: "-", with: "%").replacingOccurrences(of: "_", with: "/") }
                .flatMap { $0.removingPercentEncoding }
        }
        guard let candidate, let inner = URL(string: candidate.trimmingCharacters(in: .whitespaces)),
              IncomingURLRequest.isSupported(inner) else { return nil }
        return inner
    }

    private static func isGoogle(_ host: String) -> Bool {
        let labels = host.split(separator: ".")
        guard let index = labels.firstIndex(of: "google") else { return false }
        return index <= 1 && labels.count - index <= 3
    }

    static func isShortLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return shortLinkHosts.contains(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
    }

    static func stripTracking(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty else { return url }
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
        }
        guard kept.count != items.count else { return url }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    /// Asks the shortener where it points without following the redirect. Gives up after a few seconds.
    static func resolveShortLink(_ url: URL) async -> URL? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.httpMethod = "HEAD"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location, relativeTo: url)?.absoluteURL,
              IncomingURLRequest.isSupported(target) else { return nil }
        return target
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
