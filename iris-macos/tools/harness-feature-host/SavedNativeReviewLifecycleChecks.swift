import CryptoKit
import Foundation

@testable import IrisHarnessNative

/// End-to-end lifecycle coverage for a failed native review in the disposable
/// Iris Test policy. The first run uses the real Tier-C maker/review loop and a
/// retention callback shaped like the coordinator's checked seam. The second
/// run uses the real saved-candidate rechecker and must only ask for a fresh
/// review: it must not enter maker/repair work or launch the native executable.
@main
struct SavedNativeReviewLifecycleChecks {
    private struct CheckFailure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor
    private final class Observation {
        var firstRunRequests: [HarnessModelRequest] = []
        var recheckRequests: [HarnessModelRequest] = []
        var firstRunEvents: [MaintainTierCProgressEvent] = []
        var firstRunReceipts: [EditVerificationReceipt] = []
        var retentionRequest: MaintainFailedReviewRetentionRequest?
        var retentionCallbackCount = 0
        var retentionSucceeded = false
        var retentionFailure: String?
    }

    private struct Fixture {
        let projectRoot: URL
        let clone: URL
        let application: URL
        let artifact: URL
        let scratch: URL
        let registryURL: URL
        let originalRegistryData: Data?
        let originalRegistryExisted: Bool
        let runner: MaintainShellRunner
        let source: URL
        let nativeTest: URL
        let nativeExecutable: URL
        let nativeMarker: URL
        let project: IrisTestProjectRegistry.Project
        let brief: HarnessTaskBrief
        let briefJSON: String
        let verificationCommands: VerificationCommands
        let recipe: RepoRecipe
        let baselineSource: String
        let baselineHead: String
    }

