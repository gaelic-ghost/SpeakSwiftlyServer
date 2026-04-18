import Foundation
import SpeakSwiftly

/// Bridges package-owned startup environment overrides into `SpeakSwiftly.liftoff(...)`.
///
/// `SpeakSwiftly` currently resolves its profile-root override from the process environment during
/// runtime liftoff. The server keeps that process-global mutation serialized and narrowly scoped
/// here so embedded and standalone startup paths can use one explicit startup environment without
/// leaking those overrides across unrelated runtime launches.
actor SpeakSwiftlyRuntimeLauncher {
    static let shared = SpeakSwiftlyRuntimeLauncher()

    private static let bridgedEnvironmentKeys = [
        "SPEAKSWIFTLY_PROFILE_ROOT",
    ]

    private static func environmentOverrides(from environment: [String: String]) -> [String: String?] {
        bridgedEnvironmentKeys.reduce(into: [String: String?]()) { result, key in
            result[key] = environment[key]
        }
    }

    func launch<T: Sendable>(
        configuration: SpeakSwiftly.Configuration,
        environment: [String: String],
        makeRuntime: @escaping @Sendable (SpeakSwiftly.Configuration?) async -> T,
    ) async -> T {
        await withTemporaryEnvironment(overrides: Self.environmentOverrides(from: environment)) {
            await makeRuntime(configuration)
        }
    }

    private func withTemporaryEnvironment<T: Sendable>(
        overrides: [String: String?],
        body: @escaping @Sendable () async -> T,
    ) async -> T {
        let originalValues = captureEnvironmentValues(for: Array(overrides.keys))
        applyEnvironmentValues(overrides)
        let result = await body()
        applyEnvironmentValues(originalValues)
        return result
    }

    private func captureEnvironmentValues(for keys: [String]) -> [String: String?] {
        keys.reduce(into: [String: String?]()) { result, key in
            result[key] = ProcessInfo.processInfo.environment[key]
        }
    }

    private func applyEnvironmentValues(_ values: [String: String?]) {
        for (key, value) in values {
            switch value {
                case let .some(value):
                    setenv(key, value, 1)
                case .none:
                    unsetenv(key)
            }
        }
    }
}
