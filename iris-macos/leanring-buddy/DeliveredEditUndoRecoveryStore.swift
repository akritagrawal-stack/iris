import Foundation
import Darwin
#if canImport(IrisEnvironment)
import IrisEnvironment
#endif

/// Information for manual review, never authority to replay filesystem changes.
nonisolated struct DeliveredEditUndoRecoveryRecord: Codable, Equatable, Sendable {
    var version = 1
    let identifier: UUID
    let startedAt: Date
    let appSlug: String
    let appName: String
    let installedPath: String?
    let backupPath: String?
    let clonePath: String
    let branchName: String
    let originalCommit: String?
    let originalRef: String?
    /// The delivery receipt selected for this Undo, when the transaction was
    /// reconstructed from Saved Versions. Optional keeps the existing marker
    /// format readable and preserves the old in-session recovery path.
    // `var` is intentional: synthesized Decodable must read this key when a
    // restart marker was created from Saved Versions. Keeping the default
    // preserves decoding of the older marker format.
    var deliveryReceiptIdentifier: UUID? = nil

    var paths: [String] { [backupPath, installedPath, clonePath].compactMap { $0 } }

    var isValid: Bool {
        version == 1 && !appSlug.isEmpty && !appName.isEmpty
            && [appSlug, appName, branchName, originalCommit ?? "", originalRef ?? ""].allSatisfy {
                $0.utf8.count <= 1024 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            }
            && paths.allSatisfy {
                $0.hasPrefix("/") && $0 != "/" && $0.utf8.count <= 4096
                    && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            }
    }
}

nonisolated struct DeliveredEditUndoRecoveryStore: Sendable {
    enum Loaded: Equatable, Sendable {
        case absent
        case pending(DeliveredEditUndoRecoveryRecord)
        case unreadable

        var requiresReview: Bool { self != .absent }
    }

    enum StoreError: Error { case existingRecord, invalidRecord, recordChanged, synchronizationFailed }

    static let defaultRecordURL = IrisTestEnvironment.applicationSupportDirectory
        .appendingPathComponent("delivered-undo-recovery.json")
    let recordURL: URL

    init(recordURL: URL = Self.defaultRecordURL) { self.recordURL = recordURL }

    /// Even an unreadable marker suppresses automatic recovery. Missing targets
    /// or old timestamps never establish that an interrupted Undo finished.
    func load() -> Loaded {
        let descriptor = open(recordURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            return errno == ENOENT ? .absent : .unreadable
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
              (attributes.st_mode & S_IFMT) == S_IFREG,
              attributes.st_size >= 0,
              attributes.st_size <= 32_768,
              let data = try? handle.read(upToCount: 32_769),
              data.count <= 32_768,
              let record = try? JSONDecoder().decode(DeliveredEditUndoRecoveryRecord.self, from: data),
              record.isValid else { return .unreadable }
        return .pending(record)
    }

    func saveBeforeStarting(_ record: DeliveredEditUndoRecoveryRecord) throws {
        guard record.isValid else { throw StoreError.invalidRecord }
        guard load() == .absent else { throw StoreError.existingRecord }
        let directory = recordURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        // Exclusive creation prevents a second process from replacing pending
        // information. A crash during this write leaves a visible unreadable marker.
        let descriptor = open(recordURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw StoreError.existingRecord }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try synchronizeDirectory()
        guard load() == .pending(record) else { throw StoreError.recordChanged }
    }

    /// The coordinator calls this only for its live transaction after the
    /// recovery steps finish. Loaded records are exposed for review only.
    func clearAfterCompletion(identifier: UUID) throws {
        switch load() {
        case .absent: return
        case .pending(let record) where record.identifier == identifier:
            try FileManager.default.removeItem(at: recordURL)
            try synchronizeDirectory()
        default: throw StoreError.recordChanged
        }
    }

    private func synchronizeDirectory() throws {
        let descriptor = open(recordURL.deletingLastPathComponent().path, O_RDONLY)
        guard descriptor >= 0 else { throw StoreError.synchronizationFailed }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw StoreError.synchronizationFailed }
    }
}
