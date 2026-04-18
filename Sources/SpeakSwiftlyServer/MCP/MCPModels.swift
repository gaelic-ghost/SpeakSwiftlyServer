import Foundation

struct MCPAcceptedRequestResult: Codable {
    let requestID: String
    let requestResourceURI: String
    let statusResourceURI: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case requestResourceURI = "request_resource_uri"
        case statusResourceURI = "status_resource_uri"
        case message
    }
}
