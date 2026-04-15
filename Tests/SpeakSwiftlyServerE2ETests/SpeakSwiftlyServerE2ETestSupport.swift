import Foundation
import Testing

// MARK: - E2ETransport

enum E2ETransport {
    case http
    case mcp

    var profilePrefix: String {
        switch self {
            case .http:
                "http"
            case .mcp:
                "mcp"
        }
    }
}

// MARK: - CloneTranscriptMode

enum CloneTranscriptMode {
    case provided
    case inferred

    var slug: String {
        switch self {
            case .provided:
                "provided-transcript"
            case .inferred:
                "inferred-transcript"
        }
    }

    var providedTranscript: String? {
        switch self {
            case .provided:
                ServerE2E.testingCloneSourceText
            case .inferred:
                nil
        }
    }

    var expectTranscription: Bool {
        switch self {
            case .provided:
                false
            case .inferred:
                true
        }
    }
}

// MARK: - ServerE2ESandbox

struct ServerE2ESandbox {
    let rootURL: URL
    let profileRootURL: URL

    init() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftlyServer-E2E-\(UUID().uuidString)", isDirectory: true)
        profileRootURL = rootURL.appendingPathComponent("profiles", isDirectory: true)

        try FileManager.default.createDirectory(at: profileRootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
