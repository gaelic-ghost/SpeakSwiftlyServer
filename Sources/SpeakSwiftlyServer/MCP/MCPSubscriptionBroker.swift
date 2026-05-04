import MCP

// MARK: - Subscription Handling

actor MCPSubscriptionBroker {
    enum ResourceChange {
        case textProfiles
        case voices
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
            case .transportChanged, .playbackChanged, .recentErrorRecorded:
                ["speak-swiftly://overview"]
            case .jobEvent:
                []
            case let .jobChanged(snapshot):
                [
                    "speak-swiftly://overview",
                    "speak-swiftly://requests",
                    "speak-swiftly://requests/\(snapshot.requestID)",
                ]
            case .profileCacheChanged:
                Set(
                    [
                        "speak-swiftly://overview",
                        "speak-swiftly://voices",
                    ] + subscribedResourceURIs.filter(isVoiceProfileURI),
                )
            case .textProfilesChanged:
                Set(
                    [
                        "speak-swiftly://text-profiles",
                        "speak-swiftly://text-profiles/style",
                        "speak-swiftly://text-profiles/base",
                        "speak-swiftly://text-profiles/active",
                        "speak-swiftly://text-profiles/effective",
                    ] + subscribedResourceURIs.filter(isStoredTextProfileURI)
                        + subscribedResourceURIs.filter(isEffectiveTextProfileURI),
                )
            case .runtimeConfigurationChanged:
                [
                    "speak-swiftly://overview",
                    "speak-swiftly://configuration",
                ]
        }
        return candidateURIs
            .intersection(subscribedResourceURIs)
            .sorted()
    }

    private func candidateURIs(for change: ResourceChange) -> [String] {
        let candidateURIs: Set<String> = switch change {
            case .textProfiles:
                Set(
                    [
                        "speak-swiftly://text-profiles",
                        "speak-swiftly://text-profiles/style",
                        "speak-swiftly://text-profiles/base",
                        "speak-swiftly://text-profiles/active",
                        "speak-swiftly://text-profiles/effective",
                    ] + subscribedResourceURIs.filter(isStoredTextProfileURI)
                        + subscribedResourceURIs.filter(isEffectiveTextProfileURI),
                )
            case .voices:
                Set(
                    [
                        "speak-swiftly://voices",
                        "speak-swiftly://overview",
                    ] + subscribedResourceURIs.filter(isVoiceProfileURI),
                )
            case .runtimeOverview:
                ["speak-swiftly://overview"]
        }
        return candidateURIs.intersection(subscribedResourceURIs).sorted()
    }
}
