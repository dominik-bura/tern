// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tern",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tern", targets: ["Tern"]),
        .executable(name: "TernUpdater", targets: ["TernUpdater"])
    ],
    targets: [
        .target(name: "TernUpdateCore"),
        .testTarget(name: "TernUpdateCoreTests", dependencies: ["TernUpdateCore"]),
        .executableTarget(
            name: "Tern",
            dependencies: ["TernUpdateCore"],
            path: "Sources/Tern"
        ),
        .executableTarget(
            name: "TernUpdater",
            dependencies: ["TernUpdateCore"],
            path: "Sources/TernUpdater"
        ),
        .testTarget(
            name: "TernTests",
            dependencies: ["Tern"],
            path: "Tests/TernTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
