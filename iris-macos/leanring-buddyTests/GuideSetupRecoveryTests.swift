//
//  GuideSetupRecoveryTests.swift
//  leanring-buddyTests
//
//  Covers the setup recovery detour: what `GuideSessionController` does when the
//  branch a reader opened needs Git or Node and their computer does not have it.
//  The Tauri panel's `state.setupTool` flow (`iris-desktop/ui/app.js` —
//  `handlePrimaryAction`, `verifyCurrentTools`) remains the behavioral spec.
//
//  The guide API is answered by `StubbedGuideURLProtocol` — the same stub
//  `GuideSessionTests` uses — and the tool check is answered by
//  `RecordedToolVersionChecker`, so nothing here touches the network or spawns a
//  process. A test that shelled out for real would pass or fail depending on
//  whether the machine running it happens to have Node.
//

import Foundation
import Testing
// The module follows PRODUCT_NAME, which the fork renamed to Iris.
#if IRIS_HARNESS_STANDALONE
@testable import IrisHarnessNative
#else
@testable import Iris
#endif

/// Answers "is this tool installed?" from a table a test controls, and remembers
/// what it was asked. The record is what proves the branch with no setup steps
/// never runs a check at all, rather than running one and ignoring it.
actor RecordedToolVersionChecker {
    private var toolIsInstalledByName: [String: Bool]
    private(set) var toolNamesThatWereChecked: [String] = []

    init(toolIsInstalledByName: [String: Bool]) {
        self.toolIsInstalledByName = toolIsInstalledByName
    }

    /// The reader going away and installing the thing.
    func recordThatTheReaderInstalled(_ toolName: String) {
        toolIsInstalledByName[toolName] = true
    }

    func checkToolVersion(_ toolName: String) -> ToolVersion {
        toolNamesThatWereChecked.append(toolName)
        let toolIsInstalled = toolIsInstalledByName[toolName] ?? false
        return ToolVersion(
            tool: toolName,
            available: toolIsInstalled,
            version: toolIsInstalled ? "\(toolName) version 1.2.3" : ""
        )
    }
}

@MainActor
struct GuideSetupRecoveryTests {

    // MARK: - Entering the detour

    @Test func aMissingPrerequisiteWithSetupStepsDivertsTheReaderIntoSetup() async throws {
        let guideService = try GuideSessionTests.guideServiceAnsweredByTheStub()
        let toolChecker = RecordedToolVersionChecker(
            toolIsInstalledByName: ["git": true, "node": false]
        )
        let controller = Self.controller(guideService: guideService, toolChecker: toolChecker)

        await controller.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )

        #expect(controller.loadState == .guideIsOpen)
        #expect(controller.readerIsInSetupRecovery)

        let setupRecoveryState = try #require(controller.setupRecoveryState)
        // Only the tool that is actually missing sends the reader anywhere. Git
        // is installed, so its setup step is not part of the detour.
        #expect(setupRecoveryState.toolNamesStillMissing == ["node"])
        #expect(setupRecoveryState.setupStepsToWalk.map(\.id) == ["install-node"])
        #expect(controller.stepTheReaderIsLookingAt?.id == "install-node")

        // Both rows stay visible, so the reader can see what was checked rather
        // than only what failed.
        #expect(setupRecoveryState.prerequisiteCheckRows.map(\.toolName) == ["git", "node"])
        #expect(setupRecoveryState.prerequisiteCheckRows[0].state == .installedWithVersion(version: "git version 1.2.3"))
        #expect(setupRecoveryState.prerequisiteCheckRows[1].state == .notInstalled)

        // The card has to name the tool and say why the guide needs it — "not
        // installed" alone leaves the reader to guess whether it matters.
        #expect(controller.headlineForTheSetupRecoveryCard.contains("Node"))
        #expect(controller.explanationForTheSetupRecoveryCard.contains("Node"))
        #expect(controller.stepCounterText == "Setup")

        // The guide itself is untouched underneath: same step, same count.
        #expect(controller.currentStepIndex == 0)
        #expect(controller.currentStep?.id == "open-shell")
        #expect(controller.numberOfStepsInTheSelectedBranch == 4)

