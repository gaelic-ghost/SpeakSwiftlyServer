// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SpeakSwiftlyServer",
    platforms: [
        .macOS("15.0"),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(path: "../SpeakSwiftly"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.1.0"),
        .package(
            url: "https://github.com/apple/swift-configuration",
            from: "1.2.0",
            traits: [.defaults, "YAML"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "SpeakSwiftlyServer",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "SpeakSwiftlyCore", package: "SpeakSwiftly"),
            ]
        ),
        .testTarget(
            name: "SpeakSwiftlyServerTests",
            dependencies: [
                "SpeakSwiftlyServer",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
