import Foundation

@testable import Iris

/// Gives a native test fixture the same Test Seatbelt policy as Iris Test,
/// bound to one canonical clone instead of the shared project registry.
///
/// This is test-target code only. The closure is created after the fixture
/// directory exists, checks the exact canonical spelling, and admits no other
/// repository path. A manually launched Iris Test app still uses the normal
/// persisted registry path.
enum IrisTestFixtureSandbox {
    enum Error: Swift.Error {
        case unavailable
        case clonePathIsNotCanonical
        case scratchDirectoryUnavailable
    }

    static func processPolicy(for clonePath: String) throws -> MaintainSandbox.ProcessPolicy {
        guard IrisTestEnvironment.isEnabled, IrisTestEnvironment.isUnitTestProcess,
              MaintainSandbox.isAvailable else {
            throw Error.unavailable
        }
        guard let canonicalClonePath = MaintainSandbox.canonicalExistingDirectory(clonePath),
              URL(fileURLWithPath: clonePath).standardizedFileURL.path == canonicalClonePath else {
            throw Error.clonePathIsNotCanonical
        }

        let scratchURL = IrisTestEnvironment.commandScratchDirectory.standardizedFileURL
        do {
            try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: scratchURL.path
            )
        } catch {
            throw Error.scratchDirectoryUnavailable
        }
        guard let canonicalScratchPath = MaintainSandbox.canonicalExistingDirectory(scratchURL.path),
              canonicalScratchPath == scratchURL.path else {
            throw Error.scratchDirectoryUnavailable
        }

        return MaintainSandbox.testProcessPolicy(
            scratchDirectoryPath: canonicalScratchPath,
            repositoryIsRegistered: { candidate in
                candidate == canonicalClonePath
            }
        )
    }
}
