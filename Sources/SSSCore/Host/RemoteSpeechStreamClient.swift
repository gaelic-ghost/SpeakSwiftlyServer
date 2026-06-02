import Foundation
import SpeakSwiftly

package struct RemoteSpeechStreamRequest: Encodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case text
        case profileName = "profile_name"
        case textProfileID = "text_profile_id"
        case requestContext = "request_context"
        case qwenPreModelTextChunking = "qwen_pre_model_text_chunking"
    }

    package let text: String
    package let profileName: String
    package let textProfileID: String?
    package let requestContext: SpeakSwiftly.RequestContext?
    package let qwenPreModelTextChunking: Bool
}

package typealias RemoteGeneratedAudioStreamProvider = @Sendable (
    RemoteSpeechStreamRequest,
    RemoteGenerationService,
) -> SpeakSwiftly.GeneratedAudioChunkStream

package enum RemoteSpeechStreamClient {
    package static func stream(
        request: RemoteSpeechStreamRequest,
        service: RemoteGenerationService,
        session: URLSession = .shared,
    ) -> SpeakSwiftly.GeneratedAudioChunkStream {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(request: request, service: service)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw SpeakSwiftly.Error(
                            code: .internalError,
                            message: "SpeakSwiftlyServer remote generation request to '\(service.baseURL)' did not return an HTTP response.",
                        )
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw SpeakSwiftly.Error(
                            code: .internalError,
                            message: "SpeakSwiftlyServer remote generation request to '\(service.baseURL)' returned HTTP \(httpResponse.statusCode). Likely cause: the remote SpeakSwiftlyServer rejected /speech/stream or is not running the expected release.",
                        )
                    }

                    for try await line in bytes.lines {
                        let chunk = try GeneratedAudioHTTPStreamCodec.decodeLine(line)
                        continuation.yield(chunk)
                        if chunk.isFinal {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func makeURLRequest(
        request: RemoteSpeechStreamRequest,
        service: RemoteGenerationService,
    ) throws -> URLRequest {
        guard let baseURL = URL(string: service.baseURL) else {
            throw SpeakSwiftly.Error(
                code: .invalidRequest,
                message: "SpeakSwiftlyServer cannot route remote generation because '\(service.baseURL)' is not a valid remote server base URL.",
            )
        }

        let endpointURL = baseURL.appending(path: "speech/stream")
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(GeneratedAudioHTTPStreamCodec.contentType, forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }
}