        // The setup step keeps a guide step's affordances, including its link.
        guard case .openLinkInBrowser(let linkURLString, let buttonLabel) =
                try #require(controller.primaryActionForTheCurrentStep) else {
            Issue.record("the Node setup step should offer its download link")
            return
        }
        #expect(linkURLString == "https://nodejs.org/en/download")
        #expect(buttonLabel == "Open download")
    }

    @Test func theSameBranchWithEveryToolPresentGoesStraightIntoTheGuide() async throws {
        let guideService = try GuideSessionTests.guideServiceAnsweredByTheStub()
        let toolChecker = RecordedToolVersionChecker(
            toolIsInstalledByName: ["git": true, "node": true]
        )
        let controller = Self.controller(guideService: guideService, toolChecker: toolChecker)

        await controller.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )

        #expect(controller.loadState == .guideIsOpen)
        #expect(controller.readerIsInSetupRecovery == false)
        #expect(controller.setupRecoveryState == nil)
        #expect(controller.currentStep?.id == "open-shell")
        #expect(controller.stepCounterText == "1 / 4")
        // The check did run — the detour was skipped because it found things,
        // not because nothing was looked at.
        #expect(await toolChecker.toolNamesThatWereChecked == ["git", "node"])
    }

    @Test func aMissingToolWithNoSetupStepsDoesNotDivertAndDoesNotDeadEnd() async throws {
        let guideService = try GuideSessionTests.guideServiceAnsweredByTheStub()
        let toolChecker = RecordedToolVersionChecker(
            toolIsInstalledByName: ["git": false, "node": false]
        )
        let controller = Self.controller(guideService: guideService, toolChecker: toolChecker)

        await controller.openGuide(
            slug: "no-setup-steps",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )

        // A branch with no repair route has nothing to walk the reader through,
        // so holding them on a setup card would be a dead end with no exit.
        #expect(controller.loadState == .guideIsOpen)
        #expect(controller.readerIsInSetupRecovery == false)
        #expect(controller.currentStep?.id == "open-shell")
        #expect(controller.primaryActionForTheCurrentStep != nil)

        // And nothing was spawned to find that out: the branch declares no
        // prerequisites, so there is nothing to check.
        #expect(await toolChecker.toolNamesThatWereChecked.isEmpty)
    }

    // MARK: - Getting out of the detour

    @Test func aRecheckThatFindsTheToolReturnsTheReaderToTheirSavedStep() async throws {
        let guideService = try GuideSessionTests.guideServiceAnsweredByTheStub()

        // The reader got three steps in on a day when everything was installed.
        let controllerFromTheEarlierSession = Self.controller(
            guideService: guideService,
            toolChecker: RecordedToolVersionChecker(
                toolIsInstalledByName: ["git": true, "node": true]
            )
        )
        await controllerFromTheEarlierSession.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )
        controllerFromTheEarlierSession.advanceToTheNextStep()
        controllerFromTheEarlierSession.advanceToTheNextStep()
        #expect(controllerFromTheEarlierSession.currentStepIndex == 2)
        await controllerFromTheEarlierSession.waitUntilProgressHasBeenPersisted()

        // Today Git is gone — a new Mac, or the command line tools were wiped.
        let toolChecker = RecordedToolVersionChecker(
            toolIsInstalledByName: ["git": false, "node": true]
        )
        let controller = Self.controller(guideService: guideService, toolChecker: toolChecker)
        await controller.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )
        #expect(controller.readerIsInSetupRecovery)
        #expect(controller.stepTheReaderIsLookingAt?.id == "install-git")
        // The saved place is restored before the detour, and waits there.
        #expect(controller.currentStepIndex == 2)

        // Copying the installer command is the step's action; the only setup
        // step then turns the button into the re-check, exactly as the Tauri
        // panel does once `actionReady` is set.
        let installerCommand = try #require(controller.commandBlockTextForTheCurrentStep)
        #expect(installerCommand == "xcode-select --install")
        controller.copyCommandToClipboard(installerCommand)
        guard case .runToolChecksForThisStep(let buttonLabel) =
                try #require(controller.primaryActionForTheCurrentStep) else {
            Issue.record("the last setup step should offer the re-check")
            return
        }
        #expect(buttonLabel == "Check again")

        await toolChecker.recordThatTheReaderInstalled("git")
        controller.performPrimaryAction()
        await controller.waitUntilTheSetupRecheckHasFinished()

        // The detour ends where it started, which is step three — not step one.
        #expect(controller.readerIsInSetupRecovery == false)
        #expect(controller.setupRecoveryState == nil)
        #expect(controller.currentStepIndex == 2)
        #expect(controller.currentStep?.id == "clone")
        #expect(controller.stepCounterText == "3 / 4")
    }

    @Test func aRecheckThatStillCannotFindTheToolSaysSoAndStaysInSetup() async throws {
        let guideService = try GuideSessionTests.guideServiceAnsweredByTheStub()
        let toolChecker = RecordedToolVersionChecker(
            toolIsInstalledByName: ["git": true, "node": false]
        )
        let controller = Self.controller(guideService: guideService, toolChecker: toolChecker)

        await controller.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )
        #expect(controller.readerIsInSetupRecovery)
        // Nothing has been re-checked yet, so there is nothing to report yet.
        #expect(controller.setupRecoveryState?.messageFromTheMostRecentRecheck == nil)

        controller.recheckThePrerequisitesForSetupRecovery()
        await controller.waitUntilTheSetupRecheckHasFinished()

        // Pressing a button and seeing nothing change is how a reader decides
        // the app is broken, so a failed re-check has to say what it found.
        #expect(controller.readerIsInSetupRecovery)
        let messageFromTheMostRecentRecheck = try #require(
            controller.setupRecoveryState?.messageFromTheMostRecentRecheck
        )
        #expect(messageFromTheMostRecentRecheck.contains("still cannot find Node"))
        #expect(controller.setupRecoveryState?.aRecheckIsRunning == false)
        #expect(controller.setupRecoveryState?.toolNamesStillMissing == ["node"])
        #expect(controller.stepTheReaderIsLookingAt?.id == "install-node")
        // Both checks ran: the arrival scan and the re-check.
        #expect(await toolChecker.toolNamesThatWereChecked == ["git", "node", "git", "node"])
    }

    @Test func skippingSetupReachesTheGuideAnyway() async throws {
        let guideService = try GuideSessionTests.guideServiceAnsweredByTheStub()
        let toolChecker = RecordedToolVersionChecker(
            toolIsInstalledByName: ["git": true, "node": false]
        )
        let controller = Self.controller(guideService: guideService, toolChecker: toolChecker)

        await controller.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )
        #expect(controller.readerIsInSetupRecovery)

        // Some people have the tool under a name the check cannot see. Iris
        // being wrong about that must not be the end of their install.
        controller.skipSetupRecoveryAndContinueToTheGuide()

        #expect(controller.readerIsInSetupRecovery == false)
        #expect(controller.currentStep?.id == "open-shell")
        #expect(controller.stepCounterText == "1 / 4")
        #expect(controller.primaryActionForTheCurrentStep != nil)
        // Skipping does not move the reader, so nothing about their place
        // changed either.
        #expect(controller.currentStepIndex == 0)
    }

    // MARK: - The detour writes nothing about the guide

    @Test func walkingTheSetupStepsLeavesSavedGuideProgressAlone() async throws {
        let guideService = try GuideSessionTests.guideServiceAnsweredByTheStub()

        let controllerFromTheEarlierSession = Self.controller(
            guideService: guideService,
            toolChecker: RecordedToolVersionChecker(
                toolIsInstalledByName: ["git": true, "node": true]
            )
        )
        await controllerFromTheEarlierSession.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )
        controllerFromTheEarlierSession.advanceToTheNextStep()
        controllerFromTheEarlierSession.advanceToTheNextStep()
        await controllerFromTheEarlierSession.waitUntilProgressHasBeenPersisted()

        // Both prerequisites are gone this time, so the detour has two steps to
        // walk and every navigation control is in play.
        let toolChecker = RecordedToolVersionChecker(
            toolIsInstalledByName: ["git": false, "node": false]
        )
        let controller = Self.controller(guideService: guideService, toolChecker: toolChecker)
        await controller.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )
        #expect(controller.readerIsInSetupRecovery)
        #expect(controller.setupRecoveryState?.setupStepsToWalk.map(\.id) == ["install-git", "install-node"])
        #expect(controller.canReturnToThePreviousStep == false)

        controller.advanceToTheNextSetupStep()
        #expect(controller.stepTheReaderIsLookingAt?.id == "install-node")
        #expect(controller.canReturnToThePreviousStep)
        controller.returnToThePreviousSetupStep()
        #expect(controller.stepTheReaderIsLookingAt?.id == "install-git")

        // The guide's own navigation refuses to run during the detour, so a
        // stray press can never move the reader's place.
        controller.advanceToTheNextStep()
        controller.advanceToTheNextStep()
        #expect(controller.currentStepIndex == 2)

        // Back inside the detour behaves as the detour's Back, not the guide's.
        controller.returnToThePreviousStep()
        #expect(controller.currentStepIndex == 2)

        // The stored progress is the thing that would strand somebody at step
        // one after they went away and installed Node, so it is checked at the
        // storage layer rather than in memory.
        let savedProgress = await guideService.loadProgress(
            slug: "setup-recovery",
            version: 1,
            branchKey: "macos:desktop"
        )
        #expect(savedProgress.stepIndex == 2)
        #expect(savedProgress.isCompleted == false)

        // And a fresh session with the tools back finds the same place.
        let controllerAfterInstallingEverything = Self.controller(
            guideService: guideService,
            toolChecker: RecordedToolVersionChecker(
                toolIsInstalledByName: ["git": true, "node": true]
            )
        )
        await controllerAfterInstallingEverything.openGuide(
            slug: "setup-recovery",
            requestedVersion: 1,
            branchKeyFromDeepLink: "macos:desktop",
            stepIndexFromDeepLink: nil
        )
        #expect(controllerAfterInstallingEverything.readerIsInSetupRecovery == false)
        #expect(controllerAfterInstallingEverything.currentStepIndex == 2)
    }

    // MARK: - Test fixtures

    private static func controller(
        guideService: GuideService,
        toolChecker: RecordedToolVersionChecker
    ) -> GuideSessionController {
        GuideSessionController(
            guideService: guideService,
            platformThisAppRunsOn: .macos,
            checkToolVersion: { toolName in
                await toolChecker.checkToolVersion(toolName)
            }
        )
    }
}

