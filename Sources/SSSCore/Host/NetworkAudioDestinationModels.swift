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
    }

    public let selectedDestinationID: String?
    public let selectedDestination: NetworkAudioDestinationSnapshot?
    public let availableDestinationCount: Int
}

public struct NetworkAudioReceiverSelectionResponse: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case selection
        case message
    }

    public let selection: NetworkAudioReceiverSelectionSnapshot
    public let message: String
}

public struct NetworkAudioReceiverSelectionPayload: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case destinationID = "destination_id"
    }

    package let destinationID: String
}

package enum NetworkAudioDiscoveryTransport {
    package static let name = "network_audio_discovery"
}
