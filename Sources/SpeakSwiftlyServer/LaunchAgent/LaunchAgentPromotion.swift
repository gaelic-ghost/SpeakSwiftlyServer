import Foundation

// MARK: - LaunchAgentPromoteOptions

struct LaunchAgentPromoteOptions {
    let installOptions: LaunchAgentOptions
    let repositoryRootPath: String

    static func parse(
        arguments: [String],
        currentDirectoryPath: String,
        currentExecutablePath: String,
    ) throws -> LaunchAgentPromoteOptions {
        let repositoryRootPath = try LaunchAgentOptions.resolveRepositoryRoot(startingAt: currentDirectoryPath)
        let installOptions = try LaunchAgentOptions.parse(
            arguments: arguments,
            currentDirectoryPath: currentDirectoryPath,
            currentExecutablePath: currentExecutablePath,
            requireToolExecutableExists: false,
        )
        return .init(
            installOptions: installOptions,
            repositoryRootPath: repositoryRootPath,
        )
    }

    func promoteLive() throws {
        let stagingResult = try ReleaseArtifactPromoter.promoteLive(
            repositoryRootPath: repositoryRootPath,
            stagedExecutablePath: installOptions.toolExecutablePath,
        )

        print(
            """
            Promoted the live staged release artifact from '\(stagingResult.builtExecutablePath)' to '\(stagingResult.stagedExecutablePath)'.
            Refreshed staged metallib at '\(stagingResult.stagedMetallibPath)'.
            Refreshed staged code signature for '\(stagingResult.stagedExecutablePath)'.
            """,
        )

        let refreshedInstallOptions = try LaunchAgentOptions(
            label: installOptions.label,
            toolExecutablePath: installOptions.toolExecutablePath,
            plistPath: installOptions.plistPath,
            configFilePath: installOptions.configFilePath,
            reloadIntervalSeconds: installOptions.reloadIntervalSeconds,
            workingDirectory: installOptions.workingDirectory,
            profileRootPath: installOptions.profileRootPath,
            standardOutPath: installOptions.standardOutPath,
            standardErrorPath: installOptions.standardErrorPath,
            launchctlPath: installOptions.launchctlPath,
            userDomain: installOptions.userDomain,
        )
        try refreshedInstallOptions.install()
    }
}

// MARK: - ReleaseArtifactPromotionResult

private struct ReleaseArtifactPromotionResult {
    let builtExecutablePath: String
    let stagedExecutablePath: String
    let stagedMetallibPath: String
}

// MARK: - ReleaseArtifactPromoter

private enum ReleaseArtifactPromoter {
    private struct SpeakSwiftlyPublishedRuntimeMetadata: Decodable {
        let buildConfiguration: String
        let metallibPath: String
        let sourceRoot: String?

        enum CodingKeys: String, CodingKey {
            case buildConfiguration = "build_configuration"
            case metallibPath = "metallib_path"
            case sourceRoot = "source_root"
        }
    }

