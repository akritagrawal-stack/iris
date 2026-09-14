import Foundation
import Testing
@testable import IrisHarness

/// A small, deterministic proxy for the requests a power user is likely to
/// bring to Iris. The replies are local JSON fixtures: this matrix evaluates
/// the host-owned intake and freeze boundary without contacting a provider or
/// starting an editor.
private enum HarnessPowerUserEvaluationMatrix {
    static let candidateDigest = String(repeating: "a", count: 64)

    @MainActor
    final class CallCounter {
        var value = 0
    }

    static func reply(
        request: String,
        desiredOutcome: String,
        criteria: [HarnessAcceptanceCriterion],
        questions: [HarnessTargetedQuestion] = [],
        nonGoals: [String] = [],
        assumptions: [HarnessModelAssumption] = [],
        milestoneTitle: String = "Make the requested change"
    ) throws -> String {
        let brief = try HarnessTaskBrief(
            userRequest: request,
            desiredOutcome: desiredOutcome,
            explicitNonGoals: nonGoals,
            acceptanceCriteria: criteria,
            targetedQuestions: questions,
            milestones: [.init(id: "change", title: milestoneTitle)],
            modelAssumptions: assumptions
        )
        return String(decoding: try JSONEncoder().encode(brief), as: UTF8.self)
    }

    @MainActor
    static func session(replies: [String], callCounter: CallCounter) throws -> HarnessModelSession {
        var remaining = replies
        return try HarnessModelSession(
            implementationArm: .astraLow,
            settings: .init(maxCalls: 4, maxInputBytes: 120_000),
            maximumDurationNanoseconds: 1_000_000_000,
            now: { 100 }
        ) { _ in
            callCounter.value += 1
            guard !remaining.isEmpty else {
                throw HarnessFixtureError.unexpectedProviderCall
            }
            return HarnessModelReply(text: remaining.removeFirst())
        }
    }

    enum HarnessFixtureError: Error {
        case unexpectedProviderCall
    }
}

