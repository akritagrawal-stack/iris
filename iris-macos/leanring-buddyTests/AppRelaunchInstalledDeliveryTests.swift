//
//  AppRelaunchInstalledDeliveryTests.swift
//  leanring-buddyTests
//
//  The pure decision logic behind the founder's Sep 2 2026 override: after a
//  green build, the fresh copy is installed OVER the reader's installed app
//  rather than launched from the clone's build dir. The two things worth
//  pinning here are which copy counts as "the installed app to replace"
//  (never the clone's own build output; /Applications wins) and where the
//  pre-delivery snapshot for undo is kept. The ditto/replace filesystem work
//  itself is covered below with disposable app-shaped bundles; replacement of
//  a real installed app remains supervised dogfood, like the relaunch mechanics
//  above it.
//

import Foundation
import Testing
@testable import Iris

@MainActor
@Suite struct AppRelaunchInstalledDeliveryTests {

    private static let clonePath = "/Users/someone/whimprflow"
    private static let buildDirCopy =
        "/Users/someone/whimprflow/target/release/bundle/macos/WhimprFlow.app"

    /// Receipt storage deliberately rejects symlinked path components. Keep
    /// these disposable bundles under Iris Test's real Application Support
    /// root rather than macOS's `/var` temporary-directory alias, so the
    /// fixture exercises the same trusted-path policy used by delivery.
    private static func isolatedFixtureRoot(_ label: String) -> URL {
        let root = IrisTestEnvironment.applicationSupportDirectory
            .appendingPathComponent("test-fixtures", isDirectory: true)
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A copy under /Applications is what gets replaced, even when Launch
    /// Services' registered copy is the clone's own build output — which is
    /// exactly the case that misfired: the running copy was the build-dir one,
    /// so trusting the registered copy alone would have replaced nothing.
    @Test func prefersTheApplicationsCopyOverTheCloneBuildOutput() {
        let chosen = AppRelaunchService.chooseInstalledBundlePath(
            registeredPath: Self.buildDirCopy,
            applicationsPath: "/Applications/WhimprFlow.app",
            clonePath: Self.clonePath
        )
        #expect(chosen == "/Applications/WhimprFlow.app")
    }

    /// The clone's build output is NEVER "the installed app" — replacing it with
    /// itself would be a no-op that reads as success. With no copy outside the
    /// clone, there is nothing to replace and the caller falls back to the
    /// build-dir artifact.
    @Test func neverReturnsACopyInsideTheClone() {
        let chosen = AppRelaunchService.chooseInstalledBundlePath(
            registeredPath: Self.buildDirCopy,
            applicationsPath: nil,
            clonePath: Self.clonePath
        )
        #expect(chosen == nil)
    }

    /// A registered copy OUTSIDE the clone and outside /Applications (an app the
    /// reader keeps in ~/Applications, say) is still a real installed copy to
    /// replace when /Applications has none.
    @Test func fallsBackToARegisteredCopyOutsideTheClone() {
        let userApplications = "/Users/someone/Applications/WhimprFlow.app"
        let chosen = AppRelaunchService.chooseInstalledBundlePath(
            registeredPath: userApplications,
            applicationsPath: nil,
            clonePath: Self.clonePath
        )
        #expect(chosen == userApplications)
    }

    /// When BOTH candidates are the clone's build output (nothing installed
    /// separately at all), there is nothing to replace.
    @Test func returnsNilWhenEveryCandidateIsInsideTheClone() {
        let chosen = AppRelaunchService.chooseInstalledBundlePath(
            registeredPath: Self.buildDirCopy,
            applicationsPath: Self.buildDirCopy,
            clonePath: Self.clonePath
        )
        #expect(chosen == nil)
    }

    /// A packaging failure must remain retryable after Iris Test restarts. This
    /// simulates the restart boundary with an isolated defaults suite, then
    /// feeds the decoded identity into the coordinator's UI-admission gate.
    /// The record is intentionally only an identity handoff: it cannot retain
    /// a prompt, diff, API key, or built app. The live coordinator still
    /// rechecks this identity against Git and the Iris Test registry before it
    /// exposes a retry action.
    @Test func savedDeliveryRetryRecordRestoresIntoCoordinatorRetryAdmission() throws {
        let suiteName = "iris.saved-delivery-retry-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("the isolated UserDefaults suite could not be created")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SavedDeliveryRetryStore(userDefaults: defaults)
        let record = SavedDeliveryRetryRecord(
            appSlug: "iris-delivery-fixture",
            appName: "Iris Test Delivery",
            changeID: "change-fixture",
            identity: SavedEditDeliveryIdentity(
                clonePath: "/Users/someone/IrisTestDelivery",
                branchName: "iris/edit-fixture",
                commit: String(repeating: "a", count: 40)
            ),
            originalHeadCommit: String(repeating: "b", count: 40),
            originalHeadRef: "main"
        )

        #expect(store.load() == nil)
        store.save(record)
        let restored = try #require(store.load())
        #expect(restored == record)
        #expect(restored.originalHeadCommit == String(repeating: "b", count: 40))
        #expect(restored.originalHeadRef == "main")

        // These are the state values the coordinator publishes after a
        // valid saved source has been rechecked on startup. No edit task,
        // Undo recovery, or installed replacement may suppress the retry.
        #expect(OnDemandEditCoordinator.savedDeliveryRetryIsEligible(
            savedDeliveryMayBeRetried: true,
            hasSavedDeliveryIdentity: restored.identity == record.identity,
            phase: .done,
            hasEditTask: false,
            undoNeedsRecovery: false,
            installedCopyReplaced: false
        ))
    }

    /// The undo snapshot lives under Application Support, keyed by a
    /// filesystem-safe form of the bundle id, and keeps the app's own bundle
    /// name so the restored copy is recognizably itself.
    @Test func deliveryBackupPathIsKeyedByBundleIdUnderApplicationSupport() {
        let backupPath = AppRelaunchService.deliveryBackupPath(
            forBundleId: "com.whimpr.whimprflow", appBundleName: "WhimprFlow.app"
        )
        #expect(backupPath.contains(
            "Application Support/\(IrisTestEnvironment.applicationSupportDirectoryName)/edit-delivery-backups"
        ))
        #expect(backupPath.contains("com.whimpr.whimprflow"))
        #expect(backupPath.hasSuffix("WhimprFlow.app"))
    }

    // MARK: - Live filesystem round-trip (the real ditto + replaceItemAt swap)

    /// Build a minimal `.app`-shaped directory whose Info.plist marker records a
    /// version, so a swap can be proven by reading which version is at a path.
    private static func makeFakeBundle(
        at path: String, marker: String, bundleIdentifier: String = "com.fixture.demo"
    ) {
        let contents = (path as NSString).appendingPathComponent("Contents")
        let executableName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "")
        let executablePath = (contents as NSString).appendingPathComponent("MacOS/\(executableName)")
        try? FileManager.default.createDirectory(
            atPath: (executablePath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": executableName,
            "CFBundleName": URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        ]
        if let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0) {
            try? data.write(to: URL(fileURLWithPath: contents).appendingPathComponent("Info.plist"))
        }
        try? Data("#!/bin/sh\nexit 0\n".utf8).write(to: URL(fileURLWithPath: executablePath))
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executablePath)
        FileManager.default.createFile(
            atPath: (contents as NSString).appendingPathComponent("marker.txt"),
            contents: Data(marker.utf8)
        )
    }

    private static func markerOfBundle(at path: String) -> String? {
        let markerPath = (path as NSString)
            .appendingPathComponent("Contents/marker.txt")
        return (try? String(contentsOfFile: markerPath, encoding: .utf8))
    }

    /// A process can die after the installed swap has committed but before the
    /// receipt's prepared -> installed publication. Startup reconciliation must
    /// recognize that exact on-disk state, recover the receipt, and make the
    /// completed delivery undoable instead of leaving it stranded as pending.
    @Test func startupReconcilesAReceiptInterruptedAfterTheInstalledSwap() throws {
        let root = Self.isolatedFixtureRoot("iris-delivery-reconcile")
        defer { try? FileManager.default.removeItem(at: root) }

        let installedPath = root.appendingPathComponent("Applications/Demo.app").path
        let freshBuildPath = root.appendingPathComponent("clone/build/Demo.app").path
        let snapshotPath = root.appendingPathComponent("backups/Demo.app").path
        let receiptDirectory = root.appendingPathComponent("receipts")
        Self.makeFakeBundle(at: installedPath, marker: "installed-v1")
        Self.makeFakeBundle(at: freshBuildPath, marker: "fresh-v2")

        let store = AppDeliveryReceiptStore(baseDirectory: receiptDirectory)
        let installedIdentity = try #require(AppDeliveryReceipt.bundleIdentity(atPath: installedPath))
        let replacementIdentity = try #require(AppDeliveryReceipt.bundleIdentity(atPath: freshBuildPath))
        let sourceIdentity = AppDeliveryReceipt.SourceIdentity(
            appSlug: "demo", appName: "Demo", clonePath: root.appendingPathComponent("clone").path,
            branchName: "codex/demo", commit: String(repeating: "a", count: 40),
            baseCommit: String(repeating: "b", count: 40), baseRef: "main", changeId: "change-1"
        )
        let receipt = AppDeliveryReceipt(
            bundleIdentifier: "com.fixture.demo", installedPath: installedPath,
            sourceArtifactPath: freshBuildPath, backupPath: snapshotPath,
            sourceIdentity: sourceIdentity, installedBundleIdentity: installedIdentity,
            replacementBundleIdentity: replacementIdentity, backupBundleIdentity: installedIdentity
        )
        try store.savePrepared(receipt)

        let swap = AppRelaunchService.atomicallyReplaceBundle(
            installedPath: installedPath, withBundleAt: freshBuildPath, snapshotTo: snapshotPath
        )
        #expect(swap.isSuccess)
        #expect(Self.markerOfBundle(at: installedPath) == "fresh-v2")
        #expect(Self.markerOfBundle(at: snapshotPath) == "installed-v1")
        #expect(store.load(receipt.identifier) == .valid(receipt))

        let promoted = try store.reconcilePreparedInstallations()
        #expect(promoted == 1)
        guard case .valid(let recovered) = store.load(receipt.identifier) else {
            Issue.record("the interrupted delivery receipt was not recovered")
            return
        }
        #expect(recovered.phase == .installed)
        #expect(recovered.hasCompleteUndoMetadata)
        #expect(try store.reconcilePreparedInstallations() == 0)
    }

    /// Startup must never turn a partially changed delivery into an installed
    /// history entry. The prepared receipt remains available for diagnosis and
    /// retry, while reconciliation leaves every app bundle untouched.
    @Test func startupKeepsAChangedPreparedDeliveryPendingForRecovery() throws {
        let root = Self.isolatedFixtureRoot("iris-delivery-unconfirmed")
        defer { try? FileManager.default.removeItem(at: root) }

        let installedPath = root.appendingPathComponent("Applications/Demo.app").path
        let freshBuildPath = root.appendingPathComponent("clone/build/Demo.app").path
        let snapshotPath = root.appendingPathComponent("backups/Demo.app").path
        let receiptDirectory = root.appendingPathComponent("receipts")
        Self.makeFakeBundle(at: installedPath, marker: "installed-v1")
        Self.makeFakeBundle(at: freshBuildPath, marker: "fresh-v2")

        let store = AppDeliveryReceiptStore(baseDirectory: receiptDirectory)
        let installedIdentity = try #require(AppDeliveryReceipt.bundleIdentity(atPath: installedPath))
        let replacementIdentity = try #require(AppDeliveryReceipt.bundleIdentity(atPath: freshBuildPath))
        let sourceIdentity = AppDeliveryReceipt.SourceIdentity(
            appSlug: "demo", appName: "Demo", clonePath: root.appendingPathComponent("clone").path,
            branchName: "codex/demo", commit: String(repeating: "a", count: 40),
            baseCommit: String(repeating: "b", count: 40), baseRef: "main", changeId: "change-1"
        )
        let receipt = AppDeliveryReceipt(
            bundleIdentifier: "com.fixture.demo", installedPath: installedPath,
            sourceArtifactPath: freshBuildPath, backupPath: snapshotPath,
            sourceIdentity: sourceIdentity, installedBundleIdentity: installedIdentity,
            replacementBundleIdentity: replacementIdentity, backupBundleIdentity: installedIdentity
        )
        try store.savePrepared(receipt)
        #expect(AppRelaunchService.atomicallyReplaceBundle(
            installedPath: installedPath, withBundleAt: freshBuildPath, snapshotTo: snapshotPath
        ).isSuccess)

        let installedMarker = URL(fileURLWithPath: installedPath).appendingPathComponent("Contents/marker.txt")
        try Data("unconfirmed-change".utf8).write(to: installedMarker)
        #expect(try store.reconcilePreparedInstallations() == 0)
        guard case .valid(let retained) = store.load(receipt.identifier) else {
            Issue.record("the unconfirmed delivery receipt was not retained")
            return
        }
        #expect(retained.phase == .prepared)
        #expect(!retained.hasCompleteUndoMetadata)
        #expect(Self.markerOfBundle(at: installedPath) == "unconfirmed-change")
        #expect(Self.markerOfBundle(at: snapshotPath) == "installed-v1")
        #expect(Self.markerOfBundle(at: freshBuildPath) == "fresh-v2")
    }

    /// The core the whole delivery rests on, exercised for real: snapshot the
    /// installed bundle, swap the fresh one into its exact path, and prove the
    /// installed path now holds the FRESH build while the snapshot holds the OLD
    /// one — then run the same primitive in reverse (the undo) and prove the
    /// original is back. Real `ditto`, real `replaceItemAt`, real temp bundles;
    /// no model, no network. This is the one corruption-risking primitive, so it
    /// earns a real round trip rather than a mocked one.
    @Test func swappingABundleReplacesItInPlaceAndTheSnapshotRestoresIt() throws {
        let root = Self.isolatedFixtureRoot("iris-delivery-live")
        defer { try? FileManager.default.removeItem(at: root) }

        let installedPath = root.appendingPathComponent("Applications/Demo.app").path
        let freshBuildPath = root.appendingPathComponent("clone/build/Demo.app").path
        let snapshotPath = root.appendingPathComponent("backups/Demo.app").path
        Self.makeFakeBundle(at: installedPath, marker: "installed-v1")
        Self.makeFakeBundle(at: freshBuildPath, marker: "fresh-v2")

        // Deliver: the installed copy becomes the fresh build; the old one is
        // preserved at the snapshot path for undo.
        let delivered = AppRelaunchService.atomicallyReplaceBundle(
            installedPath: installedPath, withBundleAt: freshBuildPath, snapshotTo: snapshotPath
        )
        #expect(delivered.isSuccess)
        #expect(Self.markerOfBundle(at: installedPath) == "fresh-v2")
        #expect(Self.markerOfBundle(at: snapshotPath) == "installed-v1")
        // The fresh build the swap consumed is still where it was built — it was
        // ditto-copied, not moved, so verification/other steps can still read it.
        #expect(Self.markerOfBundle(at: freshBuildPath) == "fresh-v2")

        // Undo: the snapshot goes back into the installed path.
        let undone = AppRelaunchService.atomicallyReplaceBundle(
            installedPath: installedPath, withBundleAt: snapshotPath, snapshotTo: nil
        )
        #expect(undone.isSuccess)
        #expect(Self.markerOfBundle(at: installedPath) == "installed-v1")
    }

    /// A private recovery store is honored by the real swap primitive, so a
    /// harness can keep its Undo protection separate from Iris's normal store.
    @Test func swappingABundleUsesAnInjectedUndoRecoveryStore() throws {
        let root = Self.isolatedFixtureRoot("iris-delivery-private-recovery")
        defer { try? FileManager.default.removeItem(at: root) }

        let installedPath = root.appendingPathComponent("Applications/Demo.app").path
        let freshBuildPath = root.appendingPathComponent("clone/build/Demo.app").path
        let snapshotPath = root.appendingPathComponent("backups/Demo.app").path
        Self.makeFakeBundle(at: installedPath, marker: "installed-v1")
        Self.makeFakeBundle(at: freshBuildPath, marker: "fresh-v2")

        let privateStore = DeliveredEditUndoRecoveryStore(
            recordURL: root.appendingPathComponent("state/delivered-undo-recovery.json")
        )
        try FileManager.default.createDirectory(
            at: privateStore.archiveDirectoryURL,
            withIntermediateDirectories: true
        )
        let unreadableArchive = privateStore.archiveDirectoryURL
            .appendingPathComponent("unreadable.json")
        try Data("not-json".utf8).write(to: unreadableArchive)

        let result = AppRelaunchService.atomicallyReplaceBundle(
            installedPath: installedPath,
            withBundleAt: freshBuildPath,
            snapshotTo: snapshotPath,
            undoRecoveryStore: privateStore
        )
        #expect(!result.isSuccess)
        #expect(Self.markerOfBundle(at: installedPath) == "installed-v1")
        #expect(Self.markerOfBundle(at: freshBuildPath) == "fresh-v2")
        #expect(!FileManager.default.fileExists(atPath: snapshotPath))
    }

    /// A stale deterministic staging path must not be deleted or followed. The
    /// replacement gets a fresh UUID directory, while the old symlink and its
    /// target remain untouched.
    @Test func stalePredictableStagingPathIsPreserved() throws {
        let root = Self.isolatedFixtureRoot("iris-delivery-staging-safety")
        defer { try? FileManager.default.removeItem(at: root) }

        let installedPath = root.appendingPathComponent("Applications/Demo.app").path
        let freshBuildPath = root.appendingPathComponent("clone/build/Demo.app").path
        let targetDirectory = root.appendingPathComponent("sentinel", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let sentinel = targetDirectory.appendingPathComponent("keep.txt")
        try Data("do-not-delete".utf8).write(to: sentinel)
        Self.makeFakeBundle(at: installedPath, marker: "installed-v1")
        Self.makeFakeBundle(at: freshBuildPath, marker: "fresh-v2")

        let predictableStage = root
            .appendingPathComponent("Applications/.iris-delivery-Demo.app")
        try FileManager.default.createSymbolicLink(
            atPath: predictableStage.path, withDestinationPath: targetDirectory.path
        )

        let result = AppRelaunchService.atomicallyReplaceBundle(
            installedPath: installedPath, withBundleAt: freshBuildPath, snapshotTo: nil
        )
        #expect(result.isSuccess)
        #expect(Self.markerOfBundle(at: installedPath) == "fresh-v2")
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
        #expect(
            (try? FileManager.default.destinationOfSymbolicLink(atPath: predictableStage.path))
                == targetDirectory.path
        )
    }

    /// The delivery entry point, run for real against a bundle id that no app on
    /// this machine claims: there is nothing installed to replace, so it reports
    /// that honestly (the caller then launches the build-dir artifact) rather
    /// than inventing a target or failing. Uses a real fresh build on disk so
    /// the early "is the build there" guard is not what returns.
    @Test func installOverInstalledAppReportsNoInstalledCopyForAnUnknownBundleId() async {
        let root = Self.isolatedFixtureRoot("iris-delivery-none")
        defer { try? FileManager.default.removeItem(at: root) }
        let clonePath = root.appendingPathComponent("clone").path
        let freshBuildPath = root.appendingPathComponent("clone/build/Nope.app").path
        let bundleIdentifier = "com.iris.test.definitely-not-installed-\(UUID().uuidString)"
        Self.makeFakeBundle(at: freshBuildPath, marker: "fresh", bundleIdentifier: bundleIdentifier)

        let result = await AppRelaunchService().installFreshBuildOverInstalledApp(
            macBundleId: bundleIdentifier,
            freshBuildArtifactPath: freshBuildPath,
            clonePath: clonePath
        )
        #expect(result == .noInstalledCopyToReplace)
    }
}
