import Foundation
@testable import IrisHarnessNative

private enum RepairWindowCheckError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private enum RepairWindowScenario {
    case rejectedThenRepaired
    case buildFailureBeforeReview
    case cleanFirstDraft
}

private struct RepairWindowObservation {
    let result: MaintainOnDemandEditResult
    let requests: [HarnessModelRequest]
    let events: [MaintainTierCProgressEvent]
    let reviewRemainingCallCapacity: [UInt64]
    let admittedCallCount: UInt64
}

private func repairWindowRequire(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    guard condition() else {
        throw RepairWindowCheckError.failed(message)
    }
}

/// Exercises the bounded review and correction window with a disposable,
/// remote-free fixture. This is a headless harness check, not native app
/// acceptance.
@MainActor
func runRepairWindowChecks() async throws {
    try await runRepairWindowBudgetChecks()
    try await runReplayableEditReserveChecks()

    let repaired = try await runRepairWindowScenario(.rejectedThenRepaired)
    let repairRequests = repaired.requests.filter { $0.phase == .repair }
    let reviewRequests = repaired.requests.filter { $0.phase == .review }
    try repairWindowRequire(repaired.admittedCallCount == 18,
                            "the repair-window fixture changed the declared 18-call cap")
    try repairWindowRequire(repairRequests.count == 3,
                            "the rejected review did not get exactly its three-call repair window")
    try repairWindowRequire(reviewRequests.count == 2,
                            "the first and final independent reviews did not both run")
    try repairWindowRequire(repaired.reviewRemainingCallCapacity.count == 2,
                            "the fixture did not record both review admissions")
    try repairWindowRequire(repaired.reviewRemainingCallCapacity[0] > 0,
                            "the first review was admitted only after the call budget was exhausted")

    var verificationFailureStages: [String?] = []
    var raisedReviewIssue = false
    for event in repaired.events {
        switch event {
        case .verificationCompleted(let receipt):
            verificationFailureStages.append(receipt.failureStage)
        case .adversarialReviewRaisedIssues(let issues):
            raisedReviewIssue = raisedReviewIssue || issues.contains {
                $0.localizedCaseInsensitiveContains("changed test")
            }
        default:
            break
        }
    }
    try repairWindowRequire(verificationFailureStages.count == 2,
                            "the repair fixture did not report both verification passes")
    try repairWindowRequire(verificationFailureStages[0] == "behavior-coverage",
                            "the rejected review was treated as a successful verification")
    try repairWindowRequire(verificationFailureStages[1] == nil,
                            "the final clean review still carried the failed review status")
    try repairWindowRequire(raisedReviewIssue,
                            "the first independent review did not preserve its named defect")
    guard case .appliedAndRebuilt(_, _, _, let suitePassed, _) = repaired.result,
          suitePassed == true else {
        throw RepairWindowCheckError.failed(
            "the final clean review did not produce the ordinary applied result"
        )
    }
    print("PASS repair window: first review rejected with capacity remaining, three-call repair ran, final review cleared, cap stayed at 18")

    let clean = try await runRepairWindowScenario(.cleanFirstDraft)
    let cleanRepairs = clean.requests.filter { $0.phase == .repair }
    let cleanReviews = clean.requests.filter { $0.phase == .review }
    try repairWindowRequire(cleanRepairs.isEmpty,
                            "a clean first draft spent an unnecessary repair call")
    try repairWindowRequire(cleanReviews.count == 1,
                            "a clean first draft requested an unnecessary second review")
    try repairWindowRequire(clean.admittedCallCount == 4,
                            "the clean first draft used an unexpected extra model call")
    guard case .appliedAndRebuilt(_, _, _, let cleanSuitePassed, _) = clean.result,
          cleanSuitePassed == true else {
        throw RepairWindowCheckError.failed(
            "the clean first draft did not reach the ordinary applied result"
        )
    }
    print("PASS repair window: clean first draft used no repair call")

    let buildRepair = try await runRepairWindowScenario(.buildFailureBeforeReview)
    try repairWindowRequire(buildRepair.requests.filter { $0.phase == .repair }.count == 3
                                && buildRepair.requests.filter { $0.phase == .review }.count == 1,
                            "build failure before review did not release correction capacity")
    try repairWindowRequire(buildRepair.admittedCallCount == 17,
                            "build-failure correction changed the bounded call sequence")
    guard case .appliedAndRebuilt(_, _, _, let buildRepairSuitePassed, _) = buildRepair.result,
          buildRepairSuitePassed == true else {
        throw RepairWindowCheckError.failed("build-failure correction did not reach final checks")
    }
    try repairWindowRequire(buildRepair.events.contains {
        if case .verificationCompleted(let receipt) = $0 { return receipt.failureStage == "build" }
        return false
    }, "the fixture did not actually fail its build before review")
    print("PASS repair window: build failure before first review released correction capacity without dropping final review")
}

