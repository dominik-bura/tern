import Foundation
import Combine

@MainActor final class RoutingCoordinator: ObservableObject {
    struct Pending: Identifiable {
        let request: IncomingURLRequest
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
        for url in urls {
            guard IncomingURLRequest.isSupported(url) else { lastResult = "Only HTTP and HTTPS links are supported"; continue }
            queue.append(Pending(request: IncomingURLRequest(url: url), decision: RuleEngine.decide(url, sourceApp: sourceApp, configuration: configuration)))
        }
        advance()
    }
    func choose(_ destination: BrowserDestination) {
        guard !isDelivering, var pending = current else { return }
        if pending.error != nil, pending.decision.destination != destination {
            // An explicit redirect is a new delivery. A retry keeps the old ID
            // so a partially created Dia tab can be recovered in place.
            pending = Pending(request: IncomingURLRequest(url: pending.request.url), decision: RoutingDecision(destination: destination, ruleName: nil))
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
