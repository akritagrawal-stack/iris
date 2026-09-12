//
//  GuideSourceWorkspace.swift
//  leanring-buddy
//
//  Source preparation for a guide that must run in a clean, owned workspace.
//  This file deliberately owns no UI or guide progress. The controller chooses
//  when to offer isolation; this service only proves source identity, creates a
//  detached linked worktree, and returns a structural working-directory bind.
//

import Foundation
import CryptoKit

// MARK: - Source identity and structural guide binding

nonisolated struct GuideSourceWorkspaceOrigin: Codable, Equatable, Sendable {
    let host: String
    let path: String

    static func parse(_ value: String) -> Self? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              !text.contains("\n"), !text.contains("\r"),
              !text.contains(" ") else { return nil }

        let host: String
        let rawPath: String
        if text.hasPrefix("git@"), let colon = text.firstIndex(of: ":") {
            let userAndHost = String(text[text.index(text.startIndex, offsetBy: 4)..<colon])
            guard !userAndHost.isEmpty, !userAndHost.contains("@") else { return nil }
            host = userAndHost
            rawPath = String(text[text.index(after: colon)...])
        } else if let components = URLComponents(string: text),
                  let scheme = components.scheme?.lowercased(),
                  ["https", "ssh"].contains(scheme),
                  let parsedHost = components.host?.lowercased(),
                  (components.user == nil || (scheme == "ssh" && components.user == "git")),
                  components.password == nil,
                  components.query == nil,
                  components.fragment == nil,
                  components.port == nil {
            host = parsedHost
            rawPath = components.path
        } else {
            return nil
        }

        let path = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !host.isEmpty, !path.isEmpty,
              !path.split(separator: "/").contains(".."),
              !path.contains("\\"), !path.contains("//"),
              !path.contains(":") else { return nil }
        return Self(host: host.lowercased(), path: path.hasSuffix(".git")
            ? String(path.dropLast(4)) : path)
    }

    static func equivalent(_ left: String, _ right: String) -> Bool {
        guard let left = parse(left), let right = parse(right) else { return false }
        return left == right
    }
}

nonisolated struct GuideSourceWorkspaceIdentity: Codable, Equatable, Sendable {
    let canonicalPath: String
    let origin: GuideSourceWorkspaceOrigin
    let head: String
    let expectedCommitIsPresent: Bool
    let porcelain: String
    let commonGitDirectory: String
    let workingTreeFingerprint: String

    var isDirty: Bool {
        !porcelain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

nonisolated struct GuideSourceWorkspaceRequest: Equatable, Sendable {
    let runID: UUID
    let guideID: String
    let guideRevision: Int
    let projectID: String
    let sourcePath: String
    let expectedOrigin: String
    let expectedCommit: String
    let ownedProjectsRoot: URL
}

nonisolated enum GuideSourceWorkspaceSetupChoice: Equatable, Sendable {
    case useExistingCleanCheckout
    case createIsolatedWorktree
}

nonisolated enum GuideSourceWorkspaceInspection: Equatable, Sendable {
    case existingClean(GuideSourceWorkspaceIdentity)
    case isolatedCopyOffered(GuideSourceWorkspaceIdentity)
}

nonisolated enum GuideSourceWorkspacePreparationError: Error, Equatable, Sendable, LocalizedError {
    case invalidRequest(String)
    case sourceUnavailable(String)
    case wrongOrigin(expected: String, observed: String?)
    case expectedCommitMissing(String)
    case sourceRevisionMismatch(expected: String, observed: String)
    case sourceChangedSinceInspection
    case dirtyCheckoutRequiresIsolation
    case destinationNotOwned
    case destinationAlreadyExists
    case destinationInvalid(String)
    case worktreeCommandFailed(exitCode: Int32, output: String)
    case stagedWorkspaceVerificationFailed(String)
    case recoveryRecordCouldNotBeSaved
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason), .sourceUnavailable(let reason), .destinationInvalid(let reason),
             .stagedWorkspaceVerificationFailed(let reason): return reason
        case .wrongOrigin(let expected, let observed): return "origin mismatch: expected \(expected), observed \(observed ?? "missing")"
        case .expectedCommitMissing(let commit): return "expected commit missing: \(commit)"
        case .sourceRevisionMismatch(let expected, let observed): return "revision mismatch: expected \(expected), observed \(observed)"
        case .sourceChangedSinceInspection: return "source changed since inspection"
        case .dirtyCheckoutRequiresIsolation: return "dirty checkout requires isolation"
        case .destinationNotOwned: return "destination is not Test-owned"
        case .destinationAlreadyExists: return "destination already exists"
        case .worktreeCommandFailed(let exitCode, let output): return "worktree command failed (\(exitCode)): \(output)"
        case .recoveryRecordCouldNotBeSaved: return "workspace recovery record could not be saved"
        case .cancelled: return "workspace preparation cancelled"
        }
    }
}

