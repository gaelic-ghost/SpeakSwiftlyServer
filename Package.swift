// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpeakSwiftlyServer",
    platforms: [
        .macOS("15.0"),
    ],
    products: [
        .library(
            name: "SpeakSwiftlyServerCore",
            targets: ["SpeakSwiftlyServerCore"]
        ),
        .executable(
            name: "SpeakSwiftlyServer",
            targets: ["SpeakSwiftlyServer"]
        ),
        .executable(
            name: "SpeakSwiftlyServerCli",
            targets: ["SpeakSwiftlyServerCli"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.21.1"),
        .package(
            url: "https://github.com/gaelic-ghost/SpeakSwiftly.git",
            exact: "0.9.6"
        ),
        .package(url: "https://github.com/gaelic-ghost/TextForSpeech.git", from: "0.9.3"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.3"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
        .package(
            url: "https://github.com/apple/swift-configuration",
            from: "1.2.0",
            traits: [.defaults, "YAML", "Reloading"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SpeakSwiftlyServerCore",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SpeakSwiftlyCore", package: "SpeakSwiftly"),
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ],
            path: "Sources/SpeakSwiftlyServer"
        ),
        .executableTarget(
            name: "SpeakSwiftlyServer",
            dependencies: [
                "SpeakSwiftlyServerCore",
            ],
            path: "Sources/SpeakSwiftlyServerExecutable"
        ),
        .executableTarget(
            name: "SpeakSwiftlyServerCli",
            dependencies: [
                "SpeakSwiftlyServerCore",
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyServerTests",
            dependencies: [
                "SpeakSwiftlyServerCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyServerE2ETests",
            dependencies: [
                "SpeakSwiftlyServerCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyServerCliTests",
            dependencies: [
                "SpeakSwiftlyServerCore",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