/// The opening runtime image is a one-shot observation. Its bytes remain in
/// the ledger's actual submitted/accounted total, but after a successful
/// response they must not inflate the next correction's prospective reserve.
/// This uses the real workflow provider and model session with an inert
/// transport, so no model or native app is involved.
@MainActor
private func runReplayableEditReserveChecks() async throws {
    let imageBytes = 672_977
    let image = Data(repeating: 0xA5, count: imageBytes)
    let brief = try HarnessTaskBrief(
        userRequest: "Export the selected images",
        desiredOutcome: "The export queue preserves the selected images",
        acceptanceCriteria: [.init(id: "queue", statement: "The selected images remain queued")]
    )
    let briefJSON = String(decoding: try JSONEncoder().encode(brief), as: UTF8.self)

    func makeSession(transportFails: Bool = false) async throws ->
        (HarnessModelSession, HarnessWorkflowMaintainProvider) {
        let session = try HarnessModelSession(
            implementationArm: .astraLow,
            settings: .init(maxCalls: 18, maxInputBytes: 1_800_000),
            maximumDurationNanoseconds: 60_000_000_000,
            // These are the recorded production serializer sizes for the
            // counterfactual. Component counts below still come from the
            // real request, including the exact raw image byte count.
            serializedInputByteCounter: { request in
                if request.phase == .intake { return 13_152 }
                if request.conversation.contains(where: { $0.text == "IMAGE_EDIT" }) {
                    return 716_522
                }
                if request.conversation.contains(where: { $0.text == "LARGE_TEXT_EDIT" }) {
                    return 200_000
                }
                if request.conversation.contains(where: { $0.text == "HUGE_TEXT_EDIT" }) {
                    return 150_000
                }
                return 43_545
            }
        ) { request in
            if request.phase == .intake {
                return HarnessModelReply(text: briefJSON)
            }
            if transportFails && request.phase == .edit {
                throw NSError(domain: "inert-transport", code: 1)
            }
            return HarnessModelReply(text: "OK")
        }
        let workflow = HarnessFeatureWorkflow(modelSession: session)
        _ = try await workflow.plan(request: brief.userRequest, repositorySummary: "inert fixture")
        let provider = HarnessWorkflowMaintainProvider(workflow: workflow)
        provider.configureReviewStages(nativeChecksRequired: true)
        return (session, provider)
    }

    let (session, provider) = try await makeSession()

    _ = try await provider.respond(
        systemPrompt: "inert image edit",
        conversation: [MaintainChatTurn(role: "user", text: "IMAGE_EDIT", attachedImagePNGData: image)],
        maximumOutputTokens: 1
    )
    try repairWindowRequire(
        session.lastAdmittedInputCounts?.rawImageBytes == UInt64(imageBytes)
            && session.lastAdmittedInputCounts?.imageCount == 1,
        "the admitted image edit did not retain exact component counts without telemetry"
    )
    try repairWindowRequire(
        session.ledger.accountedInputBytes == 729_674,
        "the intake plus image edit did not retain the full 729674 ledger bytes"
    )
    try repairWindowRequire(
        provider.shouldYieldEditingToVerification,
        "the full image-bearing edit estimate did not protect both native review stages"
    )

    // This is the explicit notification the fixer emits after it has cleared
    // the opening image from the replay conversation.
    provider.openingRuntimeImageWasRetired(rawImageBytes: UInt64(imageBytes - 1))
    try repairWindowRequire(
        provider.shouldYieldEditingToVerification,
        "a mismatched image-retirement signal released the reserve"
    )
    provider.openingRuntimeImageWasRetired(rawImageBytes: UInt64(imageBytes))
    try repairWindowRequire(
        session.ledger.accountedInputBytes == 729_674,
        "retiring the opening image changed actual ledger accounting"
    )
    try repairWindowRequire(
        !provider.shouldYieldEditingToVerification,
        "the exact retired image bytes did not release the prospective reserve"
    )
    provider.openingRuntimeImageWasRetired(rawImageBytes: UInt64(imageBytes))
    try repairWindowRequire(
        !provider.shouldYieldEditingToVerification,
        "a repeated image-retirement signal changed the reserve a second time"
    )

    _ = try await provider.respond(
        systemPrompt: "inert text edit",
        conversation: [MaintainChatTurn(role: "user", text: "TEXT_EDIT")],
        maximumOutputTokens: 1
    )
    _ = try await provider.respond(
        systemPrompt: "inert larger text edit",
        conversation: [MaintainChatTurn(role: "user", text: "LARGE_TEXT_EDIT")],
        maximumOutputTokens: 1
    )
    try repairWindowRequire(
        session.ledger.accountedInputBytes == 973_219,
        "the admitted 43545 and larger 200000 text edits were not fully accounted"
    )
    var staleEstimateWouldAdmit = false
    do {
        _ = try await provider.respond(
            systemPrompt: "inert huge text edit",
            conversation: [MaintainChatTurn(role: "user", text: "HUGE_TEXT_EDIT")],
            maximumOutputTokens: 1
        )
        staleEstimateWouldAdmit = true
    } catch let error as HarnessModelSession.SessionError {
        guard case .yieldToVerification = error else { throw error }
    }
    try repairWindowRequire(
        !staleEstimateWouldAdmit && session.ledger.admittedCallCount == 4,
        "a later larger text estimate was stale or consumed a refused call"
    )
    let reserveDecisionBeforeStaleSignal = provider.shouldYieldEditingToVerification
    provider.openingRuntimeImageWasRetired(rawImageBytes: UInt64(imageBytes))
    try repairWindowRequire(
        provider.shouldYieldEditingToVerification == reserveDecisionBeforeStaleSignal,
        "a stale retirement signal changed a later text request's reserve"
    )
    try repairWindowRequire(
        provider.reviewInputBudget.stageCount == 2,
        "the mandatory native review reserve changed while retiring the image"
    )
    print("PASS replayable edit reserve: 672977 retired image bytes lowered only the future estimate; ledger stayed at 729674 and larger text refreshed the estimate")

    let (failedSession, failedProvider) = try await makeSession(transportFails: true)
    do {
        _ = try await failedProvider.respond(
            systemPrompt: "inert failed image edit",
            conversation: [MaintainChatTurn(role: "user", text: "IMAGE_EDIT", attachedImagePNGData: image)],
            maximumOutputTokens: 1
        )
        throw RepairWindowCheckError.failed("the failed image transport unexpectedly returned a reply")
    } catch let error as HarnessModelSession.SessionError {
        throw error
    } catch is NSError {
        // The provider rethrows the transport error after retaining the full
        // admitted reservation as the correction estimate.
    }
    try repairWindowRequire(
        failedSession.ledger.accountedInputBytes == 729_674,
        "a failed image transport did not retain its full admitted ledger bytes"
    )
    try repairWindowRequire(
        failedProvider.shouldYieldEditingToVerification,
        "a failed image transport incorrectly released the image reserve"
    )
    print("PASS replayable edit reserve: failed image transport kept the full future reserve")
    try await runReplayableEditFixerHookCheck()
}

