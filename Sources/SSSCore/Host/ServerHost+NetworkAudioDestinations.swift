import Foundation
import SpeakSwiftly

package extension ServerHost {
    static var networkAudioSmokeTestSampleRate: Int { 24000 }
    static var networkAudioSmokeTestChannelCount: Int { 1 }
    static var networkAudioSmokeTestSentChunkCount: Int { 2 }

    func replaceNetworkAudioDestinations(_ destinations: [SpeakSwiftly.NetworkAudioDestination]) async {
        let snapshots = destinations.map(NetworkAudioDestinationSnapshot.init(destination:))
        let manualSnapshots = networkAudioDestinations.filter(\.isManualNetworkAudioDestination)
        let knownIDs = Set((snapshots + manualSnapshots).map(\.id))
        networkAudioDestinations = snapshots + manualSnapshots.filter { manualSnapshot in
            !snapshots.contains { $0.id == manualSnapshot.id }
        }
        if let selectedNetworkAudioDestinationID, !knownIDs.contains(selectedNetworkAudioDestinationID) {
            self.selectedNetworkAudioDestinationID = nil
        }
        hostEventContinuation.yield(.networkAudioDestinationsChanged(networkAudioReceiverSelectionSnapshot()))
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    func networkAudioDestinationSnapshots() -> [NetworkAudioDestinationSnapshot] {
        networkAudioDestinations
    }

    func networkAudioReceiverSelectionSnapshot() -> NetworkAudioReceiverSelectionSnapshot {
        let selectedDestination = selectedNetworkAudioDestinationID.flatMap { id in
            networkAudioDestinations.first { $0.id == id }
        }
        let sharedTokenConfigured = networkAudioReceiverSharedTokenConfigured()
        let selectedDestinationEndpointReady = selectedDestination?.endpoint.endpoint != nil
        let lanOutputBlockedReasons = networkAudioReceiverLanOutputBlockedReasons(
            selectedDestination: selectedDestination,
            selectedDestinationEndpointReady: selectedDestinationEndpointReady,
            sharedTokenConfigured: sharedTokenConfigured,
        )
        return .init(
            selectedDestinationID: selectedNetworkAudioDestinationID,
            selectedDestination: selectedDestination,
            availableDestinationCount: networkAudioDestinations.count,
            sharedTokenConfigured: sharedTokenConfigured,
            selectedDestinationEndpointReady: selectedDestinationEndpointReady,
            lanOutputReady: lanOutputBlockedReasons.isEmpty,
            lanOutputBlockedReasons: lanOutputBlockedReasons,
        )
    }

    func networkAudioReceiverSharedTokenConfigured() -> Bool {
        networkAudioReceiverConfig.sharedToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func networkAudioReceiverLanOutputBlockedReasons(
        selectedDestination: NetworkAudioDestinationSnapshot?,
        selectedDestinationEndpointReady: Bool,
        sharedTokenConfigured: Bool,
    ) -> [String] {
        var reasons = [String]()

        if selectedNetworkAudioDestinationID == nil {
            reasons.append("no_lan_audio_receiver_selected")
        } else if selectedDestination == nil {
            reasons.append("selected_lan_audio_receiver_unavailable")
        } else if !selectedDestinationEndpointReady {
            reasons.append("selected_lan_audio_receiver_endpoint_incomplete")
        }

        if !sharedTokenConfigured {
            reasons.append("network_audio_receiver_shared_token_missing")
        }

        return reasons
    }

    func selectNetworkAudioDestination(id: String) async throws -> NetworkAudioReceiverSelectionResponse {
        guard networkAudioDestinations.contains(where: { $0.id == id }) else {
            throw ServerRequestError(
                .notFound,
                message: "SpeakSwiftlyServer could not select LAN audio receiver destination '\(id)' because Bonjour discovery has not reported that receiver. Read /network-audio/destinations and choose one of the returned destination_id values.",
            )
        }

        selectedNetworkAudioDestinationID = id
        let selection = networkAudioReceiverSelectionSnapshot()
        hostEventContinuation.yield(.networkAudioDestinationsChanged(selection))
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        let readiness = if selection.lanOutputReady {
            "LAN output is ready for remote generation audio."
        } else {
            "LAN output is not ready yet. Blocked reason(s): \(selection.lanOutputBlockedReasons.joined(separator: ", "))."
        }
        return .init(
            selection: selection,
            message: "SpeakSwiftlyServer selected LAN audio receiver destination '\(id)'. \(readiness)",
        )
    }

    func selectNetworkAudioDestination(
        endpoint: SpeakSwiftly.NetworkAudioEndpoint,
        name: String?,
    ) async throws -> NetworkAudioReceiverSelectionResponse {
        let destination = SpeakSwiftly.NetworkAudioDestination(
            id: endpoint.manualNetworkAudioDestinationID,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Manual LAN Audio Receiver",
            endpoint: endpoint,
            capabilities: .init(),
            lastSeen: Date(),
        )
        let snapshot = NetworkAudioDestinationSnapshot(destination: destination)
        networkAudioDestinations.removeAll { $0.id == snapshot.id }
        networkAudioDestinations.append(snapshot)
        selectedNetworkAudioDestinationID = snapshot.id
        let selection = networkAudioReceiverSelectionSnapshot()
        hostEventContinuation.yield(.networkAudioDestinationsChanged(selection))
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        let readiness = if selection.lanOutputReady {
            "LAN output is ready for remote generation audio."
        } else {
            "LAN output is not ready yet. Blocked reason(s): \(selection.lanOutputBlockedReasons.joined(separator: ", "))."
        }
        return .init(
            selection: selection,
            message: "SpeakSwiftlyServer selected manual LAN audio receiver endpoint '\(snapshot.id)'. \(readiness)",
        )
    }

    func clearNetworkAudioDestinationSelection() async -> NetworkAudioReceiverSelectionResponse {
        selectedNetworkAudioDestinationID = nil
        let selection = networkAudioReceiverSelectionSnapshot()
        hostEventContinuation.yield(.networkAudioDestinationsChanged(selection))
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(
            selection: selection,
            message: "SpeakSwiftlyServer cleared the selected LAN audio receiver destination.",
        )
    }

    func smokeTestSelectedNetworkAudioDestination() async throws -> NetworkAudioReceiverSmokeTestResponse {
        let selection = networkAudioReceiverSelectionSnapshot()
        guard selection.lanOutputReady else {
            throw ServerRequestError(
                .badRequest,
                message: "SpeakSwiftlyServer cannot smoke-test LAN audio output because the selected receiver is not ready. Blocked reason(s): \(selection.lanOutputBlockedReasons.joined(separator: ", ")).",
            )
        }
        guard let destination = selection.selectedDestination else {
            throw ServerRequestError(
                .badRequest,
                message: "SpeakSwiftlyServer cannot smoke-test LAN audio output because no selected LAN audio receiver destination is available.",
            )
        }

        let requestID = "network-audio-smoke-\(UUID().uuidString)"
        do {
            try await sendRemoteGeneratedAudio(
                chunks: Self.networkAudioSmokeTestChunks(requestID: requestID),
                requestID: requestID,
                destination: destination,
            )
        } catch {
            let message = Self.networkAudioSmokeTestFailureMessage(
                requestID: requestID,
                destinationName: destination.name,
                error: error,
            )
            recordRecentError(
                source: "network_audio_smoke_test",
                code: "send_failed",
                message: message,
            )
            throw ServerRequestError(.serviceUnavailable, message: message)
        }

        return .init(
            requestID: requestID,
            destinationID: destination.id,
            destinationName: destination.name,
            sampleRate: Self.networkAudioSmokeTestSampleRate,
            channelCount: Self.networkAudioSmokeTestChannelCount,
            sentChunkCount: Self.networkAudioSmokeTestSentChunkCount,
            message: "SpeakSwiftlyServer sent a silent LAN audio smoke-test stream to selected receiver '\(destination.name)'.",
        )
    }

    static func networkAudioSmokeTestChunks(requestID: String) -> SpeakSwiftly.GeneratedAudioChunkStream {
        AsyncThrowingStream { continuation in
            continuation.yield(SpeakSwiftly.GeneratedAudioChunk(
                requestID: requestID,
                sequenceNumber: 0,
                sampleRate: networkAudioSmokeTestSampleRate,
                channelCount: networkAudioSmokeTestChannelCount,
                samples: Array(repeating: 0, count: 1200),
            ))
            continuation.yield(SpeakSwiftly.GeneratedAudioChunk(
                requestID: requestID,
                sequenceNumber: 1,
                sampleRate: networkAudioSmokeTestSampleRate,
                channelCount: networkAudioSmokeTestChannelCount,
                samples: [],
                isFinal: true,
            ))
            continuation.finish()
        }
    }

    static func networkAudioSmokeTestFailureMessage(
        requestID: String,
        destinationName: String,
        error: any Error,
    ) -> String {
        let description = error.localizedDescription
        let privacyHint = networkAudioLocalNetworkPrivacyHint(for: description).map { " \($0)" } ?? ""
        return "SpeakSwiftlyServer could not send LAN audio receiver smoke-test request '\(requestID)' " +
            "to selected receiver '\(destinationName)'. Likely cause: \(description)\(privacyHint)"
    }

    static func networkAudioLocalNetworkPrivacyHint(for errorDescription: String) -> String? {
        let lowercasedDescription = errorDescription.lowercased()
        guard lowercasedDescription.contains("network is down") ||
            lowercasedDescription.contains("posixerrorcode(rawvalue: 50)") ||
            lowercasedDescription.contains("local network prohibited")
        else {
            return nil
        }

        return "On macOS, this can mean Local Network privacy is blocking the LaunchAgent-hosted " +
            "SpeakSwiftlyServer process from reaching another Mac on the LAN. Check System Settings > " +
            "Privacy & Security > Local Network for the server's install surface, or run the " +
            "receiver/sender through an app or plugin bundle that declares LAN access."
    }
}

private extension NetworkAudioDestinationSnapshot {
    var isManualNetworkAudioDestination: Bool {
        id.hasPrefix("manual-host-port:") || id.hasPrefix("manual-bonjour:")
    }
}

private extension SpeakSwiftly.NetworkAudioEndpoint {
    var manualNetworkAudioDestinationID: String {
        switch self {
            case let .hostPort(host, port):
                "manual-host-port:\(host):\(port)"
            case let .bonjourService(name, type, domain):
                "manual-bonjour:\(name).\(type).\(domain)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