// MARK: - Source workspace admission and cancellation

/// A fixed-output executor keeps source-workspace tests hermetic. It records
/// every argv so the tests can prove that a rejected binding never probes or
/// executes inside an unowned staged path.
final class GuideSetupWorkspaceScriptedExecutor: GuideSourceWorkspaceCommandExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private let head: String
    private let origin: String
    private let commonGitDirectory: String
    private let linkedGitDirectory: String
    private let materializeDestination: @Sendable (URL) -> Void
    private var shouldSuspendFirstRun: Bool
    private var pendingCancellation: CheckedContinuation<GuideSourceWorkspaceCommandResult, Error>?
    private var recordedArguments: [[String]] = []
    private var recordedCancellationCount = 0

    init(
        head: String,
        origin: String,
        commonGitDirectory: String,
        linkedGitDirectory: String,
        suspendFirstRun: Bool = false,
        materializeDestination: @escaping @Sendable (URL) -> Void = { _ in }
    ) {
        self.head = head
        self.origin = origin
        self.commonGitDirectory = commonGitDirectory
        self.linkedGitDirectory = linkedGitDirectory
        self.shouldSuspendFirstRun = suspendFirstRun
        self.materializeDestination = materializeDestination
    }

    var arguments: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedArguments
    }

    var cancellationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedCancellationCount
    }

    var hasPendingRun: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pendingCancellation != nil
    }

    func run(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        deadline: TimeInterval
    ) async throws -> GuideSourceWorkspaceCommandResult {
        _ = executable
        _ = workingDirectory
        _ = deadline
        lock.lock()
        recordedArguments.append(arguments)
        let suspend = shouldSuspendFirstRun
        shouldSuspendFirstRun = false
        lock.unlock()

        if suspend {
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<GuideSourceWorkspaceCommandResult, Error>) in
                    self.lock.lock()
                    self.pendingCancellation = continuation
                    self.lock.unlock()
                }
            }, onCancel: {
                self.cancelRunningProcess()
            })
        }

        if arguments.contains("worktree"),
           let detachIndex = arguments.firstIndex(of: "--detach"),
           detachIndex + 1 < arguments.count {
            materializeDestination(URL(fileURLWithPath: arguments[detachIndex + 1], isDirectory: true))
        }

        let output: String
        if arguments.contains("--show-toplevel") {
            output = workingDirectory.path + "\n"
        } else if arguments.contains("remote") {
            output = origin + "\n"
        } else if arguments.contains("status") {
            output = ""
        } else if arguments.contains("--git-common-dir") {
            output = commonGitDirectory + "\n"
        } else if arguments.contains("--git-dir") {
            output = linkedGitDirectory + "\n"
        } else {
            output = head + "\n"
        }
        return GuideSourceWorkspaceCommandResult(
            exitCode: 0, output: output, outputWasTruncated: false
        )
    }

    func cancelRunningProcess() {
        lock.lock()
        recordedCancellationCount += 1
        let continuation = pendingCancellation
        pendingCancellation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

private final class GuideSetupWorkspaceRecordStore: GuideSourceWorkspaceRecording, GuideSourceWorkspaceRecordReading, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [UUID: GuideSourceWorkspaceRecord] = [:]

    func save(_ record: GuideSourceWorkspaceRecord) throws {
        lock.lock()
        records[record.runID] = record
        lock.unlock()
    }

    func record(for runID: UUID) -> GuideSourceWorkspaceRecord? {
        lock.lock()
        defer { lock.unlock() }
        return records[runID]
    }
}

