import Foundation

/// Local usage checkpoints contain counts, never prompts or credentials.
@MainActor
final class IrisTestRunUsage {
    private let runID = UUID().uuidString
    private let startedAt = Date()
    private let implementationArm: HarnessImplementationArm?
    private var inputCountsByReservationID: [HarnessRunReservationID: HarnessModelInputCounts] = [:]

    init(implementationArm: HarnessImplementationArm? = nil) {
        self.implementationArm = implementationArm
    }

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
            "reasoningOutputTokens": count(call.reasoningOutputTokens)
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
        implementationArm: HarnessImplementationArm? = nil
    ) -> [String: Any] {
        func count(_ value: UInt64?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let allCallsSettled = snapshot.inFlightCallCount == 0
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
            "requestedEditor": implementationArm.map { $0.route.description as Any } ?? NSNull(),
            "providerConfirmedModel": NSNull(),
            "modelIdentity": "requested, not provider-confirmed",
            "ledgerState": ledgerState,
            "uiAccepted": NSNull(),
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

    func record(_ snapshot: HarnessRunLedgerSnapshot) {
        guard IrisTestEnvironment.isEnabled else { return }
        let document = Self.snapshotDocument(
            runID: runID,
            startedAt: startedAt,
            snapshot: snapshot,
            calls: snapshot.settledCalls.map { callDocument(for: $0) },
            implementationArm: implementationArm
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
}
