import AppKit

@MainActor protocol DestinationOpening {
    func open(_ request: IncomingURLRequest, in destination: BrowserDestination) async throws
}

@MainActor final class BrowserOpener: DestinationOpening {
    let dia: DiaService
    init(dia: DiaService) { self.dia = dia }
    func open(_ request: IncomingURLRequest, in destination: BrowserDestination) async throws {
        guard IncomingURLRequest.isSupported(request.url) else { throw TernError.message("Tern routes HTTP and HTTPS links only.") }
        try destination.validate()
        switch destination {
        case .ask: throw TernError.message("Choose a destination.")
        case .dia(let profile): try await dia.open(request, profile: profile)
        case .profile(let profile):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.browserID),
                  BrowserProfiles.dataDirectory(for: profile.browserID) != nil else {
                throw TernError.message("This browser is no longer installed. Choose another destination.")
            }
            guard !BrowserProfiles.profileIsMissing(browserID: profile.browserID, directory: profile.directory) else {
                throw TernError.message("The profile “\(profile.name)” no longer exists. Choose another destination.")
            }
            // A second instance hands the URL to the running browser, which opens it in that profile.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = BrowserProfiles.launchArguments(for: profile, url: request.url)
            try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        case .browser(let identifier):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                  let actualID = Bundle(url: app)?.bundleIdentifier, !BrowserRegistry.isTern(actualID) else {
                throw TernError.message("This browser is no longer installed. Choose another destination.")
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.open([request.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
    }
}