struct GuideSourceWorkspaceServiceTests {
    private struct Fixture {
        let source: URL
        let ownedRoot: URL
        let staged: URL
        let commonGitDirectory: URL
        let linkedGitDirectory: URL
        let runID: UUID
        let commit: String
        let origin: GuideSourceWorkspaceOrigin
        let store: GuideSetupWorkspaceRecordStore

        var binding: GuideSourceWorkspaceBinding {
            let identity = GuideSourceWorkspaceIdentity(
                canonicalPath: source.path,
                origin: origin,
                head: commit,
                expectedCommitIsPresent: true,
                porcelain: "",
                commonGitDirectory: commonGitDirectory.path,
                workingTreeFingerprint: Self.emptyFingerprint
            )
            let stagedIdentity = GuideSourceWorkspaceIdentity(
                canonicalPath: staged.path,
                origin: origin,
                head: commit,
                expectedCommitIsPresent: true,
                porcelain: "",
                commonGitDirectory: commonGitDirectory.path,
                workingTreeFingerprint: Self.emptyFingerprint
            )
            return GuideSourceWorkspaceBinding(
                runID: runID,
                guideID: "fixture",
                guideRevision: 1,
                projectID: "fixture",
                original: identity,
                staged: stagedIdentity,
                originalPath: source.path,
                stagedPath: staged.path,
                expectedOrigin: origin,
                expectedCommit: commit,
                ownershipMarker: "marker",
                commonGitDirectory: commonGitDirectory.path,
                linkedWorktreeGitDirectory: linkedGitDirectory.path,
                isIsolated: true
            )
        }