@Test @MainActor
func powerUserEvaluationMatrixCoversIntakeClarificationAndFreezeBoundaries() async throws {
    // 1. A clear local request stays on the small route and can freeze with no
    // interview.
    do {
        let request = "Make the Save button label bigger but keep saving the same."
        let profile = HarnessIntakeProfile.classify(
            request: request,
            repositorySummary: "SaveButton.swift owns the label style; save behavior is unchanged.",
            targetAppIsBound: true
        )
        #expect(profile.complexity == .small)
        #expect(profile.surface == HarnessIntakeProfile.localControlSurface)
        #expect(profile.reservedTopics.isEmpty)

        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(
            replies: [try HarnessPowerUserEvaluationMatrix.reply(
                request: request,
                desiredOutcome: "Make the Save label easier to read without changing saving.",
                criteria: [.init(id: "larger-label", statement: "The Save label is visibly larger while saving behaves the same.")]
            )],
            callCounter: calls
        )
        let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)
        _ = try await workflow.plan(request: request, repositorySummary: "SaveButton.swift owns the label style; save behavior is unchanged.")
        #expect(workflow.unansweredQuestionIDs.isEmpty)
        let frozen = try workflow.freezeExecutionBrief(forAppSlug: "notes")
        #expect(frozen.intakeProfile == profile)
        #expect(calls.value == 1)
    }

    // 2. The canonical nontechnical Whisper Flow request gets one host-owned
    // destination choice, not a guessed tab and not a second model call.
    do {
        let request = "I want Whisper Flow to paste into the right tab."
        let repositorySummary = "The browser adapter exposes tabs and an insert-only text action; no destination is selected."
        let profile = HarnessIntakeProfile.classify(
            request: request,
            repositorySummary: repositorySummary,
            targetAppIsBound: true
        )
        #expect(profile.complexity == .complex)
        #expect(profile.surface == HarnessIntakeProfile.crossSurfaceTransferSurface)
        #expect(profile.reservedTopics == [.destination])

        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(
            replies: [try HarnessPowerUserEvaluationMatrix.reply(
                request: request,
                desiredOutcome: "Put the spoken text into the intended tab without sending it.",
                criteria: [.init(id: "insert-only", statement: "The text appears in the chosen tab without being sent.")]
            )],
            callCounter: calls
        )
        let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)
        let brief = try await workflow.plan(request: request, repositorySummary: repositorySummary)
        #expect(brief.targetedQuestions.map(\.id) == ["destination-selection"])
        #expect(throws: HarnessFeatureWorkflow.WorkflowError.unansweredQuestions) {
            try workflow.freezeExecutionBrief(forAppSlug: "whisper-flow")
        }
        try workflow.recordAnswer(
            questionID: "destination-selection",
            optionID: "destination-ask-on-ambiguity",
            answer: "Ask me when more than one app or tab could match"
        )
        let frozen = try workflow.freezeExecutionBrief(forAppSlug: "whisper-flow")
        #expect(frozen.intakeProfile == profile)
        #expect(calls.value == 1)
    }

    // 3. Explicit multi-app destinations are already a product decision. The
    // harness should recognize a cross-surface request without asking the
    // user to name an API or inventing another destination question.
    do {
        let request = "Switch to the Gmail tab to review the Docs tab without sending anything."
        let repositorySummary = "The browser adapter can insert into a named tab; no send action is needed."
        let profile = HarnessIntakeProfile.classify(
            request: request,
            repositorySummary: repositorySummary,
            targetAppIsBound: true
        )
        #expect(profile.complexity == .scoped)
        #expect(profile.surface == HarnessIntakeProfile.crossSurfaceTransferSurface)
        #expect(profile.reservedTopics.isEmpty)

        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(
            replies: [try HarnessPowerUserEvaluationMatrix.reply(
                request: request,
                desiredOutcome: "Let the user move between the named Gmail and Docs tabs without sending anything.",
                criteria: [.init(id: "named-tabs", statement: "The user can move between the named Gmail and Docs tabs without sending a message.")]
            )],
            callCounter: calls
        )
        let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)
        _ = try await workflow.plan(request: request, repositorySummary: repositorySummary)
        #expect(workflow.unansweredQuestionIDs.isEmpty)
        let frozen = try workflow.freezeExecutionBrief(forAppSlug: "browser")
        #expect(frozen.intakeProfile == profile)
        #expect(calls.value == 1)
    }

    // 4. A refinement that changes the acceptance contract pauses at scope
    // reconciliation. The old frozen contract cannot be used until the user
    // explicitly approves the proposed change.
    do {
        let request = "Keep my saved note visible after reopening."
        let repositorySummary = "The notes view has a saved note and an existing reopen path."
        let initial = try HarnessPowerUserEvaluationMatrix.reply(
            request: request,
            desiredOutcome: "Keep the saved note visible.",
            criteria: [.init(id: "visible", statement: "The saved note remains visible.")]
        )
        let revised = try HarnessPowerUserEvaluationMatrix.reply(
            request: request,
            desiredOutcome: "Keep the saved note visible.",
            criteria: [.init(id: "visible", statement: "The saved note remains visible after reopening.")]
        )
        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(
            replies: [initial, revised], callCounter: calls
        )
        let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)
        _ = try await workflow.plan(request: request, repositorySummary: repositorySummary)
        let first = try workflow.freezeExecutionBrief(forAppSlug: "notes")
        _ = try await workflow.refineBrief(repositorySummary: repositorySummary)
        #expect(workflow.pendingScopeReconciliation != nil)
        #expect(throws: HarnessFeatureWorkflow.WorkflowError.scopeReconciliationPending) {
            try workflow.freezeExecutionBrief(forAppSlug: "notes")
        }
        let reconciliationID = try #require(workflow.pendingScopeReconciliationID)
        _ = try workflow.approveScopeReconciliation(id: reconciliationID)
        let second = try workflow.freezeExecutionBrief(forAppSlug: "notes")
        #expect(second.revisionID != first.revisionID)
        #expect(second.acceptanceCriteria.first?.statement == "The saved note remains visible after reopening.")
        #expect(calls.value == 2)
    }

    // 5. External side effects use the high-risk profile and remain behind an
    // explicit product choice supplied by the planner. The matrix does not
    // claim that a provider or a real external app was contacted.
    do {
        let request = "Send this customer message to the selected customer from the open app."
        let repositorySummary = "The composer can prepare the message, but sending has an external side effect."
        let profile = HarnessIntakeProfile.classify(
            request: request,
            repositorySummary: repositorySummary,
            targetAppIsBound: true
        )
        #expect(profile.complexity == .highRisk)
        #expect(profile.surface == HarnessIntakeProfile.crossSurfaceTransferSurface)

        let question = HarnessTargetedQuestion(
            id: "send-confirmation",
            prompt: "Should Iris ask before sending the message?",
            options: [
                .init(id: "ask", label: "Ask me before sending"),
                .init(id: "prepare", label: "Prepare it and let me send it myself")
            ],
            topic: .trigger
        )
        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(
            replies: [try HarnessPowerUserEvaluationMatrix.reply(
                request: request,
                desiredOutcome: "Prepare the message and require confirmation before sending.",
                criteria: [.init(id: "confirmed-send", statement: "No message is sent until the user explicitly confirms it.")],
                questions: [question]
            )],
            callCounter: calls
        )
        let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)
        _ = try await workflow.plan(request: request, repositorySummary: repositorySummary)
        #expect(throws: HarnessFeatureWorkflow.WorkflowError.unansweredQuestions) {
            try workflow.freezeExecutionBrief(forAppSlug: "mail")
        }
        try workflow.recordAnswer(
            questionID: "send-confirmation",
            optionID: "ask",
            answer: "Ask me before sending"
        )
        let frozen = try workflow.freezeExecutionBrief(forAppSlug: "mail")
        #expect(frozen.intakeProfile == profile)
        #expect(calls.value == 1)
    }

    // 6. A stale saved candidate must fail binding, and a correction after a
    // freeze must invalidate the old execution snapshot.
    do {
        let request = "Fix the Notes save button color without changing behavior."
        let repositorySummary = "SaveButton.swift owns the color; the save behavior is unchanged."
        let profile = HarnessIntakeProfile.classify(
            request: request,
            repositorySummary: repositorySummary,
            targetAppIsBound: true
        )
        #expect(profile.complexity == .small)

        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(
            replies: [try HarnessPowerUserEvaluationMatrix.reply(
                request: request,
                desiredOutcome: "Make the Notes Save button color correct without changing saving.",
                criteria: [.init(id: "color", statement: "The Save button has the requested color and still saves normally.")]
            )],
            callCounter: calls
        )
        let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)
        _ = try await workflow.plan(request: request, repositorySummary: repositorySummary)
        let snapshot = try workflow.freezeExecutionBrief(forAppSlug: "notes")
        let contract = try workflow.savedFeatureContract(
            candidateBindingDigest: HarnessPowerUserEvaluationMatrix.candidateDigest
        )
        #expect(contract.isBound(toCandidateDigest: HarnessPowerUserEvaluationMatrix.candidateDigest, request: request))
        #expect(!contract.isBound(toCandidateDigest: String(repeating: "b", count: 64), request: request))
        #expect(!contract.isBound(toCandidateDigest: HarnessPowerUserEvaluationMatrix.candidateDigest, request: "A different request"))

        try workflow.recordCorrection(
            id: "changed-scope",
            answer: "Use a darker color than the current one.",
            revision: "request-2"
        )
        #expect(workflow.frozenExecutionBrief == nil)
        #expect(throws: HarnessFeatureWorkflow.WorkflowError.stalePlan) {
            try workflow.validateExecutionBrief(snapshot, forAppSlug: "notes")
        }
        #expect(calls.value == 1)
    }

    // 7. A request without a bound editable app is blocked before any provider
    // attempt. The coordinator should stop here and explain what is missing.
    do {
        let request = "Make the Save button label bigger."
        let profile = HarnessIntakeProfile.classify(
            request: request,
            repositorySummary: "SaveButton.swift owns the label style.",
            targetAppIsBound: false
        )
        #expect(profile.complexity == .blocked)
        #expect(!profile.targetIsBound)
        #expect(!profile.plannerRequired)
        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(replies: [], callCounter: calls)
        #expect(session.ledger.snapshot.admittedCallCount == 0)
        #expect(calls.value == 0)
    }

    // 8. A feature with persistence and an absent recipe is complex. A
    // data-boundary answer is required before the execution brief can freeze.
    do {
        let request = "Add an offline mode that keeps working after restart."
        let repositorySummary = "The repository has no existing persistence implementation; offline support is not specified."
        let profile = HarnessIntakeProfile.classify(
            request: request,
            repositorySummary: repositorySummary,
            targetAppIsBound: true
        )
        #expect(profile.complexity == .complex)
        #expect(profile.surface == HarnessIntakeProfile.localControlSurface)
        #expect(profile.reservedTopics.isEmpty)
        let question = HarnessTargetedQuestion(
            id: "offline-data",
            prompt: "What should happen to changes made while offline?",
            options: [
                .init(id: "keep-local", label: "Keep them on this Mac until I reconnect"),
                .init(id: "ask-conflict", label: "Ask me if offline changes conflict")
            ],
            topic: .dataBoundary
        )
        let calls = HarnessPowerUserEvaluationMatrix.CallCounter()
        let session = try HarnessPowerUserEvaluationMatrix.session(
            replies: [try HarnessPowerUserEvaluationMatrix.reply(
                request: request,
                desiredOutcome: "The app remains usable offline and retains approved local changes after restart.",
                criteria: [.init(id: "restart", statement: "After restarting offline, the user's approved local changes are still visible.")],
                questions: [question],
                assumptions: [.init(id: "storage", statement: "Inspect the repository before choosing the safest local store.")]
            )],
            callCounter: calls
        )
        let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)
        _ = try await workflow.plan(request: request, repositorySummary: repositorySummary)
        #expect(throws: HarnessFeatureWorkflow.WorkflowError.unansweredQuestions) {
            try workflow.freezeExecutionBrief(forAppSlug: "offline-app")
        }
        try workflow.recordAnswer(
            questionID: "offline-data",
            optionID: "ask-conflict",
            answer: "Ask me if offline changes conflict"
        )
        let frozen = try workflow.freezeExecutionBrief(forAppSlug: "offline-app")
        #expect(frozen.intakeProfile == profile)
        #expect(calls.value == 1)
    }
}
