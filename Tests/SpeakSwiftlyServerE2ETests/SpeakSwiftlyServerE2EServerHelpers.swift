import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Server Runtime Helpers

extension ServerE2E {
    private struct SpeakSwiftlyPublishedRuntimeMetadata: Decodable {
        let buildConfiguration: String
        let productsPath: String
        let executablePath: String
        let launcherPath: String
        let metallibPath: String
        let aliasPath: String
        let sourceRoot: String?

        enum CodingKeys: String, CodingKey {
            case buildConfiguration = "build_configuration"
            case productsPath = "products_path"
            case executablePath = "executable_path"
            case launcherPath = "launcher_path"
            case metallibPath = "metallib_path"
            case aliasPath = "alias_path"
            case sourceRoot = "source_root"
        }
    }

    private struct SpeakSwiftlyPublishedRuntimeArtifacts {
        let metadataURL: URL
        let metadata: SpeakSwiftlyPublishedRuntimeMetadata
        let productsURL: URL
        let executableURL: URL
        let launcherURL: URL
        let metallibURL: URL
    }

    private static func speakSwiftlyPublishedRuntimeArtifacts(configuration: String) throws -> SpeakSwiftlyPublishedRuntimeArtifacts {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let metadataURL = serverRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("SpeakSwiftly/.local/xcode/SpeakSwiftly.\(configuration.lowercased()).json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The live SpeakSwiftlyServer end-to-end suite requires the sibling SpeakSwiftly published runtime metadata at '\(metadataURL.path)'. Publish and verify the sibling \(configuration) runtime first."
            )
        }

        let metadata = try decode(
            SpeakSwiftlyPublishedRuntimeMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.buildConfiguration == configuration else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata at '\(metadataURL.path)' reported build configuration '\(metadata.buildConfiguration)' instead of the expected '\(configuration)'."
            )
        }

        let siblingSourceRootURL = metadataURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let localXcodeRootURL = siblingSourceRootURL
            .appendingPathComponent(".local/xcode", isDirectory: true)
        let productsURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.productsPath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: localXcodeRootURL.appendingPathComponent(configuration, isDirectory: true),
            isDirectory: true
        )
        let executableURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.executablePath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: productsURL.appendingPathComponent("SpeakSwiftly", isDirectory: false),
            isDirectory: false
        )
        let launcherURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.launcherPath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: productsURL.appendingPathComponent("run-speakswiftly", isDirectory: false),
            isDirectory: false
        )
        let metallibURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.metallibPath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: productsURL.appendingPathComponent(
                "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib",
                isDirectory: false
            ),
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing metallib path '\(metallibURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing runtime launcher '\(launcherURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing executable '\(executableURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }

        return .init(
            metadataURL: metadataURL,
            metadata: metadata,
            productsURL: productsURL,
            executableURL: executableURL,
            launcherURL: launcherURL,
            metallibURL: metallibURL
        )
    }

    private static func resolvedPublishedRuntimeURL(
        recordedPath: String,
        recordedSourceRoot: String?,
        actualSourceRootURL: URL,
        fallbackURL: URL,
        isDirectory: Bool
    ) -> URL {
        let recordedURL = URL(fileURLWithPath: recordedPath, isDirectory: isDirectory)
        if FileManager.default.fileExists(atPath: recordedURL.path) {
            return recordedURL
        }

        guard
            let recordedSourceRoot,
            recordedPath.hasPrefix(recordedSourceRoot)
        else {
            return fallbackURL
        }

        let relativeSuffix = String(recordedPath.dropFirst(recordedSourceRoot.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard relativeSuffix.isEmpty == false else {
            return fallbackURL
        }

        let rebasedURL = actualSourceRootURL
            .appendingPathComponent(relativeSuffix, isDirectory: isDirectory)
        if FileManager.default.fileExists(atPath: rebasedURL.path) {
            return rebasedURL
        }

        return fallbackURL
    }

    static func serverToolExecutableURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = serverRootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/SpeakSwiftlyServerTool", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The SpeakSwiftlyServerTool executable was expected at '\(executableURL.path)', but it was not present. Run `swift build` before the live end-to-end suite."
            )
        }
        return executableURL
    }

    private static func stageMetallibForServerBinary(
        sourceURL: URL,
        serverExecutableURL: URL
    ) throws {
        let targetDirectoryURL = serverExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let targetURL = targetDirectoryURL.appendingPathComponent("default.metallib", isDirectory: false)

        try FileManager.default.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    }

    static func makeServer(
        port: Int,
        profileRootURL: URL,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool,
        speechBackend: String? = nil
    ) throws -> ServerProcess {
        if !silentPlayback {
            try stabilizeBuiltInAudioRouteForAudiblePlayback()
        }

        let executionLaneLease = try E2ELiveServerExecutionLaneLease.acquire(timeout: e2eTimeout)
        let publishedRuntimeArtifacts = try speakSwiftlyPublishedRuntimeArtifacts(configuration: "Debug")
        let executableURL = try serverToolExecutableURL()
        try stageMetallibForServerBinary(
            sourceURL: publishedRuntimeArtifacts.metallibURL,
            serverExecutableURL: executableURL
        )

        return try ServerProcess(
            executionLaneLease: executionLaneLease,
            executableURL: executableURL,
            profileRootURL: profileRootURL,
            port: port,
            silentPlayback: silentPlayback,
            playbackTrace: playbackTrace,
            mcpEnabled: mcpEnabled,
            speechBackend: speechBackend
        )
    }

    static func randomPort(in range: Range<Int>) -> Int {
        let shuffledCandidates = Array(range).shuffled()
        if let availablePort = shuffledCandidates.first(where: isPortAvailable(_:)) {
            return availablePort
        }

        fatalError(
            "The live end-to-end suite could not find a free localhost port inside '\(range.lowerBound)..<\(range.upperBound)'."
        )
    }

    static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    static var e2eTimeout: Duration {
        .seconds(1_200)
    }

    // MARK: - Port Selection

    private static func isPortAvailable(_ port: Int) -> Bool {
        #if canImport(Darwin)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var reuseAddress: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            return false
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        return bindStatus == 0
        #else
        return true
        #endif
    }
}