/// Runs the real edit loop with an inert transport so the retirement
/// notification is exercised at its source. The fixture is a private Git tree;
/// no model, app or installed bundle is used.
@MainActor
private func runReplayableEditFixerHookCheck() async throws {
    try repairWindowRequire(MaintainSandbox.isAvailable,
                            "the real fixer hook check needs the existing edit sandbox")
    let fileManager = FileManager.default
    let container = fileManager.temporaryDirectory
        .appendingPathComponent("iris-replayable-image-fixer-" + UUID().uuidString)
    let workRoot = container.appendingPathComponent("work")
    let scratchRoot = container.appendingPathComponent("scratch")
    try fileManager.createDirectory(at: workRoot.appendingPathComponent("src"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: container) }
    let previousScratch = ProcessInfo.processInfo.environment["IRIS_HARNESS_SCRATCH"]
    setenv("IRIS_HARNESS_SCRATCH", scratchRoot.path, 1)
    defer {
        if let previousScratch { setenv("IRIS_HARNESS_SCRATCH", previousScratch, 1) }
        else { unsetenv("IRIS_HARNESS_SCRATCH") }
    }

    let sourceURL = workRoot.appendingPathComponent("src/feature.js")
    try Data("export const featureValue = 1;\n".utf8).write(to: sourceURL)
    let runner = try MaintainShellRunner(repoRootPath: workRoot.path)
    let initialized = try await runner.run(
        "git init -q && git add src/feature.js && git -c user.name=IrisFixture -c user.email=fixture@example.invalid commit -qm baseline",
        deadline: 20
    )
    try repairWindowRequire(initialized.succeeded,
                            "could not initialize the replayable-image fixer fixture")

    let brief = try HarnessTaskBrief(
        userRequest: "Change the fixture value",
        desiredOutcome: "The fixture exports the requested value",
        acceptanceCriteria: [.init(id: "value", statement: "The source exports featureValue equal to 2")]
    )
    let briefJSON = String(decoding: try JSONEncoder().encode(brief), as: UTF8.self)
    let image = Data(repeating: 0x5A, count: 672_977)
    var requests: [HarnessModelRequest] = []
    var editCount = 0
    let session = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 18, maxInputBytes: 1_800_000),
        maximumDurationNanoseconds: 60_000_000_000,
        serializedInputByteCounter: { request in
            if request.phase == .intake { return 13_152 }
            if request.phase == .edit,
               request.conversation.contains(where: { $0.imagePNG != nil }) { return 716_522 }
            if request.phase == .edit { return 43_545 }
            return 1_000
        }
    ) { request in
        requests.append(request)
        if request.phase == .intake { return HarnessModelReply(text: briefJSON) }
        if request.phase == .edit {
            editCount += 1
            if editCount == 1 {
                return HarnessModelReply(text: "Applying the requested value.\n```write src/feature.js\nexport const featureValue = 2;\n```")
            }
            return HarnessModelReply(text: "DONE")
        }
        return HarnessModelReply(text: "VERDICT: CLEAN")
    }
    let workflow = HarnessFeatureWorkflow(modelSession: session)
    _ = try await workflow.plan(
        request: brief.userRequest,
        repositorySummary: "src/feature.js"
    )
    let provider = HarnessWorkflowMaintainProvider(workflow: workflow)
    let result = await MaintainTierCFixer(provider: provider).attemptOnDemandEdit(
        clonePath: workRoot.path,
        appSlug: "replayable-image-fixer",
        appStack: .electron,
        changeId: "1234567890abcdef1234567890abcdef",
        request: brief.userRequest,
        kind: .feature,
        cancellationCheck: { false },
        runtimeLogContext: "inert fixture log",
        appWindowScreenshotPNG: image,
        verificationCommandsOverride: VerificationCommands(
            buildCommand: "grep -q 'featureValue = 2' src/feature.js",
            testCommand: "grep -q 'featureValue = 2' src/feature.js",
            commandSubdirectory: nil
        ),
        runsAnIndependentReview: false
    )
    guard case .appliedAndRebuilt = result else {
        throw RepairWindowCheckError.failed("the real fixer hook fixture did not complete: \(result)")
    }
    let editRequests = requests.filter { $0.phase == .edit }
    try repairWindowRequire(editRequests.count == 2,
                            "the real fixer hook fixture did not make exactly two edit requests")
    try repairWindowRequire(editRequests[0].conversation.contains(where: { $0.imagePNG != nil }),
                            "the first real fixer request did not carry the opening image")
    try repairWindowRequire(editRequests[1].conversation.allSatisfy { $0.imagePNG == nil },
                            "the real fixer did not retire the opening image before the next edit request")

    // Verification has started in the real fixer. Configure the unchanged
    // native two-stage reserve and admit both mandatory review transports.
    provider.configureReviewStages(nativeChecksRequired: true)
    provider.setHarnessPhase(.review)
    _ = try await provider.respond(systemPrompt: "native review one", conversation: [], maximumOutputTokens: 1)
    _ = try await provider.respond(systemPrompt: "native review two", conversation: [], maximumOutputTokens: 1)
    let reviewRequests = requests.filter { $0.phase == .review }
    try repairWindowRequire(reviewRequests.count == 2
                                && provider.reviewInputBudget.stageCount == 2,
                            "both mandatory native review transports were not admitted")
    print("PASS replayable edit reserve: real fixer retired the opening image, next edit was image-free, and both native review transports were admitted")
}

