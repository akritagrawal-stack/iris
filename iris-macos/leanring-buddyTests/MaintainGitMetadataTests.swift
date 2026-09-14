import Foundation
import Testing

@testable import Iris

/// The edit loop temporarily moves `.git` out of the clone while a model-owned
/// command runs. These checks keep a failed Git probe distinct from a clean
/// working tree, and exercise the move/edit/restore sequence with a real Git
/// repository.
@MainActor
@Suite(.serialized)
struct MaintainGitMetadataTests {

    @Test func failedStatusProbeIsNotClassifiedAsClean() {
        let failed = MaintainCommandResult(
            exitCode: 128,
            outputTail: "fatal: not a git repository",
            timedOut: false,
            bytesDroppedBeforeTail: 0
        )
        let timedOut = MaintainCommandResult(
            exitCode: 143,
            outputTail: "",
            timedOut: true,
            bytesDroppedBeforeTail: 0
        )
        let truncated = MaintainCommandResult(
            exitCode: 0,
            outputTail: " M source.txt",
            timedOut: false,
            bytesDroppedBeforeTail: 1
        )
        let missing = MaintainTierCFixer.workingTreeChangeObservation(from: nil)

        #expect(MaintainTierCFixer.workingTreeChangeObservation(from: failed) == .unavailable)
        #expect(MaintainTierCFixer.workingTreeChangeObservation(from: timedOut) == .unavailable)
        #expect(MaintainTierCFixer.workingTreeChangeObservation(from: truncated) == .unavailable)
        #expect(missing == .unavailable)
        #expect(
            MaintainTierCFixer.workingTreeChangeObservation(
                from: MaintainCommandResult(
                    exitCode: 0, outputTail: " \n", timedOut: false, bytesDroppedBeforeTail: 0
                )
            ) == .clean
        )
    }

    @Test func restoredGitMetadataMakesTheRealEditVisibleToStatus() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("iris-git-metadata-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.txt")
        let backup = root.deletingLastPathComponent()
            .appendingPathComponent("iris-git-metadata-backup-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: backup)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("before\n".utf8).write(to: source)

        let runner = try MaintainShellRunner(repoRootPath: root.path)
        let initialized = try await runner.run(
            "git init -q && git -c user.name=Iris -c user.email=iris@example.invalid add source.txt && git -c user.name=Iris -c user.email=iris@example.invalid commit -qm baseline",
            deadline: 30
        )
        #expect(initialized.succeeded)

        let quotedBackup = shellSingleQuoted(backup.path)
        let detached = try await runner.run(
            "test -e .git && test ! -e \(quotedBackup) && mv .git \(quotedBackup) && test -e \(quotedBackup)",
            deadline: 30
        )
        #expect(detached.succeeded)

        let edited = try await runner.run(
            "printf 'after\\n' >> source.txt",
            deadline: 30
        )
        #expect(edited.succeeded)

        // This is the recovery command used by MaintainTierCFixer. It must
        // prove both sides of the move before the loop trusts Git again.
        let restored = try await runner.run(
            "test ! -e .git && test -e \(quotedBackup) && mv \(quotedBackup) .git && test -e .git && test ! -e \(quotedBackup)",
            deadline: 30
        )
        #expect(restored.succeeded)

        let status = try await runner.run(
            "git status --porcelain=v1 --untracked-files=all",
            deadline: 30
        )
        #expect(
            MaintainTierCFixer.workingTreeChangeObservation(from: status) == .changed,
            "restored Git metadata hid the real source edit: \(status.outputTail)"
        )
        #expect(fileManager.fileExists(atPath: root.appendingPathComponent(".git").path))
        #expect(!fileManager.fileExists(atPath: backup.path))
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
