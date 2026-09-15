import Foundation
import Testing
@testable import IrisHarness

private func executionBriefReply(
    request: String,
    criteria: [HarnessAcceptanceCriterion] = [
        .init(id: "visible", statement: "The requested visible result is present.")
    ],
    questions: [HarnessTargetedQuestion] = [],
    explicitNonGoals: [String] = ["Do not change the existing save behavior."],
    assumptions: [HarnessModelAssumption] = [
        .init(id: "existing-control", statement: "The existing control can be reused.")
    ]
) throws -> String {
    let brief = try HarnessTaskBrief(
        userRequest: request,
        desiredOutcome: "The requested visible result is present.",
        explicitNonGoals: explicitNonGoals,
        acceptanceCriteria: criteria,
        targetedQuestions: questions,
        milestones: [.init(id: "change", title: "Make the small requested change")],
        modelAssumptions: assumptions
    )
    return String(decoding: try JSONEncoder().encode(brief), as: UTF8.self)
}

@MainActor
private func executionBriefSession(replies: [String]) throws -> HarnessModelSession {
    var remaining = replies
    return try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 4, maxInputBytes: 120_000),
        maximumDurationNanoseconds: 1_000_000_000,
        now: { 100 }
    ) { _ in
        HarnessModelReply(text: remaining.removeFirst())
    }
}

@Test @MainActor
func freezesCurrentExecutionContractWithProfileAndDecisions() async throws {
    let request = "  Make the Save label larger; keep saving unchanged.  "
    let question = HarnessTargetedQuestion(
        id: "trigger",
        prompt: "When should the larger label appear?",
        options: [
            .init(id: "on-save", label: "When I save"),
            .init(id: "always", label: "Whenever I look at it")
        ],
        topic: .trigger
    )
    let session = try executionBriefSession(
        replies: [try executionBriefReply(request: request, questions: [question])]
    )
    let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)

    _ = try await workflow.plan(request: request, repositorySummary: "The existing Save control owns its label style.")
    try workflow.recordAnswer(
        questionID: "trigger",
        optionID: "on-save",
        answer: "When I save"
    )

    let snapshot = try workflow.freezeExecutionBrief(
        forAppSlug: "notes",
        appName: "Notes",
        sourceBindingDigest: "digest-1"
    )
    let state = try #require(workflow.state)

    #expect(snapshot.schemaVersion == HarnessExecutionBrief.currentSchemaVersion)
    #expect(snapshot.appSlug == "notes")
    #expect(snapshot.targetAppName == "Notes")
    #expect(snapshot.sourceBindingDigest == "digest-1")
    #expect(snapshot.revisionID == state.activeRevisionID)
    #expect(snapshot.activeRevisionID == state.activeRevisionID)
    #expect(snapshot.planningRevisionID == state.activeRevisionID)
    #expect(snapshot.planningGeneration == workflow.currentPlanningGeneration)
    #expect(snapshot.userRequest == request)
    #expect(snapshot.decisions == workflow.selectedDecisionSummaries)
    #expect(snapshot.acceptanceCriteria == state.brief.acceptanceCriteria)
    #expect(snapshot.explicitNonGoals == state.brief.explicitNonGoals)
    #expect(snapshot.assumptions == state.brief.modelAssumptions)
    #expect(snapshot.intakeProfile == workflow.intakeProfile)
    #expect(workflow.executionBrief == snapshot)
    #expect(try workflow.validateExecutionBrief(
        snapshot,
        forAppSlug: "notes",
        appName: "Notes",
        sourceBindingDigest: "digest-1"
    ) == snapshot)
    #expect(try workflow.implementationContext().contains("FROZEN EXECUTION BRIEF"))
}

@Test @MainActor
func freezeRefusesWhenAQuestionIsUnanswered() async throws {
    let request = "Choose how the new label should behave."
    let question = HarnessTargetedQuestion(
        id: "behavior",
        prompt: "Which visible behavior do you want?",
        options: [
            .init(id: "first", label: "Use the first behavior"),
            .init(id: "second", label: "Use the second behavior")
        ],
        topic: .successObservation
    )
    let session = try executionBriefSession(
        replies: [try executionBriefReply(request: request, questions: [question])]
    )
    let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)

    _ = try await workflow.plan(request: request, repositorySummary: "A local label is available.")

    #expect(throws: HarnessFeatureWorkflow.WorkflowError.unansweredQuestions) {
        try workflow.freezeExecutionBrief(forAppSlug: "labels")
    }
    #expect(workflow.frozenExecutionBrief == nil)
}

@Test @MainActor
func freezeRefusesWhileScopeReconciliationIsPending() async throws {
    let request = "Keep the saved note visible."
    let initialCriteria = [
        HarnessAcceptanceCriterion(id: "visible", statement: "The saved note remains visible.")
    ]
    let proposedCriteria = [
        HarnessAcceptanceCriterion(id: "visible", statement: "The saved note remains visible after reopening.")
    ]
    let initialReply = try executionBriefReply(request: request, criteria: initialCriteria)
    let proposedReply = try executionBriefReply(request: request, criteria: proposedCriteria)
    let session = try executionBriefSession(replies: [initialReply, proposedReply])
    let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)

    _ = try await workflow.plan(request: request, repositorySummary: "The notes view is local.")
    _ = try await workflow.refineBrief(repositorySummary: "The notes view now has a reopen path.")

    #expect(workflow.pendingScopeReconciliation != nil)
    #expect(throws: HarnessFeatureWorkflow.WorkflowError.scopeReconciliationPending) {
        try workflow.freezeExecutionBrief(forAppSlug: "notes")
    }
    #expect(workflow.frozenExecutionBrief == nil)
}

@Test @MainActor
func validatingAnOlderFrozenContractRefusesAStaleRevision() async throws {
    let request = "Keep the saved note visible."
    let session = try executionBriefSession(
        replies: [try executionBriefReply(request: request)]
    )
    let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)

    _ = try await workflow.plan(request: request, repositorySummary: "The notes view is local.")
    let snapshot = try workflow.freezeExecutionBrief(forAppSlug: "notes")
    try workflow.recordCorrection(
        id: "reader-correction",
        answer: "Keep the note visible after reopening.",
        revision: "request-2"
    )

    #expect(workflow.frozenExecutionBrief == nil)
    #expect(throws: HarnessFeatureWorkflow.WorkflowError.stalePlan) {
        try workflow.validateExecutionBrief(snapshot, forAppSlug: "notes")
    }
}

@Test @MainActor
func frozenContractPreservesRequestByteForByte() async throws {
    let request = "\tKeep  this label exactly as written — including spacing.  \n"
    let session = try executionBriefSession(
        replies: [try executionBriefReply(request: request)]
    )
    let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)

    let planned = try await workflow.plan(
        request: request,
        repositorySummary: "The existing label is editable."
    )
    let snapshot = try workflow.freezeExecutionBrief()

    #expect(planned.userRequest == request)
    #expect(workflow.state?.brief.userRequest == request)
    #expect(snapshot.userRequest == request)
}
