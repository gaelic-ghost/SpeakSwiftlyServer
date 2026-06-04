import Foundation

package extension ServerHost {
    func configureHTTPListenerRuntimeControl(_ control: HTTPListenerRuntimeControl) {
        httpListenerRuntimeControl = control
    }

    func enableHTTPListener(_ listener: HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot {
        guard let httpListenerRuntimeControl else {
            throw ServerRequestError(
                .serviceUnavailable,
                message: "SpeakSwiftlyServer cannot enable the \(listener.rawValue) HTTP listener because this host was started without runtime listener control support. Likely cause: the server is running in a test or custom embedding mode that did not install the listener controller.",
            )
        }

        return try await httpListenerRuntimeControl.enable(listener)
    }

    func disableHTTPListener(_ listener: HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot {
        guard let httpListenerRuntimeControl else {
            throw ServerRequestError(
                .serviceUnavailable,
                message: "SpeakSwiftlyServer cannot disable the \(listener.rawValue) HTTP listener because this host was started without runtime listener control support. Likely cause: the server is running in a test or custom embedding mode that did not install the listener controller.",
            )
        }

        return try await httpListenerRuntimeControl.disable(listener)
    }
}
