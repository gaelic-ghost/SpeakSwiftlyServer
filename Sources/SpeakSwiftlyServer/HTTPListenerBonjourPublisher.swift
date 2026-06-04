import Foundation
import SSSCore

package actor HTTPListenerBonjourPublisher {
    private let serviceName: String
    private let type: String
    private let domain: String
    private var service: NetService?

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
    }

    package func stop() {
        service?.stop()
        service = nil
    }
}
