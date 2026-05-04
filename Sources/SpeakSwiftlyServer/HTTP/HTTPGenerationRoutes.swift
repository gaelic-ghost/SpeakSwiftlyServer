import Hummingbird

func registerHTTPGenerationRoutes(
    on router: Router<BasicRequestContext>,
    host: ServerHost,
) {
    router.get("generation/queue") { _, _ -> QueueSnapshotResponse in
        await host.generationQueueSnapshot()
    }

    router.delete("generation/queue") { _, _ -> QueueClearedResponse in
        try await host.clearQueue(.generation)
    }

    router.get("generation/jobs") { _, _ -> Response in
        try await encodeJSONResponse(host.listGenerationJobs(), status: .ok)
    }

    router.get("generation/jobs/:job_id") { _, context -> Response in
        let jobID = try context.parameters.require("job_id")
        return try await encodeJSONResponse(host.generationJob(id: jobID), status: .ok)
    }

    router.delete("generation/jobs/:job_id") { _, context -> Response in
        let jobID = try context.parameters.require("job_id")
        return try await encodeJSONResponse(host.expireGenerationJob(id: jobID), status: .ok)
    }

    router.get("generation/artifacts") { _, _ -> Response in
        try await encodeJSONResponse(host.listGenerationArtifacts(), status: .ok)
    }

    router.get("generation/artifacts/:artifact_id") { _, context -> Response in
        let artifactID = try context.parameters.require("artifact_id")
        return try await encodeJSONResponse(host.generationArtifact(id: artifactID), status: .ok)
    }
}
