import Foundation
import SpeakSwiftly

public struct NetworkAudioEndpointSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case kind
        case host
        case port
        case name
        case type
        case domain
    }

    public let kind: String
    public let host: String?
    public let port: UInt16?
    public let name: String?
    public let type: String?
    public let domain: String?

    package var endpoint: SpeakSwiftly.NetworkAudioEndpoint? {
        switch kind {
            case "host_port":
                guard let host, let port else { return nil }

                return SpeakSwiftly.NetworkAudioEndpoint(host: host, port: port)
            case "bonjour_service":
                guard let name else { return nil }

                return SpeakSwiftly.NetworkAudioEndpoint(
                    serviceName: name,
                    type: type ?? SpeakSwiftly.NetworkAudioBonjour.serviceType,
                    domain: domain ?? SpeakSwiftly.NetworkAudioBonjour.domain,
                )
            default:
                return nil
        }
    }

    package init(endpoint: SpeakSwiftly.NetworkAudioEndpoint) {
        switch endpoint {
            case let .hostPort(host, port):
                kind = "host_port"
                self.host = host
                self.port = port
                name = nil
                type = nil
                domain = nil
            case let .bonjourService(name, type, domain):
                kind = "bonjour_service"
                host = nil
                port = nil
                self.name = name
                self.type = type
                self.domain = domain
        }
    }
}

public struct NetworkAudioCapabilitiesSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case sampleFormats = "sample_formats"
        case sampleRates = "sample_rates"
        case channelCounts = "channel_counts"
    }

    public let protocolVersion: Int
    public let sampleFormats: [String]
    public let sampleRates: [Int]
    public let channelCounts: [Int]

    package init(capabilities: SpeakSwiftly.NetworkAudioCapabilities) {
        protocolVersion = capabilities.protocolVersion
        sampleFormats = capabilities.sampleFormats.map(\.rawValue)
        sampleRates = capabilities.sampleRates
        channelCounts = capabilities.channelCounts
    }
}

public struct NetworkAudioDestinationSnapshot: Codable, Sendable, Equatable, Identifiable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case endpoint
        case capabilities
        case lastSeen = "last_seen"
    }

    public let id: String
    public let name: String
    public let endpoint: NetworkAudioEndpointSnapshot
    public let capabilities: NetworkAudioCapabilitiesSnapshot
    public let lastSeen: String

    package init(destination: SpeakSwiftly.NetworkAudioDestination) {
        id = destination.id
        name = destination.name
        endpoint = .init(endpoint: destination.endpoint)
        capabilities = .init(capabilities: destination.capabilities)
        lastSeen = TimestampFormatter.string(from: destination.lastSeen)
    }
}

public struct NetworkAudioReceiverSelectionSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case selectedDestinationID = "selected_destination_id"
        case selectedDestination = "selected_destination"
        case availableDestinationCount = "available_destination_count"
        case sharedTokenConfigured = "shared_token_configured"
        case selectedDestinationEndpointReady = "selected_destination_endpoint_ready"
        case lanOutputReady = "lan_output_ready"
        case lanOutputBlockedReasons = "lan_output_blocked_reasons"
    }

    public let selectedDestinationID: String?
    public let selectedDestination: NetworkAudioDestinationSnapshot?
    public let availableDestinationCount: Int
    public let sharedTokenConfigured: Bool
    public let selectedDestinationEndpointReady: Bool
    public let lanOutputReady: Bool
    public let lanOutputBlockedReasons: [String]
}

public struct NetworkAudioReceiverSelectionResponse: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case selection
        case message
    }

    public let selection: NetworkAudioReceiverSelectionSnapshot
    public let message: String
}

public struct NetworkAudioReceiverSmokeTestResponse: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case destinationID = "destination_id"
        case destinationName = "destination_name"
        case sampleRate = "sample_rate"
        case channelCount = "channel_count"
        case sentChunkCount = "sent_chunk_count"
        case message
    }

    public let requestID: String
    public let destinationID: String
    public let destinationName: String
    public let sampleRate: Int
    public let channelCount: Int
    public let sentChunkCount: Int
    public let message: String
}

public struct NetworkAudioReceiverSelectionPayload: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case destinationID = "destination_id"
        case endpoint
        case name
    }

    package let destinationID: String?
    package let endpoint: NetworkAudioEndpointSnapshot?
    package let name: String?
}

package enum NetworkAudioDiscoveryTransport {
    package static let name = "network_audio_discovery"
}