        static let emptyFingerprint = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }

    private static func fixture() throws -> Fixture {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent("iris-guide-workspace-test-\(UUID().uuidString)", isDirectory: true)
        let source = base.appendingPathComponent("source", isDirectory: true)
        let ownedRoot = base.appendingPathComponent("owned", isDirectory: true)
        let runID = UUID()
        let staged = ownedRoot.appendingPathComponent(
            "fixture-\(runID.uuidString)", isDirectory: true
        )
        let commonGitDirectory = base.appendingPathComponent("common.git", isDirectory: true)
        let linkedGitDirectory = commonGitDirectory
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent(staged.lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedGitDirectory, withIntermediateDirectories: true)
        return Fixture(
            source: source,
            ownedRoot: ownedRoot,
            staged: staged,
            commonGitDirectory: commonGitDirectory,
            linkedGitDirectory: linkedGitDirectory,
            runID: runID,
            commit: String(repeating: "a", count: 40),
            origin: GuideSourceWorkspaceOrigin(host: "github.com", path: "example/project"),
            store: GuideSetupWorkspaceRecordStore()
        )
    }

    private static func service(
        fixture: Fixture,
        executor: GuideSetupWorkspaceScriptedExecutor,
        ownedRoot: URL? = nil
    ) -> GuideSourceWorkspaceService {
        let expectedRoot = (ownedRoot ?? fixture.ownedRoot).standardizedFileURL.path
        return GuideSourceWorkspaceService(
            executor: executor,
            store: fixture.store,
            destinationIsOwned: { candidate in
                candidate.standardizedFileURL.path == expectedRoot
            }
        )
    }

