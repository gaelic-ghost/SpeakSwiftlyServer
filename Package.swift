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
            name: "SpeakSwiftlyServer",
            targets: ["SpeakSwiftlyServer"]
        ),
        .executable(
            name: "SpeakSwiftlyServerTool",
            targets: ["SpeakSwiftlyServerTool"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.21.1"),
        .package(
            url: "https://github.com/gaelic-ghost/SpeakSwiftly.git",
            exact: "2.2.0"
        ),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "2.30.6"),
        .package(url: "https://github.com/gaelic-ghost/TextForSpeech.git", from: "0.10.0"),
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
            name: "SpeakSwiftlyServer",
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
            name: "SpeakSwiftlyServerTool",
            dependencies: [
                "SpeakSwiftlyServer",
            ],
            path: "Sources/SpeakSwiftlyServerTool"
        ),
        .testTarget(
            name: "SpeakSwiftlyServerTests",
            dependencies: [
                "SpeakSwiftlyServer",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyServerE2ETests",
            dependencies: [
                // Keep the live Marvis server suite on the same MLX runtime stack as
                // SpeakSwiftly's upstream Marvis e2e coverage so model-loading behavior
                // stays deterministic across the two repositories.
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                "SpeakSwiftlyServer",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "TextForSpeech", package: "TextForSpeech"),
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyServerToolTests",
            dependencies: [
                "SpeakSwiftlyServer",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
