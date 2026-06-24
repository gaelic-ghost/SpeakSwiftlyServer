import MCP
import SSSCore

// MARK: - Subscription Handling

package actor MCPSubscriptionBroker {
    enum ResourceChange {
        case runtimeOverview
    }

    private var subscribedResourceURIs = Set<String>()
    private var eventTask: Task<Void, Never>?
    private var host: ServerHost?
    private var server: Server?

    func start(host: ServerHost, server: Server) {
        self.host = host
        self.server = server
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        host = nil
        server = nil
        subscribedResourceURIs.removeAll()
    }

    func subscribe(to uri: String) {
        subscribedResourceURIs.insert(uri)
        startEventTaskIfNeeded()
    }

    func unsubscribe(from uri: String) {
        subscribedResourceURIs.remove(uri)
        if subscribedResourceURIs.isEmpty {
            eventTask?.cancel()
            eventTask = nil
        }
    }

    func notifyResourceChanges(
        for change: ResourceChange,
        using server: Server,
    ) async {
        await notifySubscribedURIs(candidateURIs(for: change), using: server)
    }

    private func notifySubscribedURIs(
        _ uris: [String],
        using server: Server,
    ) async {
        for uri in uris {
            do {
                try await server.notify(ResourceUpdatedNotification.message(.init(uri: uri)))
            } catch {
                continue
            }
        }
    }

    private func startEventTaskIfNeeded() {
        guard eventTask == nil, subscribedResourceURIs.isEmpty == false, let host, let server else {
            return
        }

        let updates = Task { await host.eventUpdates() }
        eventTask = Task {
            let events = await updates.value
            for await event in events {
                if Task.isCancelled {
                    break
                }
                let updatedURIs = self.resourceURIsToNotify(for: event)
                guard updatedURIs.isEmpty == false else {
                    continue
                }

                await self.notifySubscribedURIs(updatedURIs, using: server)
            }
        }
    }

    private func resourceURIsToNotify(for event: HostEvent) -> [String] {
        let candidateURIs: Set<String> = switch event {
            case .transportChanged, .recentErrorRecorded:
                ["speak-swiftly://overview"]
            case .playbackChanged:
                [
                    "speak-swiftly://overview",
                    "speak-swiftly://playback",
                ]
            case .jobEvent:
                []
            case let .jobChanged(snapshot):
                [
                    "speak-swiftly://overview",
                    "speak-swiftly://requests/\(snapshot.requestID)",
                ]
            case .profileCacheChanged:
                [
                    "speak-swiftly://overview",
                    "speak-swiftly://voices",
                ]
            case .textProfilesChanged:
                ["speak-swiftly://text-profiles"]
            case .runtimeConfigurationChanged:
                ["speak-swiftly://overview"]
            case .networkAudioDestinationsChanged:
                ["speak-swiftly://overview"]
        }
        return candidateURIs
            .intersection(subscribedResourceURIs)
            .sorted()
    }

    private func candidateURIs(for change: ResourceChange) -> [String] {
        let candidateURIs: Set<String> = switch change {
            case .runtimeOverview:
                ["speak-swiftly://overview"]
        }
        return candidateURIs.intersection(subscribedResourceURIs).sorted()
    }
}