    @MainActor
    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard IrisTestEnvironment.isEnabled else {
            print("SKIP saved native review lifecycle checks: requires the Iris Test bundle")
            return
        }
        guard ProcessInfo.processInfo.environment["IRIS_UNADMITTED_FIXTURE_ROOT"] != nil else {
            print("SKIP saved native review lifecycle checks: set IRIS_UNADMITTED_FIXTURE_ROOT")
            return
        }
        do {
            try await runChecks()
            print("SAVED NATIVE REVIEW LIFECYCLE CHECKS PASS: denial -> held identity -> review-only recheck")
        } catch {
            print("SAVED NATIVE REVIEW LIFECYCLE CHECKS FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor
    private static func runChecks() async throws {
        _ = try isolatedFixtureRoot()
        guard MaintainSandbox.isAvailable else {
            throw CheckFailure(message: "sandbox-exec is unavailable")
        }
        guard case .test = MaintainSandbox.runtimeProcessPolicy() else {
            throw CheckFailure(message: "the IRIS_TEST_BUILD Test process policy was unavailable")
        }

        let fixture = try await makeFixture()
        defer { cleanup(fixture) }
        let observation = Observation()

        // A four-call run is intentional: intake + one edit + one review leave
        // the native two-call review reserve intact, so the failed review goes
        // directly to the checked retention seam instead of starting repair.
        let firstSession = try HarnessModelSession(
            implementationArm: .astraLow,
            settings: .init(maxCalls: 4, maxInputBytes: 1_000_000),
            maximumDurationNanoseconds: 60_000_000_000
        ) { request in
            observation.firstRunRequests.append(request)
            switch request.phase {
            case .intake:
                return HarnessModelReply(text: fixture.briefJSON)
            case .edit:
                return HarnessModelReply(text: """
                Implement the requested source change.
                ```write src/feature.js
                export const featureValue = 2;
                ```
                """)
            case .review:
                return HarnessModelReply(text: """
                ISSUE: the candidate does not establish the requested behavior.
                VERDICT: DISQUALIFYING
                """)
            case .repair, .recheck:
                throw CheckFailure(message: "first run entered unexpected model phase \(request.phase)")
            }
        }
        let firstWorkflow = HarnessFeatureWorkflow(modelSession: firstSession)
        _ = try await firstWorkflow.plan(
            request: fixture.brief.userRequest,
            repositorySummary: "src/feature.js and a separately declared native test in a disposable fixture"
        )
        let firstPlanningCount = observation.firstRunRequests.count
        let firstProvider = HarnessWorkflowMaintainProvider(workflow: firstWorkflow)
        let firstResult = await MaintainTierCFixer(provider: firstProvider).attemptOnDemandEdit(
            clonePath: fixture.clone.path,
            appSlug: fixture.project.slug,
            appStack: .electron,
            changeId: "saved-native-review-lifecycle",
            request: fixture.brief.userRequest,
            kind: .feature,
            progressHandler: { event in
                observation.firstRunEvents.append(event)
                if case .verificationCompleted(let receipt) = event {
                    observation.firstRunReceipts.append(receipt)
                }
            },
            cancellationCheck: { false },
            verificationCommandsOverride: fixture.verificationCommands,
            runsAnIndependentReview: true,
            failedReviewRetention: { request in
                await retainCandidate(
                    request, fixture: fixture, observation: observation, workflow: firstWorkflow
                )
            }
        )

        guard case .couldNotComplete(let firstReason) = firstResult,
              firstReason.contains("native-review-required") else {
            throw CheckFailure(message: "native denial did not return a held-review failure: \(firstResult)")
        }
        let firstPostPlanningPhases = observation.firstRunRequests
            .dropFirst(firstPlanningCount).map(\.phase)
        try require(firstPostPlanningPhases == [.edit, .review],
                    "first run phases were not exactly maker then one native review: \(firstPostPlanningPhases)")
        try require(!firstPostPlanningPhases.contains(.repair),
                    "first run entered repair despite the reserved review boundary")
        try require(observation.firstRunRequests.filter { $0.phase == .review }.count == 1,
                    "first run did not perform exactly one denying native admission review")
        try require(observation.retentionCallbackCount == 1 && observation.retentionSucceeded,
                    "failed-review retention was not called exactly once successfully"
                        + " (calls=\(observation.retentionCallbackCount), success=\(observation.retentionSucceeded)"
                        + (observation.retentionFailure.map { ", failure=\($0)" } ?? "")
                        + ", receipts=\(observation.firstRunReceipts), phases=\(firstPostPlanningPhases)"
                        + ", events=\(observation.firstRunEvents))")
        try require(observation.retentionRequest?.blockedStage == "native-review-required",
                    "retention did not receive the native review stage")
        try require(observation.retentionRequest?.changedPaths == ["src/feature.js"],
                    "retention did not receive the exact changed path set")
        try require(observation.retentionRequest?.modelOwnedPaths == ["src/feature.js"],
                    "retention did not receive the exact model-owned path set")

        let heldRecord = try requireHeldRecord(fixture: fixture)
        let heldCandidate = try requireHeldCandidate(heldRecord, fixture: fixture)
        let heldSnapshot = try await snapshot(fixture)
        try require(heldSnapshot.head == fixture.baselineHead,
                    "holding the failed review moved HEAD")
        try require(heldSnapshot.status == "M  src/feature.js",
                    "held candidate was not staged as the exact source path: \(heldSnapshot.status)")
        try require(heldSnapshot.source != fixture.baselineSource,
                    "failed review retention did not preserve the source edit")
        try require(FileManager.default.fileExists(atPath: fixture.nativeMarker.path) == false,
                    "native executable was launched before code admission")
        try require(heldCandidate.project == fixture.project,
                    "persisted candidate did not retain the complete Test project snapshot")
        try require(heldCandidate.baselineCommit == fixture.baselineHead,
                    "persisted candidate baseline did not match the pre-edit HEAD")
        try require(heldCandidate.branchName == "main",
                    "persisted candidate did not retain the source branch")
        try require(heldCandidate.changedPaths == ["src/feature.js"],
                    "persisted candidate path identity was not exact")
        let heldCandidateStillMatches = await heldCandidate.stillMatches(
            record: heldRecord, project: fixture.project, runner: fixture.runner
        )
        try require(heldCandidateStillMatches,
                    "persisted candidate did not round-trip through the exact identity check")

        // The launch/quit recovery path is fail-closed for a review-held
        // candidate. It must leave both source and identity in place until the
        // reader explicitly chooses a recheck.
        let recovery = OnDemandEditInterruptedRunRecovery.recoverNow()
        guard case .leftAlone(_, let recoveryReason, _) = recovery else {
            throw CheckFailure(message: "review-held recovery unexpectedly changed state: \(recovery)")
        }
        try require(recoveryReason.contains("awaiting review"),
                    "review-held recovery reason was not explicit: \(recoveryReason)")
        let recoverySnapshot = try await snapshot(fixture)
        try require(recoverySnapshot == heldSnapshot,
                    "review-held recovery changed the candidate before explicit recheck")
        try require(OnDemandEditInterruptedRunRecovery.recordOnDisk() == heldRecord,
                    "review-held recovery removed the persisted candidate")

        // A new workflow is deliberate: the saved candidate must be reviewed
        // in fresh context. This path has no maker callback at all; phase and
        // native marker assertions make that contract observable.
        let recheckSession = try HarnessModelSession(
            implementationArm: .astraLow,
            settings: .init(maxCalls: 4, maxInputBytes: 1_000_000),
            maximumDurationNanoseconds: 60_000_000_000
        ) { request in
            observation.recheckRequests.append(request)
            switch request.phase {
            case .intake:
                throw CheckFailure(message: "saved recheck unexpectedly entered intake planning")
            case .review:
                return HarnessModelReply(text: """
                ISSUE: the saved candidate still does not establish the requested behavior.
                VERDICT: DISQUALIFYING
                """)
            case .edit, .repair, .recheck:
                throw CheckFailure(message: "saved recheck entered maker phase \(request.phase)")
            }
        }
        let recheckWorkflow = HarnessFeatureWorkflow(modelSession: recheckSession)
        guard let savedContract = heldRecord.savedFeatureContract else {
            throw CheckFailure(message: "retained candidate did not persist its feature contract")
        }
        let originalContractContext = try firstWorkflow.implementationContext()
        try recheckWorkflow.restoreSavedContract(savedContract)
        let restoredContractContext = try recheckWorkflow.implementationContext()
        try require(
            restoredContractContext == originalContractContext,
            "restored contract changed the brief, decisions or acceptance criteria"
        )
        let recheckPlanningCount = observation.recheckRequests.count
        let recheckProvider = HarnessWorkflowMaintainProvider(workflow: recheckWorkflow)
        let recheckResult = await MaintainSavedChangeRechecker.run(
            runner: fixture.runner,
            clonePath: fixture.clone.path,
            appSlug: fixture.project.slug,
            appStack: .electron,
            changeId: "saved-native-review-lifecycle-recheck",
            request: fixture.brief.userRequest,
            provider: recheckProvider,
            derivedRecipe: fixture.recipe,
            isCurrent: {
                guard let current = OnDemandEditInterruptedRunRecovery.recordOnDisk(),
                      current == heldRecord,
                      let candidate = current.pendingCandidate,
                      let project = IrisTestProjectRegistry.project(slug: fixture.project.slug)
                else { return false }
                return await candidate.stillMatches(
                    record: current, project: project, runner: fixture.runner
                )
            },
            progress: nil,
            cancellation: { false }
        )
        guard case .couldNotComplete(let recheckReason) = recheckResult,
              recheckReason.contains("not cleared") else {
            throw CheckFailure(message: "saved recheck did not preserve a denying review result: \(recheckResult)")
        }
        let recheckPhases = observation.recheckRequests
            .dropFirst(recheckPlanningCount).map(\.phase)
        try require(recheckPlanningCount == 0,
                    "saved recheck made an unexpected planning call")
        try require(recheckPhases == [.review],
                    "saved recheck phases were not review-only: \(recheckPhases)")
        try require(!recheckPhases.contains(.edit) && !recheckPhases.contains(.repair),
                    "saved recheck entered maker/repair work")
        try require(FileManager.default.fileExists(atPath: fixture.nativeMarker.path) == false,
                    "native executable launched before saved candidate review admission")
        let recheckSnapshot = try await snapshot(fixture)
        try require(recheckSnapshot == heldSnapshot,
                    "denying saved recheck changed the held candidate")
        try require(OnDemandEditInterruptedRunRecovery.recordOnDisk() == heldRecord,
                    "denying saved recheck removed or changed the held identity")
        try require(savedContract.isBound(to: heldCandidate, request: fixture.brief.userRequest),
                    "saved contract did not remain bound to the held candidate")
        let tamperedContract = try HarnessSavedFeatureContract(
            state: try savedContract.restoredState(),
            candidateBindingDigest: String(repeating: "0", count: 64)
        )
        try require(!tamperedContract.isBound(to: heldCandidate, request: fixture.brief.userRequest),
                    "tampered contract binding was accepted")
        let malformed = try? JSONDecoder().decode(
            HarnessSavedFeatureContract.self, from: Data("{}".utf8)
        )
        try require(malformed == nil, "malformed saved contract was accepted")
        let oversizedBrief = try HarnessTaskBrief(
            userRequest: fixture.brief.userRequest,
            desiredOutcome: String(repeating: "x", count: 8_000),
            acceptanceCriteria: (0..<4).map {
                HarnessAcceptanceCriterion(
                    id: "oversized-\($0)", statement: String(repeating: "y", count: 7_000)
                )
            },
            targetedQuestions: fixture.brief.targetedQuestions,
            milestones: fixture.brief.milestones,
            modelAssumptions: fixture.brief.modelAssumptions
        )
        let oversizedState = try HarnessTaskState(
            brief: oversizedBrief, activeRevisionID: savedContract.activeRevisionID,
            userDecisions: savedContract.userDecisions,
            resolvedAcceptanceCriterionIDs: savedContract.resolvedAcceptanceCriterionIDs
        )
        let oversizedContract = try? HarnessSavedFeatureContract(
            state: oversizedState, candidateBindingDigest: heldCandidate.bindingDigest
        )
        try require(oversizedContract == nil, "oversized saved contract was accepted")
        let legacyRecord = OnDemandEditInFlightRecord(
            appSlug: heldRecord.appSlug, clonePath: heldRecord.clonePath,
            baseCommit: heldRecord.baseCommit, pathsIrisEdited: heldRecord.pathsIrisEdited,
            startedAt: heldRecord.startedAt, runLogPath: heldRecord.runLogPath,
            whatIrisWasWaitingFor: heldRecord.whatIrisWasWaitingFor,
            requiresReviewBeforeRecovery: true, pendingCandidate: heldRecord.pendingCandidate,
            recheckRequest: heldRecord.recheckRequest
        )
        try require(legacyRecord.savedFeatureContract == nil,
                    "legacy record unexpectedly acquired a contract")
        print("PASS native denial retained exact staged candidate; recheck reviewed once without maker/native execution")

        OnDemandEditInterruptedRunRecovery.forget()
    }

    @MainActor
    private static func retainCandidate(
        _ request: MaintainFailedReviewRetentionRequest,
        fixture: Fixture,
        observation: Observation,
        workflow: HarnessFeatureWorkflow
    ) async -> Bool {
        func fail(_ reason: String) -> Bool {
            observation.retentionFailure = reason
            return false
        }
        observation.retentionCallbackCount += 1
        observation.retentionRequest = request
        guard request.kind == .feature,
              request.blockedStage == "native-review-required",
              request.receipt.nativeTestsRequired,
              request.receipt.failureStage == request.blockedStage,
              request.appSlug == fixture.project.slug,
              request.clonePath == fixture.clone.path,
              request.changedPaths == request.modelOwnedPaths,
              request.changedPaths == ["src/feature.js"],
              let project = IrisTestProjectRegistry.project(slug: request.appSlug),
              project == fixture.project else { return fail("retention request or registry gate") }

        guard let head = try? await output(fixture.runner, "git rev-parse --verify HEAD^{commit}"),
              head == fixture.baselineHead,
              let branch = try? await output(fixture.runner, "git symbolic-ref --short HEAD"),
              branch == "main" else { return fail("HEAD/ref gate") }
        let record = OnDemandEditInFlightRecord(
            appSlug: request.appSlug,
            clonePath: request.clonePath,
            baseCommit: fixture.baselineHead,
            pathsIrisEdited: request.modelOwnedPaths,
            startedAt: Date(),
            runLogPath: nil,
            whatIrisWasWaitingFor: "Review incomplete edit before retrying",
            requiresReviewBeforeRecovery: true,
            pendingCandidate: nil,
            recheckRequest: fixture.brief.userRequest
        )
        OnDemandEditInterruptedRunRecovery.remember(record)
        guard OnDemandEditInterruptedRunRecovery.recordOnDisk() == record else {
            return fail("initial recovery record did not round-trip: \(String(describing: OnDemandEditInterruptedRunRecovery.recordOnDisk()))")
        }

        let add = try? await fixture.runner.run(
            "git -c core.hooksPath=/dev/null -c core.fsmonitor=false add -- src/feature.js",
            deadline: 30
        )
        guard add?.succeeded == true else { return fail("exact git add failed") }
        guard let candidate = try? await PendingEditCandidateIdentity.capture(
            record: record, project: project, runner: fixture.runner
        ) else { return fail("candidate identity capture refused") }
        guard let contract = try? workflow.savedFeatureContract(
            candidateBindingDigest: candidate.bindingDigest
        ) else { return fail("saved feature contract could not be created") }
        var held = record
        held.pathsIrisEdited = candidate.changedPaths
        held.pendingCandidate = candidate
        held.savedFeatureContract = contract
        OnDemandEditInterruptedRunRecovery.remember(held)
        guard OnDemandEditInterruptedRunRecovery.recordOnDisk() == held,
              await candidate.stillMatches(record: held, project: project, runner: fixture.runner)
        else { return fail("held candidate did not persist or still match") }
        observation.retentionSucceeded = true
        return true
    }

    private struct Snapshot: Equatable {
        let head: String
        let status: String
        let source: String
    }

    @MainActor
    private static func snapshot(_ fixture: Fixture) async throws -> Snapshot {
        Snapshot(
            head: try await output(fixture.runner, "git rev-parse --verify HEAD^{commit}"),
            status: try await output(fixture.runner, "git status --porcelain=v1 --untracked-files=all"),
            source: String(decoding: try Data(contentsOf: fixture.source), as: UTF8.self)
        )
    }

    @MainActor
    private static func requireHeldRecord(fixture: Fixture) throws -> OnDemandEditInFlightRecord {
        guard let record = OnDemandEditInterruptedRunRecovery.recordOnDisk(),
              record.appSlug == fixture.project.slug,
              record.clonePath == fixture.clone.path,
              record.baseCommit == fixture.baselineHead,
              record.requiresReviewBeforeRecovery == true,
              record.recheckRequest == fixture.brief.userRequest else {
            throw CheckFailure(message: "failed review did not persist the expected review-held record")
        }
        return record
    }

    @MainActor
    private static func requireHeldCandidate(
        _ record: OnDemandEditInFlightRecord,
        fixture: Fixture
    ) throws -> PendingEditCandidateIdentity {
        guard let candidate = record.pendingCandidate else {
            throw CheckFailure(message: "failed review did not persist a pending candidate identity")
        }
        try require(candidate.project == fixture.project, "pending candidate project snapshot was not exact")
        try require(candidate.baselineCommit == fixture.baselineHead, "pending candidate baseline was not exact")
        try require(candidate.changedPaths == ["src/feature.js"], "pending candidate paths were not exact")
        try require(!candidate.stagedTree.isEmpty, "pending candidate staged tree was empty")
        return candidate
    }

    @MainActor
    private static func makeFixture() async throws -> Fixture {
        let files = FileManager.default
        let support = IrisTestEnvironment.applicationSupportDirectory
        let projectRoot = support.appendingPathComponent(
            "Projects/iris-saved-native-review-\(UUID().uuidString)", isDirectory: true
        )
        let clone = projectRoot.appendingPathComponent("clone", isDirectory: true)
        let application = support.appendingPathComponent(
            "Projects/Apps/Saved Native Review \(UUID().uuidString).app", isDirectory: true
        )
        let artifact = clone.appendingPathComponent(
            "build/Saved Native Review.app", isDirectory: true
        )
        let scratch = IrisTestEnvironment.commandScratchDirectory.appendingPathComponent(
            "iris-saved-native-review-\(UUID().uuidString)", isDirectory: true
        )
        let registryURL = support.appendingPathComponent("test-projects.json")
        let originalRegistryExisted = files.fileExists(atPath: registryURL.path)
        let originalRegistryData = try? Data(contentsOf: registryURL)
        let source = clone.appendingPathComponent("src/feature.js")
        let nativeTest = clone.appendingPathComponent("tests/native-check.test.js")
        let nativeExecutable = clone.appendingPathComponent("tools/native-check.sh")
        let nativeMarker = clone.appendingPathComponent("native-invoked.marker")
        let gitignore = clone.appendingPathComponent(".gitignore")
        let bundleIdentifier = "com.publikhq.iris.test.savednativereview."
            + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let baselineSource = "export const featureValue = 1;\n"
        let nativeExecutableContents = "#!/bin/sh\nprintf invoked > native-invoked.marker\n"

        try files.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createDirectory(at: nativeTest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createDirectory(at: nativeExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.createDirectory(at: scratch, withIntermediateDirectories: true)
        try files.createDirectory(at: application, withIntermediateDirectories: true)
        try files.createDirectory(at: artifact, withIntermediateDirectories: true)
        try Data(baselineSource.utf8).write(to: source)
        try Data("// pinned native assertion fixture\n".utf8).write(to: nativeTest)
        try Data(nativeExecutableContents.utf8).write(to: nativeExecutable)
        // The registered build artifact is intentionally outside the source
        // candidate. Keep its Info.plist ignored so the retention path sees
        // only the model-owned source diff, as a real build workspace would.
        try Data("build/\n".utf8).write(to: gitignore)
        try files.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: nativeExecutable.path)
        try writeBundleInfo(application, bundleIdentifier: bundleIdentifier, name: "Saved Native Review")
        try writeBundleInfo(artifact, bundleIdentifier: bundleIdentifier, name: "Saved Native Review")

        let executablePath = MaintainSandbox.canonicalPath(nativeExecutable.path)
        let nativePlan = IrisTestNativeVerification.Plan(
            executablePath: executablePath,
            arguments: [],
            protectedFileSHA256: [
                MaintainSandbox.canonicalPath(nativeTest.path): try digest(nativeTest.path),
            ],
            executableSHA256: try digest(executablePath),
            deadlineSeconds: 5
        )
        let testCommand = "test -s src/feature.js"
        let declaration = IrisTestVerificationDeclaration(
            originalTestCommand: testCommand,
            confinedTestCommand: testCommand,
            native: nativePlan
        )
        let placeholder = IrisTestProjectRegistry.Project(
            slug: "saved-native-review",
            name: "Saved Native Review",
            clonePath: MaintainSandbox.canonicalPath(clone.path),
            applicationPath: MaintainSandbox.canonicalPath(application.path),
            buildArtifactPath: MaintainSandbox.canonicalPath(artifact.path),
            bundleIdentifier: bundleIdentifier,
            pinnedCommit: String(repeating: "a", count: 40),
            nativeVerification: declaration
        )
        try writeRegistry([placeholder], to: registryURL)
        let runner = try MaintainShellRunner(repoRootPath: placeholder.clonePath)
        let initialized = try await runner.run(
            "git init -q -b main && git add -- src/feature.js tests/native-check.test.js tools/native-check.sh .gitignore && "
                + "git -c user.name=Fixture -c user.email=fixture@example.invalid "
                + "commit --no-gpg-sign -qm baseline",
            deadline: 30
        )
        try require(initialized.succeeded, "could not initialize the saved native review fixture")
        let baselineHead = try await output(runner, "git rev-parse --verify HEAD^{commit}")
        let project = IrisTestProjectRegistry.Project(
            slug: placeholder.slug,
            name: placeholder.name,
            clonePath: placeholder.clonePath,
            applicationPath: placeholder.applicationPath,
            buildArtifactPath: placeholder.buildArtifactPath,
            bundleIdentifier: placeholder.bundleIdentifier,
            pinnedCommit: baselineHead,
            nativeVerification: declaration
        )
        try writeRegistry([project], to: registryURL)
        let brief = try HarnessTaskBrief(
            userRequest: "Change the fixture value and prove the behavior with a focused test.",
            desiredOutcome: "The fixture exports the requested value",
            acceptanceCriteria: [
                .init(id: "value", statement: "The source exports featureValue equal to 2")
            ]
        )
        let verificationCommands = VerificationCommands(
            buildCommand: "test -s src/feature.js",
            testCommand: testCommand,
            commandSubdirectory: nil
        )
        let recipe = RepoRecipe(
            build: RepoRecipeCommand(commandLine: verificationCommands.buildCommand!),
            test: RepoRecipeCommand(commandLine: verificationCommands.testCommand!),
            ecosystemIdentifier: "fixture",
            runtimeShape: .pureLocalApp,
            confidenceByField: [.build: 1.0, .test: 1.0],
            provenanceByField: [.build: .explicitProjectConfig, .test: .explicitProjectConfig]
        )
        return Fixture(
            projectRoot: projectRoot,
            clone: clone,
            application: application,
            artifact: artifact,
            scratch: scratch,
            registryURL: registryURL,
            originalRegistryData: originalRegistryData,
            originalRegistryExisted: originalRegistryExisted,
            runner: runner,
            source: source,
            nativeTest: nativeTest,
            nativeExecutable: nativeExecutable,
            nativeMarker: nativeMarker,
            project: project,
            brief: brief,
            briefJSON: String(decoding: try JSONEncoder().encode(brief), as: UTF8.self),
            verificationCommands: verificationCommands,
            recipe: recipe,
            baselineSource: baselineSource,
            baselineHead: baselineHead
        )
    }

    @MainActor
    private static func cleanup(_ fixture: Fixture) {
        OnDemandEditInterruptedRunRecovery.forget()
        let files = FileManager.default
        if fixture.originalRegistryExisted, let data = fixture.originalRegistryData {
            try? data.write(to: fixture.registryURL, options: .atomic)
        } else {
            try? files.removeItem(at: fixture.registryURL)
        }
        try? files.removeItem(at: fixture.projectRoot)
        try? files.removeItem(at: fixture.application)
        try? files.removeItem(at: fixture.scratch)
    }

    @MainActor
    private static func isolatedFixtureRoot() throws -> URL {
        guard let rawRoot = ProcessInfo.processInfo.environment["IRIS_UNADMITTED_FIXTURE_ROOT"] else {
            throw CheckFailure(message: "IRIS_UNADMITTED_FIXTURE_ROOT was not supplied")
        }
        let root = URL(fileURLWithPath: rawRoot, isDirectory: true).standardizedFileURL
        guard rawRoot == root.path,
              root.path.hasPrefix("/Users/Shared/iris-unadmitted-env-"),
              root.deletingLastPathComponent().path == "/Users/Shared",
              MaintainSandbox.canonicalExistingDirectory(root.path) == root.path else {
            throw CheckFailure(message: "fixture root must be canonical and directly below /Users/Shared")
        }
        let support = IrisTestEnvironment.applicationSupportDirectory.standardizedFileURL
        let scratch = IrisTestEnvironment.commandScratchDirectory.standardizedFileURL
        guard support.path.hasPrefix(root.path + "/"),
              scratch.path.hasPrefix(root.path + "/") else {
            throw CheckFailure(message: "generated Test roots escaped the disposable fixture root")
        }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let registryURL = support.appendingPathComponent("test-projects.json")
        guard !FileManager.default.fileExists(atPath: registryURL.path) else {
            throw CheckFailure(message: "refusing to replace an existing disposable Test registry")
        }
        return root
    }

    @MainActor
    private static func output(_ runner: MaintainShellRunner, _ command: String) async throws -> String {
        let result = try await runner.run(command, deadline: 30)
        try require(result.succeeded && result.bytesDroppedBeforeTail == 0,
                    "fixture command failed (\(result.exitCode)): \(result.outputTail)")
        return result.outputTail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writeBundleInfo(_ bundle: URL, bundleIdentifier: String, name: String) throws {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": name,
                "CFBundleExecutable": name.replacingOccurrences(of: " ", with: ""),
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "1",
            ],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private static func writeRegistry(
        _ projects: [IrisTestProjectRegistry.Project],
        to url: URL
    ) throws {
        try JSONEncoder().encode(projects).write(to: url, options: .atomic)
    }

    private static func digest(_ path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }
}
