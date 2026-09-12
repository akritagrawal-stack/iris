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
    let temporaryPath = files.temporaryDirectory.path.hasPrefix("/var/")
        ? "/private" + files.temporaryDirectory.path : files.temporaryDirectory.path
    let root = URL(fileURLWithPath: temporaryPath, isDirectory: true).standardizedFileURL
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
    print("PASS accepted candidate round-trip, exact revalidation, stale identities, bounded/corrupt/symlink states")
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
