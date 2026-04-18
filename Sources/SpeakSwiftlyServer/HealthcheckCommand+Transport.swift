import Foundation

// MARK: - Healthcheck Transport Support

extension SpeakSwiftlyServerHealthcheck {
    func extractInitializePayload(from response: RawHTTPResponse) throws -> Data {
        if response.httpResponse.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
            let bodyText = String(decoding: response.body, as: UTF8.self)
            for line in bodyText.split(separator: "\n") {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLine.hasPrefix("data:") else { continue }

                let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                guard payload.isEmpty == false, payload.first == "{" else { continue }

                return Data(payload.utf8)
            }

            throw HealthcheckCommandError(
                "SpeakSwiftlyServer MCP initialize returned an event stream, but the stream did not contain a JSON payload event. Body: \(response.bodyPreview)",
            )
        }

        return response.body
    }

    func endpointURL(path: String) -> URL {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return options.baseURL.appending(path: trimmedPath)
    }

    func performJSONRequest<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        responseType: Response.Type,
    ) async throws -> DecodedHTTPResponse<Response> {
        let response = try await performRawRequest(
            path: path,
            method: method,
            body: body,
            contentType: body == nil ? nil : "application/json",
        )

        do {
            let value = try JSONDecoder().decode(Response.self, from: response.body)
            return .init(
                statusCode: response.statusCode,
                value: value,
                bodyPreview: response.bodyPreview,
            )
        } catch {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck could not decode the JSON response from '\(endpointURL(path: path).absoluteString)'. Likely cause: \(error.localizedDescription). Body: \(response.bodyPreview)",
            )
        }
    }

    func performRequiredJSONRequest<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        responseType: Response.Type,
        expectedStatus: Int,
        failureContext: String,
    ) async throws -> Response {
        let response = try await performJSONRequest(
            path: path,
            method: method,
            body: body,
            responseType: responseType,
        )
        guard response.statusCode == expectedStatus else {
            throw HealthcheckCommandError(
                "\(failureContext) reached '\(endpointURL(path: path).absoluteString)', but the service reported HTTP \(response.statusCode) instead of \(expectedStatus). Body: \(response.bodyPreview)",
            )
        }

        return response.value
    }

    func performRawRequest(
        path: String,
        method: String,
        body: Data?,
        contentType: String?,
        acceptHeader: String? = nil,
    ) async throws -> RawHTTPResponse {
        var request = URLRequest(url: endpointURL(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = options.timeoutSeconds
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let acceptHeader {
            request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        }

        let session = URLSession(configuration: .ephemeral)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck could not reach '\(request.url?.absoluteString ?? path)'. Likely cause: \(error.localizedDescription)",
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck reached '\(request.url?.absoluteString ?? path)', but the response was not an HTTP response.",
            )
        }

        return .init(httpResponse: httpResponse, body: data)
    }
}

// MARK: - Healthcheck Transport Models

struct DecodedHTTPResponse<Response> {
    let statusCode: Int
    let value: Response
    let bodyPreview: String
}

struct RawHTTPResponse {
    let httpResponse: HTTPURLResponse
    let body: Data

    var statusCode: Int { httpResponse.statusCode }

    var bodyPreview: String {
        let text = String(decoding: body.prefix(400), as: UTF8.self)
        return text.isEmpty ? "<empty>" : text
    }
}

struct HealthcheckHealthSnapshot: Decodable {
    let status: String
    let serverMode: String
    let workerStage: String
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case serverMode = "server_mode"
        case workerStage = "worker_stage"
        case workerReady = "worker_ready"
    }
}

struct HealthcheckHostSnapshot: Decodable {
    let defaultVoiceProfileName: String?
    let transports: [HealthcheckTransportSnapshot]

    enum CodingKeys: String, CodingKey {
        case defaultVoiceProfileName = "default_voice_profile_name"
        case transports
    }
}

struct HealthcheckTransportSnapshot: Decodable {
    let name: String
    let state: String
}

struct MCPInitializeResult {
    let sessionID: String
    let protocolVersion: String
}
