import Foundation
import Testing
@testable import IrisHarness

@Test func routingUsesTheLocalExecutorForDeterministicOperations() {
    let decision = HarnessRoutingPolicy.decision(forLocalOperation: "git-status")
    #expect(decision.routeClass == .deterministic)
    #expect(decision.modelRoute == nil)
    #expect(decision.maximumOutputTokens == 0)
    #expect(decision.reasoningBudgetTokens == 0)
}

@Test(arguments: [HarnessRunTaskKind.intake, .edit, .repair, .review, .recheck])
func everyModelPhaseHasAnExplicitRouteClass(_ phase: HarnessRunTaskKind) {
    let decision = HarnessRoutingPolicy.decision(for: phase)
    #expect(decision.routeClass != .deterministic)
    #expect(decision.modelRoute != nil)
    #expect(decision.maximumOutputTokens > 0)
    #expect(decision.maximumInputBytes > 0)
}

@Test func simpleExtractionDoesNotSelectTheComplexImplementationRoute() {
    let extraction = HarnessRoutingPolicy.decision(for: .review)
    let implementation = HarnessRoutingPolicy.decision(
        for: .edit, implementationArm: .lunaXHigh
    )
    #expect(extraction.routeClass == .boundedExtraction)
    #expect(extraction.modelRoute == HarnessImplementationArm.lunaMax.route)
    #expect(implementation.routeClass == .complexImplementation)
    #expect(implementation.modelRoute == HarnessImplementationArm.lunaXHigh.route)
    #expect(extraction.maximumOutputTokens < implementation.maximumOutputTokens)
}

@Test func fallbackAndReviewerRoutesStayNarrowlyScoped() {
    let fallback = HarnessRoutingPolicy.decision(
        for: .repair, implementationArm: .gpt55Medium
    )
    let reviewer = HarnessRoutingPolicy.decision(
        for: .review, implementationArm: .terraHigh
    )
    let terraImplementation = HarnessRoutingPolicy.decision(
        for: .edit, implementationArm: .terraHigh
    )
    #expect(fallback.modelRoute == HarnessImplementationArm.gpt55Medium.route)
    #expect(reviewer.modelRoute == HarnessImplementationArm.terraHigh.route)
    #expect(terraImplementation.modelRoute == HarnessImplementationArm.lunaMax.route)
}

@Test func routeTelemetrySeparatesAvoidedCallsFromModelCalls() {
    var telemetry = HarnessRouteTelemetry()
    telemetry.recordDeterministicOperation()
    telemetry.recordDeterministicOperation()
    telemetry.recordModelCall(
        routeClass: .boundedExtraction,
        inputBytes: 120,
        inputTokens: 7,
        cachedInputTokens: 3,
        outputTokens: 14,
        reasoningTokens: 2
    )
    telemetry.recordModelCall(
        routeClass: .planning,
        inputBytes: 300,
        outputTokens: 80,
        reasoningTokens: 20
    )

    #expect(telemetry.policyVersion == "iris.harness.routing.v1")
    #expect(telemetry.deterministicOperations == 2)
    #expect(telemetry.modelCallsAvoided == 2)
    #expect(telemetry.modelCalls == 2)
    #expect(telemetry.modelCallsByClass[HarnessRouteClass.boundedExtraction.rawValue] == 1)
    #expect(telemetry.inputBytesByClass[HarnessRouteClass.planning.rawValue] == 300)
    #expect(telemetry.inputTokensByClass[HarnessRouteClass.boundedExtraction.rawValue] == 7)
    #expect(telemetry.cachedInputTokensByClass[HarnessRouteClass.boundedExtraction.rawValue] == 3)
    #expect(telemetry.outputTokensByClass[HarnessRouteClass.boundedExtraction.rawValue] == 14)
    #expect(telemetry.reasoningTokensByClass[HarnessRouteClass.planning.rawValue] == 20)
}

@Test @MainActor func modelSessionRecordsLocalExecutorWorkWithoutAReservation() throws {
    let session = try HarnessModelSession(
        implementationArm: .lunaMax,
        settings: try HarnessRunLedgerSettings(maxCalls: 1, maxInputBytes: 10_000),
        maximumDurationNanoseconds: 1_000_000_000,
        now: { 100 }
    ) { _ in HarnessModelReply(text: "unused") }
    var snapshots: [HarnessRouteTelemetry] = []
    session.routeTelemetryDidChange = { snapshots.append($0) }

    #expect(session.recordDeterministicOperation("verification"))
    #expect(session.routeTelemetry.deterministicOperations == 1)
    #expect(session.routeTelemetry.modelCalls == 0)
    #expect(session.ledger.snapshot.admittedCallCount == 0)
    #expect(snapshots.last?.modelCallsAvoided == 1)
}

