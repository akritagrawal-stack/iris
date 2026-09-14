import Foundation

/// Local usage checkpoints contain counts, never prompts or credentials.
@MainActor
final class IrisTestRunUsage {
    private let runID = UUID().uuidString
    private let startedAt = Date()
    private let implementationArm: HarnessImplementationArm?
    private var inputCountsByReservationID: [HarnessRunReservationID: HarnessModelInputCounts] = [:]
    private var latestSnapshot: HarnessRunLedgerSnapshot?
    private var outcomeAttribution: HarnessRunOutcomeAttribution?

    init(implementationArm: HarnessImplementationArm? = nil) {
        self.implementationArm = implementationArm
    }

    /// The opaque identifier callers use when they attach observed delivery
    /// and reader-acceptance facts to this run.
    var runIdentifier: String { runID }

    /// Serialize one settled call without retaining prompt or response data.
    /// The reservation is the authoritative submitted-input accounting even
    /// when the provider's token report is absent or differs. The component
    /// fields are pre-provider raw request counts: they exclude adapter-added
    /// notes, roles and provider framing. They are diagnostic decomposition
    /// only; `inputBytes` remains the authoritative serialized reservation.
    static func callDocument(
        for call: HarnessRunCallRecord,
        inputCounts: HarnessModelInputCounts? = nil
    ) -> [String: Any] {
        func count(_ value: UInt64?) -> Any { value.map { $0 as Any } ?? NSNull() }
        var document: [String: Any] = [
            "reservationID": call.reservation.id.rawValue,
            "attempt": call.reservation.attempt,
            "phase": call.reservation.task.rawValue,
            "outcome": call.outcome.rawValue,
            "inputBytes": call.reservation.inputBytesReserved,
            "inputTokens": count(call.inputTokens),
            "cachedInputTokens": count(call.cachedInputTokens),
            "outputTokens": count(call.outputTokens),
            "reasoningOutputTokens": count(call.reasoningOutputTokens),
            "elapsedNanoseconds": count(call.elapsedNanoseconds)
        ]
        if let inputCounts {
            document["systemPromptUTF8Bytes"] = inputCounts.systemPromptUTF8Bytes
            document["conversationTextUTF8Bytes"] = inputCounts.conversationTextUTF8Bytes
            document["rawImageBytes"] = inputCounts.rawImageBytes
            document["imageCount"] = inputCounts.imageCount
        }
        return document
    }

    /// Associate request-shape counts with the reservation that was admitted.
    /// The counts contain no prompt, image, path or credential data.
    func recordAdmission(
        _ reservation: HarnessRunReservation,
        inputCounts: HarnessModelInputCounts
    ) {
        inputCountsByReservationID[reservation.id] = inputCounts
    }

    func callDocument(for call: HarnessRunCallRecord) -> [String: Any] {
        Self.callDocument(for: call, inputCounts: inputCountsByReservationID[call.reservation.id])
    }

