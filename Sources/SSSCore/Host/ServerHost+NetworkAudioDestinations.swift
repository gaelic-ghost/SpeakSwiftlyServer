import Foundation
import SpeakSwiftly

package extension ServerHost {
    func replaceNetworkAudioDestinations(_ destinations: [SpeakSwiftly.NetworkAudioDestination]) async {
        let snapshots = destinations.map(NetworkAudioDestinationSnapshot.init(destination:))
        let knownIDs = Set(snapshots.map(\.id))
        networkAudioDestinations = snapshots
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
}