nonisolated struct GuideSourceWorkspaceBinding: Codable, Equatable, Sendable {
    let runID: UUID
    let guideID: String
    let guideRevision: Int
    let projectID: String
    let original: GuideSourceWorkspaceIdentity
    let staged: GuideSourceWorkspaceIdentity
    let originalPath: String
    let stagedPath: String
    let expectedOrigin: GuideSourceWorkspaceOrigin
    let expectedCommit: String
    let ownershipMarker: String
    let commonGitDirectory: String
    let linkedWorktreeGitDirectory: String
    let isIsolated: Bool

    /// A published guide names a directory structurally. No command text is
    /// rewritten, and an empty path is never interpreted as the project root.
    func workingDirectory(forRelativePath relativePath: String) throws -> URL {
        try GuideSourceWorkspacePath.resolve(
            relativePath: relativePath,
            within: URL(fileURLWithPath: stagedPath, isDirectory: true)
        )
    }
}

nonisolated enum GuideSourceWorkspacePath {
    static func resolve(relativePath: String, within root: URL) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              !relativePath.contains("\\"),
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("~") else {
            throw GuideSourceWorkspacePreparationError.destinationInvalid("workspace path is not relative")
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == ".." }) else {
            throw GuideSourceWorkspacePreparationError.destinationInvalid("workspace path is empty or traverses its root")
        }

        let rootURL = root.standardizedFileURL
        let candidate = components == ["."]
            ? rootURL
            : components.reduce(rootURL) { $0.appendingPathComponent($1, isDirectory: true) }
        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isContainedOrEqual(resolvedCandidate, within: resolvedRoot),
              FileManager.default.fileExists(atPath: resolvedCandidate.path) else {
            throw GuideSourceWorkspacePreparationError.destinationInvalid("workspace path is outside or unavailable")
        }
        // A symlink anywhere in the binding would make future command routing
        // depend on mutable filesystem state, so require the lexical and
        // resolved paths to agree component-for-component.
        guard candidate.path == resolvedCandidate.path else {
            throw GuideSourceWorkspacePreparationError.destinationInvalid("workspace path contains a symlink")
        }
        return resolvedCandidate
    }

    static func validateOwnedDestination(_ destination: URL, within root: URL) -> Bool {
        let fileManager = FileManager.default
        let rootURL = root.standardizedFileURL
        let destinationURL = destination.standardizedFileURL
        guard rootURL.path != "/",
              destinationURL.path != rootURL.path,
              isContained(destinationURL, within: rootURL),
              !fileManager.fileExists(atPath: destinationURL.path),
              rootURL.path == rootURL.resolvingSymlinksInPath().standardizedFileURL.path else {
            return false
        }
        let parent = destinationURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path),
              parent.path == parent.resolvingSymlinksInPath().standardizedFileURL.path else {
            return false
        }
        return true
    }

    static func isContained(_ candidate: URL, within root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func isContainedOrEqual(_ candidate: URL, within root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}

// MARK: - Minimal recoverable record

nonisolated struct GuideSourceWorkspaceRecord: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case staging
        case ready
        case cancelled
        case failed
    }

    let runID: UUID
    let guideID: String
    let guideRevision: Int
    let projectID: String
    let originalPath: String
    let stagedPath: String
    let expectedOrigin: String
    let expectedCommit: String
    let ownershipMarker: String
    let state: State
}

nonisolated final class GuideSourceWorkspaceStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
    }

    func save(_ record: GuideSourceWorkspaceRecord) throws {
        let data = try JSONEncoder().encode(record)
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(record.runID.uuidString).json")
        try data.write(to: url, options: .atomic)
    }

    enum ReadResult: Equatable, Sendable {
        case absent
        case valid(GuideSourceWorkspaceRecord)
        case corrupt
        case unavailable
    }

    func read(_ runID: UUID) -> ReadResult {
        lock.lock()
        defer { lock.unlock() }
        let url = directory.appendingPathComponent("\(runID.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 256 * 1024,
              let data = try? Data(contentsOf: url) else { return .unavailable }
        guard let record = try? JSONDecoder().decode(GuideSourceWorkspaceRecord.self, from: data) else {
            return .corrupt
        }
        return .valid(record)
    }

    func record(for runID: UUID) -> GuideSourceWorkspaceRecord? {
        guard case .valid(let record) = read(runID) else { return nil }
        return record
    }
}

// MARK: - Fixed-argv executor

nonisolated struct GuideSourceWorkspaceCommandResult: Sendable {
    let exitCode: Int32
    let output: String
    let outputWasTruncated: Bool
}

nonisolated protocol GuideSourceWorkspaceCommandExecuting: Sendable {
    func run(executable: URL, arguments: [String], workingDirectory: URL, deadline: TimeInterval) async throws -> GuideSourceWorkspaceCommandResult
    func cancelRunningProcess()
}

nonisolated final class GuideSourceWorkspaceProcessExecutor: GuideSourceWorkspaceCommandExecuting, @unchecked Sendable {
    private static let maximumOutputBytes = 64 * 1024
    private let lock = NSLock()
    private var process: Process?
    private var activeInvocation: UUID?
    private var cancelledInvocations = Set<UUID>()
    private var timedOutInvocations = Set<UUID>()

    func run(executable: URL, arguments: [String], workingDirectory: URL, deadline: TimeInterval) async throws -> GuideSourceWorkspaceCommandResult {
        try Task.checkCancellation()
        let invocation = UUID()
        beginInvocation(invocation)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GuideSourceWorkspaceCommandResult, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    let child = Process()
                    let outputPipe = Pipe()
                    child.executableURL = executable
                    child.arguments = arguments
                    child.currentDirectoryURL = workingDirectory
                    child.standardOutput = outputPipe
                    child.standardError = outputPipe
                    self.lock.lock()
                    self.process = child
                    let wasCancelledBeforeLaunch = self.cancelledInvocations.contains(invocation)
                    self.lock.unlock()
                    do {
                        if wasCancelledBeforeLaunch {
                            throw CancellationError()
                        }
                        try child.run()
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.1, deadline)) {
                            self.lock.lock()
                            if self.activeInvocation == invocation, self.process === child {
                                self.timedOutInvocations.insert(invocation)
                                child.terminate()
                            }
                            self.lock.unlock()
                        }
                        var outputData = Data()
                        var outputWasTruncated = false
                        while let chunk = try outputPipe.fileHandleForReading.read(upToCount: 16 * 1024), !chunk.isEmpty {
                            if outputData.count + chunk.count <= Self.maximumOutputBytes {
                                outputData.append(chunk)
                            } else {
                                outputWasTruncated = true
                                let room = max(0, Self.maximumOutputBytes - outputData.count)
                                if room > 0 { outputData.append(chunk.prefix(room)) }
                            }
                        }
                        child.waitUntilExit()
                        let output = String(decoding: outputData, as: UTF8.self)
                        self.lock.lock()
                        let wasCancelled = self.cancelledInvocations.remove(invocation) != nil
                        let timedOut = self.timedOutInvocations.remove(invocation) != nil
                        if self.process === child { self.process = nil }
                        if self.activeInvocation == invocation { self.activeInvocation = nil }
                        self.lock.unlock()
                        if wasCancelled || Task.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: GuideSourceWorkspaceCommandResult(
                                exitCode: child.terminationStatus, output: output,
                                outputWasTruncated: outputWasTruncated || timedOut
                            ))
                        }
                    } catch {
                        self.lock.lock()
                        self.cancelledInvocations.remove(invocation)
                        self.timedOutInvocations.remove(invocation)
                        if self.process === child { self.process = nil }
                        if self.activeInvocation == invocation { self.activeInvocation = nil }
                        self.lock.unlock()
                        continuation.resume(throwing: error)
                    }
                }
            }
        }, onCancel: {
            self.cancelRunningProcess()
        })
    }

    func cancelRunningProcess() {
        lock.lock()
        let child = process
        if let activeInvocation { cancelledInvocations.insert(activeInvocation) }
        lock.unlock()
        child?.terminate()
    }

    private func beginInvocation(_ invocation: UUID) {
        lock.lock()
        activeInvocation = invocation
        lock.unlock()
    }
}

