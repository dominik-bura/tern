import AppKit

@MainActor final class DiaService {
    private let client: AppleEventClient
    init(client: AppleEventClient = DiaAppleEventClient()) { self.client = client }
    func profiles() async throws -> [DiaProfileReference] {
        try await ensureRunning()
        let names = try await client.perform(["profiles"])
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.map { DiaProfileReference(name: $0) }
    }
    func switchProfile(_ profile: DiaProfileReference) async throws {
        try await ensureRunning()
        _ = try await client.perform(["switch", profile.name])
    }
    func currentURL() async throws -> URL {
        try await ensureRunning()
        let values = try await client.perform(["currentURL"])
        guard let value = values.first, let url = URL(string: value), IncomingURLRequest.isSupported(url) else {
            throw TernError.message("The current Dia tab has no HTTP or HTTPS URL.")
        }
        return url
    }
    func open(_ request: IncomingURLRequest, profile: DiaProfileReference) async throws {
        try await ensureRunning()
        _ = try await client.perform(["open", profile.name, request.id.uuidString, request.url.absoluteString])
    }
    private func ensureRunning() async throws {
        // Injected clients never launch an application, keeping unit tests isolated.
        guard client is DiaAppleEventClient else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "company.thebrowser.dia").isEmpty else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "company.thebrowser.dia") else {
            throw TernError.message("Install Dia to use Dia profile destinations.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
