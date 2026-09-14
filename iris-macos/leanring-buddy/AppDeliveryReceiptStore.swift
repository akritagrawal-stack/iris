import Foundation
import Darwin
import CryptoKit

private extension JSONEncoder {
    static var acceptedCandidateEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// Durable, path-bound metadata for one installed-app delivery. The receipt is
/// recovery evidence, not proof that any path still contains the recorded app.
nonisolated struct AppDeliveryReceipt: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case prepared, installed, restored }

    /// The exact source revision that produced the replacement bundle. Older
    /// receipts do not have this value, so they remain readable but cannot be
    /// used to start an Undo after a restart.
    struct SourceIdentity: Codable, Equatable, Sendable {
        let appSlug: String
        let appName: String
        let clonePath: String
        let branchName: String
        let commit: String
        let baseCommit: String
        let baseRef: String?
        let changeId: String

        init(
            appSlug: String,
            appName: String,
            clonePath: String,
            branchName: String,
            commit: String,
            baseCommit: String,
            baseRef: String?,
            changeId: String
        ) {
            self.appSlug = appSlug
            self.appName = appName
            self.clonePath = clonePath
            self.branchName = branchName
            self.commit = commit
            self.baseCommit = baseCommit
            self.baseRef = baseRef
            self.changeId = changeId
        }

        var isValid: Bool {
            let textValues = [appSlug, appName, branchName, changeId]
            return !appSlug.isEmpty && !appName.isEmpty
                && textValues.allSatisfy(AppDeliveryReceipt.isSafeMetadataText)
                && AppDeliveryReceipt.isCanonicalAbsolutePath(clonePath)
                && AppDeliveryReceipt.isGitObjectID(commit)
                && AppDeliveryReceipt.isGitObjectID(baseCommit)
                && (baseRef == nil || AppDeliveryReceipt.isSafeMetadataText(baseRef!))
        }
    }

    /// Identity read from a bundle's Info.plist before delivery. This records
    /// the old installed identity as well as the fresh replacement identity so
    /// Undo can refuse a path or bundle that changed after Iris restarted.
    struct BundleIdentity: Codable, Equatable, Sendable {
        let bundleIdentifier: String
        let bundleName: String
        let shortVersion: String?
        let version: String?
        let executable: String?
        /// A deterministic digest of the bundle payload, including relative
        /// paths, file kinds, modes, and bytes. It catches a replacement that
        /// keeps the same bundle identifier and version. This is optional only
        /// for decoding old receipts; a new receipt cannot be Undoable without
        /// it.
        let contentDigest: String?

        init(
            bundleIdentifier: String,
            bundleName: String,
            shortVersion: String? = nil,
            version: String? = nil,
            executable: String? = nil,
            contentDigest: String? = nil
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.bundleName = bundleName
            self.shortVersion = shortVersion
            self.version = version
            self.executable = executable
            self.contentDigest = contentDigest
        }

        var isValid: Bool {
            guard !bundleIdentifier.isEmpty, !bundleName.isEmpty,
                  AppDeliveryReceipt.isSafeMetadataText(bundleIdentifier),
                  AppDeliveryReceipt.isSafeMetadataText(bundleName),
                  !bundleIdentifier.contains("/") else { return false }
            guard ([shortVersion, version, executable].compactMap { $0 })
                .allSatisfy(AppDeliveryReceipt.isSafeMetadataText) else { return false }
            guard let contentDigest else { return true }
            return AppDeliveryReceipt.isSHA256Digest(contentDigest)
        }

        /// Compare the inexpensive Info.plist portion of an identity. The
        /// content digest is checked separately off the main actor.
        func matchesMetadata(of other: BundleIdentity) -> Bool {
            bundleIdentifier == other.bundleIdentifier
                && bundleName == other.bundleName
                && shortVersion == other.shortVersion
                && version == other.version
                && executable == other.executable
        }
    }

    static let currentVersion = 1
    let version: Int
    let identifier: UUID
    let bundleIdentifier: String
    let installedPath: String
    let sourceArtifactPath: String
    let backupPath: String
    let startedAt: Date
    let phase: Phase
    let sourceIdentity: SourceIdentity?
    let installedBundleIdentity: BundleIdentity?
    let replacementBundleIdentity: BundleIdentity?
    let backupBundleIdentity: BundleIdentity?

    init(
        identifier: UUID = UUID(), bundleIdentifier: String, installedPath: String,
        sourceArtifactPath: String, backupPath: String, startedAt: Date = Date(),
        phase: Phase = .prepared,
        sourceIdentity: SourceIdentity? = nil,
        installedBundleIdentity: BundleIdentity? = nil,
        replacementBundleIdentity: BundleIdentity? = nil,
        backupBundleIdentity: BundleIdentity? = nil
    ) {
        self.version = Self.currentVersion
        self.identifier = identifier
        self.bundleIdentifier = bundleIdentifier
        self.installedPath = installedPath
        self.sourceArtifactPath = sourceArtifactPath
        self.backupPath = backupPath
        self.startedAt = startedAt
        self.phase = phase
        self.sourceIdentity = sourceIdentity
        self.installedBundleIdentity = installedBundleIdentity
        self.replacementBundleIdentity = replacementBundleIdentity
        self.backupBundleIdentity = backupBundleIdentity
    }

    struct Identity: Equatable, Sendable {
        let identifier: UUID
        let bundleIdentifier: String
        let installedPath: String
        let sourceArtifactPath: String
        let backupPath: String
        let startedAt: Date
        let sourceIdentity: SourceIdentity?
        let installedBundleIdentity: BundleIdentity?
        let replacementBundleIdentity: BundleIdentity?
        let backupBundleIdentity: BundleIdentity?
    }

    var identity: Identity {
        Identity(identifier: identifier, bundleIdentifier: bundleIdentifier,
                 installedPath: installedPath, sourceArtifactPath: sourceArtifactPath,
                 backupPath: backupPath, startedAt: startedAt,
                 sourceIdentity: sourceIdentity,
                 installedBundleIdentity: installedBundleIdentity,
                 replacementBundleIdentity: replacementBundleIdentity,
                 backupBundleIdentity: backupBundleIdentity)
    }

    /// New deliveries must carry all fields needed to reconstruct an Undo.
    /// Legacy receipts remain visible and inspectable, but this is false for
    /// them so a restart cannot guess which source or bundle to restore.
    var hasCompleteUndoMetadata: Bool {
        guard phase == .installed,
              let sourceIdentity, sourceIdentity.isValid,
              let installedBundleIdentity, installedBundleIdentity.isValid,
              let replacementBundleIdentity, replacementBundleIdentity.isValid,
              let backupBundleIdentity, backupBundleIdentity.isValid,
              installedBundleIdentity.contentDigest != nil,
              replacementBundleIdentity.contentDigest != nil,
              backupBundleIdentity.contentDigest != nil else { return false }
        return installedBundleIdentity == backupBundleIdentity
            && replacementBundleIdentity.bundleIdentifier == bundleIdentifier
            && installedBundleIdentity.bundleIdentifier == bundleIdentifier
    }

    /// Read the stable bundle identity and a deterministic payload digest. The
    /// path itself stays in the receipt because two bundles with one identifier
    /// can coexist. This can be called from a detached delivery task; callers
    /// on the main actor should use `bundleMetadataIdentity` for a quick UI
    /// check and perform this full probe off the actor.
    static func bundleIdentity(atPath path: String) -> BundleIdentity? {
        guard let metadata = bundleMetadataIdentity(atPath: path) else { return nil }
        guard let contentDigest = bundleContentDigest(atPath: path) else { return nil }
        return BundleIdentity(
            bundleIdentifier: metadata.bundleIdentifier,
            bundleName: metadata.bundleName,
            shortVersion: metadata.shortVersion,
            version: metadata.version,
            executable: metadata.executable,
            contentDigest: contentDigest
        )
    }

    /// Read Info.plist only. This deliberately does not claim that the bundle
    /// payload is unchanged; it is for synchronous path/metadata checks before
    /// an asynchronous content probe.
    static func bundleMetadataIdentity(atPath path: String) -> BundleIdentity? {
        guard isCanonicalAbsolutePath(path),
              let data = FileManager.default.contents(atPath: path + "/Contents/Info.plist"),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty else { return nil }
        let bundleName = (info["CFBundleName"] as? String)
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard !bundleName.isEmpty else { return nil }
        return BundleIdentity(
            bundleIdentifier: bundleIdentifier,
            bundleName: bundleName,
            shortVersion: info["CFBundleShortVersionString"] as? String,
            version: info["CFBundleVersion"] as? String,
            executable: info["CFBundleExecutable"] as? String,
            contentDigest: nil
        )
    }

    var isValid: Bool {
        guard version == Self.currentVersion,
              !bundleIdentifier.isEmpty, bundleIdentifier == bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
              bundleIdentifier.utf8.count <= 1024,
              !bundleIdentifier.contains("/"),
              !bundleIdentifier.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              startedAt.timeIntervalSince1970.isFinite else { return false }
        let paths = [installedPath, sourceArtifactPath, backupPath]
        guard Set(paths).count == paths.count && paths.allSatisfy(Self.isCanonicalAbsolutePath) else { return false }
        if let sourceIdentity, !sourceIdentity.isValid { return false }
        return [installedBundleIdentity, replacementBundleIdentity, backupBundleIdentity]
            .compactMap { $0 }.allSatisfy { $0.isValid }
    }

    fileprivate static func isCanonicalAbsolutePath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path != "/", path.utf8.count <= 4096,
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL.path == path
    }

    fileprivate static func isSafeMetadataText(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 4096
            && !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    fileprivate static func isGitObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count) && value.allSatisfy { $0.isHexDigit }
    }

    private static func isSHA256Digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    /// Hash a bundle without following directory symlinks. Framework bundles
    /// commonly contain symlinks, so their target path is included as payload
    /// evidence while the target is not traversed a second time. A failed or
    /// unreadable entry returns nil and therefore disables Undo rather than
    /// accepting an unverified app.
    private static func bundleContentDigest(atPath path: String) -> String? {
        var hasher = SHA256()
        guard appendDigest(forPath: path, relativePath: "", hasher: &hasher) else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func appendDigest(
        forPath path: String,
        relativePath: String,
        hasher: inout SHA256
    ) -> Bool {
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else { return false }
        let kind = metadata.st_mode & S_IFMT
        if kind == S_IFLNK {
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                return false
            }
            updateDigest("link", relativePath, target, 0, metadata.st_mode, hasher: &hasher)
            return true
        }
        if kind == S_IFDIR {
            // Directory st_size is allocation/filesystem metadata and can
            // differ after a copy even when every child byte is identical.
            updateDigest("directory", relativePath, nil, 0, metadata.st_mode, hasher: &hasher)
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                return false
            }
            for child in children.sorted() {
                let childPath = (path as NSString).appendingPathComponent(child)
                let childRelativePath = relativePath.isEmpty ? child : relativePath + "/" + child
                guard appendDigest(forPath: childPath, relativePath: childRelativePath, hasher: &hasher) else {
                    return false
                }
            }
            return true
        }
        guard kind == S_IFREG else { return false }
        updateDigest("file", relativePath, nil, metadata.st_size, metadata.st_mode, hasher: &hasher)
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        while true {
            do {
                guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else {
                    return true
                }
                hasher.update(data: data)
            } catch {
                return false
            }
        }
    }

    private static func updateDigest(
        _ kind: String,
        _ relativePath: String,
        _ linkTarget: String?,
        _ size: off_t,
        _ mode: mode_t,
        hasher: inout SHA256
    ) {
        let header = [kind, relativePath, linkTarget ?? "", String(size), String(mode)]
            .joined(separator: "\u{1f}")
        let data = Data(header.utf8)
        hasher.update(data: Data("\(data.count):".utf8))
        hasher.update(data: data)
        hasher.update(data: Data([0]))
    }

    /// Count the logical payload bytes without following symlinks. Directory
    /// allocation is intentionally excluded because it varies across volumes;
    /// a symlink contributes the bytes in its link target, never the target's
    /// outside-tree contents.
    static func logicalByteCount(atPath path: String, rejectingSymlinks: Bool = false) -> UInt64? {
        var total: UInt64 = 0
        guard appendLogicalByteCount(forPath: path, total: &total, rejectingSymlinks: rejectingSymlinks) else { return nil }
        return total
    }

    /// Measure filesystem allocation without following symlinks. This is a
    /// diagnostic value only; it is deliberately not described as free space.
    static func allocatedByteCount(atPath path: String) -> UInt64? {
        var total: UInt64 = 0
        guard appendAllocatedByteCount(forPath: path, total: &total) else { return nil }
        return total
    }

    private static func appendLogicalByteCount(
        forPath path: String, total: inout UInt64, rejectingSymlinks: Bool
    ) -> Bool {
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else { return false }
        let kind = metadata.st_mode & S_IFMT
        let amount: UInt64
        switch kind {
        case S_IFLNK:
            guard !rejectingSymlinks else { return false }
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
                return false
            }
            amount = UInt64(target.utf8.count)
        case S_IFREG:
            guard metadata.st_size >= 0 else { return false }
            let descriptor = open(path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { return false }
            close(descriptor)
            amount = UInt64(metadata.st_size)
        case S_IFDIR:
            amount = 0
        default:
            return false
        }
        guard total <= UInt64.max - amount else { return false }
        total += amount
        guard kind == S_IFDIR,
              let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return kind != S_IFDIR
        }
        for child in children.sorted() {
            let childPath = (path as NSString).appendingPathComponent(child)
            guard appendLogicalByteCount(
                forPath: childPath, total: &total, rejectingSymlinks: rejectingSymlinks
            ) else { return false }
        }
        return true
    }

    private static func appendAllocatedByteCount(forPath path: String, total: inout UInt64) -> Bool {
        var metadata = stat()
        guard lstat(path, &metadata) == 0, metadata.st_blocks >= 0 else { return false }
        let blocks = UInt64(metadata.st_blocks)
        guard blocks <= UInt64.max / 512, total <= UInt64.max - blocks * 512 else { return false }
        total += blocks * 512
        guard (metadata.st_mode & S_IFMT) == S_IFDIR,
              let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return (metadata.st_mode & S_IFMT) != S_IFDIR
        }
        for child in children.sorted() {
            let childPath = (path as NSString).appendingPathComponent(child)
            guard appendAllocatedByteCount(forPath: childPath, total: &total) else { return false }
        }
        return true
    }
}

