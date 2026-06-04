import Foundation
import SSSCore

package actor HTTPListenerBonjourPublisher {
    package struct Snapshot: Sendable, Equatable {
        package let serviceName: String
        package let type: String
        package let domain: String
        package let port: Int
    }

    private let serviceName: String
    private let type: String
    private let domain: String
    private var service: NetService?
    private var publishedSnapshot: Snapshot?

    package init(
        serviceName: String,
        type: String = HTTPListenersConfig.lanBonjourType,
        domain: String = HTTPListenersConfig.bonjourDomain,
    ) {
        self.serviceName = serviceName
        self.type = type
        self.domain = domain
    }

    package func publish(port: Int) {
        stop()
        let service = NetService(
            domain: domain,
            type: type,
            name: serviceName,
            port: Int32(port),
        )
        service.publish()
        self.service = service
        publishedSnapshot = Snapshot(
            serviceName: serviceName,
            type: type,
            domain: domain,
            port: port,
        )
    }

    package func stop() {
        service?.stop()
        service = nil
        publishedSnapshot = nil
    }

    package func snapshot() -> Snapshot? {
        publishedSnapshot
    }
}
