import Hummingbird
import SSSCore

extension ServerRequestError: HTTPResponseError {
    public var status: HTTPResponse.Status {
        switch httpStatusCode {
            case 400:
                .badRequest
            case 404:
                .notFound
            case 503:
                .serviceUnavailable
            default:
                .internalServerError
        }
    }

    public func response(from request: Request, context: some RequestContext) throws -> Response {
        try HTTPError(status, message: message).response(from: request, context: context)
    }
}

extension JobSnapshot: ResponseEncodable {}
extension RequestAcceptedResponse: ResponseEncodable {}
extension RequestListResponse: ResponseEncodable {}
extension RuntimeStatusResponse: ResponseEncodable {}
extension RuntimeBackendResponse: ResponseEncodable {}
extension QueueSnapshotResponse: ResponseEncodable {}
extension PlaybackStateResponse: ResponseEncodable {}
extension QueueClearedResponse: ResponseEncodable {}
extension QueueCancellationResponse: ResponseEncodable {}
extension HealthSnapshot: ResponseEncodable {}
extension ReadinessSnapshot: ResponseEncodable {}
extension StatusSnapshot: ResponseEncodable {}
extension ProfileListResponse: ResponseEncodable {}
extension TextProfilesSnapshot: ResponseEncodable {}
extension TextProfileListResponse: ResponseEncodable {}
extension TextProfileResponse: ResponseEncodable {}
extension TextProfileStyleResponse: ResponseEncodable {}
extension RuntimeConfigurationSnapshot: ResponseEncodable {}
