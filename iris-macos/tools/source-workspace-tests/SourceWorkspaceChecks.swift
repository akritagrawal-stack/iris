import Foundation
import Darwin

private enum SourceWorkspaceCheckError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

private final class DelayingWorktreeExecutor: GuideSourceWorkspaceCommandExecuting, @unchecked Sendable {
    private let real = GuideSourceWorkspaceProcessExecutor()
    private let lock = NSLock()
    private var worktreeHasStarted = false

    var didStartWorktree: Bool {
        lock.lock(); defer { lock.unlock() }
        return worktreeHasStarted
    }

    func run(executable: URL, arguments: [String], workingDirectory: URL, deadline: TimeInterval) async throws -> GuideSourceWorkspaceCommandResult {
        if arguments.contains("worktree") {
            markWorktreeStarted()
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(10))
            }
            throw CancellationError()
        }
        return try await real.run(executable: executable, arguments: arguments, workingDirectory: workingDirectory, deadline: deadline)
    }

    func cancelRunningProcess() {
        real.cancelRunningProcess()
    }

    private func markWorktreeStarted() {
        lock.lock()
        worktreeHasStarted = true
        lock.unlock()
    }
}

private enum TestRecordFailure: Error, Equatable {
    case missing
    case persistence
}

private final class FailingRecorder: GuideSourceWorkspaceRecording, @unchecked Sendable {
    let failure: TestRecordFailure

    init(_ failure: TestRecordFailure) {
        self.failure = failure
    }

    func save(_ record: GuideSourceWorkspaceRecord) throws {
        throw failure
    }
}

