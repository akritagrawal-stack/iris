import Foundation
@testable import IrisHarnessNative

private struct AcceptedCandidateCheckFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Focused persistence and identity checks for the accepted-candidate seam.
/// Every path is a disposable fixture; no coordinator, model, app launch, or
/// delivery operation is constructed.
func runAcceptedCandidateRecordChecks() throws {
    let files = FileManager.default
    // The host's nested temporary scratch can be /var, a symlink on macOS.
    // Keep this disposable fixture under the canonical shared harness root so
    // the production no-symlink policy exercises only the two planted links.
    let root = URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
        .appendingPathComponent("iris-accepted-candidate-\(UUID().uuidString)", isDirectory: true)
    defer { try? files.removeItem(at: root) }

    let clone = root.appendingPathComponent("project", isDirectory: true)
    let application = root.appendingPathComponent("Apps/Fixture.app", isDirectory: true)
    let artifact = clone.appendingPathComponent("release/Fixture.app", isDirectory: true)
    let backup = root.appendingPathComponent("backup/Fixture.app", isDirectory: true)
    try files.createDirectory(at: clone, withIntermediateDirectories: true)
    try makeBundle(application, identifier: "com.fixture.candidate", payload: "current")
    try makeBundle(artifact, identifier: "com.fixture.candidate", payload: "candidate")
    try makeBundle(backup, identifier: "com.fixture.candidate", payload: "previous")
    let source = AppDeliveryReceipt.SourceIdentity(
        appSlug: "fixture-app", appName: "Fixture", clonePath: clone.path,
        branchName: "iris-edit", commit: String(repeating: "b", count: 40),
        baseCommit: String(repeating: "a", count: 40), baseRef: "main",
        changeId: "change-candidate"
    )
    guard let artifactIdentity = AppDeliveryReceipt.bundleIdentity(atPath: artifact.path),
          let applicationIdentity = AppDeliveryReceipt.bundleIdentity(atPath: application.path),
          let backupIdentity = AppDeliveryReceipt.bundleIdentity(atPath: backup.path),
          let artifactDigest = artifactIdentity.contentDigest else {
        throw AcceptedCandidateCheckFailure(message: "fixture bundle identity could not be captured")
    }
    let project = IrisTestProjectRegistry.Project(
        slug: "fixture-app", name: "Fixture", clonePath: clone.path,
        applicationPath: application.path, buildArtifactPath: artifact.path,
        bundleIdentifier: "com.fixture.candidate", pinnedCommit: source.baseCommit
    )
    let receipt = AppDeliveryReceipt(
        identifier: UUID(), bundleIdentifier: project.bundleIdentifier,
        installedPath: application.path, sourceArtifactPath: artifact.path,
        backupPath: backup.path, phase: .installed, sourceIdentity: source,
        installedBundleIdentity: backupIdentity, replacementBundleIdentity: artifactIdentity,
        backupBundleIdentity: backupIdentity
    )
    let record = try AcceptedCandidateRecord(
        projectSlug: project.slug, bundleIdentifier: project.bundleIdentifier,
        registeredProjectPath: project.clonePath,
        registeredApplicationPath: project.applicationPath, artifactPath: artifact.path,
        sourceIdentity: source, artifactDigest: artifactDigest,
        verificationEvidenceID: UUID(), reviewEvidenceID: UUID(),
        uiAcceptedRunID: UUID(), uiAcceptedReceiptID: receipt.identifier
    )
    do {
        _ = try AcceptedCandidateRecord(
            projectSlug: project.slug, bundleIdentifier: project.bundleIdentifier,
            registeredProjectPath: project.clonePath,
            registeredApplicationPath: project.applicationPath, artifactPath: artifact.path,
            sourceIdentity: source, artifactDigest: artifactDigest,
            verificationEvidenceID: UUID(), reviewEvidenceID: UUID(), uiAcceptedRunID: UUID()
        )
        throw AcceptedCandidateCheckFailure(message: "unpaired UI acceptance linkage was accepted")
    } catch let error as AcceptedCandidateRecord.ValidationFailure {
        guard error == .invalidRecord else { throw error }
    } catch {
        throw error
    }
    let store = AppDeliveryReceiptStore(baseDirectory: root.appendingPathComponent("receipts"))
    do {
        try store.saveAcceptedCandidate(record)
    } catch {
        throw AcceptedCandidateCheckFailure(message: "candidate save failed at " + store.acceptedCandidateURL(for: record.candidateID).path + ": " + String(describing: error))
    }
    guard case .valid(let loaded) = AppDeliveryReceiptStore(baseDirectory: store.baseDirectory)
        .loadAcceptedCandidate(record.candidateID), loaded == record else {
        throw AcceptedCandidateCheckFailure(message: "accepted candidate did not round-trip")
    }
    guard case .valid = store.revalidateAcceptedCandidate(record.candidateID, project: project, receipt: receipt) else {
        throw AcceptedCandidateCheckFailure(message: "current exact identities did not revalidate")
    }
    guard case .invalid(.receiptMissing) = store.revalidateAcceptedCandidateUsingPersistedEvidence(
        record.candidateID, project: project
    ) else {
        throw AcceptedCandidateCheckFailure(message: "caller-supplied receipt was treated as persisted evidence")
    }
    let preparedReceipt = AppDeliveryReceipt(
        identifier: receipt.identifier, bundleIdentifier: receipt.bundleIdentifier,
        installedPath: receipt.installedPath, sourceArtifactPath: receipt.sourceArtifactPath,
        backupPath: receipt.backupPath, startedAt: receipt.startedAt, phase: .prepared,
        sourceIdentity: receipt.sourceIdentity, installedBundleIdentity: receipt.installedBundleIdentity,
        replacementBundleIdentity: receipt.replacementBundleIdentity,
        backupBundleIdentity: receipt.backupBundleIdentity
    )
    try store.savePrepared(preparedReceipt)
    _ = try store.transition(preparedReceipt, to: .installed)
    guard case .invalid(.verificationEvidenceMissing) = store.revalidateAcceptedCandidateUsingPersistedEvidence(
        record.candidateID, project: project
    ) else {
        throw AcceptedCandidateCheckFailure(message: "UUID-only evidence was accepted as persisted evidence")
    }
    let reviewEvidence = try AcceptedCandidateEvidenceRecord(
        evidenceID: record.reviewEvidenceID, candidateID: record.candidateID, kind: .review,
        sourceIdentity: source, artifactDigest: artifactDigest, result: .passed
    )
    // The verifier ID was intentionally supplied above as a random UUID. The
    // persisted record must use the candidate's exact reference.
    let persistedVerification = try AcceptedCandidateEvidenceRecord(
        evidenceID: record.verificationEvidenceID, candidateID: record.candidateID,
        kind: .verification, sourceIdentity: source, artifactDigest: artifactDigest,
        result: .passed
    )
    try store.saveAcceptedCandidateEvidence(persistedVerification)
    try store.saveAcceptedCandidateEvidence(reviewEvidence)
    let liveEvidence = try AcceptedCandidateEvidenceRecord(
        evidenceID: record.uiAcceptedRunID!, candidateID: record.candidateID,
        kind: .uiAcceptance, sourceIdentity: source, artifactDigest: artifactDigest,
        result: .passed, receiptIdentifier: record.uiAcceptedReceiptID,
        runIdentifier: record.uiAcceptedRunID, observedBundleIdentity: artifactIdentity
    )
    try store.saveAcceptedCandidateEvidence(liveEvidence)
    guard case .valid = store.revalidateAcceptedCandidateUsingPersistedEvidence(
        record.candidateID, project: project
    ) else {
        throw AcceptedCandidateCheckFailure(message: "persisted receipt and evidence did not revalidate")
    }
    let forgedReview = try AcceptedCandidateEvidenceRecord(
        evidenceID: UUID(), candidateID: record.candidateID, kind: .review,
        sourceIdentity: source, artifactDigest: artifactDigest, result: .passed
    )
    do {
        try store.saveAcceptedCandidateEvidence(forgedReview)
        throw AcceptedCandidateCheckFailure(message: "unlinked review evidence was persisted")
    } catch let error as AppDeliveryReceiptStore.StoreError {
        guard error == .identityMismatch else { throw error }
    }
    print("PASS persisted candidate receipt, verifier, reviewer and live evidence gate; UUID-only records refused")
    guard case .invalid(.evidenceMismatch) = store.revalidateAcceptedCandidate(
        record.candidateID, project: project, receipt: receipt,
        expectedVerificationEvidenceID: UUID(), expectedReviewEvidenceID: record.reviewEvidenceID
    ) else { throw AcceptedCandidateCheckFailure(message: "stale review evidence was accepted") }

    let staleProject = IrisTestProjectRegistry.Project(
        slug: "different-app", name: project.name, clonePath: project.clonePath,
        applicationPath: project.applicationPath, buildArtifactPath: project.buildArtifactPath,
        bundleIdentifier: project.bundleIdentifier, pinnedCommit: project.pinnedCommit
    )
    guard case .invalid(.projectMismatch) = store.revalidateAcceptedCandidate(record.candidateID, project: staleProject, receipt: receipt) else {
        throw AcceptedCandidateCheckFailure(message: "stale registry identity was accepted")
    }
    let stalePathProject = IrisTestProjectRegistry.Project(
        slug: project.slug, name: project.name,
        clonePath: root.appendingPathComponent("other-project").path,
        applicationPath: project.applicationPath, buildArtifactPath: project.buildArtifactPath,
        bundleIdentifier: project.bundleIdentifier, pinnedCommit: project.pinnedCommit
    )
    guard case .invalid(.projectPathMismatch) = store.revalidateAcceptedCandidate(record.candidateID, project: stalePathProject, receipt: receipt) else {
        throw AcceptedCandidateCheckFailure(message: "stale project path was accepted")
    }
    let staleSourceProject = IrisTestProjectRegistry.Project(
        slug: project.slug, name: project.name, clonePath: project.clonePath,
        applicationPath: project.applicationPath, buildArtifactPath: project.buildArtifactPath,
        bundleIdentifier: project.bundleIdentifier, pinnedCommit: String(repeating: "c", count: 40)
    )
    guard case .invalid(.sourceMismatch) = store.revalidateAcceptedCandidate(record.candidateID, project: staleSourceProject, receipt: receipt) else {
        throw AcceptedCandidateCheckFailure(message: "stale source revision was accepted")
    }

    // Keep byte length stable while changing the artifact payload.
    try Data("CHANGED!!".utf8).write(to: artifact.appendingPathComponent("Contents/Payload.bin"))
    guard case .invalid(.artifactDigestMismatch) = store.revalidateAcceptedCandidate(record.candidateID, project: project, receipt: receipt) else {
        throw AcceptedCandidateCheckFailure(message: "same-size changed artifact was accepted")
    }
    try Data("candidate".utf8).write(to: artifact.appendingPathComponent("Contents/Payload.bin"))

    let absentID = UUID()
    guard case .absent = store.loadAcceptedCandidate(absentID) else {
        throw AcceptedCandidateCheckFailure(message: "absent candidate was not distinct")
    }
    let corruptID = UUID()
    try Data("{\"prompt\":\"secret\"}".utf8).write(to: store.acceptedCandidateURL(for: corruptID))
    guard case .corrupt = store.loadAcceptedCandidate(corruptID) else {
        throw AcceptedCandidateCheckFailure(message: "unknown fields were accepted as a candidate")
    }
    let oversizedID = UUID()
    try Data(repeating: 0x78, count: AppDeliveryReceiptStore.maximumRecordBytes + 1)
        .write(to: store.acceptedCandidateURL(for: oversizedID))
    guard case .oversized = store.loadAcceptedCandidate(oversizedID) else {
        throw AcceptedCandidateCheckFailure(message: "oversized candidate was not distinct")
    }
    let symlinkID = UUID()
    let symlinkDestination = store.acceptedCandidateURL(for: symlinkID)
    try FileManager.default.createSymbolicLink(at: symlinkDestination, withDestinationURL: store.acceptedCandidateURL(for: corruptID))
    guard case .symlink = store.loadAcceptedCandidate(symlinkID) else {
        throw AcceptedCandidateCheckFailure(message: "symlink candidate was not distinct")
    }

    // A symlinked base must not redirect either the candidate read or the
    // store lock into an outside fixture.
    let baseSymlinkRoot = root.appendingPathComponent("base-symlink-fixture", isDirectory: true)
    let baseTarget = baseSymlinkRoot.appendingPathComponent("outside-base", isDirectory: true)
    let baseAlias = baseSymlinkRoot.appendingPathComponent("receipts", isDirectory: true)
    try files.createDirectory(at: baseTarget, withIntermediateDirectories: true)
    let baseRecord = try recordCopy(record, candidateID: UUID())
    let baseTargetStore = AppDeliveryReceiptStore(baseDirectory: baseTarget)
    try baseTargetStore.saveAcceptedCandidate(baseRecord)
    let baseSnapshot = try snapshotRegularFiles(at: baseTarget)
    try files.createSymbolicLink(at: baseAlias, withDestinationURL: baseTarget)
    let baseSymlinkStore = AppDeliveryReceiptStore(baseDirectory: baseAlias)
    guard case .corrupt = baseSymlinkStore.loadAcceptedCandidate(baseRecord.candidateID) else {
        throw AcceptedCandidateCheckFailure(message: "symlinked base redirected an accepted-candidate read")
    }
    do {
        try baseSymlinkStore.saveAcceptedCandidate(try recordCopy(record, candidateID: UUID()))
        throw AcceptedCandidateCheckFailure(message: "symlinked base redirected an accepted-candidate write")
    } catch let error as AcceptedCandidateCheckFailure {
        throw error
    } catch {
        // Unsafe storage is a write failure, never an absent record.
    }
    guard case .storageFailure = baseSymlinkStore.revalidateAcceptedCandidate(
        baseRecord.candidateID, project: project, receipt: receipt
    ) else {
        throw AcceptedCandidateCheckFailure(message: "symlinked base acquired the redirected store lock")
    }
    guard try snapshotRegularFiles(at: baseTarget) == baseSnapshot else {
        throw AcceptedCandidateCheckFailure(message: "symlinked base changed the outside fixture")
    }
    print("PASS accepted-candidate base symlink refuses read, write and lock redirection")

    // A symlinked accepted-candidates parent must be refused after the safe
    // base lock is acquired and before a candidate leaf is opened or written.
    let parentSymlinkRoot = root.appendingPathComponent("parent-symlink-fixture", isDirectory: true)
    let parentBase = parentSymlinkRoot.appendingPathComponent("receipts", isDirectory: true)
    let parentOutside = parentSymlinkRoot.appendingPathComponent("outside-candidates", isDirectory: true)
    try files.createDirectory(at: parentBase, withIntermediateDirectories: true)
    try files.createDirectory(at: parentOutside, withIntermediateDirectories: true)
    let parentRecord = try recordCopy(record, candidateID: UUID())
    let parentData = try JSONEncoder().encode(parentRecord)
    try parentData.write(to: parentOutside.appendingPathComponent(parentRecord.candidateID.uuidString + ".json"), options: .atomic)
    let parentStore = AppDeliveryReceiptStore(baseDirectory: parentBase)
    try files.createSymbolicLink(at: parentStore.acceptedCandidatesDirectory, withDestinationURL: parentOutside)
    let parentSnapshot = try snapshotRegularFiles(at: parentOutside)
    guard case .corrupt = parentStore.loadAcceptedCandidate(parentRecord.candidateID) else {
        throw AcceptedCandidateCheckFailure(message: "symlinked candidate parent redirected an accepted-candidate read")
    }
    do {
        try parentStore.saveAcceptedCandidate(try recordCopy(record, candidateID: UUID()))
        throw AcceptedCandidateCheckFailure(message: "symlinked candidate parent redirected an accepted-candidate write")
    } catch let error as AcceptedCandidateCheckFailure {
        throw error
    } catch {
        // Unsafe storage is a write failure, never an absent record.
    }
    guard case .corrupt = parentStore.revalidateAcceptedCandidate(
        parentRecord.candidateID, project: project, receipt: receipt
    ) else {
        throw AcceptedCandidateCheckFailure(message: "symlinked candidate parent was not reported as corrupt storage")
    }
    guard try snapshotRegularFiles(at: parentOutside) == parentSnapshot else {
        throw AcceptedCandidateCheckFailure(message: "symlinked candidate parent changed the outside fixture")
    }
    print("PASS accepted-candidate parent symlink refuses read and write redirection")
    print("PASS accepted candidate round-trip, exact revalidation, stale identities, bounded/corrupt/symlink states")
}

