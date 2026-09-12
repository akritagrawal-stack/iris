import Foundation

private enum GuideSchemaCheckError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

@main
struct GuideSchemaChecks {
    static func main() {
        do {
            try checkAcceptedWorkspacePaths()
            try checkStrictWorkspaceFailures()
            try checkLegacyInitializerAndRoundTrip()
            print("GUIDE SCHEMA CHECKS PASS: strict prepared-project workspace metadata")
        } catch {
            print("GUIDE SCHEMA CHECKS FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw GuideSchemaCheckError.failed(message) }
    }

    private static func decodeStep(
        workspace: Any? = nil,
        workingDirectory: Any? = nil
    ) throws -> IrisGuideStep {
        var object: [String: Any] = [
            "id": "build",
            "kind": "terminal",
            "title": "Build",
            "body": "Run the build"
        ]
        if let workspace { object["workspace"] = workspace }
        if let workingDirectory { object["workingDirectory"] = workingDirectory }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(IrisGuideStep.self, from: data)
    }

    private static func checkAcceptedWorkspacePaths() throws {
        let root = try decodeStep(workspace: [
            "kind": "prepared-project", "relativePath": "."
        ])
        try require(root.workspace?.kind == .preparedProject,
                    "prepared-project root metadata did not decode")
        try require(root.workspace?.relativePath == ".",
                    "root workspace path was not preserved")

        let nested = try decodeStep(workspace: [
            "kind": "prepared-project", "relativePath": "apps/mobile"
        ])
        try require(nested.workspace?.relativePath == "apps/mobile",
                    "nested workspace path was not preserved")
        print("PASS prepared-project root and nested paths")
    }

    private static func checkStrictWorkspaceFailures() throws {
        let invalidValues: [Any] = [
            "",
            "/apps/mobile",
            "../mobile",
            "apps/../mobile",
            "apps//mobile",
            "apps\\mobile",
            "apps/./mobile",
            ["kind": "unsupported", "relativePath": "apps/mobile"],
            ["kind": "prepared-project"],
            ["kind": "prepared-project", "relativePath": 42],
            "prepared-project"
        ]
        for value in invalidValues {
            do {
                _ = try decodeStep(workspace: value)
                throw GuideSchemaCheckError.failed("malformed workspace metadata was accepted: \(value)")
            } catch let checkError as GuideSchemaCheckError {
                throw checkError
            } catch {
                // Every malformed or unsupported workspace must fail decoding;
                // it may never fall back to the user's HOME directory.
            }
        }
        do {
            _ = try decodeStep(
                workspace: ["kind": "prepared-project", "relativePath": "apps/mobile"],
                workingDirectory: "/Users/example/project"
            )
            throw GuideSchemaCheckError.failed("workspace and workingDirectory were both accepted")
        } catch let checkError as GuideSchemaCheckError {
            throw checkError
        } catch {
            // Mutually exclusive declarations fail as required.
        }
        print("PASS unsupported, malformed and conflicting metadata refusal")
    }

    private static func checkLegacyInitializerAndRoundTrip() throws {
        // Existing reconstruction callsites retain their source-compatible
        // initializer because workspace is appended as a defaulted argument.
        let legacy = IrisGuideStep(id: "legacy", kind: .terminal, title: "Legacy", body: "Continue")
        try require(legacy.workspace == nil && legacy.workingDirectory == nil,
                    "legacy initializer unexpectedly gained workspace state")
        let workspace = try IrisGuideStepWorkspace(kind: .preparedProject, relativePath: "apps/mobile")
        let step = IrisGuideStep(
            id: "structured", kind: .terminal, title: "Structured", body: "Build",
            workspace: workspace
        )
        let encoded = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(IrisGuideStep.self, from: encoded)
        try require(decoded == step, "workspace metadata changed across Codable round trip")
        print("PASS legacy initializer compatibility and Codable round trip")
    }
}
