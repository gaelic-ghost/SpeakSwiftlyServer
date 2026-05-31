import Foundation

package struct ServerRequestError: Error, LocalizedError {
    package enum Status {
        case badRequest
        case notFound
        case serviceUnavailable
    }

    package let responseStatus: Status
    package let message: String

    package var errorDescription: String? {
        message
    }

    package var httpStatusCode: Int {
        switch responseStatus {
            case .badRequest:
                400
            case .notFound:
                404
            case .serviceUnavailable:
                503
        }
    }

    package init(_ status: Status, message: String) {
        responseStatus = status
        self.message = message
    }
}
