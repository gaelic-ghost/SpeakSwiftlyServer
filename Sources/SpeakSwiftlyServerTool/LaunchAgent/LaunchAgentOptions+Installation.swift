import Foundation

// MARK: - Launch Agent Installation Support

extension LaunchAgentOptions {
    func propertyList() -> [String: Any] {
        var propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": [toolExecutablePath, "serve"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "WorkingDirectory": workingDirectory,
            "StandardOutPath": standardOutPath,
            "StandardErrorPath": standardErrorPath,
        ]

        let layout = ServerInstallLayout.defaultForCurrentUser(launchAgentLabel: label)
        let environmentVariables = layout.launchAgentEnvironmentVariables(
            configFilePath: effectiveConfigFilePath(layout: layout),
            reloadIntervalSeconds: reloadIntervalSeconds,
        )
        .merging(
            [
                "SPEAKSWIFTLY_PROFILE_ROOT": profileRootPath,
                LaunchAgentDefaults.defaultProfileEnvironmentKey: LaunchAgentDefaults.defaultProfileRawValue,
            ],
        ) { _, rhs in rhs }
        if !environmentVariables.isEmpty {
            propertyList["EnvironmentVariables"] = environmentVariables
        }

        return propertyList
    }

    func propertyListData() throws -> Data {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: propertyList(),
                format: .xml,
                options: 0,
            )
        } catch {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not encode the LaunchAgent property list for label '\(label)'. Likely cause: \(error.localizedDescription)",
            )
        }
    }

    func install() throws {
        let layout = ServerInstallLayout.defaultForCurrentUser(launchAgentLabel: label)
        try ensureParentDirectory(for: plistPath)
        try FileManager.default.createDirectory(atPath: profileRootPath, withIntermediateDirectories: true)
        try ensureParentDirectory(for: standardOutPath)
        try ensureParentDirectory(for: standardErrorPath)
        try prepareLaunchAgentConfig(layout: layout)
        let propertyListData = try propertyListData()

        try prepareStagedArtifactIfNeeded()

        try propertyListData.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistPath)

        let status = LaunchAgentStatusOptions(
            label: label,
            plistPath: plistPath,
            launchctlPath: launchctlPath,
            userDomain: userDomain,
        )
        if try status.isLoaded() {
            try status.unloadLoadedService()
        }

        try bootstrapInstalledService()
        print(
            """
            Installed LaunchAgent '\(label)' at '\(plistPath)' and bootstrapped it into '\(userDomain)'.
            Active tool executable: \(toolExecutableActivationSummary())
            """,
        )
        ToolLog.launchAgent.notice(
            """
            Installed LaunchAgent '\(self.label, privacy: .public)' at '\(self.plistPath, privacy: .public)' \
            and bootstrapped it into '\(self.userDomain, privacy: .public)'. \
            Active tool executable: \(self.toolExecutablePath, privacy: .public)
            """,
        )
    }

    private func prepareStagedArtifactIfNeeded() throws {
        let stagingResult: ReleaseArtifactPromotionResult
        switch stagedArtifactPolicy {
            case .useExistingExecutable:
                return

            case let .promoteCurrentCheckout(repositoryRootPath):
                stagingResult = try ReleaseArtifactPromoter.promoteLive(
                    repositoryRootPath: repositoryRootPath,
                    stagedExecutablePath: toolExecutablePath,
                )

            case let .custom(promote):
                stagingResult = try promote()
        }

        print(
            """
            Staged current release artifact from '\(stagingResult.builtExecutablePath)' to '\(stagingResult.stagedExecutablePath)'.
            Refreshed staged metallib at '\(stagingResult.stagedMetallibPath)'.
            Refreshed staged code signature for '\(stagingResult.stagedExecutablePath)'.
            """,
        )
        ToolLog.launchAgent.notice(
            """
            Staged current release artifact from '\(stagingResult.builtExecutablePath, privacy: .public)' \
            to '\(stagingResult.stagedExecutablePath, privacy: .public)' with metallib \
            '\(stagingResult.stagedMetallibPath, privacy: .public)'.
            """,
        )
    }

    func toolExecutableActivationSummary() -> String {
        let fileURL = URL(fileURLWithPath: toolExecutablePath)
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modifiedAt = attributes?[.modificationDate] as? Date
        guard let modifiedAt else {
            return "'\(toolExecutablePath)' (last modified time unavailable)"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "'\(toolExecutablePath)' (last modified \(formatter.string(from: modifiedAt)))"
    }

    private func bootstrapInstalledService() throws {
        for attempt in 0..<launchAgentBootstrapRetryCount {
            let result = try runLaunchctl(
                arguments: ["bootstrap", userDomain, plistPath],
                allowNonZeroExit: true,
                launchctlPath: launchctlPath,
            )
            if result.exitCode == 0 {
                return
            }

            guard shouldRetryLaunchAgentBootstrap(result), attempt < launchAgentBootstrapRetryCount - 1 else {
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) asked launchctl to run `bootstrap \(userDomain) \(plistPath)`, but launchctl exited with status \(result.exitCode). stderr: \(result.standardError)",
                )
            }

            usleep(launchAgentGraceIntervalMicroseconds)
        }
    }

    private func ensureParentDirectory(for path: String) throws {
        let directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not create the directory '\(directoryURL.path)' needed for LaunchAgent support. Likely cause: \(error.localizedDescription)",
            )
        }
    }

    func effectiveConfigFilePath(layout: ServerInstallLayout) -> String {
        if let configFilePath, !configFilePath.isEmpty {
            return URL(fileURLWithPath: configFilePath).standardizedFileURL.path
        }

        return layout.serverConfigFileURL.standardizedFileURL.path
    }

    func prepareLaunchAgentConfig(layout: ServerInstallLayout) throws {
        let effectiveConfigURL = URL(fileURLWithPath: effectiveConfigFilePath(layout: layout)).standardizedFileURL
        let canonicalConfigURL = layout.serverConfigFileURL.standardizedFileURL

        if effectiveConfigURL.path == canonicalConfigURL.path {
            _ = try DefaultServerConfig.seedIfMissing(at: canonicalConfigURL)
            return
        }

        guard FileManager.default.fileExists(atPath: effectiveConfigURL.path) else {
            throw LaunchAgentCommandError(
                """
                \(speakSwiftlyServerToolName) could not install the LaunchAgent because the explicit config file '\(effectiveConfigURL.path)' does not exist.
                Use the default Application Support config at '\(canonicalConfigURL.path)' to allow automatic seeding, or create the explicit config file before installing.
                """,
            )
        }
    }
}