@MainActor
private func runRepairWindowBudgetChecks() async throws {
    let generousInputLimit: UInt64 = 2_000_000
    let reserveBytes = HarnessReviewInputBudget.defaultMaximumInputBytesPerStage * 2

    let trial20EditBytes: [UInt64] = [
        224_304, 56_214, 68_957, 81_747, 94_540,
        101_257, 116_532, 125_089, 115_720, 121_191
    ]
    let trial20InitialReviewBytes: UInt64 = 101_785
    let trial20RepairBytes: UInt64 = 130_580
    var trial20Requests: [HarnessModelRequest] = []
    let trial20Brief = try HarnessTaskBrief(
        userRequest: "Change the fixture value",
        desiredOutcome: "The fixture exports the requested value",
        acceptanceCriteria: [
            .init(id: "value", statement: "The source exports featureValue equal to 2")
        ]
    )
    let trial20BriefJSON = String(
        decoding: try JSONEncoder().encode(trial20Brief),
        as: UTF8.self
    )
    let trial20Session = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 18, maxInputBytes: 1_800_000),
        maximumDurationNanoseconds: 60_000_000_000,
        serializedInputByteCounter: { request in
            if request.phase == .intake { return 13_082 }
            guard let marker = request.systemPrompt.range(of: "INPUT_BYTES=") else {
                throw HarnessModelSession.SessionError.invalidLimits
            }
            let digits = request.systemPrompt[marker.upperBound...]
                .prefix(while: { $0.isNumber })
            guard let bytes = UInt64(String(digits)) else {
                throw HarnessModelSession.SessionError.invalidLimits
            }
            return bytes
        }
    ) { request in
        trial20Requests.append(request)
        if request.phase == .intake {
            return HarnessModelReply(text: trial20BriefJSON)
        }
        return HarnessModelReply(
            text: request.phase == .review ? "VERDICT: CLEAN" : "OK"
        )
    }
    let trial20Workflow = HarnessFeatureWorkflow(modelSession: trial20Session)
    _ = try await trial20Workflow.plan(
        request: trial20Brief.userRequest,
        repositorySummary: "src/feature.js"
    )
    let trial20Provider = HarnessWorkflowMaintainProvider(workflow: trial20Workflow)
    trial20Provider.configureReviewStages(nativeChecksRequired: true)
    for bytes in trial20EditBytes {
        _ = try await trial20Provider.respond(
            systemPrompt: "INPUT_BYTES=\(bytes)",
            conversation: [],
            maximumOutputTokens: 1
        )
    }
    let remainingBeforeRefusedEdit = trial20Session.ledger.remainingInputByteCapacity
    let mandatoryReviewBytes = trial20Provider.reviewInputBudget.reservedInputBytes
    try repairWindowRequire(
        remainingBeforeRefusedEdit >= mandatoryReviewBytes
            && remainingBeforeRefusedEdit - mandatoryReviewBytes >= 128_861,
        "the old review-only reserve would not have admitted the recorded last edit"
    )
    try repairWindowRequire(
        !trial20Provider.shouldYieldEditingToVerification,
        "the byte reserve yielded before the exact recorded boundary"
    )
    let admittedBeforeRefusedEdit = trial20Session.ledger.admittedCallCount
    var refusedBeforeTransport = false
    do {
        _ = try await trial20Provider.respond(
            systemPrompt: "INPUT_BYTES=128861",
            conversation: [],
            maximumOutputTokens: 1
        )
    } catch let error as HarnessModelSession.SessionError {
        if case .yieldToVerification = error {
            refusedBeforeTransport = true
        } else {
            throw error
        }
    }
    try repairWindowRequire(
        refusedBeforeTransport,
        "the recorded last edit was admitted instead of yielding to preserve correction input"
    )
    try repairWindowRequire(
        trial20Session.ledger.admittedCallCount == admittedBeforeRefusedEdit
            && trial20Requests.filter { $0.phase == .edit }.count == trial20EditBytes.count,
        "the exact input-boundary refusal consumed a call or reached transport"
    )

    trial20Provider.beginVerification()
    try repairWindowRequire(
        !trial20Provider.shouldYieldEditingToVerification,
        "verification entry did not release only the temporary correction reserve"
    )
    trial20Provider.setHarnessPhase(.review)
    _ = try await trial20Provider.respond(
        systemPrompt: "INPUT_BYTES=\(trial20InitialReviewBytes)",
        conversation: [],
        maximumOutputTokens: 1
    )
    trial20Provider.setHarnessPhase(.repair)
    _ = try await trial20Provider.respond(
        systemPrompt: "INPUT_BYTES=\(trial20RepairBytes)",
        conversation: [],
        maximumOutputTokens: 1
    )
    trial20Provider.setHarnessPhase(.review)
    for _ in 0..<2 {
        _ = try await trial20Provider.respond(
            systemPrompt: "INPUT_BYTES=\(trial20Provider.reviewInputBudget.maximumInputBytesPerStage)",
            conversation: [],
            maximumOutputTokens: 1
        )
    }
    try repairWindowRequire(
        trial20Session.ledger.admittedCallCount == 15
            && trial20Session.ledger.accountedInputBytes == 1_695_062
            && trial20Session.ledger.settledCallCount == 15
            && trial20Requests.filter { $0.phase == .repair }.count == 1
            && trial20Requests.filter { $0.phase == .review }.count == 3,
        "the recorded edit, first review, repair and two mandatory native reviews did not fit the unchanged caps"
    )
    print("PASS trial20 input reserve: recorded last edit yielded before transport, repair was admitted and accounted normally, verification released the temporary reserve, and both mandatory native reviews fit")

    var smallInputRequests: [HarnessModelRequest] = []
    let smallInputSession = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 18, maxInputBytes: 500_000),
        maximumDurationNanoseconds: 60_000_000_000,
        serializedInputByteCounter: { request in
            if request.phase == .intake { return 13_082 }
            guard let marker = request.systemPrompt.range(of: "INPUT_BYTES=") else {
                throw HarnessModelSession.SessionError.invalidLimits
            }
            let digits = request.systemPrompt[marker.upperBound...]
                .prefix(while: { $0.isNumber })
            guard let bytes = UInt64(String(digits)) else {
                throw HarnessModelSession.SessionError.invalidLimits
            }
            return bytes
        }
    ) { request in
        smallInputRequests.append(request)
        return HarnessModelReply(text: request.phase == .intake ? trial20BriefJSON : "OK")
    }
    let smallInputWorkflow = HarnessFeatureWorkflow(modelSession: smallInputSession)
    _ = try await smallInputWorkflow.plan(
        request: trial20Brief.userRequest,
        repositorySummary: "src/feature.js"
    )
    let smallInputProvider = HarnessWorkflowMaintainProvider(workflow: smallInputWorkflow)
    smallInputProvider.configureReviewStages(nativeChecksRequired: true)
    try repairWindowRequire(
        !smallInputProvider.shouldYieldEditingToVerification,
        "a 500 KB native job yielded before its first source scan"
    )
    _ = try await smallInputProvider.respond(
        systemPrompt: "INPUT_BYTES=8000",
        conversation: [],
        maximumOutputTokens: 1
    )
    try repairWindowRequire(
        !smallInputProvider.shouldYieldEditingToVerification,
        "a 500 KB native job lost its small-input correction opportunity after the first write"
    )
    _ = try await smallInputProvider.respond(
        systemPrompt: "INPUT_BYTES=120000",
        conversation: [],
        maximumOutputTokens: 1
    )
    try repairWindowRequire(
        !smallInputProvider.shouldYieldEditingToVerification
            && smallInputSession.ledger.admittedCallCount == 3
            && smallInputRequests.filter { $0.phase == .edit }.count == 2,
        "an oversized temporary reserve blocked a large edit that fits the mandatory native reserve"
    )
    print("PASS small input fallback: the 500 KB native job kept its first scan and a large edit admissible while retaining mandatory review bytes")

    let nativeSession = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 18, maxInputBytes: generousInputLimit),
        maximumDurationNanoseconds: 60_000_000_000
    ) { _ in
        HarnessModelReply(text: "OK")
    }
    let nativeProvider = HarnessWorkflowMaintainProvider(
        workflow: HarnessFeatureWorkflow(modelSession: nativeSession)
    )
    nativeProvider.configureReviewStages(nativeChecksRequired: true)
    try repairWindowRequire(nativeProvider.reviewInputBudget.stageCount == 2,
                            "native verification did not reserve two review stages")
    for _ in 0..<11 {
        _ = try await nativeSession.respond(
            phase: .edit, systemPrompt: "reserve", conversation: [], maximumOutputTokens: 1
        )
    }
    try repairWindowRequire(nativeSession.ledger.remainingCallCapacity == 7,
                            "the native reserve fixture consumed an unexpected number of calls")
    try repairWindowRequire(!nativeProvider.shouldYieldEditingToVerification,
                            "native review capacity was yielded one call too early")
    _ = try await nativeSession.respond(
        phase: .edit, systemPrompt: "reserve", conversation: [], maximumOutputTokens: 1
    )
    try repairWindowRequire(nativeSession.ledger.remainingCallCapacity == 6,
                            "the native correction reserve did not reach its boundary")
    try repairWindowRequire(nativeProvider.shouldYieldEditingToVerification,
                            "editing did not yield to the native review and correction reserve")
    nativeProvider.beginVerification()
    try repairWindowRequire(!nativeProvider.shouldYieldEditingToVerification,
                            "verification entry did not release the initial correction reserve")
    _ = try await nativeSession.respond(
        phase: .review, systemPrompt: "first review rejects", conversation: [], maximumOutputTokens: 1)
    for _ in 0..<3 {
        try repairWindowRequire(!nativeProvider.shouldYieldEditingToVerification,
                                "native repair opportunity ended before its remaining three calls")
        _ = try await nativeSession.respond(
            phase: .repair, systemPrompt: "correct", conversation: [], maximumOutputTokens: 1)
    }
    try repairWindowRequire(nativeSession.ledger.remainingCallCapacity == 2
                                && nativeProvider.shouldYieldEditingToVerification,
                            "repair consumed mandatory native review capacity")
    for _ in 0..<2 {
        _ = try await nativeSession.respond(
            phase: .review, systemPrompt: "final review", conversation: [], maximumOutputTokens: 1)
    }
    try repairWindowRequire(nativeSession.ledger.admittedCallCount == 18,
                            "native review reserve created or lost calls")

    let postVerificationSession = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 18, maxInputBytes: generousInputLimit),
        maximumDurationNanoseconds: 60_000_000_000
    ) { _ in
        HarnessModelReply(text: "OK")
    }
    let postVerificationProvider = HarnessWorkflowMaintainProvider(
        workflow: HarnessFeatureWorkflow(modelSession: postVerificationSession)
    )
    postVerificationProvider.configureReviewStages(nativeChecksRequired: true)
    postVerificationProvider.beginVerification()
    // A later configuration observation must not re-arm the initial correction
    // window after verification has started.
    postVerificationProvider.configureReviewStages(nativeChecksRequired: true)
    for _ in 0..<11 {
        _ = try await postVerificationSession.respond(
            phase: .edit, systemPrompt: "reserve", conversation: [], maximumOutputTokens: 1
        )
    }
    try repairWindowRequire(postVerificationSession.ledger.remainingCallCapacity == 7,
                            "the post-verification reserve fixture consumed an unexpected number of calls")
    _ = try await postVerificationSession.respond(
        phase: .edit, systemPrompt: "reserve", conversation: [], maximumOutputTokens: 1
    )
    try repairWindowRequire(postVerificationSession.ledger.remainingCallCapacity == 6,
                            "the post-verification reserve fixture did not reach its check boundary")
    try repairWindowRequire(!postVerificationProvider.shouldYieldEditingToVerification,
                            "reconfiguring after verification re-armed the initial correction window")

    let tinySession = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 8, maxInputBytes: generousInputLimit),
        maximumDurationNanoseconds: 60_000_000_000
    ) { _ in
        HarnessModelReply(text: "OK")
    }
    let tinyProvider = HarnessWorkflowMaintainProvider(
        workflow: HarnessFeatureWorkflow(modelSession: tinySession)
    )
    tinyProvider.configureReviewStages(nativeChecksRequired: true)
    try repairWindowRequire(tinyProvider.reviewInputBudget.stageCount == 2,
                            "the tiny native job dropped its review-only reserve")
    for _ in 0..<5 {
        _ = try await tinySession.respond(
            phase: .edit, systemPrompt: "reserve", conversation: [], maximumOutputTokens: 1
        )
    }
    try repairWindowRequire(tinySession.ledger.remainingCallCapacity == 3,
                            "the tiny budget fixture consumed an unexpected number of calls")
    try repairWindowRequire(!tinyProvider.shouldYieldEditingToVerification,
                            "the tiny job yielded before its two review calls were reached")
    _ = try await tinySession.respond(
        phase: .edit, systemPrompt: "reserve", conversation: [], maximumOutputTokens: 1
    )
    try repairWindowRequire(tinyProvider.shouldYieldEditingToVerification,
                            "the tiny job did not retain its review-only reserve")

    let byteSession = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 18, maxInputBytes: reserveBytes),
        maximumDurationNanoseconds: 60_000_000_000
    ) { _ in
        HarnessModelReply(text: "transport must not run")
    }
    let byteProvider = HarnessWorkflowMaintainProvider(
        workflow: HarnessFeatureWorkflow(modelSession: byteSession)
    )
    byteProvider.configureReviewStages(nativeChecksRequired: true)
    try repairWindowRequire(byteProvider.shouldYieldEditingToVerification,
                            "input-byte exhaustion did not block editing")
    byteProvider.beginVerification()
    try repairWindowRequire(byteProvider.shouldYieldEditingToVerification,
                            "verification entry released mandatory review bytes")
    var yieldedForReviewBytes = false
    do {
        _ = try await byteSession.respond(
            phase: .edit,
            systemPrompt: "byte boundary",
            conversation: [],
            maximumOutputTokens: 1,
            preservingInputBytes: byteProvider.reviewInputBudget.reservedInputBytes
        )
    } catch let error as HarnessModelSession.SessionError {
        if case .yieldToVerification = error {
            yieldedForReviewBytes = true
        } else {
            throw error
        }
    }
    try repairWindowRequire(yieldedForReviewBytes,
                            "the model session admitted a request after the review byte reserve was exhausted")
    try repairWindowRequire(byteSession.ledger.snapshot.admittedCallCount == 0,
                            "the byte-boundary refusal consumed a model call")
    print("PASS repair window budget: native two-stage reserve, tiny review-only reserve, reconfiguration guard and byte exhaustion")
}

