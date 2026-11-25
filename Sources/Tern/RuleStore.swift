import Foundation

struct RuleStore {
    let fileURL: URL
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dominikbura.tern.dev", isDirectory: true)
            .appendingPathComponent("rules.json")
    }
    func load() throws -> RoutingConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return RoutingConfiguration() }
        return try Self.decode(Data(contentsOf: fileURL))
    }
    func save(_ configuration: RoutingConfiguration) throws {
        try configuration.validate()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(configuration).write(to: fileURL, options: .atomic)
    }
    static func decode(_ data: Data) throws -> RoutingConfiguration {
        let value = try JSONDecoder().decode(RoutingConfiguration.self, from: data)
        try value.validate()
        return value
    }
    static func encode(_ configuration: RoutingConfiguration) throws -> Data {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(configuration)
    }
}
