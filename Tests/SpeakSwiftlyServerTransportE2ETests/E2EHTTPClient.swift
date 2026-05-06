import Foundation

// MARK: - E2EHTTPClient

struct E2EHTTPClient {
    let baseURL: URL
    private let requestTimeout: TimeInterval = 120

    func request(
        path: String,
        method: String,
        jsonBody: [String: Any]? = nil,
    ) async throws -> E2EHTTPResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw E2ETransportError("The live HTTP request to '\(path)' did not return an HTTPURLResponse.")
        }

        return E2EHTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, data: data)
    }
}

// MARK: - E2EHTTPResponse

struct E2EHTTPResponse {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let data: Data

    var text: String {
        String(decoding: data, as: UTF8.self)
    }
}
