import Foundation
import SpeakSwiftly

package enum GeneratedAudioHTTPStreamCodec {
    package static let contentType = "application/x-ndjson; charset=utf-8"

    package static func encodeLine(chunk: SpeakSwiftly.GeneratedAudioChunk) throws -> Data {
        var data = try JSONEncoder().encode(SpeakSwiftly.HTTPGeneratedAudioFrame(chunk: chunk))
        data.append(0x0A)
        return data
    }

    package static func decodeLine(_ line: String) throws -> SpeakSwiftly.GeneratedAudioChunk {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftlyServer received an empty generated-audio stream frame from the remote server.",
            )
        }

        let frame = try JSONDecoder().decode(
            SpeakSwiftly.HTTPGeneratedAudioFrame.self,
            from: Data(trimmed.utf8),
        )
        return try SpeakSwiftly.GeneratedAudioChunk(
            requestID: frame.header.requestID,
            sequenceNumber: frame.header.sequenceNumber,
            sampleRate: frame.header.sampleRate,
            channelCount: frame.header.channelCount,
            sampleFormat: frame.header.sampleFormat,
            samples: frame.decodedSamples(),
            isFinal: frame.header.isFinal,
        )
    }
}