@Test @MainActor func modelSessionPersistsRouteAndLifecycleCheckpoints() async throws {
    var requests: [HarnessModelRequest] = []
    let session = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: try HarnessRunLedgerSettings(maxCalls: 2, maxInputBytes: 10_000),
        maximumDurationNanoseconds: 1_000_000_000,
        now: { 100 }
    ) { request in
        requests.append(request)
        return HarnessModelReply(text: "ok", usage: .init(
            inputTokens: 3, outputTokens: 4, reasoningOutputTokens: 1
        ))
    }
    var routeSnapshots: [HarnessRouteTelemetry] = []
    var lifecycleSnapshots: [HarnessTaskLifecycleSnapshot] = []
    session.routeTelemetryDidChange = { routeSnapshots.append($0) }
    session.lifecycleDidChange = { lifecycleSnapshots.append($0) }

    _ = try await session.respond(
        phase: .review,
        systemPrompt: "extract",
        conversation: [],
        maximumOutputTokens: 100
    )

    #expect(requests.count == 1)
    #expect(requests[0].routeClass == .boundedExtraction)
    #expect(requests[0].route == HarnessImplementationArm.lunaMax.route)
    #expect(session.ledger.snapshot.settledCalls[0].reservation.routeClass == .boundedExtraction)
    #expect(routeSnapshots.last?.modelCalls == 1)
    #expect(routeSnapshots.last?.modelCallsByClass[HarnessRouteClass.boundedExtraction.rawValue] == 1)
    #expect(routeSnapshots.last?.inputTokensByClass[HarnessRouteClass.boundedExtraction.rawValue] == 3)
    #expect(routeSnapshots.last?.cachedInputTokensByClass[HarnessRouteClass.boundedExtraction.rawValue] == nil)
    #expect(lifecycleSnapshots.contains { $0.state == .running })
    #expect(session.taskLifecycle.snapshot.state == .running)

    #expect(session.finish(reason: .completed))
    #expect(session.taskLifecycle.snapshot.state == .completed)
    #expect(session.taskLifecycle.snapshot.terminalReason == "Task completed.")
}

@Test func dispatchedTaskCannotBecomeIdleWithoutAnExplicitBlocker() throws {
    let policy = HarnessTaskLifecyclePolicy(
        dispatchStartGraceNanoseconds: 10,
        heartbeatIntervalNanoseconds: 5,
        maximumSilenceNanoseconds: 20
    )
    var lifecycle = try HarnessTaskLifecycle(
        taskID: "task-1", dispatchedAt: 100, policy: policy
    )
    #expect(lifecycle.snapshot.state == .dispatched)
    #expect(try lifecycle.reconcile(at: 109) == .none)
    #expect(try lifecycle.reconcile(at: 110) == .blocked(
        reason: "Task was dispatched but did not report a start checkpoint."
    ))
    #expect(lifecycle.snapshot.state == .blocked)
    #expect(lifecycle.snapshot.terminalReason?.contains("did not report") == true)
    #expect(try lifecycle.reconcile(at: 1_000) == .none)
}

@Test func runningTaskRequestsBoundedHeartbeatsThenBlocksOnSilence() throws {
    let policy = HarnessTaskLifecyclePolicy(
        dispatchStartGraceNanoseconds: 10,
        heartbeatIntervalNanoseconds: 5,
        maximumSilenceNanoseconds: 20
    )
    var lifecycle = try HarnessTaskLifecycle(
        taskID: "task-2", dispatchedAt: 100, policy: policy
    )
    try lifecycle.markStarted(at: 101)
    #expect(lifecycle.snapshot.state == .running)
    #expect(try lifecycle.reconcile(at: 105) == .heartbeatDue)
    #expect(lifecycle.snapshot.missedHeartbeats == 1)
    #expect(try lifecycle.reconcile(at: 110) == .heartbeatDue)
    #expect(lifecycle.snapshot.missedHeartbeats == 2)
    #expect(try lifecycle.reconcile(at: 121) == .blocked(
        reason: "Task stopped reporting progress within its allowed heartbeat window."
    ))
    #expect(lifecycle.snapshot.state == .blocked)
}

@Test func awaitingReaderIsExplicitAndCanFinishOnlyWithARecordedTransition() throws {
    let policy = HarnessTaskLifecyclePolicy(
        dispatchStartGraceNanoseconds: 10,
        heartbeatIntervalNanoseconds: 5,
        maximumSilenceNanoseconds: 20
    )
    var lifecycle = try HarnessTaskLifecycle(
        taskID: "task-3", dispatchedAt: 100, policy: policy
    )
    try lifecycle.markStarted(at: 101)
    try lifecycle.awaitReader(reason: "Choose the destination before continuing.", at: 102)
    #expect(lifecycle.snapshot.state == .awaitingReader)
    #expect(lifecycle.snapshot.statusMessage == "Choose the destination before continuing.")
    #expect(try lifecycle.reconcile(at: 1_000) == .awaitingReader)
    try lifecycle.complete(at: 103)
    #expect(lifecycle.snapshot.state == .completed)
    #expect(lifecycle.snapshot.sequence == 3)
    #expect(throws: HarnessTaskLifecycleError.taskAlreadyTerminal(.completed)) {
        try lifecycle.heartbeat(at: 104)
    }
}

@Test func lifecycleRejectsBackwardsTimeAndInvalidPolicy() throws {
    #expect(throws: HarnessTaskLifecycleError.invalidPolicy) {
        _ = try HarnessTaskLifecycle(
            taskID: "task", dispatchedAt: 1,
            policy: HarnessTaskLifecyclePolicy(
                dispatchStartGraceNanoseconds: 1,
                heartbeatIntervalNanoseconds: 5,
                maximumSilenceNanoseconds: 4
            )
        )
    }
    var lifecycle = try HarnessTaskLifecycle(taskID: "task-4", dispatchedAt: 100)
    try lifecycle.markStarted(at: 101)
    #expect(throws: HarnessTaskLifecycleError.timestampWentBackwards) {
        try lifecycle.heartbeat(at: 100)
    }
    #expect(throws: HarnessTaskLifecycleError.invalidTaskID) {
        _ = try HarnessTaskLifecycle(taskID: "bad\nvalue", dispatchedAt: 1)
    }
}
