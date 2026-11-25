import Foundation
import Combine

@MainActor final class RoutingCoordinator: ObservableObject {
    struct Pending: Identifiable {
        let request: IncomingURLRequest
        /// The link rules were matched against: the destination inside a security scanner's wrapper.
        var match: URL
        var decision: RoutingDecision
        var error: String?
        var id: UUID { request.id }
    }
    @Published private(set) var current: Pending?
    @Published private(set) var queuedCount = 0
    @Published private(set) var isDelivering = false
    @Published private(set) var lastResult = "Ready for links"
    var onNeedsAttention: (() -> Void)?
    /// Called after a link was delivered, with the decision that delivered it.
    var onOpened: ((RoutingDecision) -> Void)?
    private var queue: [Pending] = []
    private let opener: DestinationOpening
    init(opener: DestinationOpening) { self.opener = opener }

    func enqueue(_ urls: [URL], sourceApp: String? = nil, configuration: RoutingConfiguration) {
        enqueue(urls.map { LinkCleaner.Result(match: $0, open: $0) }, sourceApp: sourceApp, configuration: configuration)
    }
    /// Decides by each link's `match` URL and opens its `open` URL.
    func enqueue(_ links: [LinkCleaner.Result], sourceApp: String? = nil, configuration: RoutingConfiguration) {
        for link in links {
            guard IncomingURLRequest.isSupported(link.match), IncomingURLRequest.isSupported(link.open) else {
                lastResult = "Only HTTP and HTTPS links are supported"; continue
            }
            queue.append(Pending(request: IncomingURLRequest(url: link.open), match: link.match, decision: RuleEngine.decide(link.match, sourceApp: sourceApp, configuration: configuration)))
        }
        advance()
    }
    func choose(_ destination: BrowserDestination) {
        guard !isDelivering, var pending = current else { return }
        if pending.error != nil, pending.decision.destination != destination {
            // An explicit redirect is a new delivery. A retry keeps the old ID
            // so a partially created Dia tab can be recovered in place.
            pending = Pending(request: IncomingURLRequest(url: pending.request.url), match: pending.match, decision: RoutingDecision(destination: destination, ruleName: nil))
        }
        pending.decision = RoutingDecision(destination: destination, ruleName: pending.decision.ruleName, ruleID: pending.decision.ruleID)
        pending.error = nil
        current = pending
        deliver()
    }
    func retry() { guard current?.decision.destination != .ask else { return }; deliver() }
    func cancel() {
        guard !isDelivering else { return }
        current = nil
        lastResult = "Link cancelled"
        advance()
    }
    private func advance() {
        queuedCount = queue.count
        guard current == nil, !isDelivering, !queue.isEmpty else { return }
        current = queue.removeFirst()
        queuedCount = queue.count
        if current?.decision.destination == .ask { onNeedsAttention?() } else { deliver() }
    }
    private func deliver() {
        guard !isDelivering, let pending = current else { return }
        isDelivering = true
        Task {
            do {
                try await opener.open(pending.request, in: pending.decision.destination)
                lastResult = pending.decision.ruleName.map { "Opened with \($0)" } ?? "Link opened"
                current = nil
                onOpened?(pending.decision)
            } catch {
                current?.error = error.localizedDescription
                onNeedsAttention?()
            }
            isDelivering = false
            advance()
        }
    }
}
