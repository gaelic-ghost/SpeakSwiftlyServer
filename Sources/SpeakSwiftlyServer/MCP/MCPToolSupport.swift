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
        requestResourceURI: "speak://requests/\(requestID)",
        statusResourceURI: "speak://runtime/overview",
        message: message,
    )
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

func normalizationContext(in arguments: [String: Value]) throws -> SpeechNormalizationContext? {
    let context = try SpeechNormalizationContext(
        cwd: optionalString("cwd", in: arguments),
        repoRoot: optionalString("repo_root", in: arguments),
        textFormat: requestTextFormat(in: arguments),
        nestedSourceFormat: requestSourceFormat("nested_source_format", in: arguments),
    )
    guard
        context.cwd != nil
        || context.repoRoot != nil
        || context.textFormat != nil
        || context.nestedSourceFormat != nil
    else {
        return nil
    }

    return context
}

func sourceFormat(in arguments: [String: Value]) throws -> TextForSpeech.SourceFormat? {
    try requestSourceFormat("source_format", in: arguments)
}

func requestTextFormat(in arguments: [String: Value]) throws -> TextForSpeech.TextFormat? {
    guard let rawValue = optionalString("text_format", in: arguments) else {
        return nil
    }
    guard let format = TextForSpeech.TextFormat(rawValue: rawValue) else {
        let acceptedValues = TextForSpeech.TextFormat.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument 'text_format' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues).",
        )
    }

    return format
}

func requestSourceFormat(
    _ key: String,
    in arguments: [String: Value],
) throws -> TextForSpeech.SourceFormat? {
    guard let rawValue = optionalString(key, in: arguments) else {
        return nil
    }
    guard let format = TextForSpeech.SourceFormat(rawValue: rawValue) else {
        let acceptedValues = TextForSpeech.SourceFormat.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues).",
        )
    }

    return format
}

func requiredVibe(
    _ key: String,
    in arguments: [String: Value],
) throws -> SpeakSwiftly.Vibe {
    let rawValue = try requiredString(key, in: arguments)
    guard let vibe = SpeakSwiftly.Vibe(rawValue: rawValue) else {
        let acceptedValues = SpeakSwiftly.Vibe.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues).",
        )
    }

    return vibe
}

func requiredSpeechBackend(
    _ key: String,
    in arguments: [String: Value],
) throws -> SpeakSwiftly.SpeechBackend {
    let rawValue = try requiredString(key, in: arguments)
    guard let speechBackend = SpeakSwiftly.SpeechBackend(rawValue: rawValue) else {
        let acceptedValues = SpeakSwiftly.SpeechBackend.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues).",
        )
    }

    return speechBackend
}

func requiredBuiltInTextProfileStyle(
    _ key: String,
    in arguments: [String: Value],
) throws -> TextForSpeech.BuiltInProfileStyle {
    let rawValue = try requiredString(key, in: arguments)
    guard let style = TextForSpeech.BuiltInProfileStyle(rawValue: rawValue) else {
        let acceptedValues = TextForSpeech.BuiltInProfileStyle.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues).",
        )
    }

    return style
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
