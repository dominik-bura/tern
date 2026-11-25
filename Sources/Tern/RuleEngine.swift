import Foundation

enum RuleEngine {
    static func decide(_ url: URL, sourceApp: String? = nil, configuration: RoutingConfiguration) -> RoutingDecision {
        if let rule = configuration.rules.first(where: { $0.enabled && $0.matcher.matches(url, sourceApp: sourceApp) }) {
            return RoutingDecision(destination: rule.destination, ruleName: rule.name, ruleID: rule.id)
        }
        return RoutingDecision(destination: configuration.fallback, ruleName: nil)
    }
}
