import Foundation
import SpeakSwiftly
import Testing

// MARK: - Shared End-to-End Assertions

extension ServerE2E {
    static func recordQueuedMarvisHTTPDiagnostics(
        using client: E2EHTTPClient,
        requestIDs: [String],
        expectedProfiles: [String],
    ) async {
        do {
            let requestList = try await decode(
                E2ERequestListResponse.self,
                from: client.request(path: "/requests", method: "GET").data,
            )
            let hostState = try await jsonObject(
                from: client.request(path: "/runtime/host", method: "GET").data,
            )

            let retainedRequests = requestList.requests
                .filter { requestIDs.contains($0.requestID) }
                .sorted { lhs, rhs in
                    requestIDs.firstIndex(of: lhs.requestID) ?? .max
                        < requestIDs.firstIndex(of: rhs.requestID) ?? .max
                }
                .map(requestDiagnosticSummary)
                .joined(separator: "\n")

            let playbackQueue = try diagnosticJSONString(from: hostState["playback_queue"])
            let generationQueue = try diagnosticJSONString(from: hostState["generation_queue"])
            let currentGenerationJobs = try diagnosticJSONString(from: hostState["current_generation_jobs"])

            Issue.record(
                """
                Queued Marvis HTTP diagnostics
                expected_profiles: \(expectedProfiles.joined(separator: ", "))
                request_ids: \(requestIDs.joined(separator: ", "))
                playback_queue: \(playbackQueue)
                generation_queue: \(generationQueue)
                current_generation_jobs: \(currentGenerationJobs)
                retained_requests:
                \(retainedRequests.isEmpty ? "none" : retainedRequests)
                """,
            )
        } catch {
            Issue.record(
                "Queued Marvis HTTP diagnostics could not be captured after a live-playback failure. Likely cause: \(error.localizedDescription)",
            )
        }
    }

    static func requestDiagnosticSummary(_ snapshot: E2EJobSnapshot) -> String {
        let latestEvent = snapshot.history.last?.event ?? "nil"
        let latestStage = snapshot.history.last?.stage ?? "nil"
        let terminalEvent = snapshot.terminalEvent?.event ?? "nil"
        let historySummary = snapshot.history
            .map {
                [
                    $0.event ?? "message",
                    $0.stage,
                    $0.reason,
                    $0.op,
                ]
                .compactMap { $0 }
                .joined(separator: ":")
            }
            .joined(separator: " -> ")

        return "- \(snapshot.requestID) status=\(snapshot.status) latest=\(latestEvent):\(latestStage) terminal=\(terminalEvent) history=\(historySummary)"
    }

    static func diagnosticJSONString(from value: Any?) throws -> String {
        guard let value else { return "null" }

        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func assertSpeechJobCompleted(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        if snapshot.status != "completed" || snapshot.terminalEvent?.ok != true {
            let terminalCode = snapshot.terminalEvent?.code ?? "nil"
            let terminalMessage = snapshot.terminalEvent?.message ?? "nil"
            Issue.record(
                """
                Audible speech job did not complete successfully.
                request_id: \(jobID)
                status: \(snapshot.status)
                terminal_code: \(terminalCode)
                terminal_message: \(terminalMessage)
                summary: \(requestDiagnosticSummary(snapshot))
                """,
            )
        }
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.id == jobID)
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.history.contains { $0.ok == true })
    }

    static func assertSpeechJobCancelled(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.id == jobID)
        #expect(snapshot.terminalEvent?.ok == false)
        #expect(snapshot.terminalEvent?.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
    }

    static func assertCloneTranscriptionStages(
        in snapshot: E2EJobSnapshot,
        expectTranscription: Bool,
    ) {
        let sawLoading = snapshot.history.contains {
            $0.event == "progress" && $0.stage == "loading_clone_transcription_model"
        }
        let sawTranscribing = snapshot.history.contains {
            $0.event == "progress" && $0.stage == "transcribing_clone_audio"
        }

        if expectTranscription {
            #expect(sawLoading)
            #expect(sawTranscribing)
        } else {
            #expect(!sawLoading)
            #expect(!sawTranscribing)
        }
    }

    static func transcriptLooksCloseToCloneSource(_ transcript: String) -> Bool {
        let expectedTokens = normalizedTranscriptTokens(from: testingCloneSourceText)
        let actualTokens = normalizedTranscriptTokens(from: transcript)

        guard !expectedTokens.isEmpty, !actualTokens.isEmpty else {
            return false
        }

        let sharedTokens = expectedTokens.intersection(actualTokens)
        let recall = Double(sharedTokens.count) / Double(expectedTokens.count)
        let precision = Double(sharedTokens.count) / Double(actualTokens.count)

        return recall >= 0.7 && precision >= 0.6
    }

    static func normalizedTranscriptTokens(from text: String) -> Set<String> {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(scalars)
        return Set(
            normalized
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { !$0.isEmpty },
        )
    }

    static func replacementJSON(
        id: String,
        text: String,
        replacement: String,
        match: String = "exact_phrase",
        phase: String = "before_built_ins",
        isCaseSensitive: Bool = false,
        formats: [String] = [],
        priority: Int = 0,
    ) -> [String: Any] {
        [
            "id": id,
            "text": text,
            "replacement": replacement,
            "match": match,
            "phase": phase,
            "is_case_sensitive": isCaseSensitive,
            "formats": formats,
            "priority": priority,
        ]
    }

    static func requirePromptText(in result: [String: Any]) throws -> String {
        let messages = try requireArray("messages", in: result)
        let firstMessage = try requireFirstDictionary(in: messages)
        let content = try requireDictionary("content", in: firstMessage)
        return try requireString("text", in: content)
    }

    static func requireObjectPayload(from payload: Any) throws -> [String: Any] {
        guard let object = payload as? [String: Any] else {
            throw E2ETransportError(
                "The live end-to-end helper expected a JSON object payload, but received '\(type(of: payload))'.",
            )
        }

        return object
    }

    static func requireArrayPayload(from payload: Any) throws -> [[String: Any]] {
        guard let array = payload as? [[String: Any]] else {
            throw E2ETransportError(
                "The live end-to-end helper expected a JSON array payload, but received '\(type(of: payload))'.",
            )
        }

        return array
    }

    static func decodePayload<Value: Decodable>(_ type: Value.Type, from payload: [String: Any]) throws -> Value {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try decode(Value.self, from: data)
    }
}
