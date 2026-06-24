import Foundation
import MCP
import SpeakSwiftly
import SSSCore

private func acceptedRequestToolResult(
    requestID: String,
    message: String,
) throws -> CallTool.Result {
    try toolResult(
        acceptedRequestResult(
            requestID: requestID,
            message: message,
        ),
    )
}

package extension MCPSurface {
    static func registerToolHandlers(
        on server: Server,
        host: ServerHost,
        subscriptionBroker _: MCPSubscriptionBroker,
        clientIdentity: MCPClientIdentity,
    ) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: MCPToolCatalog.definitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = params.arguments ?? [:]
            let requestContextDefaults = await mcpSpeechRequestContextDefaults(
                toolName: params.name,
                clientInfo: clientIdentity.snapshot(),
            )

            switch params.name {
                case "generate_speech":
                    guard let profileName = await host.resolvedRequestedVoiceProfileName(optionalString("profile_name", in: arguments)) else {
                        throw await MCPError.invalidParams(
                            host.missingVoiceProfileNameMessage(for: "the live speech request"),
                        )
                    }

                    let requestID = try await host.queueSpeechLive(
                        text: requiredString("text", in: arguments),
                        profileName: profileName,
                        textProfileID: optionalString("text_profile_id", in: arguments),
                        requestContext: requestContext(
                            in: arguments,
                            defaults: requestContextDefaults,
                        ),
                        qwenPreModelTextChunking: decodeOptionalArgument(
                            "qwen_pre_model_text_chunking",
                            in: arguments,
                            default: false,
                        ),
                        generationLocation: decodeOptionalArgument(
                            "generation_location",
                            in: arguments,
                            default: GenerationLocation.local,
                        ),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the live speech request. Read the returned request resource for progress or read speak-swiftly://overview to monitor generation, playback, and transport state.",
                    )

                default:
                    throw MCPError.methodNotFound(
                        "Tool '\(params.name)' is not registered on this slim SpeakSwiftly MCP surface. Use HTTP for voice profile, text profile, retained generation, playback, runtime, network-audio, queue, cancellation, and artifact workflows.",
                    )
            }
        }
    }
}