/// A small durable receipt directory. It deliberately does not delete old
/// receipts: retention and filesystem cleanup belong to the delivery owner.
nonisolated struct AppDeliveryReceiptStore: Sendable {
    enum LoadState: Equatable, Sendable { case absent, valid(AppDeliveryReceipt), corrupt }
    enum Entry: Equatable, Sendable {
        case valid(AppDeliveryReceipt)
        case corrupt(path: String)
        case unreadable(path: String)
    }
    enum StoreError: Error, Equatable {
        case invalidReceipt, alreadyExists, absent, corrupt, identityMismatch
        case invalidTransition, writeFailed
    }

    enum AcceptedCandidateLoadState: Equatable, Sendable {
        case absent
        case valid(AcceptedCandidateRecord)
        case corrupt
        case oversized
        case symlink
    }

    enum AcceptedCandidateRevalidation: Equatable, Sendable {
        case absent
        case valid(AcceptedCandidateRecord)
        case corrupt
        case oversized
        case symlink
        case invalid(AcceptedCandidateRecord.ValidationFailure)
        case storageFailure
    }

    enum AcceptedCandidateEvidenceLoadState: Equatable, Sendable {
        case absent
        case valid(AcceptedCandidateEvidenceRecord)
        case corrupt
        case oversized
        case symlink
    }

    /// A measured, non-destructive admission policy for the previous-app
    /// snapshot. The default scope is Iris's own delivery-backup directory;
    /// callers may inject a strict root and a small logical-byte limit for
    /// disposable checks.
    struct BackupRetentionPolicy: Equatable, Sendable {
        static let defaultLogicalByteLimit: UInt64 = 2 * 1024 * 1024 * 1024

        let logicalByteLimit: UInt64
        let backupRoot: URL
        fileprivate let isStrictScope: Bool

        init(logicalByteLimit: UInt64 = Self.defaultLogicalByteLimit, backupRoot: URL? = nil) {
            self.logicalByteLimit = logicalByteLimit
            self.backupRoot = (backupRoot ?? IrisTestEnvironment.applicationSupportDirectory
                .appendingPathComponent("edit-delivery-backups", isDirectory: true)).standardizedFileURL
            self.isStrictScope = backupRoot != nil
        }
    }

    /// Explicit policy for the Test-only, receipt-owned cleanup operation. A
    /// recent rollback is retained by timestamp in addition to the newest
    /// restored receipt, so callers cannot accidentally turn cleanup into an
    /// implicit age-based purge.
    struct BackupCleanupPolicy: Equatable, Sendable {
        let now: Date
        let recentRollbackWindow: TimeInterval

        init(now: Date = Date(), recentRollbackWindow: TimeInterval = 7 * 24 * 60 * 60) {
            self.now = now
            self.recentRollbackWindow = recentRollbackWindow
        }
    }

    struct BackupCleanupResult: Equatable, Sendable {
        let deletedPaths: [String]
        let retainedPaths: [String]
        let logicalBytesRemoved: UInt64
        /// `st_blocks` measured before deletion. This is allocation accounting,
        /// not a claim about physical free space reclaimed on the volume.
        let allocatedBytesMeasured: UInt64
    }

    enum RetentionError: Error, Equatable, LocalizedError {
        case invalidPolicy
        case outsideBackupRoot
        case unsafePath
        case backupDestinationExists
        case protectedReference
        case corruptInventory
        case inventoryEntryLimitExceeded(limit: Int)
        case unreadableInventory
        case unreadableMeasurement
        case budgetExceeded(current: UInt64, candidate: UInt64, limit: UInt64)

        var errorDescription: String? {
            switch self {
            case .invalidPolicy: return "the backup retention policy is invalid"
            case .outsideBackupRoot: return "the backup destination is outside Iris's backup directory"
            case .unsafePath: return "a backup path contains an unsafe filesystem component"
            case .backupDestinationExists: return "the backup destination already exists"
            case .protectedReference: return "the backup destination is protected by saved recovery information"
            case .corruptInventory: return "saved backup inventory is incomplete or corrupt"
            case .inventoryEntryLimitExceeded(let limit):
                return "saved backup inventory has more than \(limit) records; cleanup stopped before scanning the rest"
            case .unreadableInventory: return "saved backup inventory could not be read"
            case .unreadableMeasurement: return "a bundle's logical size could not be measured"
            case .budgetExceeded(let current, let candidate, let limit):
                return "the saved backup budget would be exceeded (existing \(current) bytes plus \(candidate) bytes exceeds the \(limit)-byte limit)"
            }
        }
    }

    enum CleanupError: Error, Equatable, Sendable, LocalizedError {
        case invalidPolicy
        case unsafePath
        case corruptInventory
        case inventoryEntryLimitExceeded(limit: Int)
        case unreadableInventory
        case ambiguousRecovery
        case changedIdentity(path: String)
        case deletionFailed(path: String, deletedPaths: [String], logicalBytesRemoved: UInt64, allocatedBytesMeasured: UInt64)

        var errorDescription: String? {
            switch self {
            case .invalidPolicy: return "the backup cleanup policy is invalid"
            case .unsafePath: return "the backup cleanup target contains an unsafe filesystem path"
            case .corruptInventory: return "saved backup inventory is incomplete or corrupt"
            case .inventoryEntryLimitExceeded(let limit):
                return "saved backup inventory has more than \(limit) records; no files were removed"
            case .unreadableInventory: return "saved backup inventory could not be read"
            case .ambiguousRecovery: return "saved Undo recovery information is ambiguous"
            case .changedIdentity(let path): return "the saved backup changed before cleanup: \(path)"
            case .deletionFailed(let path, let deleted, _, _):
                return "backup cleanup stopped at \(path) after deleting \(deleted.count) backup(s)"
            }
        }
    }

    struct BackupRetentionInventory: Equatable, Sendable {
        let logicalBytes: UInt64
        let allocatedBytes: UInt64
        let protectedLogicalBytes: UInt64
        let previewEligibleLogicalBytes: UInt64
        let protectedBackupPaths: [String]
        let previewEligibleBackupPaths: [String]
        let receiptCount: Int
    }

    struct BackupRetentionAdmission: Equatable, Sendable {
        let inventory: BackupRetentionInventory
        let candidateLogicalBytes: UInt64

        var totalLogicalBytes: UInt64 {
            inventory.logicalBytes + candidateLogicalBytes
        }
    }

    static let maximumRecordBytes = 32_768
    static let maximumEntries = 256
    /// Explicit cleanup may recover a valid history beyond the admission cap,
    /// but it never scans an unbounded directory.
    static let maximumCleanupReceiptEntries = 1_024
    static let maximumCleanupEvidenceRecords = 1_024
    static let defaultBaseDirectory = IrisTestEnvironment.applicationSupportDirectory
        .appendingPathComponent("edit-delivery-receipts", isDirectory: true)
    let baseDirectory: URL
    typealias DirectoryEnumeratorFactory = (
        URL, FileManager.DirectoryEnumerationOptions, @escaping (URL, Error) -> Bool
    ) -> FileManager.DirectoryEnumerator?
    private let directoryEnumeratorFactory: DirectoryEnumeratorFactory?

    init(
        baseDirectory: URL = Self.defaultBaseDirectory,
        directoryEnumeratorFactory: DirectoryEnumeratorFactory? = nil
    ) {
        self.baseDirectory = baseDirectory.standardizedFileURL
        self.directoryEnumeratorFactory = directoryEnumeratorFactory
    }

    /// Return whether a saved installed receipt has been superseded by a
    /// newer installed delivery at the same app path. The current installed
    /// bundle is intentionally not inspected here: this is a synchronous UI
    /// affordance filter, while the Undo coordinator still performs its full
    /// identity and payload checks before changing anything.
    static func isSupersededInstalledReceipt(
        _ receipt: AppDeliveryReceipt,
        among entries: [Entry]
    ) -> Bool {
        guard receipt.phase == .installed else { return false }
        let installedPath = URL(fileURLWithPath: receipt.installedPath)
            .standardizedFileURL.path
        return entries.contains { entry in
            guard case .valid(let candidate) = entry,
                  candidate.phase == .installed,
                  candidate.identifier != receipt.identifier,
                  candidate.bundleIdentifier == receipt.bundleIdentifier,
                  URL(fileURLWithPath: candidate.installedPath)
                    .standardizedFileURL.path == installedPath else {
                return false
            }
            if candidate.startedAt != receipt.startedAt {
                return candidate.startedAt > receipt.startedAt
            }
            return candidate.identifier.uuidString > receipt.identifier.uuidString
        }
    }

    /// Measure all existing backup bundles and validate every receipt and
    /// recovery reference before a new snapshot is written. No cleanup is
    /// performed here: unreferenced material remains protected and is counted.
    /// A nil result means the default policy is being used for a disposable
    /// caller whose destination is outside Iris's production backup scope.
    func admitBackup(
        sourcePath: String,
        destinationPath: String,
        policy: BackupRetentionPolicy,
        recoveryStore: DeliveredEditUndoRecoveryStore = DeliveredEditUndoRecoveryStore(),
        allowingPreparedReceiptIdentifier: UUID? = nil
    ) throws -> BackupRetentionAdmission? {
        guard policy.logicalByteLimit > 0,
              AppDeliveryReceipt.isCanonicalAbsolutePath(policy.backupRoot.path),
              AppDeliveryReceipt.isCanonicalAbsolutePath(destinationPath),
              AppDeliveryReceipt.isCanonicalAbsolutePath(sourcePath) else {
            throw RetentionError.invalidPolicy
        }
        guard isWithin(destinationPath, root: policy.backupRoot.path) else {
            if policy.isStrictScope { throw RetentionError.outsideBackupRoot }
            return nil
        }
        guard pathHasNoSymlinkComponents(policy.backupRoot.path, allowMissing: true),
              pathHasNoSymlinkComponents(destinationPath, allowMissing: true),
              pathHasNoSymlinkComponents(sourcePath, allowMissing: false) else {
            throw RetentionError.unsafePath
        }
        var destinationMetadata = stat()
        guard lstat(destinationPath, &destinationMetadata) != 0 else {
            throw RetentionError.backupDestinationExists
        }
        guard errno == ENOENT else { throw RetentionError.unreadableInventory }

        let inventory = try backupRetentionInventory(
            backupRoot: policy.backupRoot, recoveryStore: recoveryStore,
            allowingPreparedReceiptIdentifier: allowingPreparedReceiptIdentifier,
            allowingPreparedDestination: destinationPath
        )
        guard !inventory.protectedBackupPaths.contains(destinationPath) else {
            throw RetentionError.protectedReference
        }
        guard let candidateLogicalBytes = AppDeliveryReceipt.logicalByteCount(atPath: sourcePath) else {
            throw RetentionError.unreadableMeasurement
        }
        guard inventory.logicalBytes <= UInt64.max - candidateLogicalBytes else {
            throw RetentionError.budgetExceeded(
                current: inventory.logicalBytes, candidate: candidateLogicalBytes,
                limit: policy.logicalByteLimit
            )
        }
        let total = inventory.logicalBytes + candidateLogicalBytes
        guard total <= policy.logicalByteLimit else {
            throw RetentionError.budgetExceeded(
                current: inventory.logicalBytes, candidate: candidateLogicalBytes,
                limit: policy.logicalByteLimit
            )
        }
        return BackupRetentionAdmission(
            inventory: inventory, candidateLogicalBytes: candidateLogicalBytes
        )
    }

    /// Read-only retention preview for one registered Test project. The
    /// receipt classifier is shared with admission and cleanup, while this
    /// method performs no deletion and never discovers projects itself.
    func previewRestoredBackups(
        bundleIdentifier: String,
        backupRoot: URL,
        recoveryStore: DeliveredEditUndoRecoveryStore,
        protectedPaths: [String] = [],
        policy: BackupCleanupPolicy = .init()
    ) throws -> BackupRetentionInventory {
        guard !bundleIdentifier.isEmpty,
              AppDeliveryReceipt.isSafeMetadataText(bundleIdentifier),
              policy.now.timeIntervalSinceReferenceDate.isFinite,
              policy.recentRollbackWindow.isFinite,
              policy.recentRollbackWindow >= 0,
              AppDeliveryReceipt.isCanonicalAbsolutePath(backupRoot.path),
              protectedPaths.allSatisfy(AppDeliveryReceipt.isCanonicalAbsolutePath),
              protectedPaths.allSatisfy({ pathHasNoSymlinkComponents($0, allowMissing: false) }) else {
            throw RetentionError.invalidPolicy
        }
        guard let preview = try withExistingStoreSharedLock({
            let inventory = try backupRetentionInventory(
                backupRoot: backupRoot,
                recoveryStore: recoveryStore,
                bundleIdentifier: bundleIdentifier,
                additionalProtectedPaths: protectedPaths,
                // Preview is the read-only front door to explicit cleanup.
                // Allow it to inspect a bounded history that has outgrown the
                // normal admission/display cap so the user can see what can
                // be compacted before confirming removal.
                allowingMoreThanMaximumEntries: true
            )
            let selectedPrefix = backupRoot.appendingPathComponent(bundleIdentifier, isDirectory: true)
                .standardizedFileURL.path + "/"
            let allSelectedEligible = inventory.previewEligibleBackupPaths.filter {
                $0.hasPrefix(selectedPrefix)
            }
            let selectedReceipts = try retentionReceipts().filter {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.phase == .restored
                    && allSelectedEligible.contains(URL(fileURLWithPath: $0.backupPath).standardizedFileURL.path)
            }
            let newestID = selectedReceipts.max {
                if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
                return $0.identifier.uuidString < $1.identifier.uuidString
            }?.identifier
            let cutoff = policy.now.addingTimeInterval(-policy.recentRollbackWindow)
            let rollbackProtected = Set(selectedReceipts.compactMap { receipt -> String? in
                guard receipt.identifier == newestID || receipt.startedAt >= cutoff else { return nil }
                return URL(fileURLWithPath: receipt.backupPath).standardizedFileURL.path
            })
            let eligible = allSelectedEligible.filter { !rollbackProtected.contains($0) }
            let eligibleLogical = try measuredBytes(for: eligible, allocated: false)
            let eligibleAllocated = try measuredBytes(for: eligible, allocated: true)
            let selectedProtected = Set(inventory.protectedBackupPaths.filter {
                $0.hasPrefix(selectedPrefix)
            }).union(rollbackProtected).sorted()
            let protectedLogical = try measuredBytes(for: selectedProtected, allocated: false)
            let protectedAllocated = try measuredBytes(for: selectedProtected, allocated: true)
            guard protectedLogical <= UInt64.max - eligibleLogical,
                  protectedAllocated <= UInt64.max - eligibleAllocated else {
                throw RetentionError.unreadableMeasurement
            }
            return BackupRetentionInventory(
                logicalBytes: protectedLogical + eligibleLogical,
                allocatedBytes: protectedAllocated + eligibleAllocated,
                protectedLogicalBytes: protectedLogical,
                previewEligibleLogicalBytes: eligibleLogical,
                protectedBackupPaths: selectedProtected,
                previewEligibleBackupPaths: eligible,
                receiptCount: inventory.receiptCount
            )
        }) else {
            return BackupRetentionInventory(
                logicalBytes: 0, allocatedBytes: 0,
                protectedLogicalBytes: 0, previewEligibleLogicalBytes: 0,
                protectedBackupPaths: [], previewEligibleBackupPaths: [], receiptCount: 0
            )
        }
        return preview
    }

    /// Remove only obsolete, receipt-owned restored backups. This is an owner
    /// operation rather than admission policy: all inventory and candidate
    /// checks happen before the first unlink, while the receipt-store lock
    /// serializes receipt writers. Receipt JSON and parent directories remain.
    func cleanupRestoredBackups(
        bundleIdentifier: String,
        backupRoot: URL,
        recoveryStore: DeliveredEditUndoRecoveryStore,
        protectedPaths: [String],
        policy: BackupCleanupPolicy = .init(),
        removeReceiptEnvelope: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) throws -> BackupCleanupResult {
        guard !bundleIdentifier.isEmpty,
              AppDeliveryReceipt.isSafeMetadataText(bundleIdentifier),
              policy.now.timeIntervalSinceReferenceDate.isFinite,
              policy.recentRollbackWindow.isFinite,
              policy.recentRollbackWindow >= 0,
              AppDeliveryReceipt.isCanonicalAbsolutePath(backupRoot.path),
              protectedPaths.allSatisfy(AppDeliveryReceipt.isCanonicalAbsolutePath) else {
            throw CleanupError.invalidPolicy
        }
        guard protectedPaths.allSatisfy({ pathHasNoSymlinkComponents($0, allowMissing: false) }) else {
            throw CleanupError.unsafePath
        }

        return try withExclusiveStoreLock {
            let receipts: [AppDeliveryReceipt]
            do {
                // Explicit cleanup is the bounded recovery route for a valid
                // history which has grown past the normal admission cap. It
                // still validates every receipt and stops at the separate
                // cleanup ceiling before deleting anything.
                receipts = try retentionReceipts(allowingMoreThanMaximumEntries: true)
            } catch {
                throw cleanupError(for: error)
            }

            var rootMetadata = stat()
            let rootExists = lstat(backupRoot.path, &rootMetadata) == 0
            if !rootExists {
                guard errno == ENOENT, receipts.isEmpty else { throw CleanupError.corruptInventory }
                return BackupCleanupResult(
                    deletedPaths: [], retainedPaths: [], logicalBytesRemoved: 0,
                    allocatedBytesMeasured: 0
                )
            }
            guard (rootMetadata.st_mode & S_IFMT) == S_IFDIR,
                  pathHasNoSymlinkComponents(backupRoot.path, allowMissing: false) else {
                throw CleanupError.unsafePath
            }
            do { try validateBackupNamespace(backupRoot) }
            catch { throw cleanupError(for: error) }

            let recovery = try cleanupRecoverySnapshot(
                recoveryStore: recoveryStore, backupRoot: backupRoot
            )
            var protected = Set(protectedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
            protected.formUnion(recovery.protectedBackupPaths)
            let acceptedEvidenceReceiptIDs = try acceptedEvidenceReceiptIDs()
            let currentInstalledReceiptIDs = currentInstalledReceiptIDs(
                in: receipts, bundleIdentifier: bundleIdentifier
            ) ?? Set(receipts.compactMap { receipt in
                receipt.bundleIdentifier == bundleIdentifier && receipt.phase == .installed
                    ? receipt.identifier : nil
            })
            var obsoleteCandidates: [AppDeliveryReceipt] = []
            var danglingObsoleteReceipts: [AppDeliveryReceipt] = []
            var restoredPaths = Set<String>()
            var receiptPayloadPaths: [String] = []
            for receipt in receipts {
                guard isWithin(receipt.backupPath, root: backupRoot.path),
                      pathHasNoSymlinkComponents(receipt.backupPath, allowMissing: true) else {
                    throw CleanupError.unsafePath
                }
                let backupPath = URL(fileURLWithPath: receipt.backupPath).standardizedFileURL.path
                guard !receiptPayloadPaths.contains(where: { pathsOverlap(backupPath, $0) }) else {
                    // A receipt whose payload has already disappeared still
                    // owns its recorded path until reconciliation removes its
                    // exact envelope. Do not let another record reuse it.
                    throw CleanupError.corruptInventory
                }
                receiptPayloadPaths.append(backupPath)
                var metadata = stat()
                guard lstat(receipt.backupPath, &metadata) == 0 else {
                    // Legacy restored records may have no payload. An older
                    // cleanup can also have removed a superseded payload just
                    // before its receipt unlink failed; reconcile only that
                    // already-proven-obsolete envelope on the next explicit run.
                    if errno == ENOENT, receipt.phase == .restored { continue }
                    if errno == ENOENT,
                       receipt.phase == .installed,
                       receipt.bundleIdentifier == bundleIdentifier,
                       !currentInstalledReceiptIDs.contains(receipt.identifier),
                       !acceptedEvidenceReceiptIDs.contains(receipt.identifier),
                       !protected.contains(where: { pathsOverlap(backupPath, $0) }),
                       isReceiptPayloadEligibleForCleanup(receipt) {
                        danglingObsoleteReceipts.append(receipt)
                        continue
                    }
                    throw CleanupError.corruptInventory
                }
                guard (metadata.st_mode & S_IFMT) == S_IFDIR else {
                    throw CleanupError.corruptInventory
                }
                if receipt.phase == .prepared
                    || acceptedEvidenceReceiptIDs.contains(receipt.identifier) {
                    protected.insert(backupPath)
                    continue
                }
                guard receipt.bundleIdentifier == bundleIdentifier else {
                    protected.insert(backupPath)
                    continue
                }
                switch receipt.phase {
                case .restored:
                    guard isReceiptPayloadEligibleForCleanup(receipt) else {
                        protected.insert(backupPath)
                        continue
                    }
                    restoredPaths.insert(backupPath)
                    obsoleteCandidates.append(receipt)
                case .installed:
                    guard !currentInstalledReceiptIDs.contains(receipt.identifier),
                          isReceiptPayloadEligibleForCleanup(receipt) else {
                        protected.insert(backupPath)
                        continue
                    }
                    obsoleteCandidates.append(receipt)
                case .prepared:
                    protected.insert(backupPath)
                }
            }

            let newestRestored = obsoleteCandidates.filter { $0.phase == .restored }.max {
                if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
                return $0.identifier.uuidString < $1.identifier.uuidString
            }?.identifier
            let cutoff = policy.now.addingTimeInterval(-policy.recentRollbackWindow)
            var candidates: [AppDeliveryReceipt] = []
            var retainedPaths = Set<String>()
            for receipt in obsoleteCandidates {
                let path = URL(fileURLWithPath: receipt.backupPath).standardizedFileURL.path
                let retainedForRollback = receipt.phase == .restored
                    && (receipt.identifier == newestRestored || receipt.startedAt >= cutoff)
                let overlapsProtection = protected.contains { pathsOverlap(path, $0) }
                if retainedForRollback || overlapsProtection {
                    retainedPaths.insert(path)
                    protected.insert(path)
                } else {
                    candidates.append(receipt)
                }
            }

            // A restored receipt can be an alias of another protected receipt;
            // no candidate is allowed to overlap any live/recovery path.
            var preflightLogicalBytes: UInt64 = 0
            var preflightAllocatedBytes: UInt64 = 0
            for receipt in candidates {
                let path = URL(fileURLWithPath: receipt.backupPath).standardizedFileURL.path
                guard !protected.contains(where: { pathsOverlap(path, $0) }),
                      let expectedIdentity = receipt.backupBundleIdentity,
                      let actualIdentity = AppDeliveryReceipt.bundleIdentity(atPath: path),
                      actualIdentity == expectedIdentity,
                      let logicalBytes = AppDeliveryReceipt.logicalByteCount(
                        atPath: path, rejectingSymlinks: false
                      ),
                      let allocatedBytes = AppDeliveryReceipt.allocatedByteCount(atPath: path),
                      preflightLogicalBytes <= UInt64.max - logicalBytes,
                      preflightAllocatedBytes <= UInt64.max - allocatedBytes else {
                    throw CleanupError.changedIdentity(path: path)
                }
                preflightLogicalBytes += logicalBytes
                preflightAllocatedBytes += allocatedBytes
            }

            // Recovery files are owned by a separate store, so compare their
            // complete bounded snapshot once more after candidate preflight.
            // A concurrent change cannot be made atomic with this receipt lock;
            // it is therefore treated as an ambiguous, no-delete condition.
            guard try cleanupRecoverySnapshot(
                recoveryStore: recoveryStore, backupRoot: backupRoot
            ) == recovery else {
                throw CleanupError.ambiguousRecovery
            }

            for receipt in danglingObsoleteReceipts {
                guard (try? cleanupRecoverySnapshot(
                    recoveryStore: recoveryStore, backupRoot: backupRoot
                )) == recovery,
                case .valid(let storedReceipt) = loadUnlocked(receipt.identifier),
                storedReceipt == receipt else {
                    throw CleanupError.ambiguousRecovery
                }
                do { try removeReceiptEnvelope(url(for: receipt.identifier)) }
                catch {
                    throw CleanupError.deletionFailed(
                        path: receipt.backupPath, deletedPaths: [],
                        logicalBytesRemoved: 0, allocatedBytesMeasured: 0
                    )
                }
            }

            var deleted: [String] = []
            var logicalBytesRemoved: UInt64 = 0
            var allocatedBytesMeasured: UInt64 = 0
            for receipt in candidates {
                guard (try? cleanupRecoverySnapshot(
                    recoveryStore: recoveryStore, backupRoot: backupRoot
                )) == recovery else {
                    throw CleanupError.deletionFailed(
                        path: receipt.backupPath, deletedPaths: deleted,
                        logicalBytesRemoved: logicalBytesRemoved,
                        allocatedBytesMeasured: allocatedBytesMeasured
                    )
                }
                let path = URL(fileURLWithPath: receipt.backupPath).standardizedFileURL.path
                guard pathHasNoSymlinkComponents(path, allowMissing: false),
                      let expectedIdentity = receipt.backupBundleIdentity,
                      AppDeliveryReceipt.bundleIdentity(atPath: path) == expectedIdentity,
                      let logicalBytes = AppDeliveryReceipt.logicalByteCount(
                        atPath: path, rejectingSymlinks: false
                      ),
                      let allocatedBytes = AppDeliveryReceipt.allocatedByteCount(atPath: path) else {
                    throw CleanupError.deletionFailed(
                        path: path, deletedPaths: deleted,
                        logicalBytesRemoved: logicalBytesRemoved,
                        allocatedBytesMeasured: allocatedBytesMeasured
                    )
                }
                guard logicalBytesRemoved <= UInt64.max - logicalBytes,
                      allocatedBytesMeasured <= UInt64.max - allocatedBytes else {
                    throw CleanupError.deletionFailed(
                        path: path, deletedPaths: deleted,
                        logicalBytesRemoved: logicalBytesRemoved,
                        allocatedBytesMeasured: allocatedBytesMeasured
                    )
                }
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    throw CleanupError.deletionFailed(
                        path: path, deletedPaths: deleted,
                        logicalBytesRemoved: logicalBytesRemoved,
                        allocatedBytesMeasured: allocatedBytesMeasured
                    )
                }
                logicalBytesRemoved += logicalBytes
                allocatedBytesMeasured += allocatedBytes
                deleted.append(path)
                guard case .valid(let storedReceipt) = loadUnlocked(receipt.identifier),
                      storedReceipt == receipt else {
                    throw CleanupError.deletionFailed(
                        path: path, deletedPaths: deleted,
                        logicalBytesRemoved: logicalBytesRemoved,
                        allocatedBytesMeasured: allocatedBytesMeasured
                    )
                }
                do {
                    try removeReceiptEnvelope(url(for: receipt.identifier))
                } catch {
                    throw CleanupError.deletionFailed(
                        path: path, deletedPaths: deleted,
                        logicalBytesRemoved: logicalBytesRemoved,
                        allocatedBytesMeasured: allocatedBytesMeasured
                    )
                }
                var after = stat()
                guard lstat(path, &after) != 0, errno == ENOENT else {
                    throw CleanupError.deletionFailed(
                        path: path, deletedPaths: deleted,
                        logicalBytesRemoved: logicalBytesRemoved,
                        allocatedBytesMeasured: allocatedBytesMeasured
                    )
                }
            }
            retainedPaths.formUnion(restoredPaths.subtracting(deleted))
            _ = recovery // Keeps the preflight snapshot alive through deletion.
            return BackupCleanupResult(
                deletedPaths: deleted.sorted(), retainedPaths: retainedPaths.sorted(),
                logicalBytesRemoved: logicalBytesRemoved,
                allocatedBytesMeasured: allocatedBytesMeasured
            )
        }
    }

    /// Cheap UI gate. It proves only that the recorded backup is a safe,
    /// readable bundle at the recorded path. Undo still performs the existing
    /// full content-digest and source-identity checks off the main actor.
    func backupIsAvailable(for receipt: AppDeliveryReceipt) -> Bool {
        let metadataPath = URL(fileURLWithPath: receipt.backupPath)
            .appendingPathComponent("Contents/Info.plist").path
        guard receipt.isValid,
              AppDeliveryReceipt.isCanonicalAbsolutePath(receipt.backupPath),
              pathHasNoSymlinkComponents(metadataPath, allowMissing: false) else {
            return false
        }
        var propertyListMetadata = stat()
        guard lstat(metadataPath, &propertyListMetadata) == 0,
              (propertyListMetadata.st_mode & S_IFMT) == S_IFREG,
              propertyListMetadata.st_size > 0,
              propertyListMetadata.st_size <= 1_048_576 else { return false }
        var metadata = stat()
        guard lstat(receipt.backupPath, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              let identity = AppDeliveryReceipt.bundleMetadataIdentity(atPath: receipt.backupPath) else {
            return false
        }
        return identity.bundleIdentifier == receipt.bundleIdentifier
    }

    private struct CleanupRecoverySnapshot: Equatable {
        let live: DeliveredEditUndoRecoveryStore.Loaded
        let archivedRecords: [DeliveredEditUndoRecoveryRecord]
        let archivePaths: [String]
        let protectedBackupPaths: [String]
    }

    private func cleanupRecoverySnapshot(
        recoveryStore: DeliveredEditUndoRecoveryStore, backupRoot: URL
    ) throws -> CleanupRecoverySnapshot {
        let live = recoveryStore.load()
        switch live {
        case .absent: break
        case .pending(let record):
            guard let path = record.backupPath else { break }
            guard AppDeliveryReceipt.isCanonicalAbsolutePath(path),
                  isWithin(path, root: backupRoot.path),
                  pathHasNoSymlinkComponents(path, allowMissing: true) else {
                throw CleanupError.unsafePath
            }
        case .unreadable:
            throw CleanupError.ambiguousRecovery
        }
        let archived = recoveryStore.archivedRecoveryInventory()
        guard !archived.hasUnknownTargets else { throw CleanupError.ambiguousRecovery }
        var protected: Set<String> = []
        if case .pending(let record) = live {
            try addCleanupRecoveryRecordReferences(record, root: backupRoot, protected: &protected)
        }
        for record in archived.records {
            try addCleanupRecoveryRecordReferences(record, root: backupRoot, protected: &protected)
        }
        return CleanupRecoverySnapshot(
            live: live, archivedRecords: archived.records,
            archivePaths: archived.archivePaths,
            protectedBackupPaths: protected.sorted()
        )
    }

    private func addCleanupRecoveryReference(
        _ path: String, root: URL, protected: inout Set<String>
    ) throws {
        guard AppDeliveryReceipt.isCanonicalAbsolutePath(path),
              isWithin(path, root: root.path),
              pathHasNoSymlinkComponents(path, allowMissing: true) else {
            throw CleanupError.unsafePath
        }
        var metadata = stat()
        if lstat(path, &metadata) == 0 {
            guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw CleanupError.unsafePath }
        } else if errno != ENOENT {
            throw CleanupError.unreadableInventory
        }
        protected.insert(URL(fileURLWithPath: path).standardizedFileURL.path)
    }

    private func addCleanupRecoveryRecordReferences(
        _ record: DeliveredEditUndoRecoveryRecord, root: URL, protected: inout Set<String>
    ) throws {
        if let backupPath = record.backupPath {
            try addCleanupRecoveryReference(backupPath, root: root, protected: &protected)
        }
        for path in [record.installedPath, record.clonePath].compactMap({ $0 }) {
            guard AppDeliveryReceipt.isCanonicalAbsolutePath(path),
                  pathHasNoSymlinkComponents(path, allowMissing: true) else {
                throw CleanupError.unsafePath
            }
            var metadata = stat()
            if lstat(path, &metadata) == 0 {
                guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw CleanupError.unsafePath }
            } else if errno != ENOENT {
                throw CleanupError.unreadableInventory
            }
            protected.insert(URL(fileURLWithPath: path).standardizedFileURL.path)
        }
    }

    private func cleanupError(for error: Error) -> CleanupError {
        if let error = error as? CleanupError { return error }
        guard let error = error as? RetentionError else { return .unreadableInventory }
        switch error {
        case .unsafePath, .outsideBackupRoot: return .unsafePath
        case .corruptInventory, .budgetExceeded, .backupDestinationExists: return .corruptInventory
        case .inventoryEntryLimitExceeded(let limit): return .inventoryEntryLimitExceeded(limit: limit)
        case .unreadableInventory, .unreadableMeasurement: return .unreadableInventory
        case .invalidPolicy: return .invalidPolicy
        case .protectedReference: return .ambiguousRecovery
        }
    }

    private func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let identities = [
            URL(fileURLWithPath: lhs).standardizedFileURL.path,
            URL(fileURLWithPath: lhs).resolvingSymlinksInPath().path
        ]
        let protected = [
            URL(fileURLWithPath: rhs).standardizedFileURL.path,
            URL(fileURLWithPath: rhs).resolvingSymlinksInPath().path
        ]
        return identities.contains { candidate in
            protected.contains { other in
                candidate == other || candidate.hasPrefix(other + "/") || other.hasPrefix(candidate + "/")
            }
        }
    }

    private func backupRetentionInventory(
        backupRoot: URL,
        recoveryStore: DeliveredEditUndoRecoveryStore,
        allowingPreparedReceiptIdentifier: UUID? = nil,
        allowingPreparedDestination: String? = nil,
        bundleIdentifier: String? = nil,
        additionalProtectedPaths: [String] = [],
        allowingMoreThanMaximumEntries: Bool = false
    ) throws -> BackupRetentionInventory {
        let receipts = try retentionReceipts(
            allowingMoreThanMaximumEntries: allowingMoreThanMaximumEntries
        )
        let acceptedReceiptIDs: Set<UUID>
        do {
            acceptedReceiptIDs = try acceptedEvidenceReceiptIDs()
        } catch let error as CleanupError {
            if case .inventoryEntryLimitExceeded(let limit) = error {
                throw RetentionError.inventoryEntryLimitExceeded(limit: limit)
            }
            throw RetentionError.corruptInventory
        } catch {
            throw RetentionError.corruptInventory
        }
        let currentReceiptIDs: Set<UUID>
        if let bundleIdentifier {
            currentReceiptIDs = currentInstalledReceiptIDs(
                in: receipts, bundleIdentifier: bundleIdentifier
            ) ?? Set(receipts.compactMap { receipt in
                receipt.bundleIdentifier == bundleIdentifier && receipt.phase == .installed
                    ? receipt.identifier : nil
            })
        } else {
            currentReceiptIDs = []
        }
        var protected = Set(additionalProtectedPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        var previewEligible = Set<String>()
        let logicalBytes: UInt64
        var rootMetadata = stat()
        let rootExists = lstat(backupRoot.path, &rootMetadata) == 0
        if !rootExists && errno != ENOENT { throw RetentionError.unreadableInventory }
        if rootExists {
            guard (rootMetadata.st_mode & S_IFMT) == S_IFDIR,
                  pathHasNoSymlinkComponents(backupRoot.path, allowMissing: false) else {
                throw RetentionError.unsafePath
            }
            // The backup namespace itself is a strict directory tree. Stop at
            // each recorded .app root so legitimate framework-internal links
            // remain payload entries rather than namespace escapes.
            try validateBackupNamespace(backupRoot)
            guard let bytes = AppDeliveryReceipt.logicalByteCount(
                atPath: backupRoot.path, rejectingSymlinks: false
            ) else { throw RetentionError.unreadableMeasurement }
            logicalBytes = bytes
        } else {
            logicalBytes = 0
        }

        for receipt in receipts {
            guard isWithin(receipt.backupPath, root: backupRoot.path),
                  pathHasNoSymlinkComponents(receipt.backupPath, allowMissing: true) else {
                throw RetentionError.unsafePath
            }
            if let bundleIdentifier, receipt.bundleIdentifier != bundleIdentifier {
                protected.insert(URL(fileURLWithPath: receipt.backupPath).standardizedFileURL.path)
                continue
            }
            var metadata = stat()
            if lstat(receipt.backupPath, &metadata) == 0 {
                guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw RetentionError.corruptInventory }
                let isAllowedPreparedReceipt = receipt.identifier == allowingPreparedReceiptIdentifier
                    && receipt.phase == .prepared
                    && receipt.backupPath == allowingPreparedDestination
                if isAllowedPreparedReceipt {
                    continue
                }
                if acceptedReceiptIDs.contains(receipt.identifier) {
                    protected.insert(receipt.backupPath)
                } else if isPreviewEligible(receipt) {
                    previewEligible.insert(receipt.backupPath)
                } else if receipt.phase == .installed,
                          !currentReceiptIDs.contains(receipt.identifier),
                          isReceiptPayloadEligibleForCleanup(receipt) {
                    previewEligible.insert(receipt.backupPath)
                } else {
                    protected.insert(receipt.backupPath)
                }
            } else if errno != ENOENT || receipt.phase != .prepared {
                throw RetentionError.corruptInventory
            } else if receipt.identifier != allowingPreparedReceiptIdentifier
                        || receipt.backupPath != allowingPreparedDestination {
                // A prepared receipt reserves its destination even before the
                // bundle snapshot exists. Only the receipt being completed by
                // this admission may be exempted.
                protected.insert(receipt.backupPath)
            }
        }

        switch recoveryStore.load() {
        case .absent:
            break
        case .unreadable:
            throw RetentionError.unreadableInventory
        case .pending(let record):
            try addRecoveryReference(record.backupPath, root: backupRoot, protected: &protected)
        }
        let archived = recoveryStore.archivedRecoveryInventory()
        guard !archived.hasUnknownTargets else { throw RetentionError.corruptInventory }
        for record in archived.records {
            try addRecoveryReference(record.backupPath, root: backupRoot, protected: &protected)
        }
        // A payload with no receipt is an unknown reference, not an obsolete
        // version. Keep it protected so preview and later cleanup cannot infer
        // authority from a directory name or arbitrary UUID.
        for payloadPath in try backupPayloadPaths(backupRoot) {
            if !receipts.contains(where: { URL(fileURLWithPath: $0.backupPath).standardizedFileURL.path == payloadPath }) {
                protected.insert(payloadPath)
            }
        }
        // A restored receipt is only a preview candidate while no live or
        // archived recovery record, nor another non-restored receipt, aliases
        // the same backup path.
        previewEligible = Set(previewEligible.filter { candidate in
            !protected.contains { pathsOverlap(candidate, $0) }
        })

        let protectedPaths = protected.sorted()
        let eligiblePaths = previewEligible.sorted()
        let allocatedBytes: UInt64
        if rootExists {
            guard let measured = AppDeliveryReceipt.allocatedByteCount(atPath: backupRoot.path) else {
                throw RetentionError.unreadableMeasurement
            }
            allocatedBytes = measured
        } else {
            allocatedBytes = 0
        }
        return BackupRetentionInventory(
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            protectedLogicalBytes: try measuredBytes(for: protectedPaths, allocated: false),
            previewEligibleLogicalBytes: try measuredBytes(for: eligiblePaths, allocated: false),
            protectedBackupPaths: protectedPaths,
            previewEligibleBackupPaths: eligiblePaths,
            receiptCount: receipts.count
        )
    }

    private func backupPayloadPaths(_ root: URL) throws -> [String] {
        var metadata = stat()
        guard lstat(root.path, &metadata) == 0 else {
            if errno == ENOENT { return [] }
            throw RetentionError.unreadableInventory
        }
        guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw RetentionError.unsafePath }
        var payloads: [String] = []
        for bundleGroup in try safeDirectoryEntries(at: root) {
            for delivery in try safeDirectoryEntries(at: bundleGroup) {
                for payload in try safeDirectoryEntries(at: delivery) {
                    let path = payload.standardizedFileURL.path
                    guard pathHasNoSymlinkComponents(path, allowMissing: false) else {
                        throw RetentionError.unsafePath
                    }
                    payloads.append(path)
                }
            }
        }
        return payloads.sorted()
    }

    private func measuredBytes(for paths: [String], allocated: Bool) throws -> UInt64 {
        var total: UInt64 = 0
        for path in paths {
            var metadata = stat()
            guard lstat(path, &metadata) == 0 else {
                guard errno == ENOENT else { throw RetentionError.unreadableMeasurement }
                continue
            }
            let bytes = allocated
                ? AppDeliveryReceipt.allocatedByteCount(atPath: path)
                : AppDeliveryReceipt.logicalByteCount(atPath: path, rejectingSymlinks: false)
            guard let bytes, total <= UInt64.max - bytes else {
                throw RetentionError.unreadableMeasurement
            }
            total += bytes
        }
        return total
    }

    private func validateBackupNamespace(_ root: URL) throws {
        for bundleGroup in try safeDirectoryEntries(at: root) {
            for delivery in try safeDirectoryEntries(at: bundleGroup) {
                _ = try safeDirectoryEntries(at: delivery)
            }
        }
    }

    private func safeDirectoryEntries(at parent: URL) throws -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: nil
        ) else { throw RetentionError.unreadableInventory }
        return try entries.map { entry in
            var metadata = stat()
            guard lstat(entry.path, &metadata) == 0 else {
                throw RetentionError.unreadableInventory
            }
            let kind = metadata.st_mode & S_IFMT
            guard kind == S_IFDIR else {
                if kind == S_IFLNK { throw RetentionError.unsafePath }
                throw RetentionError.corruptInventory
            }
            return entry
        }
    }

    private func isReceiptPayloadEligibleForCleanup(_ receipt: AppDeliveryReceipt) -> Bool {
        guard receipt.phase == .restored || receipt.phase == .installed,
              let source = receipt.sourceIdentity, source.isValid,
              let installed = receipt.installedBundleIdentity, installed.isValid,
              let replacement = receipt.replacementBundleIdentity, replacement.isValid,
              let backup = receipt.backupBundleIdentity, backup.isValid,
              installed.contentDigest != nil, replacement.contentDigest != nil,
              backup.contentDigest != nil else { return false }
        return installed == backup
            && installed.bundleIdentifier == receipt.bundleIdentifier
            && replacement.bundleIdentifier == receipt.bundleIdentifier
    }

    private func isPreviewEligible(_ receipt: AppDeliveryReceipt) -> Bool {
        receipt.phase == .restored && isReceiptPayloadEligibleForCleanup(receipt)
    }

    /// The newest receipt whose replacement is the app currently at the
    /// recorded installed path owns the one rollback bundle that must remain.
    /// An unknown or moved installed app returns nil so the caller protects all
    /// installed receipts instead of guessing which historical copy is stale.
    private func currentInstalledReceiptIDs(
        in receipts: [AppDeliveryReceipt], bundleIdentifier: String
    ) -> Set<UUID>? {
        let installedReceipts = receipts.filter {
            $0.bundleIdentifier == bundleIdentifier && $0.phase == .installed
        }
        guard !installedReceipts.isEmpty else { return [] }
        let grouped = Dictionary(grouping: installedReceipts, by: \.installedPath)
        var currentIDs = Set<UUID>()
        for (_, group) in grouped {
            guard let currentIdentity = AppDeliveryReceipt.bundleIdentity(atPath: group[0].installedPath) else {
                return nil
            }
            let matching = group.filter { $0.replacementBundleIdentity == currentIdentity }
            guard let newest = matching.max(by: receiptIsOlder) else { return nil }
            currentIDs.insert(newest.identifier)
        }
        return currentIDs
    }

    private func receiptIsOlder(_ lhs: AppDeliveryReceipt, _ rhs: AppDeliveryReceipt) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        return lhs.identifier.uuidString < rhs.identifier.uuidString
    }

    /// Accepted candidates and their evidence are durable reuse gates. Any
    /// syntactically valid reference protects its receipt; a malformed entry
    /// fails the cleanup before deletion rather than weakening that gate.
    private func acceptedEvidenceReceiptIDs() throws -> Set<UUID> {
        var protectedIDs = Set<UUID>()
        var recordCount = 0
        for directory in [acceptedCandidatesDirectory, acceptedCandidateEvidenceDirectory] {
            var metadata = stat()
            guard lstat(directory.path, &metadata) == 0 else {
                if errno == ENOENT { continue }
                throw CleanupError.unreadableInventory
            }
            guard (metadata.st_mode & S_IFMT) == S_IFDIR,
                  pathHasNoSymlinkComponents(directory.path, allowMissing: false) else {
                throw CleanupError.corruptInventory
            }
            var enumerationFailed = false
            guard let files = enumerator(
                at: directory, options: [.skipsSubdirectoryDescendants],
                errorHandler: { _, _ in enumerationFailed = true; return false }
            ) else { throw CleanupError.unreadableInventory }
            while let file = files.nextObject() as? URL {
                let name = file.lastPathComponent
                if directory == acceptedCandidatesDirectory && file == acceptedCandidateEvidenceDirectory {
                    continue
                }
                guard name.hasSuffix(".json"),
                      let identifier = UUID(uuidString: String(name.dropLast(5))),
                      let data = try? boundedData(at: file) else {
                    throw CleanupError.corruptInventory
                }
                recordCount += 1
                guard recordCount <= Self.maximumCleanupEvidenceRecords else {
                    throw CleanupError.inventoryEntryLimitExceeded(
                        limit: Self.maximumCleanupEvidenceRecords
                    )
                }
                if directory == acceptedCandidatesDirectory {
                    guard let record = try? JSONDecoder().decode(AcceptedCandidateRecord.self, from: data),
                          record.candidateID == identifier else { throw CleanupError.corruptInventory }
                    if let receiptID = record.uiAcceptedReceiptID { protectedIDs.insert(receiptID) }
                } else {
                    guard let evidence = try? JSONDecoder().decode(AcceptedCandidateEvidenceRecord.self, from: data),
                          evidence.evidenceID == identifier else { throw CleanupError.corruptInventory }
                    if let receiptID = evidence.receiptIdentifier { protectedIDs.insert(receiptID) }
                }
            }
            guard !enumerationFailed else { throw CleanupError.unreadableInventory }
        }
        return protectedIDs
    }

    private func retentionReceipts(
        allowingMoreThanMaximumEntries: Bool = false
    ) throws -> [AppDeliveryReceipt] {
        var directoryMetadata = stat()
        guard lstat(baseDirectory.path, &directoryMetadata) == 0 else {
            if errno == ENOENT { return [] }
            throw RetentionError.unreadableInventory
        }
        guard (directoryMetadata.st_mode & S_IFMT) == S_IFDIR,
              pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: false) else {
            throw RetentionError.unsafePath
        }
        var enumerationFailed = false
        guard let files = enumerator(
            at: baseDirectory, options: [.skipsSubdirectoryDescendants],
            errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw RetentionError.unreadableInventory }
        var receipts: [AppDeliveryReceipt] = []
        while let file = files.nextObject() as? URL {
            let name = file.lastPathComponent
            var metadata = stat()
            guard lstat(file.path, &metadata) == 0 else { throw RetentionError.unreadableInventory }
            if name == ".lock" {
                guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw RetentionError.corruptInventory }
                continue
            }
            // Accepted-candidate records live under a bounded child
            // directory of the receipt store. They are scanned separately by
            // acceptedEvidenceReceiptIDs(); never treat that directory as a
            // receipt envelope or walk its payloads here.
            if file == acceptedCandidatesDirectory {
                guard (metadata.st_mode & S_IFMT) == S_IFDIR,
                      pathHasNoSymlinkComponents(file.path, allowMissing: false) else {
                    throw RetentionError.corruptInventory
                }
                continue
            }
            guard name.hasSuffix(".json"),
                  let identifier = UUID(uuidString: String(name.dropLast(5))),
                  (metadata.st_mode & S_IFMT) == S_IFREG,
                  let data = try? boundedData(at: file),
                  let receipt = try? JSONDecoder().decode(AppDeliveryReceipt.self, from: data),
                  receipt.identifier == identifier, receipt.isValid else {
                throw RetentionError.corruptInventory
            }
            receipts.append(receipt)
            if allowingMoreThanMaximumEntries,
               receipts.count > Self.maximumCleanupReceiptEntries {
                throw RetentionError.inventoryEntryLimitExceeded(
                    limit: Self.maximumCleanupReceiptEntries
                )
            }
            guard allowingMoreThanMaximumEntries || receipts.count <= Self.maximumEntries else {
                throw RetentionError.corruptInventory
            }
        }
        guard !enumerationFailed else { throw RetentionError.unreadableInventory }
        return receipts
    }

    private func enumerator(
        at directory: URL,
        options: FileManager.DirectoryEnumerationOptions,
        errorHandler: @escaping (URL, Error) -> Bool
    ) -> FileManager.DirectoryEnumerator? {
        if let directoryEnumeratorFactory {
            return directoryEnumeratorFactory(directory, options, errorHandler)
        }
        return FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil,
            options: options, errorHandler: errorHandler
        )
    }

    private func addRecoveryReference(
        _ path: String?, root: URL, protected: inout Set<String>
    ) throws {
        guard let path else { return }
        guard AppDeliveryReceipt.isCanonicalAbsolutePath(path), isWithin(path, root: root.path) else {
            throw RetentionError.unsafePath
        }
        guard pathHasNoSymlinkComponents(path, allowMissing: true) else {
            throw RetentionError.unsafePath
        }
        var metadata = stat()
        if lstat(path, &metadata) == 0 {
            guard (metadata.st_mode & S_IFMT) == S_IFDIR else { throw RetentionError.unsafePath }
        } else if errno != ENOENT {
            throw RetentionError.unreadableInventory
        }
        protected.insert(path)
    }

    private func isWithin(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private func pathHasNoSymlinkComponents(_ path: String, allowMissing: Bool) -> Bool {
        var current = "/"
        for component in path.split(separator: "/") {
            current = (current as NSString).appendingPathComponent(String(component))
            var metadata = stat()
            guard lstat(current, &metadata) == 0 else {
                return allowMissing && errno == ENOENT
            }
            guard (metadata.st_mode & S_IFMT) != S_IFLNK else { return false }
        }
        return true
    }

    func url(for identifier: UUID) -> URL {
        baseDirectory.appendingPathComponent(identifier.uuidString + ".json")
    }

    func savePrepared(_ receipt: AppDeliveryReceipt) throws {
        guard receipt.isValid, receipt.phase == .prepared else { throw StoreError.invalidReceipt }
        let data = try encoded(receipt)
        try withExclusiveStoreLock {
            try publish(data, at: url(for: receipt.identifier), refusingExisting: true)
        }
    }

    var acceptedCandidatesDirectory: URL {
        baseDirectory.appendingPathComponent("accepted-candidates", isDirectory: true)
    }

    var acceptedCandidateEvidenceDirectory: URL {
        acceptedCandidatesDirectory.appendingPathComponent("evidence", isDirectory: true)
    }

    func acceptedCandidateURL(for identifier: UUID) -> URL {
        acceptedCandidatesDirectory.appendingPathComponent(identifier.uuidString + ".json")
    }

    func acceptedCandidateEvidenceURL(for identifier: UUID) -> URL {
        acceptedCandidateEvidenceDirectory.appendingPathComponent(identifier.uuidString + ".json")
    }

    /// Persist accepted-candidate metadata beside, and under the same lock as,
    /// delivery receipts. The candidate payload is never copied into this
    /// record, and publication is atomic through the existing store writer.
    func saveAcceptedCandidate(_ record: AcceptedCandidateRecord) throws {
        guard record.isValid else { throw StoreError.invalidReceipt }
        let data = try JSONEncoder.acceptedCandidateEncoder.encode(record)
        guard data.count <= Self.maximumRecordBytes else { throw StoreError.invalidReceipt }
        try withExclusiveStoreLock {
            guard pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: false),
                  pathHasNoSymlinkComponents(acceptedCandidatesDirectory.path, allowMissing: true) else {
                throw StoreError.writeFailed
            }
            try FileManager.default.createDirectory(at: acceptedCandidatesDirectory,
                withIntermediateDirectories: true)
            var candidateDirectoryMetadata = stat()
            guard lstat(acceptedCandidatesDirectory.path, &candidateDirectoryMetadata) == 0,
                  (candidateDirectoryMetadata.st_mode & S_IFMT) == S_IFDIR,
                  pathHasNoSymlinkComponents(acceptedCandidatesDirectory.path, allowMissing: false) else {
                throw StoreError.writeFailed
            }
            try publish(data, at: acceptedCandidateURL(for: record.candidateID), refusingExisting: true)
        }
    }

    func loadAcceptedCandidate(_ identifier: UUID) -> AcceptedCandidateLoadState {
        loadAcceptedCandidateUnlocked(identifier)
    }

    func loadAcceptedCandidateEvidence(_ identifier: UUID) -> AcceptedCandidateEvidenceLoadState {
        loadAcceptedCandidateEvidenceUnlocked(identifier)
    }

    /// Store one bounded, persisted evidence fact only when it is already
    /// linked to the candidate record. This keeps UUIDs as references rather
    /// than proof and prevents an evidence file from becoming delivery
    /// authority on its own.
    func saveAcceptedCandidateEvidence(_ evidence: AcceptedCandidateEvidenceRecord) throws {
        guard evidence.isValid else { throw StoreError.invalidReceipt }
        try withExclusiveStoreLock {
            guard pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: false),
                  pathHasNoSymlinkComponents(acceptedCandidatesDirectory.path, allowMissing: true) else {
                throw StoreError.writeFailed
            }
            guard case .valid(let candidate) = loadAcceptedCandidateUnlocked(evidence.candidateID) else {
                throw StoreError.identityMismatch
            }
            guard evidence.sourceIdentity == candidate.sourceIdentity,
                  evidence.artifactDigest == candidate.artifactDigest else {
                throw StoreError.identityMismatch
            }
            switch evidence.kind {
            case .verification:
                guard evidence.evidenceID == candidate.verificationEvidenceID,
                      evidence.result == .passed else { throw StoreError.identityMismatch }
            case .review:
                guard evidence.evidenceID == candidate.reviewEvidenceID,
                      evidence.result == .passed else { throw StoreError.identityMismatch }
            case .uiAcceptance:
                guard evidence.result == .passed,
                      evidence.runIdentifier == candidate.uiAcceptedRunID,
                      evidence.receiptIdentifier == candidate.uiAcceptedReceiptID,
                      let receiptIdentifier = evidence.receiptIdentifier,
                      case .valid(let receipt) = loadUnlocked(receiptIdentifier),
                      receipt.phase == .installed || receipt.phase == .restored,
                      receipt.bundleIdentifier == candidate.bundleIdentifier,
                      receipt.sourceArtifactPath == candidate.artifactPath,
                      receipt.sourceIdentity == candidate.sourceIdentity,
                      receipt.replacementBundleIdentity?.bundleIdentifier == candidate.bundleIdentifier,
                      receipt.replacementBundleIdentity?.contentDigest == candidate.artifactDigest
                else { throw StoreError.identityMismatch }
            }
            try FileManager.default.createDirectory(
                at: acceptedCandidateEvidenceDirectory, withIntermediateDirectories: true
            )
            var metadata = stat()
            guard lstat(acceptedCandidateEvidenceDirectory.path, &metadata) == 0,
                  (metadata.st_mode & S_IFMT) == S_IFDIR,
                  pathHasNoSymlinkComponents(acceptedCandidateEvidenceDirectory.path, allowMissing: false) else {
                throw StoreError.writeFailed
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(evidence)
            guard data.count <= Self.maximumRecordBytes else { throw StoreError.invalidReceipt }
            try publish(data, at: acceptedCandidateEvidenceURL(for: evidence.evidenceID), refusingExisting: true)
        }
    }

    /// Re-read the record and all exact identities while holding the existing
    /// receipt-store lock. This is a callable seam for a later coordinator;
    /// it performs no generation, delivery, cleanup, or app launch.
    func revalidateAcceptedCandidate(
        _ identifier: UUID,
        project: IrisTestProjectRegistry.Project,
        receipt: AppDeliveryReceipt?,
        expectedVerificationEvidenceID: UUID? = nil,
        expectedReviewEvidenceID: UUID? = nil
    ) -> AcceptedCandidateRevalidation {
        do {
            return try withExclusiveStoreLock {
                switch loadAcceptedCandidateUnlocked(identifier) {
                case .absent: return .absent
                case .corrupt: return .corrupt
                case .oversized: return .oversized
                case .symlink: return .symlink
                case .valid(let record):
                    if let failure = record.failureAgainst(project: project, receipt: receipt,
                        expectedVerificationEvidenceID: expectedVerificationEvidenceID,
                        expectedReviewEvidenceID: expectedReviewEvidenceID) {
                        return .invalid(failure)
                    }
                    guard record.artifactDigestMatchesFilesystem() else {
                        return .invalid(.artifactDigestMismatch)
                    }
                    return .valid(record)
                }
            }
        } catch {
            return .storageFailure
        }
    }

    /// Strict reuse gate. It resolves the receipt and all three positive
    /// evidence records from this store while holding its lock. No caller
    /// supplied UUID, receipt, or reviewer prose can satisfy this route.
    /// Current Git/source probing remains an explicit coordinator seam and is
    /// intentionally not inferred here.
    func revalidateAcceptedCandidateUsingPersistedEvidence(
        _ identifier: UUID,
        project: IrisTestProjectRegistry.Project
    ) -> AcceptedCandidateRevalidation {
        do {
            return try withExclusiveStoreLock {
                guard case .valid(let candidate) = loadAcceptedCandidateUnlocked(identifier) else {
                    switch loadAcceptedCandidateUnlocked(identifier) {
                    case .absent: return .absent
                    case .corrupt: return .corrupt
                    case .oversized: return .oversized
                    case .symlink: return .symlink
                    case .valid: return .corrupt
                    }
                }
                guard let uiRunID = candidate.uiAcceptedRunID,
                      let uiReceiptID = candidate.uiAcceptedReceiptID else {
                    return .invalid(.liveEvidenceMissing)
                }
                guard case .valid(let receipt) = loadUnlocked(uiReceiptID) else {
                    return .invalid(.receiptMissing)
                }
                guard receipt.phase == .installed || receipt.phase == .restored else {
                    return .invalid(.receiptMismatch)
                }
                if let failure = candidate.failureAgainst(project: project, receipt: receipt) {
                    return .invalid(failure)
                }
                guard candidate.artifactDigestMatchesFilesystem() else {
                    return .invalid(.artifactDigestMismatch)
                }
                switch persistedEvidenceFailure(
                    candidate: candidate,
                    kind: .verification,
                    expectedIdentifier: candidate.verificationEvidenceID
                ) {
                case .none: break
                case .failure(let failure): return .invalid(failure)
                }
                switch persistedEvidenceFailure(
                    candidate: candidate,
                    kind: .review,
                    expectedIdentifier: candidate.reviewEvidenceID
                ) {
                case .none: break
                case .failure(let failure): return .invalid(failure)
                }
                guard case .valid(let liveEvidence) = loadAcceptedCandidateEvidenceUnlocked(uiRunID),
                      liveEvidence.kind == .uiAcceptance,
                      liveEvidence.result == .passed,
                      liveEvidence.candidateID == candidate.candidateID,
                      liveEvidence.runIdentifier == uiRunID,
                      liveEvidence.receiptIdentifier == uiReceiptID,
                      liveEvidence.sourceIdentity == candidate.sourceIdentity,
                      liveEvidence.artifactDigest == candidate.artifactDigest,
                      liveEvidence.observedBundleIdentity == receipt.replacementBundleIdentity else {
                    return .invalid(.liveEvidenceMismatch)
                }
                return .valid(candidate)
            }
        } catch {
            return .storageFailure
        }
    }

    private enum EvidenceFailure {
        case none
        case failure(AcceptedCandidateRecord.ValidationFailure)
    }

    private func persistedEvidenceFailure(
        candidate: AcceptedCandidateRecord,
        kind: AcceptedCandidateEvidenceRecord.Kind,
        expectedIdentifier: UUID
    ) -> EvidenceFailure {
        switch loadAcceptedCandidateEvidenceUnlocked(expectedIdentifier) {
        case .absent, .oversized, .symlink, .corrupt:
            return .failure(kind == .verification ? .verificationEvidenceMissing : .reviewEvidenceMissing)
        case .valid(let evidence):
            guard evidence.isValid,
                  evidence.kind == kind,
                  evidence.evidenceID == expectedIdentifier,
                  evidence.candidateID == candidate.candidateID,
                  evidence.sourceIdentity == candidate.sourceIdentity,
                  evidence.artifactDigest == candidate.artifactDigest,
                  evidence.result == .passed else {
                return .failure(.evidenceMismatch)
            }
            return .none
        }
    }

    func load(_ identifier: UUID) -> LoadState {
        loadUnlocked(identifier)
    }

    private func loadUnlocked(_ identifier: UUID) -> LoadState {
        let destination = url(for: identifier)
        var metadata = stat()
        guard lstat(destination.path, &metadata) == 0 else {
            return errno == ENOENT ? .absent : .corrupt
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { return .corrupt }
        guard let data = try? boundedData(at: destination),
              let receipt = try? JSONDecoder().decode(AppDeliveryReceipt.self, from: data),
              receipt.identifier == identifier, receipt.isValid else { return .corrupt }
        return .valid(receipt)
    }

    /// Lists bounded metadata for a settings/recovery surface, retaining a
    /// visible corrupt entry rather than silently treating it as absent.
    func entries(limit: Int = maximumEntries) -> [Entry] {
        guard limit > 0 else { return [] }
        var directoryMetadata = stat()
        guard lstat(baseDirectory.path, &directoryMetadata) == 0 else {
            return errno == ENOENT ? [] : [.unreadable(path: baseDirectory.path)]
        }
        guard (directoryMetadata.st_mode & S_IFMT) == S_IFDIR else {
            return [.unreadable(path: baseDirectory.path)]
        }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: baseDirectory, includingPropertiesForKeys: nil
            )
        } catch {
            return [.unreadable(path: baseDirectory.path)]
        }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
            .prefix(min(limit, Self.maximumEntries)).map { file in
                guard let identifier = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                    return .corrupt(path: file.path)
                }
                switch load(identifier) {
                case .valid(let receipt): return .valid(receipt)
                case .absent, .corrupt: return .corrupt(path: file.path)
                }
            }
    }

    func transition(_ current: AppDeliveryReceipt, to phase: AppDeliveryReceipt.Phase) throws -> AppDeliveryReceipt {
        guard current.isValid else { throw StoreError.invalidReceipt }
        return try withExclusiveStoreLock {
            let existing: AppDeliveryReceipt
            switch load(current.identifier) {
            case .valid(let receipt): existing = receipt
            case .absent: throw StoreError.absent
            case .corrupt: throw StoreError.corrupt
            }
            guard existing.identity == current.identity else { throw StoreError.identityMismatch }
            guard existing.phase == current.phase else { throw StoreError.identityMismatch }
            guard existing.phase == phase || (existing.phase == .prepared && phase == .installed)
                    || (existing.phase == .installed && phase == .restored) else {
                throw StoreError.invalidTransition
            }
            if existing.phase == phase { return existing }
        let next = AppDeliveryReceipt(identifier: existing.identifier,
            bundleIdentifier: existing.bundleIdentifier, installedPath: existing.installedPath,
            sourceArtifactPath: existing.sourceArtifactPath, backupPath: existing.backupPath,
            startedAt: existing.startedAt, phase: phase,
            sourceIdentity: existing.sourceIdentity,
            installedBundleIdentity: existing.installedBundleIdentity,
            replacementBundleIdentity: existing.replacementBundleIdentity,
            backupBundleIdentity: existing.backupBundleIdentity)
            try publish(try encoded(next), at: url(for: next.identifier), refusingExisting: false)
            return next
        }
    }

    /// Finish the one durable state transition that can be interrupted by a
    /// process crash. Installed delivery publishes a `.prepared` receipt before
    /// swapping the app, then changes it to `.installed` after the swap. If
    /// Iris dies between those writes, the app on disk is already the new app
    /// but Saved Versions would otherwise keep showing a prepared record that
    /// cannot be used for Undo after restart.
    ///
    /// This is deliberately conservative: a prepared receipt is promoted only
    /// when it has complete identity metadata and the installed and backup
    /// payloads still match the exact recorded replacement and prior app. A
    /// failed or partial swap therefore remains prepared and is never guessed
    /// into history. The operation is idempotent and never changes app files.
    @discardableResult
    func reconcilePreparedInstallations() throws -> Int {
        try withExclusiveStoreLock {
            var promoted = 0
            for receipt in try retentionReceipts() where receipt.phase == .prepared {
                guard let source = receipt.sourceIdentity, source.isValid,
                      let installed = receipt.installedBundleIdentity, installed.isValid,
                      let replacement = receipt.replacementBundleIdentity, replacement.isValid,
                      let backup = receipt.backupBundleIdentity, backup.isValid,
                      installed.contentDigest != nil,
                      replacement.contentDigest != nil,
                      backup.contentDigest != nil,
                      installed == backup,
                      installed.bundleIdentifier == receipt.bundleIdentifier,
                      replacement.bundleIdentifier == receipt.bundleIdentifier,
                      pathHasNoSymlinkComponents(receipt.installedPath, allowMissing: false),
                      pathHasNoSymlinkComponents(receipt.backupPath, allowMissing: false),
                      AppDeliveryReceipt.bundleIdentity(atPath: receipt.installedPath) == replacement,
                      AppDeliveryReceipt.bundleIdentity(atPath: receipt.backupPath) == backup else {
                    continue
                }

                let next = AppDeliveryReceipt(
                    identifier: receipt.identifier,
                    bundleIdentifier: receipt.bundleIdentifier,
                    installedPath: receipt.installedPath,
                    sourceArtifactPath: receipt.sourceArtifactPath,
                    backupPath: receipt.backupPath,
                    startedAt: receipt.startedAt,
                    phase: .installed,
                    sourceIdentity: source,
                    installedBundleIdentity: installed,
                    replacementBundleIdentity: replacement,
                    backupBundleIdentity: backup
                )
                try publish(try encoded(next), at: url(for: next.identifier), refusingExisting: false)
                promoted += 1
            }
            return promoted
        }
    }

    private func encoded(_ receipt: AppDeliveryReceipt) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipt)
        guard data.count <= Self.maximumRecordBytes else { throw StoreError.invalidReceipt }
        return data
    }

    private func loadAcceptedCandidateUnlocked(_ identifier: UUID) -> AcceptedCandidateLoadState {
        guard pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: true),
              pathHasNoSymlinkComponents(acceptedCandidatesDirectory.path, allowMissing: true) else {
            return .corrupt
        }
        let destination = acceptedCandidateURL(for: identifier)
        var metadata = stat()
        guard lstat(destination.path, &metadata) == 0 else {
            return errno == ENOENT ? .absent : .corrupt
        }
        let kind = metadata.st_mode & S_IFMT
        if kind == S_IFLNK { return .symlink }
        guard kind == S_IFREG else { return .corrupt }
        guard metadata.st_size <= off_t(Self.maximumRecordBytes) else { return .oversized }
        guard let data = try? boundedData(at: destination),
              let record = try? JSONDecoder().decode(AcceptedCandidateRecord.self, from: data),
              record.candidateID == identifier else { return .corrupt }
        return .valid(record)
    }

    private func loadAcceptedCandidateEvidenceUnlocked(
        _ identifier: UUID
    ) -> AcceptedCandidateEvidenceLoadState {
        guard pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: true),
              pathHasNoSymlinkComponents(acceptedCandidatesDirectory.path, allowMissing: true),
              pathHasNoSymlinkComponents(acceptedCandidateEvidenceDirectory.path, allowMissing: true) else {
            return .corrupt
        }
        let destination = acceptedCandidateEvidenceURL(for: identifier)
        var metadata = stat()
        guard lstat(destination.path, &metadata) == 0 else {
            return errno == ENOENT ? .absent : .corrupt
        }
        let kind = metadata.st_mode & S_IFMT
        if kind == S_IFLNK { return .symlink }
        guard kind == S_IFREG else { return .corrupt }
        guard metadata.st_size <= off_t(Self.maximumRecordBytes) else { return .oversized }
        guard let data = try? boundedData(at: destination),
              let evidence = try? JSONDecoder().decode(
                AcceptedCandidateEvidenceRecord.self, from: data
              ), evidence.evidenceID == identifier else { return .corrupt }
        return .valid(evidence)
    }

    private func boundedData(at url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StoreError.corrupt }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var information = stat()
        guard fstat(descriptor, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_size <= off_t(Self.maximumRecordBytes) else { throw StoreError.corrupt }
        let data = try handle.read(upToCount: Self.maximumRecordBytes + 1) ?? Data()
        guard data.count == information.st_size else { throw StoreError.corrupt }
        return data
    }

    private func withExclusiveStoreLock<T>(_ operation: () throws -> T) throws -> T {
        guard pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: true) else {
            throw StoreError.writeFailed
        }
        do {
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } catch {
            throw StoreError.writeFailed
        }
        guard pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: false) else {
            throw StoreError.writeFailed
        }
        let lockURL = baseDirectory.appendingPathComponent(".lock")
        guard pathHasNoSymlinkComponents(lockURL.path, allowMissing: true) else {
            throw StoreError.writeFailed
        }
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw StoreError.writeFailed }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.writeFailed }
        return try operation()
    }

    /// Read-only counterpart to the writer lock. It never creates a missing
    /// receipt directory or lock file, which keeps a preview non-mutating.
    private func withExistingStoreSharedLock<T>(_ operation: () throws -> T) throws -> T? {
        guard pathHasNoSymlinkComponents(baseDirectory.path, allowMissing: true) else {
            throw RetentionError.unsafePath
        }
        var baseMetadata = stat()
        guard lstat(baseDirectory.path, &baseMetadata) == 0 else {
            if errno == ENOENT { return nil }
            throw RetentionError.unreadableInventory
        }
        guard (baseMetadata.st_mode & S_IFMT) == S_IFDIR else {
            throw RetentionError.unsafePath
        }
        let lockURL = baseDirectory.appendingPathComponent(".lock")
        guard pathHasNoSymlinkComponents(lockURL.path, allowMissing: true) else {
            throw RetentionError.unsafePath
        }
        var lockMetadata = stat()
        guard lstat(lockURL.path, &lockMetadata) == 0 else {
            if errno == ENOENT { return nil }
            throw RetentionError.unreadableInventory
        }
        guard (lockMetadata.st_mode & S_IFMT) == S_IFREG else {
            throw RetentionError.unsafePath
        }
        let descriptor = open(lockURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw RetentionError.unreadableInventory }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_SH) == 0 else { throw RetentionError.unreadableInventory }
        return try operation()
    }

    private func publish(_ data: Data, at destination: URL, refusingExisting: Bool) throws {
        let stagingDirectory = destination.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true) }
        catch { throw StoreError.writeFailed }
        let temporary = stagingDirectory.appendingPathComponent(".staging-" + UUID().uuidString)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw StoreError.writeFailed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); _ = unlink(temporary.path) }
        do { try handle.write(contentsOf: data); try handle.synchronize() }
        catch { throw StoreError.writeFailed }
        if refusingExisting {
            guard link(temporary.path, destination.path) == 0 else {
                if errno == EEXIST { throw StoreError.alreadyExists }
                throw StoreError.writeFailed
            }
            _ = unlink(temporary.path)
        } else if rename(temporary.path, destination.path) != 0 {
            throw StoreError.writeFailed
        }
        let directory = open(stagingDirectory.path, O_RDONLY | O_NOFOLLOW)
        guard directory >= 0 else { throw StoreError.writeFailed }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw StoreError.writeFailed }
    }
}
