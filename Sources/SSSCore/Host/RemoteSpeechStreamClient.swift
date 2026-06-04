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
    String,
) -> RemoteSpeechStreamSession

package struct RemoteSpeechStreamSession {
    package let chunks: SpeakSwiftly.GeneratedAudioChunkStream
    package let cancelUpstream: @Sendable () async throws -> Void

    package init(
        chunks: SpeakSwiftly.GeneratedAudioChunkStream,
        cancelUpstream: @escaping @Sendable () async throws -> Void = {},
    ) {
        self.chunks = chunks
        self.cancelUpstream = cancelUpstream
    }
}

package enum RemoteSpeechStreamClient {
    package static func stream(
        request: RemoteSpeechStreamRequest,
        service: RemoteGenerationService,
        sharedToken: String,
        session: URLSession = .shared,
    ) -> RemoteSpeechStreamSession {
        let cancellation = RemoteSpeechStreamCancellation()
        let chunks = AsyncThrowingStream<SpeakSwiftly.GeneratedAudioChunk, Error> { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeURLRequest(
                        request: request,
                        service: service,
                        sharedToken: sharedToken,
                    )
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

                    if let upstreamRequestID = httpResponse.value(forHTTPHeaderField: "X-SpeakSwiftly-Request-ID"),
                       !upstreamRequestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await cancellation.recordUpstreamRequestID(upstreamRequestID)
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

            Task {
                await cancellation.recordStreamTask(task)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        return RemoteSpeechStreamSession(
            chunks: chunks,
            cancelUpstream: {
                guard let upstreamRequestID = await cancellation.cancelAndReturnUpstreamRequestID() else {
                    return
                }

                try await cancelRemoteRequest(
                    requestID: upstreamRequestID,
                    service: service,
                    sharedToken: sharedToken,
                    session: session,
                )
            },
        )
    }

    private static func makeURLRequest(
        request: RemoteSpeechStreamRequest,
        service: RemoteGenerationService,
        sharedToken: String,
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
        urlRequest.setValue(sharedToken, forHTTPHeaderField: RemoteGenerationConfig.streamTokenHeaderName)
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }

    private static func cancelRemoteRequest(
        requestID: String,
        service: RemoteGenerationService,
        sharedToken: String,
        session: URLSession,
    ) async throws {
        guard let baseURL = URL(string: service.baseURL) else {
            throw SpeakSwiftly.Error(
                code: .invalidRequest,
                message: "SpeakSwiftlyServer cannot cancel remote generation request '\(requestID)' because '\(service.baseURL)' is not a valid remote server base URL.",
            )
        }

        let endpointURL = baseURL
            .appending(path: "requests")
            .appending(path: requestID)
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue(sharedToken, forHTTPHeaderField: RemoteGenerationConfig.streamTokenHeaderName)

        let (_, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftlyServer remote cancellation request for upstream request '\(requestID)' at '\(service.baseURL)' did not return an HTTP response.",
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftlyServer remote cancellation request for upstream request '\(requestID)' at '\(service.baseURL)' returned HTTP \(httpResponse.statusCode). Likely cause: the remote server already completed, does not know the request id, or rejected the shared token.",
            )
        }
    }
}

private actor RemoteSpeechStreamCancellation {
    private var upstreamRequestID: String?
    private var streamTask: Task<Void, Never>?
    private var cancellationRequested = false

    func recordStreamTask(_ task: Task<Void, Never>) {
        streamTask = task
        if cancellationRequested {
            task.cancel()
        }
    }

    func recordUpstreamRequestID(_ requestID: String) {
        upstreamRequestID = requestID
    }

    func cancelAndReturnUpstreamRequestID() -> String? {
        cancellationRequested = true
        streamTask?.cancel()
        return upstreamRequestID
    }
}
