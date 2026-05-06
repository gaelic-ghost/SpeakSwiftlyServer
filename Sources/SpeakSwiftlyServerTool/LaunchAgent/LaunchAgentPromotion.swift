import Darwin
import Foundation

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

struct ReleaseArtifactPromotionResult {
    let builtExecutablePath: String
    let stagedExecutablePath: String
    let stagedMetallibPath: String
}

enum ReleaseArtifactPromoter {
    static func promoteLive(
        repositoryRootPath: String,
        stagedExecutablePath: String,
    ) throws -> ReleaseArtifactPromotionResult {
        try buildReleaseTool(repositoryRootPath: repositoryRootPath)

        let builtExecutablePath = try builtReleaseExecutablePath(repositoryRootPath: repositoryRootPath)
        let builtMetallibURL = try builtReleaseMetallibURL(
            productsURL: URL(fileURLWithPath: builtExecutablePath, isDirectory: false)
                .deletingLastPathComponent(),
        )
        let stagedExecutableURL = URL(fileURLWithPath: stagedExecutablePath, isDirectory: false)
        let stagedDirectoryURL = stagedExecutableURL.deletingLastPathComponent()
        let stagedMetallibURL = stagedDirectoryURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("default.metallib", isDirectory: false)

        try FileManager.default.createDirectory(
            at: stagedMetallibURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )

        let preparedExecutableURL = try prepareReplacementItem(
            at: stagedExecutableURL,
            with: URL(fileURLWithPath: builtExecutablePath, isDirectory: false),
            permissions: 0o755,
            prepareTemporaryItem: refreshAdHocSignature,
        )
        defer {
            try? FileManager.default.removeItem(at: preparedExecutableURL)
        }

        let preparedMetallibURL = try prepareReplacementItem(
            at: stagedMetallibURL,
            with: builtMetallibURL,
        )
        defer {
            try? FileManager.default.removeItem(at: preparedMetallibURL)
        }

        let metallibBackupURL = try backupItemIfPresent(at: stagedMetallibURL)
        defer {
            if let metallibBackupURL {
                try? FileManager.default.removeItem(at: metallibBackupURL)
            }
        }

        try commitPreparedReplacement(preparedMetallibURL, to: stagedMetallibURL)
        do {
            try commitPreparedReplacement(preparedExecutableURL, to: stagedExecutableURL)
        } catch {
            try rollbackItem(at: stagedMetallibURL, from: metallibBackupURL, after: error)
            throw error
        }

        return .init(
            builtExecutablePath: builtExecutablePath,
            stagedExecutablePath: stagedExecutableURL.path,
            stagedMetallibPath: stagedMetallibURL.path,
        )
    }

    static func replaceItem(
        at destinationURL: URL,
        with sourceURL: URL,
        permissions: NSNumber? = nil,
    ) throws {
        let temporaryURL = try prepareReplacementItem(
            at: destinationURL,
            with: sourceURL,
            permissions: permissions,
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        try commitPreparedReplacement(temporaryURL, to: destinationURL)
    }

    private static func prepareReplacementItem(
        at destinationURL: URL,
        with sourceURL: URL,
        permissions: NSNumber? = nil,
        prepareTemporaryItem: ((URL) throws -> Void)? = nil,
    ) throws -> URL {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: false)

        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporaryURL.path)
        }
        try prepareTemporaryItem?(temporaryURL)

        return temporaryURL
    }

    private static func commitPreparedReplacement(_ temporaryURL: URL, to destinationURL: URL) throws {
        guard rename(temporaryURL.path, destinationURL.path) == 0 else {
            let failureDescription = String(cString: strerror(errno))
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not atomically replace staged artifact '\(destinationURL.path)' with temporary artifact '\(temporaryURL.path)'. Likely cause: \(failureDescription)",
            )
        }
    }

    private static func backupItemIfPresent(at destinationURL: URL) throws -> URL? {
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            return nil
        }

        let backupURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).backup", isDirectory: false)
        try FileManager.default.copyItem(at: destinationURL, to: backupURL)
        return backupURL
    }

    private static func rollbackItem(
        at destinationURL: URL,
        from backupURL: URL?,
        after replacementError: Error,
    ) throws {
        do {
            if let backupURL {
                try commitPreparedReplacement(backupURL, to: destinationURL)
            } else if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
        } catch {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not roll back staged artifact '\(destinationURL.path)' after promotion failed. Promotion error: \(replacementError). Rollback error: \(error).",
            )
        }
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

    private static func builtReleaseMetallibURL(productsURL: URL) throws -> URL {
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

        throw LaunchAgentCommandError(
            "\(speakSwiftlyServerToolName) completed a release build, but no SpeakSwiftly MLX metallib was found in SwiftPM product directory '\(productsURL.path)'. Expected the SpeakSwiftly package dependency to bundle mlx-swift_Cmlx.bundle in the release build products.",
        )
    }

    private static func refreshAdHocSignature(for executableURL: URL) throws {
        _ = try runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["--force", "--sign", "-", executableURL.path],
            failureSummary: "\(speakSwiftlyServerToolName) could not refresh the staged ad-hoc code signature for '\(executableURL.path)'.",
        )
    }
}