@MainActor
private func runRepairWindowScenario(
    _ scenario: RepairWindowScenario
) async throws -> RepairWindowObservation {
    let fileManager = FileManager.default
    let container = fileManager.temporaryDirectory
        .appendingPathComponent("iris-repair-window-" + UUID().uuidString)
    let workRoot = container.appendingPathComponent("work")
    let scratchRoot = container.appendingPathComponent("scratch")
    try fileManager.createDirectory(
        at: workRoot.appendingPathComponent("src"), withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
        at: workRoot.appendingPathComponent("tests"), withIntermediateDirectories: true
    )
    try fileManager.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: container) }

    let previousScratch = ProcessInfo.processInfo.environment["IRIS_HARNESS_SCRATCH"]
    setenv("IRIS_HARNESS_SCRATCH", scratchRoot.path, 1)
    defer {
        if let previousScratch {
            setenv("IRIS_HARNESS_SCRATCH", previousScratch, 1)
        } else {
            unsetenv("IRIS_HARNESS_SCRATCH")
        }
    }

    let sourceURL = workRoot.appendingPathComponent("src/feature.js")
    let testURL = workRoot.appendingPathComponent("tests/feature.test.js")
    try Data("export const featureValue = 1;\n".utf8).write(to: sourceURL)
    try Data("// baseline fixture test\n".utf8).write(to: testURL)

    let runner = try MaintainShellRunner(repoRootPath: workRoot.path)
    let initialized = try await runner.run(
        "git init -q && git add src/feature.js tests/feature.test.js && git -c user.name=IrisFixture -c user.email=fixture@example.invalid commit -qm baseline",
        deadline: 20
    )
    try repairWindowRequire(initialized.succeeded,
                            "could not initialize the private repair-window fixture")

    let brief = try HarnessTaskBrief(
        userRequest: "Change the fixture value",
        desiredOutcome: "The fixture exports the requested value",
        acceptanceCriteria: [
            .init(id: "value", statement: "The source exports featureValue equal to 2")
        ]
    )
    let briefJSON = String(decoding: try JSONEncoder().encode(brief), as: UTF8.self)
    let maxCalls: Int = {
        switch scenario {
        case .rejectedThenRepaired, .buildFailureBeforeReview:
            return 18
        case .cleanFirstDraft:
            return 18
        }
    }()
    let buildCommand = "grep -q 'featureValue = 2' src/feature.js"
    let testCommand = "test -f tests/feature.test.js && grep -q 'featureValue = 2' src/feature.js"
    var editCount = 0
    var repairCount = 0
    var reviewCount = 0
    var requests: [HarnessModelRequest] = []
    var reviewRemainingCallCapacity: [UInt64] = []

    let session = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: maxCalls, maxInputBytes: 2_000_000),
        maximumDurationNanoseconds: 180_000_000_000
    ) { request in
        requests.append(request)
        switch request.phase {
        case .intake:
            return HarnessModelReply(text: briefJSON)
        case .edit:
            editCount += 1
            switch scenario {
            case .rejectedThenRepaired, .buildFailureBeforeReview:
                if editCount <= 12 {
                    let value: Int
                    if case .buildFailureBeforeReview = scenario { value = 3 } else { value = 2 }
                    return HarnessModelReply(text: """
                    Keep the requested export in place while drafting the change.
                    ```write src/feature.js
                    export const featureValue = \(value); // draft-\(editCount)
                    ```
                    """)
                }
                return HarnessModelReply(text: "DONE")
            case .cleanFirstDraft:
                if editCount == 1 {
                    return HarnessModelReply(text: """
                    Implement the requested value and its focused test.
                    ```write src/feature.js
                    export const featureValue = 2;
                    ```
                    ```write tests/feature.test.js
                    // featureValue equals 2
                    if (featureValue !== 2) throw new Error('wrong value');
                    ```
                    """)
                }
                return HarnessModelReply(text: "DONE")
            }
        case .review:
            reviewCount += 1
            reviewRemainingCallCapacity.append(UInt64(maxCalls - requests.count))
            if case .rejectedThenRepaired = scenario, reviewCount == 1 {
                return HarnessModelReply(text: """
                ISSUE: no changed test asserts the requested featureValue behavior
                VERDICT: DISQUALIFYING
                """)
            }
            return HarnessModelReply(text: """
            COVERED: value | tests/feature.test.js | featureValue equals 2
            VERDICT: CLEAN
            """)
        case .repair:
            repairCount += 1
            switch repairCount {
            case 1:
                return HarnessModelReply(text: "Inspecting the changed source.\n```bash\nsed -n '1,10p' src/feature.js\n```")
            case 2:
                return HarnessModelReply(text: """
                Add the missing deterministic behavior check.
                ```write src/feature.js
                export const featureValue = 2;
                ```
                ```write tests/feature.test.js
                // featureValue equals 2
                if (featureValue !== 2) throw new Error('wrong value');
                ```
                """)
            default:
                return HarnessModelReply(text: "DONE")
            }
        case .recheck:
            return HarnessModelReply(text: "DONE")
        }
    }
    let workflow = HarnessFeatureWorkflow(modelSession: session)
    _ = try await workflow.plan(
        request: brief.userRequest,
        repositorySummary: "src/feature.js tests/feature.test.js"
    )
    let provider = HarnessWorkflowMaintainProvider(workflow: workflow)
    var events: [MaintainTierCProgressEvent] = []
    let result = await MaintainTierCFixer(provider: provider).attemptOnDemandEdit(
        clonePath: workRoot.path,
        appSlug: "repair-window-fixture",
        appStack: .electron,
        changeId: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
        request: brief.userRequest,
        kind: .feature,
        progressHandler: { event in events.append(event) },
        cancellationCheck: { false },
        manifestChangeApproval: { _ in false },
        verificationCommandsOverride: VerificationCommands(
            buildCommand: buildCommand,
            testCommand: testCommand,
            commandSubdirectory: nil
        ),
        runsAnIndependentReview: true
    )
    return RepairWindowObservation(
        result: result,
        requests: requests,
        events: events,
        reviewRemainingCallCapacity: reviewRemainingCallCapacity,
        admittedCallCount: session.ledger.snapshot.admittedCallCount
    )
}
