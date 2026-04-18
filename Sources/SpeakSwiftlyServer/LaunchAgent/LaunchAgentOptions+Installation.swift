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
            configFilePath: configFilePath,
            reloadIntervalSeconds: reloadIntervalSeconds,
        )
        .merging(
            [
                "SPEAKSWIFTLY_PROFILE_ROOT": profileRootPath,
                AppRuntimeDefaultProfile.environmentKey: LaunchAgentDefaults.defaultProfile.rawValue,
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
        try stageLaunchAgentConfigAliasIfNeeded(layout: layout)

        try propertyListData().write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistPath)

        let status = LaunchAgentStatusOptions(
            label: label,
            plistPath: plistPath,
            launchctlPath: launchctlPath,
            userDomain: userDomain,
        )
        if try status.isLoaded() {
            try status.bootoutLoadedService()
            try status.waitUntilNotLoaded()
        }

        try bootstrapInstalledService()
        print(
            """
            Installed LaunchAgent '\(label)' at '\(plistPath)' and bootstrapped it into '\(userDomain)'.
            Active tool executable: \(toolExecutableActivationSummary())
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

    private func stageLaunchAgentConfigAliasIfNeeded(layout: ServerInstallLayout) throws {
        guard let configFilePath, !configFilePath.isEmpty else { return }

        let canonicalConfigURL = URL(fileURLWithPath: configFilePath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: canonicalConfigURL.path) else {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not install the LaunchAgent because the config file '\(canonicalConfigURL.path)' does not exist.",
            )
        }

        let aliasedConfigPath = layout.launchAgentConfigPath(for: canonicalConfigURL.path)
        guard aliasedConfigPath != canonicalConfigURL.path else { return }

        let aliasURL = URL(fileURLWithPath: aliasedConfigPath)
        try ensureParentDirectory(for: aliasURL.path)

        do {
            if FileManager.default.fileExists(atPath: aliasURL.path) {
                try FileManager.default.removeItem(at: aliasURL)
            }
            try FileManager.default.copyItem(at: canonicalConfigURL, to: aliasURL)
        } catch {
            throw LaunchAgentCommandError(
                """
                \(speakSwiftlyServerToolName) could not stage the LaunchAgent config copy at '\(aliasURL.path)' from canonical config '\(canonicalConfigURL.path)'.
                Likely cause: \(error.localizedDescription)
                """,
            )
        }
    }
}