// MARK: - Preparation service

nonisolated final class GuideSourceWorkspaceService: @unchecked Sendable {
    private static let gitExecutable = URL(fileURLWithPath: "/usr/bin/git")
    private static let maximumFingerprintFileBytes = 1 * 1024 * 1024
    private static let maximumFingerprintTotalBytes = 4 * 1024 * 1024
    private let executor: any GuideSourceWorkspaceCommandExecuting
    private let store: GuideSourceWorkspaceStore?
    private let destinationIsOwned: @Sendable (URL) -> Bool

    init(
        executor: any GuideSourceWorkspaceCommandExecuting = GuideSourceWorkspaceProcessExecutor(),
        store: GuideSourceWorkspaceStore? = nil,
        destinationIsOwned: @escaping @Sendable (URL) -> Bool
    ) {
        self.executor = executor
        self.store = store
        self.destinationIsOwned = destinationIsOwned
    }

    func inspect(_ request: GuideSourceWorkspaceRequest) async -> Result<GuideSourceWorkspaceInspection, GuideSourceWorkspacePreparationError> {
        do {
            let identity = try await inspectIdentity(request)
            if identity.isDirty || identity.head != request.expectedCommit {
                return .success(.isolatedCopyOffered(identity))
            }
            return .success(.existingClean(identity))
        } catch let error as GuideSourceWorkspacePreparationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.sourceUnavailable(error.localizedDescription))
        }
    }

    func prepare(
        _ request: GuideSourceWorkspaceRequest,
        from inspection: GuideSourceWorkspaceInspection,
        choice: GuideSourceWorkspaceSetupChoice
    ) async throws -> GuideSourceWorkspaceBinding {
        do {
            return try await prepareImpl(request, from: inspection, choice: choice)
        } catch is CancellationError {
            throw GuideSourceWorkspacePreparationError.cancelled
        }
    }

    private func prepareImpl(
        _ request: GuideSourceWorkspaceRequest,
        from inspection: GuideSourceWorkspaceInspection,
        choice: GuideSourceWorkspaceSetupChoice
    ) async throws -> GuideSourceWorkspaceBinding {
        let freshIdentity = try await inspectIdentity(request)
        let inspectedIdentity: GuideSourceWorkspaceIdentity
        switch inspection {
        case .existingClean(let identity), .isolatedCopyOffered(let identity):
            inspectedIdentity = identity
        }
        guard freshIdentity == inspectedIdentity else {
            throw GuideSourceWorkspacePreparationError.sourceChangedSinceInspection
        }

        switch (inspection, choice) {
        case (.existingClean, .useExistingCleanCheckout):
            guard freshIdentity.head == request.expectedCommit else {
                throw GuideSourceWorkspacePreparationError.sourceRevisionMismatch(
                    expected: request.expectedCommit, observed: freshIdentity.head
                )
            }
            return makeExistingBinding(request: request, identity: freshIdentity)
        case (.existingClean, .createIsolatedWorktree):
            return try await stage(request: request, identity: freshIdentity)
        case (.isolatedCopyOffered, .useExistingCleanCheckout):
            throw GuideSourceWorkspacePreparationError.dirtyCheckoutRequiresIsolation
        case (.isolatedCopyOffered, .createIsolatedWorktree):
            return try await stage(request: request, identity: freshIdentity)
        }
    }

    private func inspectIdentity(_ request: GuideSourceWorkspaceRequest) async throws -> GuideSourceWorkspaceIdentity {
        guard isSafeIdentifier(request.guideID),
              isSafeIdentifier(request.projectID),
              request.guideRevision >= 0,
              isValidCommit(request.expectedCommit),
              let expectedOrigin = GuideSourceWorkspaceOrigin.parse(request.expectedOrigin) else {
            throw GuideSourceWorkspacePreparationError.invalidRequest("guide, project, origin, or commit is invalid")
        }
        let source = URL(fileURLWithPath: request.sourcePath).standardizedFileURL
        guard request.sourcePath.hasPrefix("/"), source.path != "/",
              FileManager.default.fileExists(atPath: source.path),
              source.path == source.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("source path is unavailable or contains a symlink")
        }

        // The executor owns one child process. Keep these probes serial so a
        // stop request always owns and terminates the active child.
        let headResult = try await runGit(["rev-parse", "--verify", "HEAD^{commit}"], in: source)
        let originResult = try await runGit(["remote", "get-url", "origin"], in: source)
        let statusResult = try await runGit(["status", "--porcelain=v1", "--untracked-files=all", "-z"], in: source)
        let expectedResult = try await runGit(["rev-parse", "--verify", "\(request.expectedCommit)^{commit}"], in: source)
        let commonResult = try await runGit(["rev-parse", "--git-common-dir"], in: source)
        guard headResult.exitCode == 0 else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("HEAD could not be read")
        }
        let observedHead = headResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidCommit(observedHead) else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("Git returned an invalid HEAD")
        }
        guard expectedResult.exitCode == 0 else {
            throw GuideSourceWorkspacePreparationError.expectedCommitMissing(request.expectedCommit)
        }
        let observedOrigin = originResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard originResult.exitCode == 0,
              let parsedOrigin = GuideSourceWorkspaceOrigin.parse(observedOrigin) else {
            throw GuideSourceWorkspacePreparationError.wrongOrigin(
                expected: expectedOrigin.path, observed: observedOrigin.isEmpty ? nil : observedOrigin
            )
        }
        guard parsedOrigin == expectedOrigin else {
            throw GuideSourceWorkspacePreparationError.wrongOrigin(
                expected: request.expectedOrigin, observed: observedOrigin
            )
        }
        guard statusResult.exitCode == 0, commonResult.exitCode == 0,
              !statusResult.outputWasTruncated else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("Git status or common directory could not be read")
        }
        let workingTreeFingerprint = try fingerprint(
            source: source, porcelain: statusResult.output
        )
        let commonText = commonResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let commonURL = URL(fileURLWithPath: commonText, relativeTo: source).standardizedFileURL
        guard commonURL.path == commonURL.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("Git common directory contains a symlink")
        }
        return GuideSourceWorkspaceIdentity(
            canonicalPath: source.path,
            origin: parsedOrigin,
            head: observedHead,
            expectedCommitIsPresent: true,
            porcelain: statusResult.output,
            commonGitDirectory: commonURL.path,
            workingTreeFingerprint: workingTreeFingerprint
        )
    }

    private func stage(
        request: GuideSourceWorkspaceRequest,
        identity: GuideSourceWorkspaceIdentity
    ) async throws -> GuideSourceWorkspaceBinding {
        let root = request.ownedProjectsRoot.standardizedFileURL
        guard destinationIsOwned(root) else {
            throw GuideSourceWorkspacePreparationError.destinationNotOwned
        }
        let destination = root.appendingPathComponent(
            "\(request.projectID)-\(request.runID.uuidString)", isDirectory: true
        )
        guard GuideSourceWorkspacePath.validateOwnedDestination(destination, within: root) else {
            throw GuideSourceWorkspacePreparationError.destinationAlreadyExists
        }
        let marker = UUID().uuidString
        try store?.save(GuideSourceWorkspaceRecord(
            runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
            projectID: request.projectID, originalPath: identity.canonicalPath, stagedPath: destination.path,
            expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
            ownershipMarker: marker, state: .staging
        ))

        do {
            let result = try await runGit([
                "worktree", "add", "--detach", destination.path, request.expectedCommit
            ], in: URL(fileURLWithPath: identity.canonicalPath, isDirectory: true))
            guard result.exitCode == 0 else {
                do {
                    try saveRecord(GuideSourceWorkspaceRecord(
                    runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                    projectID: request.projectID, originalPath: identity.canonicalPath, stagedPath: destination.path,
                    expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                    ownershipMarker: marker, state: .failed
                    ))
                } catch {
                    throw GuideSourceWorkspacePreparationError.recoveryRecordCouldNotBeSaved
                }
                throw GuideSourceWorkspacePreparationError.worktreeCommandFailed(
                    exitCode: result.exitCode, output: result.output
                )
            }
            let stagedIdentity = try await inspectIdentity(
                GuideSourceWorkspaceRequest(
                    runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                    projectID: request.projectID, sourcePath: destination.path,
                    expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                    ownedProjectsRoot: request.ownedProjectsRoot
                )
            )
            guard !stagedIdentity.isDirty, stagedIdentity.head == request.expectedCommit else {
                throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("staged worktree is not clean at the expected commit")
            }
            let linkedGitDirectory = try await readGitDirectory(in: destination)
            let binding = GuideSourceWorkspaceBinding(
                runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                projectID: request.projectID, original: identity, staged: stagedIdentity,
                originalPath: identity.canonicalPath, stagedPath: destination.path,
                expectedOrigin: identity.origin, expectedCommit: request.expectedCommit,
                ownershipMarker: marker, commonGitDirectory: identity.commonGitDirectory,
                linkedWorktreeGitDirectory: linkedGitDirectory, isIsolated: true
            )
            do {
                try saveRecord(GuideSourceWorkspaceRecord(
                runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                projectID: request.projectID, originalPath: identity.canonicalPath, stagedPath: destination.path,
                expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                ownershipMarker: marker, state: .ready
                ))
            } catch {
                throw GuideSourceWorkspacePreparationError.recoveryRecordCouldNotBeSaved
            }
            return binding
        } catch is CancellationError {
            do {
                try saveRecord(GuideSourceWorkspaceRecord(
                    runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                    projectID: request.projectID, originalPath: identity.canonicalPath, stagedPath: destination.path,
                    expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                    ownershipMarker: marker, state: .cancelled
                ))
            } catch {
                throw GuideSourceWorkspacePreparationError.recoveryRecordCouldNotBeSaved
            }
            throw GuideSourceWorkspacePreparationError.cancelled
        }
    }

    private func makeExistingBinding(
        request: GuideSourceWorkspaceRequest,
        identity: GuideSourceWorkspaceIdentity
    ) -> GuideSourceWorkspaceBinding {
        GuideSourceWorkspaceBinding(
            runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
            projectID: request.projectID, original: identity, staged: identity,
            originalPath: identity.canonicalPath, stagedPath: identity.canonicalPath,
            expectedOrigin: identity.origin, expectedCommit: request.expectedCommit,
            ownershipMarker: "existing-user-checkout", commonGitDirectory: identity.commonGitDirectory,
            linkedWorktreeGitDirectory: identity.commonGitDirectory, isIsolated: false
        )
    }

    private func readGitDirectory(in worktree: URL) async throws -> String {
        let result = try await runGit(["rev-parse", "--git-dir"], in: worktree)
        guard result.exitCode == 0 else {
            throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("linked worktree admin path could not be read")
        }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = URL(fileURLWithPath: text, relativeTo: worktree).standardizedFileURL
        guard path.path == path.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("linked worktree admin path contains a symlink")
        }
        return path.path
    }

    private func saveRecord(_ record: GuideSourceWorkspaceRecord) throws {
        try store?.save(record)
    }

    private func runGit(_ arguments: [String], in directory: URL) async throws -> GuideSourceWorkspaceCommandResult {
        let fixedArguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "-c", "core.hooksPath=/dev/null", "-c", "credential.helper=", "-C", directory.path] + arguments
        let isWorktreeCommand = arguments.first == "worktree"
        let deadline: TimeInterval = isWorktreeCommand ? 120 : 15
        return try await executor.run(
            executable: Self.gitExecutable, arguments: fixedArguments,
            workingDirectory: directory, deadline: deadline
        )
    }

    private func fingerprint(source: URL, porcelain: String) throws -> String {
        var hasher = SHA256()
        var fingerprintedBytes = 0
        hasher.update(data: Data(porcelain.utf8))
        let records = porcelain.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var recordIndex = 0
        while recordIndex < records.count {
            let record = records[recordIndex]
            guard record.count >= 4 else { recordIndex += 1; continue }
            var rawPaths = [String(record.dropFirst(3))]
            let status = String(record.prefix(2))
            if (status.hasPrefix("R") || status.hasPrefix("C")), recordIndex + 1 < records.count {
                rawPaths.append(records[recordIndex + 1])
                recordIndex += 1
            }
            for rawPath in rawPaths {
                let decodedPath: String
                if rawPath.hasPrefix("\"") && rawPath.hasSuffix("\"") && rawPath.count >= 2 {
                    decodedPath = String(rawPath.dropFirst().dropLast())
                        .replacingOccurrences(of: "\\\\\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\\\\\", with: "\\\\")
                } else {
                    decodedPath = rawPath
                }
                let path = decodedPath
            guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"),
                  !path.contains("\\"), !path.contains("//"),
                  !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
                  !path.split(separator: "/").contains("..") else {
                throw GuideSourceWorkspacePreparationError.sourceUnavailable("Git status contained an unsafe path: \(path)")
            }
            hasher.update(data: Data(path.utf8))
            let fileURL = source.appendingPathComponent(path).standardizedFileURL
            guard GuideSourceWorkspacePath.isContainedOrEqualForFingerprint(fileURL, within: source),
                  fileURL.path == fileURL.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw GuideSourceWorkspacePreparationError.sourceUnavailable("Git status escaped the source path")
            }
            try appendBoundedFileFingerprint(
                fileURL, to: &hasher, totalBytes: &fingerprintedBytes
            )
            }
            recordIndex += 1
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func appendBoundedFileFingerprint(
        _ fileURL: URL,
        to hasher: inout SHA256,
        totalBytes: inout Int
    ) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            hasher.update(data: Data("<missing>".utf8))
            return
        }
        let values = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let type = values[.type] as? FileAttributeType else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("changed path type could not be read")
        }
        if type == .typeDirectory {
            hasher.update(data: Data("<directory>".utf8))
            return
        }
        guard type == .typeRegular,
              let size = values[.size] as? NSNumber,
              size.intValue <= Self.maximumFingerprintFileBytes,
              totalBytes + size.intValue <= Self.maximumFingerprintTotalBytes,
              let handle = FileHandle(forReadingAtPath: fileURL.path) else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable(
                "changed file exceeds the fingerprint budget or cannot be read"
            )
        }
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 16 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
            totalBytes += chunk.count
        }
    }

    private func isValidCommit(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    private func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 160
            && value.first!.isASCII
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

private extension GuideSourceWorkspacePath {
    static func isContainedOrEqualForFingerprint(_ candidate: URL, within root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count >= rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
