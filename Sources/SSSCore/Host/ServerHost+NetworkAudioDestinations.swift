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
        return .init(
            selectedDestinationID: selectedNetworkAudioDestinationID,
            selectedDestination: selectedDestination,
            availableDestinationCount: networkAudioDestinations.count,
        )
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
        return .init(
            selection: selection,
            message: "SpeakSwiftlyServer selected LAN audio receiver destination '\(id)'. Remote playback request routing is not active yet; the selected receiver is retained for the next package-backed routing slice.",
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
