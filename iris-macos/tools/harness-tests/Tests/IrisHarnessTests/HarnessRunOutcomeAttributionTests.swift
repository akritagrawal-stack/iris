import Testing
@testable import IrisHarness

@Suite("Harness product outcome attribution")
struct HarnessRunOutcomeAttributionTests {
    private let route = HarnessModelRoute(model: "gpt-6-astra", effort: "low")

    @Test("accepted evidence requires verification delivery and relaunch")
    func acceptedEvidenceRequiresCoreLifecycleStages() {
        let missingVerification = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                runID: "run-accepted-missing-verification",
                requestedRoute: route,
                verification: .unknown,
                delivery: .passed,
                relaunch: .passed,
                uiAcceptance: .accepted
            )
        }
        #expect(missingVerification == .acceptedWithoutVerification)

        let missingDelivery = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                runID: "run-accepted-missing-delivery",
                requestedRoute: route,
                verification: .passed,
                delivery: .unknown,
                relaunch: .passed,
                uiAcceptance: .accepted
            )
        }
        #expect(missingDelivery == .acceptedWithoutDelivery)

        let missingRelaunch = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                runID: "run-accepted-missing-relaunch",
                requestedRoute: route,
                verification: .passed,
                delivery: .passed,
                relaunch: .unknown,
                uiAcceptance: .accepted
            )
        }
        #expect(missingRelaunch == .acceptedWithoutRelaunch)
    }

    @Test("accepted reader evidence distinguishes full lifecycle from an undo gap")
    func acceptedEvidenceDistinguishesUndoCoverage() throws {
        let full = try HarnessRunOutcomeAttribution(
            runID: "run-full-lifecycle",
            candidateID: "candidate-42",
            requestedRoute: route,
            providerConfirmedModel: "gpt-6-astra-2026-09-14",
            elapsedNanoseconds: 2_500_000_000,
            verification: .passed,
            delivery: .passed,
            relaunch: .passed,
            undo: .passed,
            uiAcceptance: .accepted
        )
        #expect(full.uiAccepted == true)
        #expect(full.outcome == .acceptedFullLifecycle)
        #expect(full.isAcceptedLifecycle)

        let undoUnavailable = try HarnessRunOutcomeAttribution(
            runID: "run-ui-accepted-without-undo",
            requestedRoute: route,
            verification: .passed,
            delivery: .passed,
            relaunch: .passed,
            undo: .unavailable,
            uiAcceptance: .accepted
        )
        #expect(undoUnavailable.uiAccepted == true)
        #expect(undoUnavailable.outcome == .acceptedWithLifecycleGap)
        #expect(!undoUnavailable.isAcceptedLifecycle)
    }

    @Test("rejection, unknown, unavailable, and stage failure stay distinguishable")
    func nonAcceptedOutcomesStayHonest() throws {
        let rejected = try HarnessRunOutcomeAttribution(
            runID: "run-rejected",
            requestedRoute: route,
            verification: .passed,
            delivery: .passed,
            relaunch: .passed,
            uiAcceptance: .rejected
        )
        #expect(rejected.uiAccepted == false)
        #expect(rejected.outcome == .generatedNotAccepted)

        let unknown = try HarnessRunOutcomeAttribution(
            runID: "run-unknown",
            requestedRoute: route,
            verification: .unknown,
            delivery: .unknown,
            relaunch: .unknown,
            uiAcceptance: .unknown
        )
        #expect(unknown.uiAccepted == nil)
        #expect(unknown.outcome == .unknown)

        let unavailable = try HarnessRunOutcomeAttribution(
            runID: "run-unavailable",
            requestedRoute: route,
            verification: .unavailable,
            delivery: .unavailable,
            relaunch: .unavailable,
            uiAcceptance: .unavailable
        )
        #expect(unavailable.uiAccepted == nil)
        #expect(unavailable.outcome == .unavailable)

        let failed = try HarnessRunOutcomeAttribution(
            runID: "run-failed",
            requestedRoute: route,
            verification: .failed,
            delivery: .unknown,
            relaunch: .unknown,
            uiAcceptance: .unknown
        )
        #expect(failed.outcome == .failed)
    }

    @Test("identities and route metadata reject control data and oversized values")
    func identityAndRouteBoundsFailClosed() {
        let controlID = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                runID: "run-\nwith-control",
                requestedRoute: route,
                verification: .unknown,
                delivery: .unknown,
                relaunch: .unknown,
                uiAcceptance: .unknown
            )
        }
        #expect(controlID == .invalidRunID)

        let oversizedCandidate = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                runID: "run-oversized-candidate",
                candidateID: String(repeating: "x", count: 257),
                requestedRoute: route,
                verification: .unknown,
                delivery: .unknown,
                relaunch: .unknown,
                uiAcceptance: .unknown
            )
        }
        #expect(oversizedCandidate == .invalidCandidateID)

        let invalidProvider = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                runID: "run-invalid-provider",
                requestedRoute: route,
                providerConfirmedModel: "provider\u{0}",
                verification: .unknown,
                delivery: .unknown,
                relaunch: .unknown,
                uiAcceptance: .unknown
            )
        }
        #expect(invalidProvider == .invalidProviderModel)

        let invalidRoute = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                runID: "run-invalid-route",
                requestedRoute: HarnessModelRoute(model: "", effort: "low"),
                verification: .unknown,
                delivery: .unknown,
                relaunch: .unknown,
                uiAcceptance: .unknown
            )
        }
        #expect(invalidRoute == .invalidRoute)

        let unsupportedSchema = #expect(throws: HarnessRunOutcomeAttributionError.self) {
            try HarnessRunOutcomeAttribution(
                schemaVersion: 2,
                runID: "run-future-schema",
                requestedRoute: route,
                verification: .unknown,
                delivery: .unknown,
                relaunch: .unknown,
                uiAcceptance: .unknown
            )
        }
        #expect(unsupportedSchema == .unsupportedSchema)
    }

    @Test("ledger snapshots carry hard caps and remaining capacity")
    func snapshotCarriesBudgetMetadata() throws {
        var ledger = HarnessRunLedger(
            settings: try HarnessRunLedgerSettings(maxCalls: 3, maxInputBytes: 100),
            startedAt: 0
        )
        let reservation = try ledger.reserve(task: .edit, inputBytes: 37, at: 1)
        let snapshot = ledger.snapshot
        #expect(snapshot.maxCalls == 3)
        #expect(snapshot.maxInputBytes == 100)
        #expect(snapshot.admittedCallCount == 1)
        #expect(snapshot.accountedInputBytes == 37)
        #expect(snapshot.inFlightCallCount == 1)

        try ledger.settle(
            reservation,
            outcome: .succeeded,
            usage: HarnessMeasuredUsage(inputTokens: 12, outputTokens: 8),
            at: 2
        )
        #expect(ledger.snapshot.maxCalls == 3)
        #expect(ledger.snapshot.maxInputBytes == 100)
        #expect(ledger.snapshot.measuredInputTokens == 12)
        #expect(ledger.snapshot.measuredOutputTokens == 8)
    }

    @Test("later lifecycle evidence enriches unknown stages without changing run identity")
    func laterEvidenceEnrichesTheSameRun() throws {
        let initial = try HarnessRunOutcomeAttribution(
            runID: "run-enrichment",
            requestedRoute: route,
            verification: .unknown,
            delivery: .unknown,
            relaunch: .unknown,
            uiAcceptance: .unknown
        )
        let later = try HarnessRunOutcomeAttribution(
            runID: "run-enrichment",
            candidateID: "candidate-9",
            requestedRoute: route,
            providerConfirmedModel: "gpt-6-astra-confirmed",
            elapsedNanoseconds: 42,
            verification: .passed,
            delivery: .passed,
            relaunch: .passed,
            undo: .passed,
            uiAcceptance: .accepted
        )

        let merged = try #require(initial.merging(later))
        #expect(merged.candidateID == "candidate-9")
        #expect(merged.providerConfirmedModel == "gpt-6-astra-confirmed")
        #expect(merged.elapsedNanoseconds == 42)
        #expect(merged.uiAccepted == true)
        #expect(merged.outcome == .acceptedFullLifecycle)
    }

    @Test("conflicting known reader decisions or candidate identities are rejected")
    func conflictingEvidenceIsRejected() throws {
        let accepted = try HarnessRunOutcomeAttribution(
            runID: "run-conflict",
            candidateID: "candidate-a",
            requestedRoute: route,
            verification: .passed,
            delivery: .passed,
            relaunch: .passed,
            uiAcceptance: .accepted
        )
        let rejected = try HarnessRunOutcomeAttribution(
            runID: "run-conflict",
            candidateID: "candidate-a",
            requestedRoute: route,
            verification: .passed,
            delivery: .passed,
            relaunch: .passed,
            uiAcceptance: .rejected
        )
        #expect(accepted.merging(rejected) == nil)

        let differentCandidate = try HarnessRunOutcomeAttribution(
            runID: "run-conflict",
            candidateID: "candidate-b",
            requestedRoute: route,
            verification: .passed,
            delivery: .passed,
            relaunch: .passed,
            uiAcceptance: .accepted
        )
        #expect(accepted.merging(differentCandidate) == nil)
    }
}
