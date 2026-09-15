import Foundation

/// Durable identity for a candidate that already passed the edit and review
/// gates. This is deliberately separate from PendingEditCandidateIdentity,
/// which describes a dirty pre-commit recovery state.
nonisolated struct AcceptedCandidateRecord: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum ValidationFailure: String, Codable, Equatable, Sendable, Error {
        case invalidRecord
        case projectMismatch
        case projectPathMismatch
        case bundleMismatch
        case sourceMismatch
        case evidenceMismatch
        case artifactPathMismatch
        case artifactDigestMismatch
        case receiptMissing
        case receiptMismatch
        case verificationEvidenceMissing
        case reviewEvidenceMissing
        case liveEvidenceMissing
        case liveEvidenceMismatch
    }

    let version: Int
    let candidateID: UUID
    let projectSlug: String
    let bundleIdentifier: String
    let registeredProjectPath: String
    let registeredApplicationPath: String
    let artifactPath: String
    let sourceIdentity: AppDeliveryReceipt.SourceIdentity
    let artifactDigest: String
    let verificationEvidenceID: UUID
    let reviewEvidenceID: UUID
    let uiAcceptedRunID: UUID?
    let uiAcceptedReceiptID: UUID?

    init(
        candidateID: UUID = UUID(),
        projectSlug: String,
        bundleIdentifier: String,
        registeredProjectPath: String,
        registeredApplicationPath: String,
        artifactPath: String,
        sourceIdentity: AppDeliveryReceipt.SourceIdentity,
        artifactDigest: String,
        verificationEvidenceID: UUID,
        reviewEvidenceID: UUID,
        uiAcceptedRunID: UUID? = nil,
        uiAcceptedReceiptID: UUID? = nil
    ) throws {
        self.version = Self.currentVersion
        self.candidateID = candidateID
        self.projectSlug = projectSlug
        self.bundleIdentifier = bundleIdentifier
        self.registeredProjectPath = registeredProjectPath
        self.registeredApplicationPath = registeredApplicationPath
        self.artifactPath = artifactPath
        self.sourceIdentity = sourceIdentity
        self.artifactDigest = artifactDigest.lowercased()
        self.verificationEvidenceID = verificationEvidenceID
        self.reviewEvidenceID = reviewEvidenceID
        self.uiAcceptedRunID = uiAcceptedRunID
        self.uiAcceptedReceiptID = uiAcceptedReceiptID
        guard isValid else { throw ValidationFailure.invalidRecord }
    }

    var isValid: Bool {
        version == Self.currentVersion
            && Self.isNonzero(candidateID)
            && Self.isSafeMetadata(projectSlug, maximumBytes: 256)
            && Self.isSafeBundleIdentifier(bundleIdentifier)
            && Self.isCanonicalAbsolutePath(registeredProjectPath)
            && Self.isCanonicalAbsolutePath(registeredApplicationPath)
            && Self.isCanonicalAbsolutePath(artifactPath)
            && sourceIdentity.isValid
            && Self.isSHA256Digest(artifactDigest)
            && Self.isNonzero(verificationEvidenceID)
            && Self.isNonzero(reviewEvidenceID)
            && ((uiAcceptedRunID == nil) == (uiAcceptedReceiptID == nil))
            && (uiAcceptedRunID == nil || Self.isNonzero(uiAcceptedRunID!))
            && (uiAcceptedReceiptID == nil || Self.isNonzero(uiAcceptedReceiptID!))
    }

    /// The registry and source checks are exact value checks. The caller must
    /// supply IDs that already refer to independently persisted positive
    /// verifier/reviewer evidence; UUID shape alone never proves a review.
    /// Filesystem content is checked separately so callers can report which identity
    /// became stale before any delivery action is considered.
    func failureAgainst(
        project: IrisTestProjectRegistry.Project,
        receipt: AppDeliveryReceipt?,
        expectedVerificationEvidenceID: UUID? = nil,
        expectedReviewEvidenceID: UUID? = nil
    ) -> ValidationFailure? {
        guard isValid else { return .invalidRecord }
        guard project.slug == projectSlug else { return .projectMismatch }
        guard project.clonePath == registeredProjectPath else { return .projectPathMismatch }
        guard project.applicationPath == registeredApplicationPath else { return .projectPathMismatch }
        guard project.buildArtifactPath == artifactPath else { return .artifactPathMismatch }
        guard project.bundleIdentifier == bundleIdentifier else { return .bundleMismatch }
        guard sourceIdentity.appSlug == project.slug,
              sourceIdentity.clonePath == project.clonePath,
              sourceIdentity.baseCommit == project.pinnedCommit else { return .sourceMismatch }
        guard expectedVerificationEvidenceID == nil || expectedVerificationEvidenceID == verificationEvidenceID,
              expectedReviewEvidenceID == nil || expectedReviewEvidenceID == reviewEvidenceID else {
            return .evidenceMismatch
        }
        guard let receipt else { return .receiptMissing }
        guard receipt.bundleIdentifier == bundleIdentifier,
              receipt.sourceArtifactPath == artifactPath,
              receipt.sourceIdentity == sourceIdentity,
              uiAcceptedReceiptID == nil || uiAcceptedReceiptID == receipt.identifier,
              receipt.replacementBundleIdentity?.bundleIdentifier == bundleIdentifier,
              receipt.replacementBundleIdentity?.contentDigest == artifactDigest else {
            return .receiptMismatch
        }
        return nil
    }

    /// Reuses AppDeliveryReceipt's existing deterministic bundle walk. No
    /// second hashing implementation is introduced for accepted candidates.
    func artifactDigestMatchesFilesystem() -> Bool {
        guard let identity = AppDeliveryReceipt.bundleIdentity(atPath: artifactPath) else { return false }
        return identity.bundleIdentifier == bundleIdentifier && identity.contentDigest == artifactDigest
    }

    static func digest(atArtifactPath path: String) -> String? {
        AppDeliveryReceipt.bundleIdentity(atPath: path)?.contentDigest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, candidateID, projectSlug, bundleIdentifier, registeredProjectPath
        case registeredApplicationPath, artifactPath, sourceIdentity, artifactDigest
        case verificationEvidenceID, reviewEvidenceID, uiAcceptedRunID, uiAcceptedReceiptID
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        guard rawContainer.allKeys.allSatisfy({ knownKeys.contains($0.stringValue) }) else {
            throw ValidationFailure.invalidRecord
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        candidateID = try container.decode(UUID.self, forKey: .candidateID)
        projectSlug = try container.decode(String.self, forKey: .projectSlug)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        registeredProjectPath = try container.decode(String.self, forKey: .registeredProjectPath)
        registeredApplicationPath = try container.decode(String.self, forKey: .registeredApplicationPath)
        artifactPath = try container.decode(String.self, forKey: .artifactPath)
        sourceIdentity = try container.decode(AppDeliveryReceipt.SourceIdentity.self, forKey: .sourceIdentity)
        artifactDigest = try container.decode(String.self, forKey: .artifactDigest)
        verificationEvidenceID = try container.decode(UUID.self, forKey: .verificationEvidenceID)
        reviewEvidenceID = try container.decode(UUID.self, forKey: .reviewEvidenceID)
        uiAcceptedRunID = try container.decodeIfPresent(UUID.self, forKey: .uiAcceptedRunID)
        uiAcceptedReceiptID = try container.decodeIfPresent(UUID.self, forKey: .uiAcceptedReceiptID)
        guard isValid else { throw ValidationFailure.invalidRecord }
    }

    private static func isSafeMetadata(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func isSafeBundleIdentifier(_ value: String) -> Bool {
        isSafeMetadata(value, maximumBytes: 256) && !value.contains("/")
    }

    private static func isCanonicalAbsolutePath(_ value: String) -> Bool {
        guard value.hasPrefix("/"), value != "/", value.utf8.count <= 4096,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return false }
        return URL(fileURLWithPath: value).standardizedFileURL.path == value
    }

    private static func isSHA256Digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    private static func isNonzero(_ value: UUID) -> Bool {
        value != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
}
