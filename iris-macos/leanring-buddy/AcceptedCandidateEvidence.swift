import Foundation

/// Persisted facts that make an accepted candidate reusable. These records are
/// deliberately metadata-only. They are not a delivery command, a source
/// snapshot, or a substitute for a fresh source probe.
nonisolated struct AcceptedCandidateEvidenceRecord: Codable, Equatable, Sendable {
    static let currentVersion = 1

    enum Kind: String, Codable, Sendable {
        case verification
        case review
        case uiAcceptance
    }

    enum Result: String, Codable, Sendable {
        case passed
        case failed
    }

    let version: Int
    let evidenceID: UUID
    let candidateID: UUID
    let kind: Kind
    let sourceIdentity: AppDeliveryReceipt.SourceIdentity
    let artifactDigest: String
    let result: Result
    /// Only UI acceptance evidence binds to a persisted delivery receipt and
    /// run. The run ID is also the evidence filename, so a random UUID cannot
    /// be presented as live acceptance without a matching persisted record.
    let receiptIdentifier: UUID?
    let runIdentifier: UUID?
    let observedBundleIdentity: AppDeliveryReceipt.BundleIdentity?

    init(
        evidenceID: UUID = UUID(),
        candidateID: UUID,
        kind: Kind,
        sourceIdentity: AppDeliveryReceipt.SourceIdentity,
        artifactDigest: String,
        result: Result,
        receiptIdentifier: UUID? = nil,
        runIdentifier: UUID? = nil,
        observedBundleIdentity: AppDeliveryReceipt.BundleIdentity? = nil
    ) throws {
        self.version = Self.currentVersion
        self.evidenceID = evidenceID
        self.candidateID = candidateID
        self.kind = kind
        self.sourceIdentity = sourceIdentity
        self.artifactDigest = artifactDigest.lowercased()
        self.result = result
        self.receiptIdentifier = receiptIdentifier
        self.runIdentifier = runIdentifier
        self.observedBundleIdentity = observedBundleIdentity
        guard isValid else { throw ValidationFailure.invalid }
    }

    enum ValidationFailure: Error, Equatable, Sendable {
        case invalid
    }

    var isValid: Bool {
        guard version == Self.currentVersion,
              evidenceID != UUID.zero,
              candidateID != UUID.zero,
              sourceIdentity.isValid,
              artifactDigest.utf8.count == 64,
              artifactDigest.allSatisfy({ $0.isHexDigit }) else { return false }
        switch kind {
        case .verification, .review:
            return receiptIdentifier == nil && runIdentifier == nil
                && observedBundleIdentity == nil
        case .uiAcceptance:
            guard let receiptIdentifier, receiptIdentifier != UUID.zero,
                  let runIdentifier, runIdentifier != UUID.zero,
                  evidenceID == runIdentifier,
                  let observedBundleIdentity, observedBundleIdentity.isValid,
                  observedBundleIdentity.contentDigest == artifactDigest else { return false }
            return true
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, evidenceID, candidateID, kind, sourceIdentity, artifactDigest
        case result, receiptIdentifier, runIdentifier, observedBundleIdentity
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        guard raw.allKeys.allSatisfy({ known.contains($0.stringValue) }) else {
            throw ValidationFailure.invalid
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        evidenceID = try container.decode(UUID.self, forKey: .evidenceID)
        candidateID = try container.decode(UUID.self, forKey: .candidateID)
        kind = try container.decode(Kind.self, forKey: .kind)
        sourceIdentity = try container.decode(AppDeliveryReceipt.SourceIdentity.self, forKey: .sourceIdentity)
        artifactDigest = try container.decode(String.self, forKey: .artifactDigest).lowercased()
        result = try container.decode(Result.self, forKey: .result)
        receiptIdentifier = try container.decodeIfPresent(UUID.self, forKey: .receiptIdentifier)
        runIdentifier = try container.decodeIfPresent(UUID.self, forKey: .runIdentifier)
        observedBundleIdentity = try container.decodeIfPresent(
            AppDeliveryReceipt.BundleIdentity.self, forKey: .observedBundleIdentity
        )
        guard isValid else { throw ValidationFailure.invalid }
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