    static func promoteLive(
        repositoryRootPath: String,
        stagedExecutablePath: String,
    ) throws -> ReleaseArtifactPromotionResult {
        let repositoryRootURL = URL(fileURLWithPath: repositoryRootPath, isDirectory: true)
        try buildReleaseTool(repositoryRootPath: repositoryRootPath)

        let builtExecutablePath = try builtReleaseExecutablePath(repositoryRootPath: repositoryRootPath)
        let builtMetallibURL = try publishedRuntimeMetallibURL(repositoryRootURL: repositoryRootURL)
        let stagedExecutableURL = URL(fileURLWithPath: stagedExecutablePath, isDirectory: false)
        let stagedDirectoryURL = stagedExecutableURL.deletingLastPathComponent()
        let stagedMetallibURL = stagedDirectoryURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("default.metallib", isDirectory: false)

        try FileManager.default.createDirectory(at: stagedDirectoryURL, withIntermediateDirectories: true)
        try replaceItem(
            at: stagedExecutableURL,
            with: URL(fileURLWithPath: builtExecutablePath, isDirectory: false),
            permissions: 0o755,
        )
        try FileManager.default.createDirectory(
            at: stagedMetallibURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try replaceItem(
            at: stagedMetallibURL,
            with: builtMetallibURL,
        )
        try refreshAdHocSignature(for: stagedExecutableURL)

        return .init(
            builtExecutablePath: builtExecutablePath,
            stagedExecutablePath: stagedExecutableURL.path,
            stagedMetallibPath: stagedMetallibURL.path,
        )
    }

    private static func buildReleaseTool(repositoryRootPath: String) throws {
        _ = try runProcess(
            executablePath: "/usr/bin/xcrun",
            arguments: ["swift", "build", "-c", "release", "--product", speakSwiftlyServerToolName],
            currentDirectoryPath: repositoryRootPath,
            failureSummary: "\(speakSwiftlyServerToolName) could not build the release executable from repository root '\(repositoryRootPath)'.",
        )
    }

    private static func builtReleaseExecutablePath(repositoryRootPath: String) throws -> String {
        let showBinPathResult = try runProcess(
            executablePath: "/usr/bin/xcrun",
            arguments: ["swift", "build", "-c", "release", "--show-bin-path"],
            currentDirectoryPath: repositoryRootPath,
            failureSummary: "\(speakSwiftlyServerToolName) could not determine the SwiftPM release bin path from repository root '\(repositoryRootPath)'.",
        )
        let binPath = showBinPathResult.standardOutput
        guard binPath.isEmpty == false else {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) asked SwiftPM for the release bin path, but SwiftPM returned an empty path.",
            )
        }

        let executablePath = URL(fileURLWithPath: binPath, isDirectory: true)
            .appendingPathComponent(speakSwiftlyServerToolName, isDirectory: false)
            .path
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) completed a release build, but the expected executable '\(executablePath)' was missing or not executable.",
            )
        }

        return executablePath
    }

    private static func publishedRuntimeMetallibURL(repositoryRootURL: URL) throws -> URL {
        let metadataURL = repositoryRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("SpeakSwiftly/.local/xcode/SpeakSwiftly.release.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw LaunchAgentCommandError(
                "The live-service promotion path requires sibling SpeakSwiftly release runtime metadata at '\(metadataURL.path)'. Publish and verify the sibling release runtime first.",
            )
        }

        let metadata = try JSONDecoder().decode(
            SpeakSwiftlyPublishedRuntimeMetadata.self,
            from: Data(contentsOf: metadataURL),
        )
        guard metadata.buildConfiguration == "Release" else {
            throw LaunchAgentCommandError(
                "The sibling SpeakSwiftly release runtime metadata at '\(metadataURL.path)' reported build configuration '\(metadata.buildConfiguration)' instead of the expected 'Release'.",
            )
        }

        let recordedURL = URL(fileURLWithPath: metadata.metallibPath, isDirectory: false)
        if FileManager.default.fileExists(atPath: recordedURL.path) {
            return recordedURL
        }

        if let sourceRoot = metadata.sourceRoot, metadata.metallibPath.hasPrefix(sourceRoot) {
            let relativeSuffix = String(metadata.metallibPath.dropFirst(sourceRoot.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relativeSuffix.isEmpty == false {
                let rebasedURL = repositoryRootURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("SpeakSwiftly", isDirectory: true)
                    .appendingPathComponent(relativeSuffix, isDirectory: false)
                if FileManager.default.fileExists(atPath: rebasedURL.path) {
                    return rebasedURL
                }
            }
        }

        throw LaunchAgentCommandError(
            "The sibling SpeakSwiftly release runtime metadata at '\(metadataURL.path)' pointed at a missing metallib path '\(metadata.metallibPath)'. Publish and verify the sibling release runtime first.",
        )
    }

    private static func replaceItem(
        at destinationURL: URL,
        with sourceURL: URL,
        permissions: NSNumber? = nil,
    ) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: destinationURL.path)
        }
    }

    private static func refreshAdHocSignature(for executableURL: URL) throws {
        _ = try runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["--force", "--sign", "-", executableURL.path],
            failureSummary: "\(speakSwiftlyServerToolName) could not refresh the staged ad-hoc code signature for '\(executableURL.path)'.",
        )
    }
}
