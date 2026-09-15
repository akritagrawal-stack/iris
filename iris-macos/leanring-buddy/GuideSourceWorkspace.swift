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
import Darwin

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

    /// Validate a destination after a worktree has been created. The creation
    /// check above intentionally requires the path to be absent; this check
    /// covers the other side of that boundary and rejects a replacement
    /// parent, symlink, regular-file destination, or a worktree that escaped
    /// the one owned directory after the Git process returned.
    static func validateExistingOwnedDestination(_ destination: URL, within root: URL) -> Bool {
        let fileManager = FileManager.default
        let rootURL = root.standardizedFileURL
        let destinationURL = destination.standardizedFileURL
        guard rootURL.path != "/",
              destinationURL.deletingLastPathComponent().path == rootURL.path,
              isContained(destinationURL, within: rootURL),
              rootURL.path == rootURL.resolvingSymlinksInPath().standardizedFileURL.path,
              destinationURL.path == destinationURL.resolvingSymlinksInPath().standardizedFileURL.path,
              fileManager.fileExists(atPath: destinationURL.path),
              let values = try? destinationURL.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true else {
            return false
        }
        let parent = destinationURL.deletingLastPathComponent()
        return fileManager.fileExists(atPath: parent.path)
            && parent.path == parent.resolvingSymlinksInPath().standardizedFileURL.path
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

nonisolated protocol GuideSourceWorkspaceRecording: Sendable {
    func save(_ record: GuideSourceWorkspaceRecord) throws
}

/// Reading is kept as a separate capability so the existing staging fakes only
/// need to implement the write-ahead recovery contract. Production stores
/// implement both capabilities; a binding without a readable ready record is
/// never admitted to execution.
nonisolated protocol GuideSourceWorkspaceRecordReading: Sendable {
    func record(for runID: UUID) -> GuideSourceWorkspaceRecord?
}

nonisolated final class GuideSourceWorkspaceStore: GuideSourceWorkspaceRecording, GuideSourceWorkspaceRecordReading, @unchecked Sendable {
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

nonisolated enum GuideSourceWorkspaceExecutorError: Error, Equatable, Sendable {
    case busy
}

nonisolated protocol GuideSourceWorkspaceCommandExecuting: Sendable {
    func run(executable: URL, arguments: [String], workingDirectory: URL, deadline: TimeInterval) async throws -> GuideSourceWorkspaceCommandResult
    func cancelRunningProcess()
}

nonisolated final class GuideSourceWorkspaceProcessExecutor: GuideSourceWorkspaceCommandExecuting, @unchecked Sendable {
    private static let maximumOutputBytes = 64 * 1024
    private static let hardStopGrace: TimeInterval = 0.25
    private let lock = NSLock()
    private var process: Process?
    private var activeInvocation: UUID?
    private var cancelledInvocations = Set<UUID>()
    private var timedOutInvocations = Set<UUID>()

    func run(executable: URL, arguments: [String], workingDirectory: URL, deadline: TimeInterval) async throws -> GuideSourceWorkspaceCommandResult {
        try Task.checkCancellation()
        let invocation = UUID()
        guard beginInvocation(invocation) else {
            // The service deliberately serializes Git probes. Rejecting a
            // second caller keeps cancellation ownership deterministic for
            // direct users of this small executor too.
            throw GuideSourceWorkspaceExecutorError.busy
        }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GuideSourceWorkspaceCommandResult, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    let child = Process()
                    let outputPipe = Pipe()
                    let output = BoundedOutputAccumulator(maximumBytes: Self.maximumOutputBytes)
                    child.executableURL = executable
                    child.arguments = arguments
                    child.currentDirectoryURL = workingDirectory
                    child.standardOutput = outputPipe
                    child.standardError = outputPipe
                    // Do not inherit the caller's environment. In particular,
                    // GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, GIT_CONFIG_* and
                    // related routing variables can redirect a fixed argv.
                    child.environment = [
                        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                        "GIT_CONFIG_NOSYSTEM": "1",
                        "GIT_CONFIG_GLOBAL": "/dev/null",
                        "GIT_CONFIG_SYSTEM": "/dev/null",
                        "GIT_OPTIONAL_LOCKS": "0",
                        "GIT_TERMINAL_PROMPT": "0",
                        "GIT_ASKPASS": "/usr/bin/false"
                    ]
                    do {
                        // Hold ownership through Process.run(). This closes
                        // the cancellation-before-launch gap: a cancellation
                        // cannot observe an unlaunched child and then have it
                        // start after terminate() was attempted.
                        self.lock.lock()
                        self.process = child
                        if self.cancelledInvocations.contains(invocation) {
                            self.lock.unlock()
                            throw CancellationError()
                        }
                        do {
                            try child.run()
                        } catch {
                            self.lock.unlock()
                            throw error
                        }
                        self.lock.unlock()

                        let drainGroup = DispatchGroup()
                        drainGroup.enter()
                        DispatchQueue.global(qos: .utility).async {
                            defer { drainGroup.leave() }
                            do {
                                while let chunk = try outputPipe.fileHandleForReading.read(upToCount: 16 * 1024), !chunk.isEmpty {
                                    output.append(chunk)
                                }
                            } catch {
                                // The deadline/cancellation path closes the
                                // reader to bound a pipe held by a descendant.
                            }
                        }

                        let deadlineDate = Date().addingTimeInterval(max(0.1, deadline))
                        var hardStopAt: Date?
                        var timedOut = false
                        while child.isRunning {
                            let cancelled = self.isCancelled(invocation: invocation)
                            let deadlineReached = Date() >= deadlineDate
                            if (cancelled || deadlineReached), hardStopAt == nil {
                                timedOut = timedOut || deadlineReached
                                if deadlineReached { self.markTimedOut(invocation: invocation, child: child) }
                                child.terminate()
                                hardStopAt = Date().addingTimeInterval(Self.hardStopGrace)
                            } else if let hardStopAt, Date() >= hardStopAt {
                                // SIGTERM is advisory. A fixed Git operation
                                // must have a bounded completion even when a
                                // child ignores it or keeps the pipe open.
                                kill(child.processIdentifier, SIGKILL)
                                break
                            }
                            usleep(10_000)
                        }
                        child.waitUntilExit()
                        // Let a normal probe drain to EOF before closing its
                        // read end. Closing first can discard a fast Git
                        // response that the drain has not scheduled yet.
                        // Only a drain that misses the bounded grace period is
                        // forced closed, which also handles a descendant that
                        // inherited the pipe's write end.
                        let drainCompleted = drainGroup.wait(timeout: .now() + Self.hardStopGrace) == .success
                        if !drainCompleted {
                            outputPipe.fileHandleForReading.closeFile()
                            _ = drainGroup.wait(timeout: .now() + Self.hardStopGrace)
                        }
                        let outputText = output.string
                        self.lock.lock()
                        let wasCancelled = self.cancelledInvocations.remove(invocation) != nil
                        let recordedTimeout = self.timedOutInvocations.remove(invocation) != nil
                        if self.process === child { self.process = nil }
                        if self.activeInvocation == invocation { self.activeInvocation = nil }
                        self.lock.unlock()
                        // The dispatch-queue closure has its own task context;
                        // use the cancellation bit set by the parent's
                        // cancellation handler rather than consulting it here.
                        if wasCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: GuideSourceWorkspaceCommandResult(
                                exitCode: child.terminationStatus, output: outputText,
                                outputWasTruncated: output.wasTruncated || recordedTimeout || timedOut || !drainCompleted
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
            self.cancel(invocation: invocation)
        })
    }

    func cancelRunningProcess() {
        lock.lock()
        let invocation = activeInvocation
        lock.unlock()
        if let invocation { cancel(invocation: invocation) }
    }

    private func cancel(invocation: UUID) {
        lock.lock()
        guard activeInvocation == invocation else {
            lock.unlock()
            return
        }
        cancelledInvocations.insert(invocation)
        let child = process
        lock.unlock()
        child?.terminate()
    }

    private func isCancelled(invocation: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelledInvocations.contains(invocation)
    }

    private func markTimedOut(invocation: UUID, child: Process) {
        lock.lock()
        if activeInvocation == invocation, process === child {
            timedOutInvocations.insert(invocation)
        }
        lock.unlock()
    }

    private func beginInvocation(_ invocation: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeInvocation == nil else { return false }
        activeInvocation = invocation
        return true
    }
}

private final class BoundedOutputAccumulator: @unchecked Sendable {
    private let maximumBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard data.count < maximumBytes else {
            truncated = true
            return
        }
        let room = maximumBytes - data.count
        data.append(chunk.prefix(room))
        if chunk.count > room { truncated = true }
    }

    var wasTruncated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return truncated
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Preparation service

nonisolated final class GuideSourceWorkspaceService: @unchecked Sendable {
    private static let gitExecutable = URL(fileURLWithPath: "/usr/bin/git")
    private static let maximumFingerprintFileBytes = 1 * 1024 * 1024
    private static let maximumFingerprintTotalBytes = 4 * 1024 * 1024
    private let executor: any GuideSourceWorkspaceCommandExecuting
    private let store: any GuideSourceWorkspaceRecording
    private let destinationIsOwned: @Sendable (URL) -> Bool
    /// There is one fixed-argv process lane. Keeping operation identity here
    /// lets a controller cancel exactly the stale setup it superseded without
    /// terminating a newer retry that has already acquired the lane.
    private let operationLock = NSLock()
    private var activeOperationID: UUID?
    private var cancelledOperationIDs = Set<UUID>()

    init(
        executor: any GuideSourceWorkspaceCommandExecuting = GuideSourceWorkspaceProcessExecutor(),
        store: any GuideSourceWorkspaceRecording,
        destinationIsOwned: @escaping @Sendable (URL) -> Bool
    ) {
        self.executor = executor
        self.store = store
        self.destinationIsOwned = destinationIsOwned
    }

    /// Cancel a setup operation that is currently inspecting or staging. The
    /// in-memory identity guard alone is not enough: without stopping the
    /// executor, a cancelled inspection can keep probing and a cancelled
    /// staging attempt can still create a worktree after the user has pressed
    /// Cancel. A call for an already-finished operation is harmless.
    func cancel(runID: UUID) {
        operationLock.lock()
        cancelledOperationIDs.insert(runID)
        let ownsExecutor = activeOperationID == runID
        operationLock.unlock()
        if ownsExecutor {
            executor.cancelRunningProcess()
        }
    }

    func inspect(_ request: GuideSourceWorkspaceRequest) async -> Result<GuideSourceWorkspaceInspection, GuideSourceWorkspacePreparationError> {
        guard await beginOperation(request.runID) else {
            return .failure(.invalidRequest("another workspace operation is already in progress"))
        }
        defer { endOperation(request.runID) }
        do {
            try throwIfOperationWasCancelled(request.runID)
            let identity = try await inspectIdentity(request)
            try throwIfOperationWasCancelled(request.runID)
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
        guard await beginOperation(request.runID) else {
            throw GuideSourceWorkspacePreparationError.invalidRequest(
                "another workspace operation is already in progress"
            )
        }
        defer { endOperation(request.runID) }
        do {
            try throwIfOperationWasCancelled(request.runID)
            return try await prepareImpl(request, from: inspection, choice: choice)
        } catch is CancellationError {
            throw GuideSourceWorkspacePreparationError.cancelled
        }
    }

    /// Re-probes every identity that makes a prepared workspace safe to use.
    /// Persisted bindings are only hints: a changed checkout, replaced staged
    /// directory, guide revision, or missing ready record invalidates them.
    func revalidate(_ binding: GuideSourceWorkspaceBinding) async -> Result<GuideSourceWorkspaceBinding, GuideSourceWorkspacePreparationError> {
        guard await beginOperation(binding.runID) else {
            return .failure(.invalidRequest("another workspace operation is already in progress"))
        }
        defer { endOperation(binding.runID) }
        do {
            guard binding.guideID.isEmpty == false,
                  binding.guideRevision >= 0,
                  isSafeIdentifier(binding.guideID),
                  isSafeIdentifier(binding.projectID),
                  binding.originalPath.hasPrefix("/"),
                  binding.stagedPath.hasPrefix("/"),
                  binding.expectedOrigin == binding.original.origin,
                  binding.original.commonGitDirectory == binding.commonGitDirectory,
                  binding.staged.commonGitDirectory == binding.commonGitDirectory else {
                throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("workspace binding metadata is inconsistent")
            }
            let originalRequest = GuideSourceWorkspaceRequest(
                runID: binding.runID, guideID: binding.guideID, guideRevision: binding.guideRevision,
                projectID: binding.projectID, sourcePath: binding.originalPath,
                expectedOrigin: "https://\(binding.expectedOrigin.host)/\(binding.expectedOrigin.path)",
                expectedCommit: binding.expectedCommit,
                ownedProjectsRoot: URL(fileURLWithPath: binding.stagedPath).deletingLastPathComponent()
            )
            let original = try await inspectIdentity(originalRequest)
            // The source checkout may already be dirty and can legitimately
            // receive unrelated edits while the isolated worktree is being
            // used. Isolation pins execution to the staged revision, so do
            // not invalidate that safe binding merely because the original's
            // porcelain or fingerprint changed. Keep its location, origin,
            // revision, and Git common directory anchored.
            guard original.canonicalPath == binding.original.canonicalPath,
                  original.origin == binding.original.origin,
                  original.head == binding.original.head,
                  original.expectedCommitIsPresent,
                  original.commonGitDirectory == binding.commonGitDirectory else {
                throw GuideSourceWorkspacePreparationError.sourceRevisionMismatch(
                    expected: binding.original.head, observed: original.head
                )
            }
            let stagedURL = URL(fileURLWithPath: binding.stagedPath, isDirectory: true).standardizedFileURL
            if binding.isIsolated {
                let ownedRoot = stagedURL.deletingLastPathComponent()
                let expectedDestinationName = "\(binding.projectID)-\(binding.runID.uuidString)"
                guard destinationIsOwned(ownedRoot),
                      stagedURL.lastPathComponent == expectedDestinationName,
                      GuideSourceWorkspacePath.validateExistingOwnedDestination(
                          stagedURL, within: ownedRoot
                      ) else {
                    throw GuideSourceWorkspacePreparationError.destinationNotOwned
                }
            }
            guard stagedURL.path == stagedURL.resolvingSymlinksInPath().standardizedFileURL.path,
                  FileManager.default.fileExists(atPath: stagedURL.path) else {
                throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("staged workspace directory is unavailable")
            }
            if binding.isIsolated {
                guard let recordReader = store as? any GuideSourceWorkspaceRecordReading,
                      let record = recordReader.record(for: binding.runID),
                      record.state == .ready,
                      record.guideID == binding.guideID,
                      record.guideRevision == binding.guideRevision,
                      record.projectID == binding.projectID,
                      record.originalPath == binding.originalPath,
                      record.stagedPath == binding.stagedPath,
                      record.expectedOrigin == "https://\(binding.expectedOrigin.host)/\(binding.expectedOrigin.path)",
                      record.expectedCommit == binding.expectedCommit,
                      record.ownershipMarker == binding.ownershipMarker else {
                    throw GuideSourceWorkspacePreparationError.destinationNotOwned
                }
            } else {
                guard binding.ownershipMarker == "existing-user-checkout" else {
                    throw GuideSourceWorkspacePreparationError.destinationNotOwned
                }
            }
            let stagedRequest = GuideSourceWorkspaceRequest(
                runID: binding.runID, guideID: binding.guideID, guideRevision: binding.guideRevision,
                projectID: binding.projectID, sourcePath: binding.stagedPath,
                expectedOrigin: "https://\(binding.expectedOrigin.host)/\(binding.expectedOrigin.path)",
                expectedCommit: binding.expectedCommit,
                ownedProjectsRoot: URL(fileURLWithPath: binding.stagedPath).deletingLastPathComponent()
            )
            let staged = try await inspectIdentity(stagedRequest)
            // A staged worktree can acquire ignored/generated files between
            // launches (for example package-manager caches).  Those files do
            // not change the reviewed Git revision and must not make a valid
            // binding unusable.  Keep the security boundary on canonical
            // location, origin, revision, common Git directory, and a clean
            // tracked checkout; refresh the non-authoritative fingerprint in
            // the returned binding instead of requiring byte-for-byte
            // identity with the previous probe.
            guard staged.canonicalPath == binding.staged.canonicalPath,
                  staged.origin == binding.staged.origin,
                  staged.commonGitDirectory == binding.commonGitDirectory,
                  staged.head == binding.expectedCommit,
                  staged.expectedCommitIsPresent,
                  !staged.isDirty else {
                throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("staged workspace identity changed")
            }
            let linkedGitDirectory = try await readGitDirectory(in: stagedURL)
            guard linkedGitDirectory == binding.linkedWorktreeGitDirectory else {
                throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed(
                    "linked worktree identity changed"
                )
            }
            let refreshedBinding = GuideSourceWorkspaceBinding(
                runID: binding.runID,
                guideID: binding.guideID,
                guideRevision: binding.guideRevision,
                projectID: binding.projectID,
                original: binding.original,
                staged: staged,
                originalPath: binding.originalPath,
                stagedPath: binding.stagedPath,
                expectedOrigin: binding.expectedOrigin,
                expectedCommit: binding.expectedCommit,
                ownershipMarker: binding.ownershipMarker,
                commonGitDirectory: binding.commonGitDirectory,
                linkedWorktreeGitDirectory: binding.linkedWorktreeGitDirectory,
                isIsolated: binding.isIsolated
            )
            return .success(refreshedBinding)
        } catch let error as GuideSourceWorkspacePreparationError {
            return .failure(error)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.stagedWorkspaceVerificationFailed(error.localizedDescription))
        }
    }

    /// Name used by callers that want the admission operation to read like a
    /// guard immediately before a command or retry.
    func validateBinding(_ binding: GuideSourceWorkspaceBinding) async -> Bool {
        if case .success = await revalidate(binding) { return true }
        return false
    }

    private func prepareImpl(
        _ request: GuideSourceWorkspaceRequest,
        from inspection: GuideSourceWorkspaceInspection,
        choice: GuideSourceWorkspaceSetupChoice
    ) async throws -> GuideSourceWorkspaceBinding {
        try throwIfOperationWasCancelled(request.runID)
        let freshIdentity = try await inspectIdentity(request)
        try throwIfOperationWasCancelled(request.runID)
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
            return try await makeExistingBinding(request: request, identity: freshIdentity)
        case (.existingClean, .createIsolatedWorktree):
            return try await stage(request: request, identity: freshIdentity)
        case (.isolatedCopyOffered, .useExistingCleanCheckout):
            throw GuideSourceWorkspacePreparationError.dirtyCheckoutRequiresIsolation
        case (.isolatedCopyOffered, .createIsolatedWorktree):
            return try await stage(request: request, identity: freshIdentity)
        }
    }

    private func inspectIdentity(_ request: GuideSourceWorkspaceRequest) async throws -> GuideSourceWorkspaceIdentity {
        try throwIfOperationWasCancelled(request.runID)
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
        let topLevelResult = try await runGit(["rev-parse", "--show-toplevel"], in: source)
        try throwIfOperationWasCancelled(request.runID)
        let headResult = try await runGit(["rev-parse", "--verify", "HEAD^{commit}"], in: source)
        try throwIfOperationWasCancelled(request.runID)
        let originResult = try await runGit(["remote", "get-url", "origin"], in: source)
        try throwIfOperationWasCancelled(request.runID)
        let statusResult = try await runGit(["status", "--porcelain=v1", "--untracked-files=all", "-z"], in: source)
        try throwIfOperationWasCancelled(request.runID)
        let expectedResult = try await runGit(["rev-parse", "--verify", "\(request.expectedCommit)^{commit}"], in: source)
        try throwIfOperationWasCancelled(request.runID)
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
        guard topLevelResult.exitCode == 0, statusResult.exitCode == 0, commonResult.exitCode == 0,
              !topLevelResult.outputWasTruncated,
              !statusResult.outputWasTruncated else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("Git checkout identity could not be read")
        }
        let topLevelText = topLevelResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topLevelText.isEmpty else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("Git checkout root could not be read")
        }
        let topLevel = URL(fileURLWithPath: topLevelText).standardizedFileURL
        guard topLevel.path == source.path,
              topLevel.path == topLevel.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw GuideSourceWorkspacePreparationError.sourceUnavailable("select the Git repository root")
        }
        let workingTreeFingerprint = try fingerprint(
            source: source, porcelain: statusResult.output
        )
        try throwIfOperationWasCancelled(request.runID)
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
        try throwIfOperationWasCancelled(request.runID)
        let root = request.ownedProjectsRoot.standardizedFileURL
        guard destinationIsOwned(root) else {
            throw GuideSourceWorkspacePreparationError.destinationNotOwned
        }
        let destination = root.appendingPathComponent(
            "\(request.projectID)-\(request.runID.uuidString)", isDirectory: true
        )
        // A cancelled Git process can finish creating the linked worktree just
        // before cancellation reaches this service. Reusing that path is safe
        // only when the write-ahead record names this exact request and the
        // destination still proves it is a Test-owned, clean worktree. Without
        // this branch, a retry gets a new run ID and leaves the old owned copy
        // behind while creating a duplicate.
        let existingRecord: GuideSourceWorkspaceRecord?
        if FileManager.default.fileExists(atPath: destination.path) {
            guard let recordReader = store as? any GuideSourceWorkspaceRecordReading,
                  let record = recordReader.record(for: request.runID),
                  record.guideID == request.guideID,
                  record.guideRevision == request.guideRevision,
                  record.projectID == request.projectID,
                  record.originalPath == identity.canonicalPath,
                  record.stagedPath == destination.path,
                  record.expectedOrigin == request.expectedOrigin,
                  record.expectedCommit == request.expectedCommit,
                  record.state != .ready,
                  GuideSourceWorkspacePath.validateExistingOwnedDestination(
                      destination, within: root
                  ) else {
                throw GuideSourceWorkspacePreparationError.destinationAlreadyExists
            }
            existingRecord = record
        } else {
            guard GuideSourceWorkspacePath.validateOwnedDestination(destination, within: root) else {
                throw GuideSourceWorkspacePreparationError.destinationAlreadyExists
            }
            existingRecord = nil
        }
        let marker = existingRecord?.ownershipMarker ?? UUID().uuidString
        do {
            if let existingRecord {
                return try await resumeExistingStage(
                    request: request, identity: identity, record: existingRecord
                )
            }
            do {
                try saveRecord(GuideSourceWorkspaceRecord(
                    runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                    projectID: request.projectID, originalPath: identity.canonicalPath, stagedPath: destination.path,
                    expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                    ownershipMarker: marker, state: .staging
                ))
            } catch {
                throw GuideSourceWorkspacePreparationError.recoveryRecordCouldNotBeSaved
            }
            try throwIfOperationWasCancelled(request.runID)
            let result = try await runGit([
                "worktree", "add", "--detach", destination.path, request.expectedCommit
            ], in: URL(fileURLWithPath: identity.canonicalPath, isDirectory: true))
            guard result.exitCode == 0 else {
                throw GuideSourceWorkspacePreparationError.worktreeCommandFailed(
                    exitCode: result.exitCode, output: result.output
                )
            }
            guard GuideSourceWorkspacePath.validateExistingOwnedDestination(
                destination, within: root
            ) else {
                throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed(
                    "created worktree is not inside the Test-owned destination"
                )
            }
            try throwIfOperationWasCancelled(request.runID)
            let stagedIdentity = try await inspectIdentity(
                GuideSourceWorkspaceRequest(
                    runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                    projectID: request.projectID, sourcePath: destination.path,
                    expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                    ownedProjectsRoot: request.ownedProjectsRoot
                )
            )
            try throwIfOperationWasCancelled(request.runID)
            guard !stagedIdentity.isDirty, stagedIdentity.head == request.expectedCommit else {
                throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("staged worktree is not clean at the expected commit")
            }
            // Worktree creation touches the shared Git administrative area.
            // Re-read the source after it returns so a source edited while Git
            // was staging is never represented by a stale binding.
            let finalOriginalIdentity = try await inspectIdentity(request)
            guard finalOriginalIdentity == identity else {
                throw GuideSourceWorkspacePreparationError.sourceChangedSinceInspection
            }
            try throwIfOperationWasCancelled(request.runID)
            let linkedGitDirectory = try await readGitDirectory(in: destination)
            try throwIfOperationWasCancelled(request.runID)
            let binding = GuideSourceWorkspaceBinding(
                runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                projectID: request.projectID, original: identity, staged: stagedIdentity,
                originalPath: identity.canonicalPath, stagedPath: destination.path,
                expectedOrigin: identity.origin, expectedCommit: request.expectedCommit,
                ownershipMarker: marker, commonGitDirectory: identity.commonGitDirectory,
                linkedWorktreeGitDirectory: linkedGitDirectory, isIsolated: true
            )
            do {
                try throwIfOperationWasCancelled(request.runID)
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
        } catch let error as GuideSourceWorkspacePreparationError {
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
            throw error
        } catch {
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
            throw error
        }
    }

    /// Admit a destination left by a cancelled or failed setup attempt. The
    /// persisted record is only a candidate: Git origin, commit, clean state,
    /// source identity, ownership and linked-worktree admin identity are all
    /// re-read before the record can become ready again.
    private func resumeExistingStage(
        request: GuideSourceWorkspaceRequest,
        identity: GuideSourceWorkspaceIdentity,
        record: GuideSourceWorkspaceRecord
    ) async throws -> GuideSourceWorkspaceBinding {
        guard [.staging, .cancelled, .failed].contains(record.state),
              record.originalPath == identity.canonicalPath,
              record.stagedPath == URL(fileURLWithPath: record.stagedPath).standardizedFileURL.path else {
            throw GuideSourceWorkspacePreparationError.destinationNotOwned
        }
        let destination = URL(fileURLWithPath: record.stagedPath, isDirectory: true)
        let root = request.ownedProjectsRoot.standardizedFileURL
        guard GuideSourceWorkspacePath.validateExistingOwnedDestination(destination, within: root) else {
            throw GuideSourceWorkspacePreparationError.destinationNotOwned
        }
        try throwIfOperationWasCancelled(request.runID)
        let stagedIdentity = try await inspectIdentity(
            GuideSourceWorkspaceRequest(
                runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                projectID: request.projectID, sourcePath: destination.path,
                expectedOrigin: request.expectedOrigin, expectedCommit: request.expectedCommit,
                ownedProjectsRoot: request.ownedProjectsRoot
            )
        )
        try throwIfOperationWasCancelled(request.runID)
        guard !stagedIdentity.isDirty, stagedIdentity.head == request.expectedCommit else {
            throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed(
                "recorded worktree is not clean at the expected commit"
            )
        }
        let finalOriginalIdentity = try await inspectIdentity(request)
        guard finalOriginalIdentity == identity else {
            throw GuideSourceWorkspacePreparationError.sourceChangedSinceInspection
        }
        try throwIfOperationWasCancelled(request.runID)
        let linkedGitDirectory = try await readGitDirectory(in: destination)
        let binding = GuideSourceWorkspaceBinding(
            runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
            projectID: request.projectID, original: identity, staged: stagedIdentity,
            originalPath: identity.canonicalPath, stagedPath: destination.path,
            expectedOrigin: identity.origin, expectedCommit: request.expectedCommit,
            ownershipMarker: record.ownershipMarker, commonGitDirectory: identity.commonGitDirectory,
            linkedWorktreeGitDirectory: linkedGitDirectory, isIsolated: true
        )
        do {
            try throwIfOperationWasCancelled(request.runID)
            try saveRecord(GuideSourceWorkspaceRecord(
                runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
                projectID: request.projectID, originalPath: identity.canonicalPath,
                stagedPath: destination.path, expectedOrigin: request.expectedOrigin,
                expectedCommit: request.expectedCommit, ownershipMarker: record.ownershipMarker,
                state: .ready
            ))
        } catch {
            throw GuideSourceWorkspacePreparationError.recoveryRecordCouldNotBeSaved
        }
        return binding
    }

    private func makeExistingBinding(
        request: GuideSourceWorkspaceRequest,
        identity: GuideSourceWorkspaceIdentity
    ) async throws -> GuideSourceWorkspaceBinding {
        let linkedGitDirectory = try await readGitDirectory(
            in: URL(fileURLWithPath: identity.canonicalPath, isDirectory: true)
        )
        try throwIfOperationWasCancelled(request.runID)
        return GuideSourceWorkspaceBinding(
            runID: request.runID, guideID: request.guideID, guideRevision: request.guideRevision,
            projectID: request.projectID, original: identity, staged: identity,
            originalPath: identity.canonicalPath, stagedPath: identity.canonicalPath,
            expectedOrigin: identity.origin, expectedCommit: request.expectedCommit,
            ownershipMarker: "existing-user-checkout", commonGitDirectory: identity.commonGitDirectory,
            linkedWorktreeGitDirectory: linkedGitDirectory, isIsolated: false
        )
    }

    private func readGitDirectory(in worktree: URL) async throws -> String {
        let result = try await runGit(["rev-parse", "--git-dir"], in: worktree)
        guard result.exitCode == 0 else {
            throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("linked worktree admin path could not be read")
        }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\n"), !text.contains("\r") else {
            throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("linked worktree admin path is empty")
        }
        let path = URL(fileURLWithPath: text, relativeTo: worktree).standardizedFileURL
        guard path.path == path.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw GuideSourceWorkspacePreparationError.stagedWorkspaceVerificationFailed("linked worktree admin path contains a symlink")
        }
        return path.path
    }

    private func saveRecord(_ record: GuideSourceWorkspaceRecord) throws {
        try store.save(record)
    }

    private func beginOperation(_ operationID: UUID) async -> Bool {
        // A cancelled operation may still be unwinding the process executor
        // when the reader immediately retries. Wait for that bounded teardown
        // instead of turning a normal retry into an executor-busy error. A
        // live operation that was not cancelled remains a hard single-flight
        // refusal, so two independent setup requests cannot overlap. The
        // timeout keeps a broken executor from making the retry wait forever.
        let teardownDeadline = Date().addingTimeInterval(5)
        while true {
            switch beginOperationAttempt(operationID) {
            case .acquired:
                return true
            case .busy:
                return false
            case .waitForCancelledOperation:
                guard Date() < teardownDeadline else { return false }
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    return false
                }
            }
        }
    }

    private enum OperationStartDecision {
        case acquired
        case waitForCancelledOperation
        case busy
    }

    private func beginOperationAttempt(_ operationID: UUID) -> OperationStartDecision {
        operationLock.lock()
        defer { operationLock.unlock() }
        guard activeOperationID == nil else {
            let activeOperationWasCancelled = activeOperationID
                .map { cancelledOperationIDs.contains($0) } ?? false
            return activeOperationWasCancelled ? .waitForCancelledOperation : .busy
        }
        activeOperationID = operationID
        return .acquired
    }

    private func endOperation(_ operationID: UUID) {
        operationLock.lock()
        if activeOperationID == operationID {
            activeOperationID = nil
        }
        cancelledOperationIDs.remove(operationID)
        operationLock.unlock()
    }

    private func throwIfOperationWasCancelled(_ operationID: UUID) throws {
        try Task.checkCancellation()
        operationLock.lock()
        let cancelled = cancelledOperationIDs.contains(operationID)
        operationLock.unlock()
        if cancelled { throw CancellationError() }
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