private func recordCopy(_ source: AcceptedCandidateRecord, candidateID: UUID) throws -> AcceptedCandidateRecord {
    try AcceptedCandidateRecord(
        candidateID: candidateID, projectSlug: source.projectSlug,
        bundleIdentifier: source.bundleIdentifier,
        registeredProjectPath: source.registeredProjectPath,
        registeredApplicationPath: source.registeredApplicationPath,
        artifactPath: source.artifactPath, sourceIdentity: source.sourceIdentity,
        artifactDigest: source.artifactDigest,
        verificationEvidenceID: source.verificationEvidenceID,
        reviewEvidenceID: source.reviewEvidenceID,
        uiAcceptedRunID: source.uiAcceptedRunID,
        uiAcceptedReceiptID: source.uiAcceptedReceiptID
    )
}

private func snapshotRegularFiles(at root: URL) throws -> [String: Data] {
    let files = FileManager.default
    let relativePaths = try files.subpathsOfDirectory(atPath: root.path)
    var snapshot: [String: Data] = [:]
    for relativePath in relativePaths {
        let path = root.appendingPathComponent(relativePath)
        var metadata = stat()
        guard lstat(path.path, &metadata) == 0 else {
            throw AcceptedCandidateCheckFailure(message: "outside fixture could not be inspected")
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { continue }
        snapshot[relativePath] = try Data(contentsOf: path)
    }
    return snapshot
}

private func makeBundle(_ path: URL, identifier: String, payload: String) throws {
    let contents = path.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info: [String: Any] = [
        "CFBundleIdentifier": identifier,
        "CFBundleName": "Fixture",
        "CFBundleExecutable": "Fixture",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1"
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    try Data(payload.utf8).write(to: contents.appendingPathComponent("Payload.bin"))
}
