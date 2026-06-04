import Foundation

package enum HTTPListenerRuntimeName: String, Codable, Sendable, CaseIterable {
    case localhost
    case lan

    package var transportName: String {
        switch self {
            case .localhost:
                HTTPListenersConfig.localhostTransportName
            case .lan:
                HTTPListenersConfig.lanTransportName
        }
    }

    package init(pathComponent: String) throws {
        guard let value = Self(rawValue: pathComponent) else {
            throw ServerRequestError(
                .badRequest,
                message: "SpeakSwiftlyServer could not control HTTP listener '\(pathComponent)' because only 'localhost' and 'lan' listeners are supported.",
            )
        }

        self = value
    }
}

package struct HTTPListenerRuntimeControl: Sendable {
    package let enable: @Sendable (HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot
    package let disable: @Sendable (HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot

    package init(
        enable: @escaping @Sendable (HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot,
        disable: @escaping @Sendable (HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot,
    ) {
        self.enable = enable
        self.disable = disable
    }
}
