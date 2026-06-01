import Foundation

@MainActor
package protocol ServerHostStatePublishing: AnyObject, Sendable {
    var overview: HostOverviewSnapshot { get set }
    var generationQueue: QueueStatusSnapshot { get set }
    var playbackQueue: QueueStatusSnapshot { get set }
    var playback: PlaybackStatusSnapshot { get set }
    var runtimeRefresh: RuntimeRefreshSnapshot? { get set }
    var runtimeBackendTransition: RuntimeBackendTransitionSnapshot { get set }
    var currentGenerationJobs: [CurrentGenerationJobSnapshot] { get set }
    var runtimeConfiguration: RuntimeConfigurationSnapshot { get set }
    var voiceProfiles: [ProfileSnapshot] { get set }
    var transports: [TransportStatusSnapshot] { get set }
    var networkAudioDestinations: [NetworkAudioDestinationSnapshot] { get set }
    var networkAudioReceiverSelection: NetworkAudioReceiverSelectionSnapshot { get set }
    var recentErrors: [RecentErrorSnapshot] { get set }
}
