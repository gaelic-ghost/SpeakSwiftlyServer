import Foundation
import MCP
import SpeakSwiftly
import TextForSpeech

// MARK: - Tool Encoding

func toolResult(_ output: some Encodable) throws -> CallTool.Result {
    let data = try JSONEncoder().encode(output)
    let json = String(decoding: data, as: UTF8.self)
    return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
}

func acceptedRequestResult(requestID: String, message: String) -> MCPAcceptedRequestResult {
    .init(
        requestID: requestID,
        requestResourceURI: "speak-swiftly://requests/\(requestID)",
        statusResourceURI: "speak-swiftly://overview",
        message: message,
    )
}

func supportedRawValuesDescription<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> String
    where T.AllCases: Collection, T.RawValue == String {
    T.allCases.map(\.rawValue).joined(separator: ", ")
}

func decodeStringEnum<T: RawRepresentable & CaseIterable>(
    _ rawValue: String,
    fieldName: String,
    valueType: T.Type,
) throws -> T
    where T.AllCases: Collection, T.RawValue == String {
    guard let value = T(rawValue: rawValue) else {
        throw MCPError.invalidParams(
            "Tool argument '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedRawValuesDescription(T.self)).",
        )
    }

    return value
}

// MARK: - Tool Argument Parsing

func requiredString(_ key: String, in arguments: [String: Value]) throws -> String {
    guard let value = arguments[key]?.stringValue, value.isEmpty == false else {
        throw MCPError.invalidParams(
            "Tool arguments are missing the required string field '\(key)'.",
        )
    }

    return value
}

func optionalString(_ key: String, in arguments: [String: Value]) -> String? {
    guard let value = arguments[key]?.stringValue, value.isEmpty == false else {
        return nil
    }

    return value
}

func optionalRequestCancellationScope(
    _ key: String,
    in arguments: [String: Value],
) throws -> RequestCancellationScope? {
    guard let rawValue = RequestCancellationScope.normalized(optionalString(key, in: arguments)) else {
        return nil
    }

    return try decodeStringEnum(
        rawValue,
        fieldName: key,
        valueType: RequestCancellationScope.self,
    )
}

func decodeArgument<T: Decodable>(
    _ key: String,
    in arguments: [String: Value],
) throws -> T {
    guard let value = arguments[key] else {
        throw MCPError.invalidParams(
            "Tool arguments are missing the required field '\(key)'.",
        )
    }

    return try decodeValue(value, fieldName: key)
}

func decodeOptionalArgument<T: Decodable>(
    _ key: String,
    in arguments: [String: Value],
    default defaultValue: T,
) throws -> T {
    guard let value = arguments[key] else {
        return defaultValue
    }

    return try decodeValue(value, fieldName: key)
}

func sourceFormat(in arguments: [String: Value]) throws -> TextForSpeech.SourceFormat? {
    try requestSourceFormat("source_format", in: arguments)
}

func requestContext(
    in arguments: [String: Value],
    defaults: SpeechRequestContextDefaults = .init(),
) throws -> SpeakSwiftly.RequestContext? {
    let decodedContext: SpeakSwiftly.RequestContext? = if let value = arguments["request_context"] {
        try decodeValue(value, fieldName: "request_context")
    } else {
        nil
    }
    return makeSpeechRequestContext(
        cwd: optionalString("cwd", in: arguments),
        repoRoot: optionalString("repo_root", in: arguments),
        requestContext: decodedContext,
        defaults: defaults,
    )
}

func requestSourceFormat(
    _ key: String,
    in arguments: [String: Value],
) throws -> TextForSpeech.SourceFormat? {
    guard let rawValue = optionalString(key, in: arguments) else {
        return nil
    }

    return try decodeStringEnum(rawValue, fieldName: key, valueType: TextForSpeech.SourceFormat.self)
}

func requiredVibe(
    _ key: String,
    in arguments: [String: Value],
) throws -> SpeakSwiftly.Vibe {
    let rawValue = try requiredString(key, in: arguments)
    return try decodeStringEnum(rawValue, fieldName: key, valueType: SpeakSwiftly.Vibe.self)
}

func requiredSpeechBackend(
    _ key: String,
    in arguments: [String: Value],
) throws -> SpeakSwiftly.SpeechBackend {
    let rawValue = try requiredString(key, in: arguments)
    return try requiredSpeechBackend(rawValue, key: key)
}

func requiredSpeechBackend(
    _ rawValue: String,
    key: String,
) throws -> SpeakSwiftly.SpeechBackend {
    guard let speechBackend = SpeakSwiftly.SpeechBackend.normalized(rawValue: rawValue) else {
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(supportedSpeechBackendDescription()).",
        )
    }

    return speechBackend
}

func optionalQwenSpeechBackend(
    _ key: String,
    in arguments: [String: Value],
    rawSpeechBackend: String,
) throws -> SpeakSwiftly.SpeechBackend? {
    guard rawSpeechBackend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        == SpeakSwiftly.SpeechBackend.legacyQwenRawValue
    else {
        return nil
    }
    guard let rawValue = optionalString(key, in: arguments) else {
        return nil
    }

    do {
        return try RuntimeStartupConfiguration.speechBackend(forLegacyQwenResidentModel: rawValue)
    } catch {
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(supportedQwenResidentModelDescription()).",
        )
    }
}

func optionalMarvisResidentPolicy(
    _ key: String,
    in arguments: [String: Value],
) throws -> SpeakSwiftly.MarvisResidentPolicy? {
    guard let rawValue = optionalString(key, in: arguments) else {
        return nil
    }

    return try decodeStringEnum(rawValue, fieldName: key, valueType: SpeakSwiftly.MarvisResidentPolicy.self)
}

func requiredBuiltInTextProfileStyle(
    _ key: String,
    in arguments: [String: Value],
) throws -> TextForSpeech.BuiltInProfileStyle {
    let rawValue = try requiredString(key, in: arguments)
    return try decodeStringEnum(rawValue, fieldName: key, valueType: TextForSpeech.BuiltInProfileStyle.self)
}

func decodeValue<T: Decodable>(_ value: Value, fieldName: String) throws -> T {
    do {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw MCPError.invalidParams(
            "Tool argument '\(fieldName)' could not be decoded into the expected payload shape. Likely cause: \(error.localizedDescription)",
        )
    }
}
