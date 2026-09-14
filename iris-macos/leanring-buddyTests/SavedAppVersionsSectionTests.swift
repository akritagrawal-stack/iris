import Testing
#if canImport(Iris)
@testable import Iris
#else
@testable import IrisUsability
#endif

struct SavedAppVersionsSectionTests {
    @Test func missingProjectIdentityExplainsWhyUndoIsUnavailable() {
        let receipt = AppDeliveryReceipt(
            bundleIdentifier: "com.example.app",
            installedPath: "/tmp/App.app",
            sourceArtifactPath: "/tmp/build/App.app",
            backupPath: "/tmp/backup/App.app"
        )

        let result = SavedAppVersionsSection.testProjectUndoFailure(receipt: receipt, project: nil)

        #expect(result == "Undo is unavailable because the exact Test project identity was not saved.")
    }

    @Test func unregisteredProjectExplainsWhyUndoIsUnavailable() {
        let receipt = Self.receipt()

        let result = SavedAppVersionsSection.testProjectUndoFailure(receipt: receipt, project: nil)

        #expect(result == "Undo is unavailable because this Test app is no longer registered.")
    }

    @Test func changedProjectIdentityBlocksUndo() {
        let receipt = Self.receipt()
        let project = Self.project(clonePath: "/tmp/changed-clone")

        let result = SavedAppVersionsSection.testProjectUndoFailure(receipt: receipt, project: project)

        #expect(result == "Undo is unavailable because this Test app's registered identity changed since delivery.")
    }

    @Test func exactProjectIdentityAllowsUndo() {
        let receipt = Self.receipt()
        let result = SavedAppVersionsSection.testProjectUndoFailure(receipt: receipt, project: Self.project())

        #expect(result == nil)
    }

    private static func receipt() -> AppDeliveryReceipt {
        AppDeliveryReceipt(
            bundleIdentifier: "com.example.app",
            installedPath: "/tmp/App.app",
            sourceArtifactPath: "/tmp/build/App.app",
            backupPath: "/tmp/backup/App.app",
            sourceIdentity: .init(
                appSlug: "example",
                appName: "Example",
                clonePath: "/tmp/example",
                branchName: "codex/example",
                commit: String(repeating: "a", count: 40),
                baseCommit: String(repeating: "b", count: 40),
                baseRef: "main",
                changeId: "change-1"
            )
        )
    }

    private static func project(clonePath: String = "/tmp/example") -> IrisTestProjectRegistry.Project {
        .init(
            slug: "example",
            name: "Example",
            clonePath: clonePath,
            applicationPath: "/tmp/App.app",
            buildArtifactPath: "/tmp/build/App.app",
            bundleIdentifier: "com.example.app",
            pinnedCommit: String(repeating: "a", count: 40)
        )
    }
}