    /// Build the payload-free run document independently of file I/O so the
    /// in-flight token policy can be checked without enabling Iris Test.
    /// Aggregate token totals are intentionally unknown until every admitted
    /// call has settled, while settled per-call measurements remain available.
    static func snapshotDocument(
        runID: String,
        startedAt: Date,
        snapshot: HarnessRunLedgerSnapshot,
        calls: [[String: Any]],
        implementationArm: HarnessImplementationArm? = nil,
        outcomeAttribution: HarnessRunOutcomeAttribution? = nil
    ) -> [String: Any] {
        func count(_ value: UInt64?) -> Any { value.map { $0 as Any } ?? NSNull() }
        func value<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let allCallsSettled = snapshot.inFlightCallCount == 0
        let requestedRoute = outcomeAttribution?.requestedRoute ?? implementationArm?.route
        let ledgerState: String
        switch snapshot.status {
        case .running: ledgerState = "running"
        case .stopped(let reason): ledgerState = reason.rawValue
        }
        return [
            "schemaVersion": 1, "runID": runID,
            "appBundleIdentifier": IrisTestEnvironment.testBundleIdentifier,
            "startedAt": ISO8601DateFormatter().string(from: startedAt),
            "elapsedSeconds": Date().timeIntervalSince(startedAt),
            "requestedPlanner": HarnessModelRoute.planner.description,
            "requestedEditor": requestedRoute.map { $0.description as Any } ?? NSNull(),
            "requestedModel": requestedRoute.map { $0.model as Any } ?? NSNull(),
            "requestedEffort": requestedRoute.map { $0.effort as Any } ?? NSNull(),
            "providerConfirmedModel": value(outcomeAttribution?.providerConfirmedModel),
            "modelIdentity": outcomeAttribution?.providerConfirmedModel == nil
                ? "requested, not provider-confirmed"
                : "provider-confirmed",
            "ledgerState": ledgerState,
            "candidateID": value(outcomeAttribution?.candidateID),
            "verificationResult": value(outcomeAttribution?.verification.rawValue),
            "deliveryResult": value(outcomeAttribution?.delivery.rawValue),
            "relaunchResult": value(outcomeAttribution?.relaunch.rawValue),
            "undoResult": value(outcomeAttribution?.undo.rawValue),
            "uiAccepted": value(outcomeAttribution?.uiAccepted),
            "productOutcome": value(outcomeAttribution?.outcome.rawValue),
            "acceptedLifecycle": value(outcomeAttribution?.isAcceptedLifecycle),
            "elapsedNanoseconds": value(outcomeAttribution?.elapsedNanoseconds),
            "maxCalls": count(snapshot.maxCalls),
            "maxInputBytes": count(snapshot.maxInputBytes),
            "remainingCalls": remaining(snapshot.maxCalls, used: snapshot.admittedCallCount),
            "remainingInputBytes": remaining(snapshot.maxInputBytes, used: snapshot.accountedInputBytes),
            "admittedCalls": snapshot.admittedCallCount,
            "settledCalls": snapshot.settledCallCount,
            "inFlightCalls": snapshot.inFlightCallCount,
            "submittedInputBytes": snapshot.accountedInputBytes,
            "inputTokens": count(allCallsSettled ? snapshot.measuredInputTokens : nil),
            "cachedInputTokens": count(allCallsSettled ? snapshot.measuredCachedInputTokens : nil),
            "outputTokens": count(allCallsSettled ? snapshot.measuredOutputTokens : nil),
            "reasoningOutputTokens": count(allCallsSettled ? snapshot.measuredReasoningOutputTokens : nil),
            "estimatedCostUSD": NSNull(),
            "acceptanceVerdict": "See the edit result; settled usage is not success.",
            "calls": calls
        ]
    }

    /// Record a ledger checkpoint and, when supplied, the observed product
    /// result. A mismatched or second conflicting attribution is ignored so a
    /// stale async callback cannot overwrite the current run's evidence.
    func record(
        _ snapshot: HarnessRunLedgerSnapshot,
        outcome: HarnessRunOutcomeAttribution? = nil
    ) {
        latestSnapshot = snapshot
        if let outcome {
            guard acceptOutcome(outcome) else { return }
        }
        write(snapshot)
    }

    /// Attach lifecycle evidence after delivery or the reader's answer. The
    /// latest ledger checkpoint is rewritten so the evidence and token totals
    /// remain in one bounded run document across relaunch and Undo.
    func recordOutcome(
        _ outcome: HarnessRunOutcomeAttribution,
        snapshot: HarnessRunLedgerSnapshot? = nil
    ) {
        guard acceptOutcome(outcome) else { return }
        if let snapshot {
            record(snapshot)
        } else if let latestSnapshot {
            write(latestSnapshot)
        }
    }

    private func acceptOutcome(_ outcome: HarnessRunOutcomeAttribution) -> Bool {
        guard outcome.runID == runID else {
            irisTrace("Iris Test ignored lifecycle evidence for another run")
            return false
        }
        if let implementationArm,
           implementationArm.route != outcome.requestedRoute {
            irisTrace("Iris Test ignored lifecycle evidence for another model route")
            return false
        }
        if let existing = outcomeAttribution, existing != outcome {
            irisTrace("Iris Test ignored conflicting lifecycle evidence")
            return false
        }
        outcomeAttribution = outcome
        return true
    }

    private func write(_ snapshot: HarnessRunLedgerSnapshot) {
        guard IrisTestEnvironment.isEnabled else { return }
        let document = Self.snapshotDocument(
            runID: runID,
            startedAt: startedAt,
            snapshot: snapshot,
            calls: snapshot.settledCalls.map { callDocument(for: $0) },
            implementationArm: implementationArm,
            outcomeAttribution: outcomeAttribution
        )
        do {
            let directory = IrisTestEnvironment.logsDirectory.appendingPathComponent("harness-usage")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(runID + ".json"), options: .atomic)
        } catch {
            irisTrace("Iris Test could not save a usage checkpoint")
        }
    }

    private static func remaining(_ limit: UInt64?, used: UInt64) -> Any {
        guard let limit else { return NSNull() }
        return limit >= used ? limit - used : 0
    }
}