@main
struct SourceWorkspaceChecks {
    static func main() async {
        do {
            try checkAdversarialContracts()
            try await checkExecutorBoundsAndCancellation()
            try await checkRealLocalGitPreparation()
            try await checkCancellationLeavesRecoverableRecord()
            print("SOURCE WORKSPACE CHECKS PASS: structural guards, local Git staging, identity preservation, cancellation")
        } catch {
            print("SOURCE WORKSPACE CHECKS FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SourceWorkspaceCheckError.failed(message) }
    }

    private static func checkAdversarialContracts() throws {
        let root = URL(fileURLWithPath: "/Users/Shared/iris-source-workspace-adversarial")
        let child = root.appendingPathComponent("stage-1")
        try require(!GuideSourceWorkspacePath.validateOwnedDestination(child, within: root),
                    "a missing root was accepted as an owned destination")
        try require(GuideSourceWorkspaceOrigin.equivalent(
            "git@github.com:Blueturboguy07/kneecap.git",
            "https://github.com/Blueturboguy07/kneecap"
        ), "equivalent HTTPS and SSH origins did not normalize")
        try require(!GuideSourceWorkspaceOrigin.equivalent(
            "https://evil.example/kneecap", "https://github.com/Blueturboguy07/kneecap"
        ), "surprising origin host was accepted")

        let fixtureParent = URL(fileURLWithPath: "/Users/Shared/iris-source-workspace-adversarial-\(UUID().uuidString)")
        let fixtureRoot = fixtureParent.appendingPathComponent("root")
        let outside = fixtureParent.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureParent) }
        let symlink = fixtureRoot.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        try require(!GuideSourceWorkspacePath.validateOwnedDestination(
            symlink.appendingPathComponent("stage"), within: fixtureRoot
        ), "a symlinked destination component was accepted")
        let recordDirectory = fixtureRoot.appendingPathComponent("records")
        try FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: true)
        let recordID = UUID()
        let recordURL = recordDirectory.appendingPathComponent("\(recordID.uuidString).json")
        try Data("not json".utf8).write(to: recordURL)
        let store = GuideSourceWorkspaceStore(directory: recordDirectory)
        try require(store.read(recordID) == .corrupt, "corrupt recovery state was treated as absent")
        try Data(repeating: 0, count: 300 * 1024).write(to: recordURL)
        try require(store.read(recordID) == .unavailable, "oversized recovery state was read without a bound")
        for path in ["", "/tmp/project", "../escape", "foo/../escape", "foo//bar", "foo\\bar", "~user/project"] {
            do {
                _ = try GuideSourceWorkspacePath.resolve(relativePath: path, within: fixtureRoot)
                throw SourceWorkspaceCheckError.failed("unsafe relative path was accepted: \(path)")
            } catch is GuideSourceWorkspacePreparationError {
                continue
            }
        }
        print("PASS adversarial origin, ownership and structural path guards")
    }

    private static func checkExecutorBoundsAndCancellation() async throws {
        let executor = GuideSourceWorkspaceProcessExecutor()
        let largeOutput = try await executor.run(
            executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [],
            workingDirectory: URL(fileURLWithPath: "/Users/Shared"), deadline: 0.2
        )
        try require(largeOutput.outputWasTruncated,
                    "large Git-like output was not bounded")
        let hardStopStarted = Date()
        let ignoringSignal = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "trap '' TERM; while :; do :; done"],
            workingDirectory: URL(fileURLWithPath: "/Users/Shared"), deadline: 0.1
        )
        try require(Date().timeIntervalSince(hardStopStarted) < 2,
                    "deadline hard-stop waited on a child that ignored SIGTERM")
        try require(ignoringSignal.outputWasTruncated,
                    "deadline hard-stop did not mark the bounded operation")
        let task = Task {
            try await executor.run(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"],
                workingDirectory: URL(fileURLWithPath: "/Users/Shared"), deadline: 10
            )
        }
        try await Task.sleep(for: .milliseconds(50))
        let concurrentTask = Task {
            try await executor.run(
                executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["must-not-run"],
                workingDirectory: URL(fileURLWithPath: "/Users/Shared"), deadline: 2
            )
        }
        do {
            _ = try await concurrentTask.value
            throw SourceWorkspaceCheckError.failed("concurrent executor use was not rejected")
        } catch GuideSourceWorkspaceExecutorError.busy {
            // A second command cannot replace the process owned by the first.
        }
        task.cancel()
        do {
            _ = try await task.value
            throw SourceWorkspaceCheckError.failed("executor cancellation did not stop the child")
        } catch is CancellationError { }
        let afterCancellation = try await executor.run(
            executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["second-command"],
            workingDirectory: URL(fileURLWithPath: "/Users/Shared"), deadline: 2
        )
        try require(afterCancellation.exitCode == 0 && afterCancellation.output.contains("second-command"),
                    "executor did not release ownership after targeted cancellation")
        print("PASS bounded output, deadline and child cancellation")
    }

    private static func checkRealLocalGitPreparation() async throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: "/Users/Shared/iris-source-workspace-checks-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source with spaces")
        let projects = root.appendingPathComponent("Projects")
        try fileManager.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: source.appendingPathComponent("apps/mobile"), withIntermediateDirectories: true)
        try Data("fixture\n".utf8).write(to: source.appendingPathComponent("README.md"))
        try Data("{}\n".utf8).write(to: source.appendingPathComponent("apps/mobile/package.json"))
        try runGit(["init", "-q", "-b", "main"], in: source)
        try runGit(["config", "user.name", "Iris Fixture"], in: source)
        try runGit(["config", "user.email", "iris-fixture@example.test"], in: source)
        try runGit(["add", "README.md", "apps/mobile/package.json"], in: source)
        try runGit(["commit", "-q", "-m", "fixture"], in: source)
        try runGit(["remote", "add", "origin", "https://github.com/Blueturboguy07/kneecap.git"], in: source)
        let hookMarker = root.appendingPathComponent("hook-fired")
        let postCheckoutHook = source.appendingPathComponent(".git/hooks/post-checkout")
        try Data("#!/bin/sh\ntouch '\(hookMarker.path)'\n".utf8).write(to: postCheckoutHook)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: postCheckoutHook.path)
        let expectedCommit = try runGit(["rev-parse", "HEAD"], in: source).trimmingCharacters(in: .whitespacesAndNewlines)
        try Data("newer source revision\n".utf8).write(to: source.appendingPathComponent("newer.txt"))
        try runGit(["add", "newer.txt"], in: source)
        try runGit(["commit", "-q", "-m", "newer revision"], in: source)
        let lockfile = source.appendingPathComponent("bun lockfile.txt")
        try Data("dirty but must be preserved\n".utf8).write(to: lockfile)
        let beforeHead = try runGit(["rev-parse", "HEAD"], in: source)
        let beforeStatus = try runGit(["status", "--porcelain=v1", "--untracked-files=all"], in: source)
        let beforeReadme = try Data(contentsOf: source.appendingPathComponent("README.md"))
        let beforeLock = try Data(contentsOf: lockfile)
        var sourceGitIsDirectory: ObjCBool = false
        try require(fileManager.fileExists(atPath: source.appendingPathComponent(".git").path,
                                            isDirectory: &sourceGitIsDirectory),
                    "fixture Git metadata was missing before staging")

        let request = GuideSourceWorkspaceRequest(
            runID: UUID(), guideID: "kneecap", guideRevision: 5, projectID: "kneecap",
            sourcePath: source.path, expectedOrigin: "https://github.com/Blueturboguy07/kneecap",
            expectedCommit: expectedCommit, ownedProjectsRoot: projects
        )
        let records = GuideSourceWorkspaceStore(directory: root.appendingPathComponent("records"))
        let service = GuideSourceWorkspaceService(
            store: records,
            destinationIsOwned: { $0.path == projects.path }
        )
        let unsafeProjectRequest = GuideSourceWorkspaceRequest(
            runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
            projectID: "../escaped", sourcePath: request.sourcePath,
            expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
            ownedProjectsRoot: request.ownedProjectsRoot
        )
        guard case .failure(.invalidRequest) = await service.inspect(unsafeProjectRequest) else {
            throw SourceWorkspaceCheckError.failed("project identifier escaped the destination name")
        }
        let inspectionResult = await service.inspect(request)
        guard case .success(.isolatedCopyOffered(let identity)) = inspectionResult else {
            throw SourceWorkspaceCheckError.failed("dirty matching source did not offer an isolated workspace")
        }

        // A recovery record is a precondition for any worktree mutation. Both
        // missing and persistence-failing recorders must stop before Git sees
        // `worktree add`, leaving no destination or linked-worktree metadata.
        let worktreeMetadata = source.appendingPathComponent(".git/worktrees")
        try require(!fileManager.fileExists(atPath: worktreeMetadata.path),
                    "fixture unexpectedly had linked-worktree metadata before staging")
        for failure in [TestRecordFailure.missing, .persistence] {
            let failingService = GuideSourceWorkspaceService(
                store: FailingRecorder(failure),
                destinationIsOwned: { $0.path == projects.path }
            )
            let failingRequest = GuideSourceWorkspaceRequest(
                runID: UUID(), guideID: request.guideID, guideRevision: request.guideRevision,
                projectID: request.projectID, sourcePath: request.sourcePath,
                expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                ownedProjectsRoot: request.ownedProjectsRoot
            )
            do {
                _ = try await failingService.prepare(
                    failingRequest, from: .isolatedCopyOffered(identity), choice: .createIsolatedWorktree
                )
                throw SourceWorkspaceCheckError.failed("staging proceeded without a recoverable record")
            } catch GuideSourceWorkspacePreparationError.recoveryRecordCouldNotBeSaved {
                // Different persistence failures have the same safe outcome:
                // no Git mutation is allowed without a recoverable record.
            }
            try require(!fileManager.fileExists(atPath: worktreeMetadata.path),
                        "record failure created linked-worktree metadata")
            try require((try fileManager.contentsOfDirectory(atPath: projects.path)).isEmpty,
                        "record failure created an unrecorded destination")
        }

        let hostileOutside = root.appendingPathComponent("hostile-git-dir")
        let hostileSentinel = hostileOutside.appendingPathComponent("sentinel")
        try fileManager.createDirectory(at: hostileOutside, withIntermediateDirectories: true)
        try Data("must remain untouched\n".utf8).write(to: hostileSentinel)
        let hostileEnvironment: [String: String] = [
            "GIT_DIR": hostileOutside.path,
            "GIT_WORK_TREE": hostileOutside.path,
            "GIT_INDEX_FILE": hostileOutside.appendingPathComponent("index").path,
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "core.hooksPath",
            "GIT_CONFIG_VALUE_0": hostileOutside.appendingPathComponent("hooks").path,
            "GIT_OBJECT_DIRECTORY": hostileOutside.appendingPathComponent("objects").path,
            "GIT_ALTERNATE_OBJECT_DIRECTORIES": hostileOutside.appendingPathComponent("alternate").path,
            "GIT_COMMON_DIR": hostileOutside.path,
            "GIT_CEILING_DIRECTORIES": hostileOutside.path
        ]
        for (key, value) in hostileEnvironment { setenv(key, value, 1) }
        defer { for key in hostileEnvironment.keys { unsetenv(key) } }
        try Data("changed after inspection\n".utf8).write(to: lockfile)
        do {
            _ = try await service.prepare(
                request, from: .isolatedCopyOffered(identity), choice: .createIsolatedWorktree
            )
            throw SourceWorkspaceCheckError.failed("source mutation between inspect and stage was accepted")
        } catch GuideSourceWorkspacePreparationError.sourceChangedSinceInspection {
            // The staged operation must bind to the exact inspected dirty tree.
        }
        try beforeLock.write(to: lockfile)
        let binding = try await service.prepare(
            request, from: .isolatedCopyOffered(identity), choice: .createIsolatedWorktree
        )
        try require(binding.isIsolated, "isolated preparation returned an existing checkout")
        try require(binding.originalPath == source.path && binding.stagedPath != source.path,
                    "source and stage paths were not distinct")
        try require(binding.staged.head == expectedCommit && !binding.staged.isDirty,
                    "linked worktree was not clean at the expected commit")
        try require(fileManager.fileExists(atPath: source.appendingPathComponent(".git").path),
                    "source repository disappeared")
        var sourceGitAfterIsDirectory: ObjCBool = false
        try require(fileManager.fileExists(atPath: source.appendingPathComponent(".git").path,
                                            isDirectory: &sourceGitAfterIsDirectory)
                    && sourceGitAfterIsDirectory.boolValue == sourceGitIsDirectory.boolValue,
                    "source Git metadata was rewritten")
        try require(binding.linkedWorktreeGitDirectory.contains("worktrees"),
                    "linked worktree administrative directory was not recorded")
        try require(fileManager.fileExists(atPath: source.appendingPathComponent(".git/worktrees").path),
                    "expected linked-worktree administrative metadata was not created")
        try require(!fileManager.fileExists(atPath: hookMarker.path),
                    "repository hook executed during controlled worktree creation")
        try require(Data(contentsOf: hostileSentinel) == Data("must remain untouched\n".utf8),
                    "inherited GIT_* routing/config variables touched an outside path")
        try require((try fileManager.contentsOfDirectory(atPath: hostileOutside.path)) == ["sentinel"],
                    "inherited GIT_* routing/config variables created outside-fixture entries")
        try require(try binding.workingDirectory(forRelativePath: ".").path == binding.stagedPath,
                    "root structural binding did not resolve to the stage")
        try require(try binding.workingDirectory(forRelativePath: "apps/mobile").path
                    == URL(fileURLWithPath: binding.stagedPath).appendingPathComponent("apps/mobile").path,
                    "nested structural binding did not resolve inside the stage")
        for path in ["", "../outside", "/tmp/outside", "apps/../outside"] {
            do {
                _ = try binding.workingDirectory(forRelativePath: path)
                throw SourceWorkspaceCheckError.failed("unsafe guide path was accepted: \(path)")
            } catch is GuideSourceWorkspacePreparationError { }
        }
        try require(try runGit(["rev-parse", "HEAD"], in: source) == beforeHead,
                    "original HEAD changed during staging")
        try require(try runGit(["status", "--porcelain=v1", "--untracked-files=all"], in: source) == beforeStatus,
                    "original porcelain changed during staging")
        try require(Data(contentsOf: source.appendingPathComponent("README.md")) == beforeReadme,
                    "original tracked file changed during staging")
        try require(Data(contentsOf: lockfile) == beforeLock,
                    "original dirty lockfile changed during staging")

        do {
            _ = try await service.prepare(
                request, from: .isolatedCopyOffered(identity), choice: .createIsolatedWorktree
            )
            throw SourceWorkspaceCheckError.failed("repeated staging reused an existing destination")
        } catch GuideSourceWorkspacePreparationError.destinationAlreadyExists {
            // A repeated click for the same run is refused rather than creating
            // a second workspace with ambiguous ownership.
        }

        try runGit(["remote", "set-url", "origin", "https://evil.example/source"], in: source)
        let wrongOrigin = await service.inspect(request)
        guard case .failure(.wrongOrigin) = wrongOrigin else {
            throw SourceWorkspaceCheckError.failed("wrong origin was not refused")
        }
        try runGit(["remote", "set-url", "origin", "https://github.com/Blueturboguy07/kneecap.git"], in: source)
        let missing = GuideSourceWorkspaceRequest(
            runID: UUID(), guideID: request.guideID, guideRevision: request.guideRevision,
            projectID: request.projectID, sourcePath: source.path, expectedOrigin: request.expectedOrigin,
            expectedCommit: String(repeating: "f", count: 40), ownedProjectsRoot: projects
        )
        guard case .failure(.expectedCommitMissing) = await service.inspect(missing) else {
            throw SourceWorkspaceCheckError.failed("absent expected commit was not refused")
        }
        print("PASS real local Git dirty-source offer, detached worktree, common-dir record and preservation")
    }

    private static func checkCancellationLeavesRecoverableRecord() async throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: "/Users/Shared/iris-source-workspace-cancel-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let projects = root.appendingPathComponent("Projects")
        try fileManager.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("fixture\n".utf8).write(to: source.appendingPathComponent("README.md"))
        try runGit(["init", "-q", "-b", "main"], in: source)
        try runGit(["config", "user.name", "Iris Fixture"], in: source)
        try runGit(["config", "user.email", "iris-fixture@example.test"], in: source)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-q", "-m", "fixture"], in: source)
        try runGit(["remote", "add", "origin", "https://github.com/Blueturboguy07/kneecap.git"], in: source)
        let commit = try runGit(["rev-parse", "HEAD"], in: source).trimmingCharacters(in: .whitespacesAndNewlines)
        let request = GuideSourceWorkspaceRequest(
            runID: UUID(), guideID: "kneecap", guideRevision: 5, projectID: "kneecap",
            sourcePath: source.path, expectedOrigin: "https://github.com/Blueturboguy07/kneecap",
            expectedCommit: commit, ownedProjectsRoot: projects
        )
        let records = GuideSourceWorkspaceStore(directory: root.appendingPathComponent("records"))
        let executor = DelayingWorktreeExecutor()
        let service = GuideSourceWorkspaceService(
            executor: executor, store: records, destinationIsOwned: { $0.path == projects.path }
        )
        guard case .success(.existingClean(let identity)) = await service.inspect(request) else {
            throw SourceWorkspaceCheckError.failed("clean fixture was not recognized")
        }
        let task = Task {
            try await service.prepare(request, from: .existingClean(identity), choice: .createIsolatedWorktree)
        }
        for _ in 0..<200 where !executor.didStartWorktree {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(executor.didStartWorktree, "cancellation fixture never reached the owned staging process")
        task.cancel()
        do {
            _ = try await task.value
            throw SourceWorkspaceCheckError.failed("cancelled staging returned a workspace")
        } catch is GuideSourceWorkspacePreparationError { }
        guard let record = records.record(for: request.runID) else {
            throw SourceWorkspaceCheckError.failed("cancelled staging did not retain a recoverable record")
        }
        try require(record.state == .cancelled, "cancelled staging record was not marked cancelled")
        try require(!fileManager.fileExists(atPath: record.stagedPath),
                    "cancelled fake stage unexpectedly claimed an installed workspace")
        print("PASS cancellation retains a truthful owned recovery record")
    }

    @discardableResult
    private static func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false"] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        for key in [
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0",
            "GIT_CONFIG_VALUE_0", "GIT_CONFIG_PARAMETERS", "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_CEILING_DIRECTORIES"
        ] {
            environment.removeValue(forKey: key)
        }
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        var outputData = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 16 * 1024), !chunk.isEmpty {
            guard outputData.count + chunk.count <= 256 * 1024 else {
                throw SourceWorkspaceCheckError.failed("fixture Git output exceeded the test bound")
            }
            outputData.append(chunk)
        }
        let output = String(decoding: outputData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw SourceWorkspaceCheckError.failed("git \(arguments.joined(separator: " ")) failed: \(output)")
        }
        return output
    }
}