    private static func readyRecord(for binding: GuideSourceWorkspaceBinding) -> GuideSourceWorkspaceRecord {
        GuideSourceWorkspaceRecord(
            runID: binding.runID,
            guideID: binding.guideID,
            guideRevision: binding.guideRevision,
            projectID: binding.projectID,
            originalPath: binding.originalPath,
            stagedPath: binding.stagedPath,
            expectedOrigin: "https://\(binding.expectedOrigin.host)/\(binding.expectedOrigin.path)",
            expectedCommit: binding.expectedCommit,
            ownershipMarker: binding.ownershipMarker,
            state: .ready
        )
    }

    @Test func revalidationRejectsAnIsolatedPathOutsideTheOwnedRoot() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        let outsideRoot = fixture.source.deletingLastPathComponent()
            .appendingPathComponent("unowned", isDirectory: true)
        let outsideStage = outsideRoot.appendingPathComponent(
            fixture.staged.lastPathComponent, isDirectory: true
        )
        try FileManager.default.createDirectory(at: outsideStage, withIntermediateDirectories: true)
        var binding = fixture.binding
        binding = GuideSourceWorkspaceBinding(
            runID: binding.runID, guideID: binding.guideID, guideRevision: binding.guideRevision,
            projectID: binding.projectID, original: binding.original, staged: binding.staged,
            originalPath: binding.originalPath, stagedPath: outsideStage.path,
            expectedOrigin: binding.expectedOrigin, expectedCommit: binding.expectedCommit,
            ownershipMarker: binding.ownershipMarker, commonGitDirectory: binding.commonGitDirectory,
            linkedWorktreeGitDirectory: binding.linkedWorktreeGitDirectory, isIsolated: true
        )
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path
        )
        let service = Self.service(fixture: fixture, executor: executor)
        try fixture.store.save(Self.readyRecord(for: binding))

        let result = await service.revalidate(binding)
        guard case .failure(.destinationNotOwned) = result else {
            Issue.record("an isolated workspace outside the owned root must be rejected: \(result)")
            return
        }
        #expect(executor.arguments.allSatisfy { arguments in
            guard let index = arguments.firstIndex(of: "-C"), index + 1 < arguments.count else {
                return false
            }
            return arguments[index + 1] == fixture.source.path
        })
    }

    @Test func isolatedPreparationUsesTheOwnedWorktreeAndPersistsReadyState() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        try FileManager.default.removeItem(at: fixture.staged)
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path,
            materializeDestination: { destination in
                try? FileManager.default.createDirectory(
                    at: destination, withIntermediateDirectories: true
                )
            }
        )
        let service = Self.service(fixture: fixture, executor: executor)
        let request = GuideSourceWorkspaceRequest(
            runID: fixture.runID,
            guideID: "fixture",
            guideRevision: 1,
            projectID: "fixture",
            sourcePath: fixture.source.path,
            expectedOrigin: "https://github.com/example/project",
            expectedCommit: fixture.commit,
            ownedProjectsRoot: fixture.ownedRoot
        )
        let inspection = GuideSourceWorkspaceInspection.existingClean(fixture.binding.original)

        let binding = try await service.prepare(
            request, from: inspection, choice: .createIsolatedWorktree
        )

        #expect(binding.isIsolated)
        #expect(binding.stagedPath == fixture.staged.path)
        #expect(binding.linkedWorktreeGitDirectory == fixture.linkedGitDirectory.path)
        #expect(fixture.store.record(for: fixture.runID)?.state == .ready)
        let worktreeArguments = try #require(
            executor.arguments.first(where: { $0.contains("worktree") })
        )
        #expect(worktreeArguments.contains("worktree"))
        #expect(worktreeArguments.contains("add"))
        #expect(worktreeArguments.contains("--detach"))
        #expect(worktreeArguments.contains(fixture.staged.path))
        #expect(worktreeArguments.contains(fixture.commit))
        #expect(!executor.arguments.contains(where: { $0.contains("clone") }))
    }

    @Test func retryResumesARecordedOwnedWorktreeWithoutCreatingADuplicate() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path
        )
        let service = Self.service(fixture: fixture, executor: executor)
        let request = GuideSourceWorkspaceRequest(
            runID: fixture.runID,
            guideID: "fixture",
            guideRevision: 1,
            projectID: "fixture",
            sourcePath: fixture.source.path,
            expectedOrigin: "https://github.com/example/project",
            expectedCommit: fixture.commit,
            ownedProjectsRoot: fixture.ownedRoot
        )
        let inspection = GuideSourceWorkspaceInspection.existingClean(fixture.binding.original)
        try fixture.store.save(GuideSourceWorkspaceRecord(
            runID: fixture.runID,
            guideID: request.guideID,
            guideRevision: request.guideRevision,
            projectID: request.projectID,
            originalPath: request.sourcePath,
            stagedPath: fixture.staged.path,
            expectedOrigin: request.expectedOrigin,
            expectedCommit: request.expectedCommit,
            ownershipMarker: "cancelled-stage-marker",
            state: .cancelled
        ))

        let binding = try await service.prepare(
            request, from: inspection, choice: .createIsolatedWorktree
        )

        #expect(binding.stagedPath == fixture.staged.path)
        #expect(binding.ownershipMarker == "cancelled-stage-marker")
        #expect(fixture.store.record(for: fixture.runID)?.state == .ready)
        #expect(!executor.arguments.contains(where: { $0.contains("worktree") }),
                "a retry must validate and resume the recorded worktree instead of adding another one")
    }

    @Test func existingCheckoutBindingRecordsItsActualGitDirectory() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path
        )
        let service = Self.service(fixture: fixture, executor: executor)
        let request = GuideSourceWorkspaceRequest(
            runID: fixture.runID,
            guideID: "fixture",
            guideRevision: 1,
            projectID: "fixture",
            sourcePath: fixture.source.path,
            expectedOrigin: "https://github.com/example/project",
            expectedCommit: fixture.commit,
            ownedProjectsRoot: fixture.ownedRoot
        )
        let inspection = GuideSourceWorkspaceInspection.existingClean(fixture.binding.original)

        let binding = try await service.prepare(
            request, from: inspection, choice: .useExistingCleanCheckout
        )

        #expect(binding.isIsolated == false)
        #expect(binding.ownershipMarker == "existing-user-checkout")
        #expect(binding.linkedWorktreeGitDirectory == fixture.linkedGitDirectory.path)
        #expect(executor.arguments.contains(where: { $0.contains("--git-dir") }))
        #expect(!executor.arguments.contains(where: { $0.contains("worktree") }))
    }

    @Test func revalidationRejectsAChangedLinkedWorktreeIdentity() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path
        )
        let service = Self.service(fixture: fixture, executor: executor)
        var binding = fixture.binding
        binding = GuideSourceWorkspaceBinding(
            runID: binding.runID, guideID: binding.guideID, guideRevision: binding.guideRevision,
            projectID: binding.projectID, original: binding.original, staged: binding.staged,
            originalPath: binding.originalPath, stagedPath: binding.stagedPath,
            expectedOrigin: binding.expectedOrigin, expectedCommit: binding.expectedCommit,
            ownershipMarker: binding.ownershipMarker, commonGitDirectory: binding.commonGitDirectory,
            linkedWorktreeGitDirectory: fixture.commonGitDirectory.path, isIsolated: true
        )
        try fixture.store.save(Self.readyRecord(for: binding))

        let result = await service.revalidate(binding)
        guard case .failure(.stagedWorkspaceVerificationFailed(let reason)) = result else {
            Issue.record("a changed linked worktree admin path must be rejected: \(result)")
            return
        }
        #expect(reason == "linked worktree identity changed")
    }

    @Test func revalidationRefreshesIgnoredFileFingerprintForAStableCleanWorktree() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path
        )
        let service = Self.service(fixture: fixture, executor: executor)
        let staleStaged = GuideSourceWorkspaceIdentity(
            canonicalPath: fixture.binding.staged.canonicalPath,
            origin: fixture.binding.staged.origin,
            head: fixture.binding.staged.head,
            expectedCommitIsPresent: true,
            porcelain: "",
            commonGitDirectory: fixture.binding.staged.commonGitDirectory,
            workingTreeFingerprint: "stale-ignored-file-fingerprint"
        )
        let binding = GuideSourceWorkspaceBinding(
            runID: fixture.binding.runID, guideID: fixture.binding.guideID,
            guideRevision: fixture.binding.guideRevision, projectID: fixture.binding.projectID,
            original: fixture.binding.original, staged: staleStaged,
            originalPath: fixture.binding.originalPath, stagedPath: fixture.binding.stagedPath,
            expectedOrigin: fixture.binding.expectedOrigin, expectedCommit: fixture.binding.expectedCommit,
            ownershipMarker: fixture.binding.ownershipMarker, commonGitDirectory: fixture.binding.commonGitDirectory,
            linkedWorktreeGitDirectory: fixture.binding.linkedWorktreeGitDirectory, isIsolated: true
        )
        try fixture.store.save(Self.readyRecord(for: binding))

        let result = await service.revalidate(binding)
        guard case .success(let refreshed) = result else {
            Issue.record("a clean reviewed worktree should survive ignored-file fingerprint drift: \(result)")
            return
        }
        #expect(refreshed.staged.workingTreeFingerprint != "stale-ignored-file-fingerprint")
        #expect(refreshed.staged.head == fixture.commit)
    }

    @Test func cancellationStopsTheActiveProbeBeforeTheNextGitCommand() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path,
            suspendFirstRun: true
        )
        let service = Self.service(fixture: fixture, executor: executor)
        let request = GuideSourceWorkspaceRequest(
            runID: fixture.runID,
            guideID: "fixture",
            guideRevision: 1,
            projectID: "fixture",
            sourcePath: fixture.source.path,
            expectedOrigin: "https://github.com/example/project",
            expectedCommit: fixture.commit,
            ownedProjectsRoot: fixture.ownedRoot
        )
        let inspectionTask = Task { await service.inspect(request) }
        for _ in 0..<2_000 where !executor.hasPendingRun {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(executor.hasPendingRun)
        service.cancel(runID: fixture.runID)

        let result = await inspectionTask.value
        #expect(result == .failure(.cancelled))
        #expect(executor.cancellationCount == 1)
        #expect(executor.arguments.count == 1)
    }

    @Test func anImmediateRetryWaitsForCancelledSetupToFinishUnwinding() async throws {
        let fixture = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: fixture.source.deletingLastPathComponent()) }
        let executor = GuideSetupWorkspaceScriptedExecutor(
            head: fixture.commit,
            origin: "https://github.com/example/project",
            commonGitDirectory: fixture.commonGitDirectory.path,
            linkedGitDirectory: fixture.linkedGitDirectory.path,
            suspendFirstRun: true
        )
        let service = Self.service(fixture: fixture, executor: executor)
        let firstRequest = GuideSourceWorkspaceRequest(
            runID: fixture.runID,
            guideID: "fixture",
            guideRevision: 1,
            projectID: "fixture",
            sourcePath: fixture.source.path,
            expectedOrigin: "https://github.com/example/project",
            expectedCommit: fixture.commit,
            ownedProjectsRoot: fixture.ownedRoot
        )
        let secondRequest = GuideSourceWorkspaceRequest(
            runID: UUID(),
            guideID: firstRequest.guideID,
            guideRevision: firstRequest.guideRevision,
            projectID: firstRequest.projectID,
            sourcePath: firstRequest.sourcePath,
            expectedOrigin: firstRequest.expectedOrigin,
            expectedCommit: firstRequest.expectedCommit,
            ownedProjectsRoot: firstRequest.ownedProjectsRoot
        )

        let firstInspection = Task { await service.inspect(firstRequest) }
        for _ in 0..<2_000 where !executor.hasPendingRun {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(executor.hasPendingRun)
        service.cancel(runID: firstRequest.runID)

        let secondInspection = Task { await service.inspect(secondRequest) }
        let firstResult = await firstInspection.value
        let secondResult = await secondInspection.value
        #expect(firstResult == .failure(.cancelled))
        guard case .success(.existingClean(let identity)) = secondResult else {
            Issue.record("a retry after cancellation should run the fresh inspection: \(secondResult)")
            return
        }
        #expect(identity.canonicalPath == fixture.source.path)
        // The cancelled first probe is recorded before the fresh retry's six
        // Git probes, so the scripted executor sees seven invocations total.
        #expect(executor.arguments.count == 7)
    }
}
