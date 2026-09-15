import Foundation
import Testing
@testable import IrisHarness

@Suite("Codex production usage accounting")
struct CodexRunUsageAccountingTests {
    @Test("records intake, repair, cancellation, and late settlement without pretending usage is known")
    @MainActor
    func recordsAttemptLifecycle() throws {
        let accounting = CodexRunUsageAccounting(settings: try HarnessRunLedgerSettings(
            maxCalls: 4, maxInputBytes: 1_000
        ))
        let intakeID = UUID()
        let repairID = UUID()

        try accounting.admit(
            attemptID: intakeID,
            requestedModel: "model-picked-by-reader",
            requestedEffort: nil,
            task: .intake,
            submittedInputBytes: 120
        )
        try accounting.admit(
            attemptID: repairID,
            requestedModel: "model-picked-by-reader",
            requestedEffort: nil,
            task: .repair,
            submittedInputBytes: 180
        )
        #expect(accounting.finish(reason: .userStopped))

        // A process completion can arrive after the reader stops. It must settle
        // the already-admitted attempt, while the closed run rejects no new work.
        accounting.settle(
            attemptID: intakeID,
            outcome: .succeeded,
            usage: HarnessMeasuredUsage(
                inputTokens: 11,
                cachedInputTokens: 2,
                outputTokens: 7,
                reasoningOutputTokens: 3
            )
        )
        accounting.settle(attemptID: repairID, outcome: .cancelled, usage: nil)

        let snapshot = accounting.snapshot
        #expect(snapshot.status == .stopped(.userStopped))
        #expect(snapshot.admittedCallCount == 2)
        #expect(snapshot.settledCallCount == 2)
        #expect(snapshot.settledCalls.map(\.reservation.task) == [.intake, .repair])
        #expect(snapshot.measuredInputTokens == nil)
        #expect(snapshot.measuredCachedInputTokens == nil)
        #expect(snapshot.measuredOutputTokens == nil)
        #expect(snapshot.measuredReasoningOutputTokens == nil)
        #expect(accounting.summary.contains("requested model-picked-by-reader"))
        #expect(accounting.summary.contains("provider-confirmed model: unknown"))
        #expect(accounting.summary.contains("USD: unknown"))
    }
}
