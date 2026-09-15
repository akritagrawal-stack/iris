import Foundation

extension OnDemandEditInterruptedRunRecovery {
    enum FailedReviewArchiveError: Error, Equatable {
        case recordTooLarge
        case archiveLimitExceeded
        case invalidArchiveEntry
    }

    static let maximumFailedReviewArchives = 256
    static let maximumFailedReviewArchiveBytes = 8 * 1024 * 1024
    static let maximumFailedReviewRecordBytes = 32 * 1024

    /// Dismissing a failure is not permission to lose its recovery record.
    static func forgetUnlessReviewIsRequired(recordPath: String = defaultRecordPath) {
        guard recordOnDisk(recordPath: recordPath)?.requiresReviewBeforeRecovery != true else { return }
        forget(recordPath: recordPath)
    }

    /// Before a new clean run takes ownership, preserve the previous failed
    /// run's exact record. This archives metadata, not source or app files.
    static func archiveHeldReviewBeforeNewRun(recordPath: String = defaultRecordPath) throws {
        guard recordOnDisk(recordPath: recordPath)?.requiresReviewBeforeRecovery == true else { return }
        let source = URL(fileURLWithPath: recordPath)
        let original = try Data(contentsOf: source)
        guard original.count <= maximumFailedReviewRecordBytes else {
            throw FailedReviewArchiveError.recordTooLarge
        }
        let directory = source.deletingLastPathComponent().appendingPathComponent("failed-edit-reviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".staging-") }
        guard existing.count < maximumFailedReviewArchives else {
            throw FailedReviewArchiveError.archiveLimitExceeded
        }
        var existingBytes = 0
        for entry in existing {
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  size.intValue >= 0,
                  size.intValue <= maximumFailedReviewRecordBytes,
                  existingBytes <= maximumFailedReviewArchiveBytes - size.intValue else {
                throw FailedReviewArchiveError.invalidArchiveEntry
            }
            existingBytes += size.intValue
        }
        guard existingBytes <= maximumFailedReviewArchiveBytes - original.count else {
            throw FailedReviewArchiveError.archiveLimitExceeded
        }
        let destination = directory.appendingPathComponent(UUID().uuidString + ".json")
        try original.write(to: destination, options: .withoutOverwriting)
        guard try Data(contentsOf: destination) == original,
              try Data(contentsOf: source) == original else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.removeItem(at: source)
    }
}
