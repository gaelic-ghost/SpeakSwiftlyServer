import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Server Runtime Helpers

extension ServerE2E {
    static func serverToolExecutableURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = serverRootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/SpeakSwiftlyServerTool", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The SpeakSwiftlyServerTool executable was expected at '\(executableURL.path)', but it was not present. Run `swift build` before the live end-to-end suite.",
            )
        }

        return executableURL
    }

    static func serverBuildMetallibURL(serverExecutableURL: URL) throws -> URL {
        let productsURL = serverExecutableURL.deletingLastPathComponent()
        let candidates = [
            productsURL.appendingPathComponent(
                "SpeakSwiftly_SpeakSwiftly.bundle/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib",
                isDirectory: false,
            ),
            productsURL.appendingPathComponent(
                "SpeakSwiftly_SpeakSwiftlyCore.bundle/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib",
                isDirectory: false,
            ),
            productsURL.appendingPathComponent("Resources/default.metallib", isDirectory: false),
        ]

        if let metallibURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return metallibURL
        }

        throw SpeakSwiftlyBuildError(
            "The live SpeakSwiftlyServer end-to-end suite could not find the SpeakSwiftly MLX metallib in SwiftPM product directory '\(productsURL.path)'. Run `swift build` before the live end-to-end suite and confirm the SpeakSwiftly package dependency bundled mlx-swift_Cmlx.bundle.",
        )
    }

    private static func stageMetallibForServerBinary(
        sourceURL: URL,
        serverExecutableURL: URL,
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
        speechBackend: String? = nil,
    ) throws -> ServerProcess {
        if !silentPlayback {
            try stabilizeBuiltInAudioRouteForAudiblePlayback()
        }

        let executionLaneLease = try E2ELiveServerExecutionLaneLease.acquire(timeout: e2eTimeout)
        let executableURL = try serverToolExecutableURL()
        try stageMetallibForServerBinary(
            sourceURL: serverBuildMetallibURL(serverExecutableURL: executableURL),
            serverExecutableURL: executableURL,
        )

        return try ServerProcess(
            executionLaneLease: executionLaneLease,
            executableURL: executableURL,
            profileRootURL: profileRootURL,
            port: port,
            silentPlayback: silentPlayback,
            playbackTrace: playbackTrace,
            mcpEnabled: mcpEnabled,
            speechBackend: speechBackend,
        )
    }

    static func randomPort(in range: Range<Int>) -> Int {
        let shuffledCandidates = Array(range).filter { !reservedLiveServicePorts.contains($0) }.shuffled()
        if let availablePort = shuffledCandidates.first(where: isPortAvailable(_:)) {
            return availablePort
        }

        fatalError(
            "The live end-to-end suite could not find a free localhost port inside '\(range.lowerBound)..<\(range.upperBound)'.",
        )
    }

    static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    static var e2eTimeout: Duration {
        .seconds(1200)
    }

    // MARK: - Port Selection

    private static let reservedLiveServicePorts: Set<Int> = [7337, 7338, 7339]

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
            socklen_t(MemoryLayout<Int32>.size),
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
