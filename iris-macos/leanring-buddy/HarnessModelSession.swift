import Foundation

nonisolated struct HarnessModelRequest: Sendable {
    let route: HarnessModelRoute
    let routeClass: HarnessRouteClass
    let phase: HarnessRunTaskKind
    let systemPrompt: String
    let conversation: [HarnessModelMessage]
    let maximumOutputTokens: Int
}

nonisolated struct HarnessModelMessage: Sendable {
    let role: String
    let text: String
    var imagePNG: Data? = nil
}

nonisolated struct HarnessModelReply: Sendable {
    let text: String
    var usage: HarnessMeasuredUsage? = nil
}

/// Counts the request components without retaining any request content.
/// `conversationTextUTF8Bytes` counts message text only; role and provider
/// framing remain represented by the authoritative serialized input bytes.
nonisolated struct HarnessModelInputCounts: Equatable, Sendable {
    let systemPromptUTF8Bytes: UInt64
    let conversationTextUTF8Bytes: UInt64
    let rawImageBytes: UInt64
    let imageCount: UInt64
}

nonisolated struct HarnessModelTransportFailure: Error {
    let cause: any Error
    let usage: HarnessMeasuredUsage?
}

/// One owner for a job's model requests. The injected transport must perform
/// exactly one physical attempt, so retries cannot hide outside the accounting.
@MainActor
final class HarnessModelSession {
    typealias Transport = @MainActor @Sendable (HarnessModelRequest) async throws -> HarnessModelReply
    typealias SerializedInputByteCounter = @Sendable (HarnessModelRequest) throws -> UInt64
    typealias AdmissionObserver = (HarnessRunReservation, HarnessModelInputCounts) -> Void
    enum SessionError: Error, LocalizedError, Equatable, Sendable {
        case deadlineReached
        case responseTooLarge
        case invalidLimits
        case deterministicRouteRequiresLocalExecutor
        case routeInputBudgetExceeded(
            phase: HarnessRunTaskKind,
            requestedInputBytes: UInt64,
            maximumInputBytes: UInt64
        )
        case yieldToVerification(
            inputBytes: UInt64,
            preservedInputBytes: UInt64,
            availableInputBytes: UInt64
        )

        var errorDescription: String? {
            switch self {
            case .deadlineReached: return "This edit reached its time allowance and stopped without confirming completion."
            case .responseTooLarge: return "The model returned more data than this edit can safely process."
            case .invalidLimits: return "The edit's resource limits are invalid."
            case .deterministicRouteRequiresLocalExecutor:
                return "This operation is deterministic and must use the local executor; no model request was sent."
            case .routeInputBudgetExceeded(let phase, let requestedInputBytes, let maximumInputBytes):
                return "The \(phase.rawValue) request is \(requestedInputBytes) bytes, above its \(maximumInputBytes)-byte route allowance. No model request was sent."
            case .yieldToVerification:
                return "This edit stopped before its next request could consume the input space preserved for independent review. The current source still needs verification."
            }
        }
    }

    private(set) var ledger: HarnessRunLedger
    /// The most recent reservation accepted before transport began. The
    /// adapter uses this to associate a later successful image-retirement
    /// notification with the exact physical request that carried the image.
    /// It remains populated after a failed transport so the full admitted
    /// reservation stays the replay estimate.
    private(set) var lastAdmittedReservation: HarnessRunReservation?
    /// Component counts for `lastAdmittedReservation`. These are retained even
    /// when no telemetry observer is installed so an image-retirement signal
    /// can be matched conservatively in every harness run.
    private(set) var lastAdmittedInputCounts: HarnessModelInputCounts?
    /// Optional host checkpoint, called after each accounting mutation.
    var ledgerDidChange: ((HarnessRunLedgerSnapshot) -> Void)?
    /// Optional observer for admitted requests. It receives counts only after
    /// the ledger accepts a reservation, never for rejected preflight.
    var admissionDidSucceed: AdmissionObserver?
    /// Counts-only route evidence. Deterministic operations are recorded by
    /// their local executor; model turns are recorded when they settle.
    private(set) var routeTelemetry = HarnessRouteTelemetry()
    /// Optional host checkpoint for route telemetry.
    var routeTelemetryDidChange: ((HarnessRouteTelemetry) -> Void)?
    /// Bounded lifecycle state for mission-control/status consumers. The first
    /// model request acknowledges dispatch; `finish` records a terminal state.
    private(set) var taskLifecycle: HarnessTaskLifecycle
    var lifecycleDidChange: ((HarnessTaskLifecycleSnapshot) -> Void)?
    let implementationArm: HarnessImplementationArm
    private let transport: Transport
    private let now: @Sendable () -> UInt64
    private let deadline: UInt64
    private let maximumReplyBytes: Int
    let reviewInputBytesPerStage: UInt64
    private let serializedInputByteCounter: SerializedInputByteCounter

    init(implementationArm: HarnessImplementationArm, settings: HarnessRunLedgerSettings,
         maximumDurationNanoseconds: UInt64, maximumReplyBytes: Int = 128_000,
         reviewInputBytesPerStage: UInt64 = HarnessReviewInputBudget.defaultMaximumInputBytesPerStage,
         serializedInputByteCounter: SerializedInputByteCounter? = nil,
         now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
         transport: @escaping Transport) throws {
        let started = now()
        let deadlineResult = started.addingReportingOverflow(maximumDurationNanoseconds)
        guard maximumDurationNanoseconds > 0, maximumReplyBytes > 0, !deadlineResult.overflow else {
            throw SessionError.invalidLimits
        }
        self.implementationArm = implementationArm
        self.now = now
        self.deadline = deadlineResult.partialValue
        self.maximumReplyBytes = maximumReplyBytes
        self.reviewInputBytesPerStage = reviewInputBytesPerStage
        self.serializedInputByteCounter = serializedInputByteCounter
            ?? Self.defaultSerializedInputByteCount
        self.transport = transport
        self.ledger = HarnessRunLedger(settings: settings, startedAt: .init(nanoseconds: started))
        self.taskLifecycle = try HarnessTaskLifecycle(
            taskID: UUID().uuidString,
            dispatchedAt: .init(nanoseconds: started)
        )
    }

    func respond(phase: HarnessRunTaskKind, systemPrompt: String,
                 conversation: [HarnessModelMessage], maximumOutputTokens: Int,
                 preservingInputBytes: UInt64 = 0) async throws -> String {
        do {
            try Task.checkCancellation()
        } catch {
            markLifecycleCancelled(at: now())
            throw error
        }
        guard maximumOutputTokens > 0 else {
            markLifecycleBlocked(
                reason: "The model output limit was invalid.",
                at: .init(nanoseconds: now())
            )
            throw SessionError.invalidLimits
        }
        let timestamp = now()
        guard timestamp < deadline else {
            markLifecycleBlocked(
                reason: "The task reached its time allowance before a request started.",
                at: .init(nanoseconds: timestamp)
            )
            throw SessionError.deadlineReached
        }
        let decision = HarnessRoutingPolicy.decision(
            for: phase, implementationArm: implementationArm
        )
        guard let route = decision.modelRoute else {
            markLifecycleBlocked(
                reason: "This operation must be handled by the local executor.",
                at: .init(nanoseconds: timestamp)
            )
            throw SessionError.deterministicRouteRequiresLocalExecutor
        }
        markLifecycleStarted(at: .init(nanoseconds: timestamp))
        // The policy owns the upper bound. A caller can request a smaller
        // response for a cheap turn, but cannot silently enlarge a route's
        // output budget and bypass the routing contract.
        let effectiveMaximumOutputTokens = min(
            maximumOutputTokens,
            Int(decision.maximumOutputTokens)
        )
        let request = HarnessModelRequest(route: route, routeClass: decision.routeClass, phase: phase,
            systemPrompt: systemPrompt, conversation: conversation,
            maximumOutputTokens: effectiveMaximumOutputTokens)
        let inputBytes = try serializedInputByteCounter(request)
        let inputCounts = try Self.inputCounts(for: request)
        guard inputBytes <= decision.maximumInputBytes else {
            markLifecycleBlocked(
                reason: "The request exceeded the selected route's input allowance.",
                at: .init(nanoseconds: timestamp)
            )
            throw SessionError.routeInputBudgetExceeded(
                phase: phase,
                requestedInputBytes: inputBytes,
                maximumInputBytes: decision.maximumInputBytes
            )
        }
        let availableAfterPreserving = ledger.remainingInputByteCapacity(
            afterPreservingInputBytes: preservingInputBytes
        )
        if preservingInputBytes > 0, inputBytes > availableAfterPreserving {
            throw SessionError.yieldToVerification(
                inputBytes: inputBytes,
                preservedInputBytes: preservingInputBytes,
                availableInputBytes: availableAfterPreserving
            )
        }
        let attempt = ledger.snapshot.admittedCallCount.addingReportingOverflow(1)
        guard !attempt.overflow else { throw SessionError.invalidLimits }
        let reservation: HarnessRunReservation
        do {
            reservation = try ledger.reserve(task: phase, attempt: attempt.partialValue,
                inputBytes: inputBytes, routeClass: decision.routeClass,
                at: .init(nanoseconds: timestamp))
        } catch {
            if case HarnessRunLedgerError.budgetExceeded = error {
                markLifecycleBlocked(reason: "The task reached its measured resource allowance.", at: .init(nanoseconds: timestamp))
            } else {
                markLifecycleFailed(reason: "The task could not be admitted safely.", at: .init(nanoseconds: timestamp))
            }
            throw error
        }
        lastAdmittedReservation = reservation
        lastAdmittedInputCounts = inputCounts
        admissionDidSucceed?(reservation, inputCounts)
        ledgerDidChange?(ledger.snapshot)
        let reply: HarnessModelReply
        do {
            let remaining = deadline - timestamp
            let transport = self.transport
            reply = try await withThrowingTaskGroup(of: HarnessModelReply.self) { group in
                defer { group.cancelAll() }
                group.addTask { try await transport(request) }
                group.addTask {
                    try await Task.sleep(nanoseconds: remaining)
                    throw SessionError.deadlineReached
                }
                guard let first = try await group.next() else { throw CancellationError() }
                return first
            }
        } catch {
            let measuredUsage = (error as? HarnessModelTransportFailure)?.usage
            try ledger.settle(reservation, outcome: Task.isCancelled ? .cancelled : .failed,
                              usage: measuredUsage, at: .init(nanoseconds: now()))
            recordSettledRoute(reservation, usage: measuredUsage)
            markLifecycleProgress(at: .init(nanoseconds: now()))
            ledgerDidChange?(ledger.snapshot)
            let surfacedError = (error as? HarnessModelTransportFailure)?.cause ?? error
            if Task.isCancelled {
                _ = finish(reason: .cancelled)
            } else if (error as? SessionError) == .deadlineReached {
                // The transport was accounted for exactly once above. Close
                // the run separately so a deadline cannot leave Mission
                // Control showing a running task after its final attempt.
                _ = finish(reason: .uncertainFailure)
            }
            throw surfacedError
        }
        try ledger.settle(reservation, outcome: Task.isCancelled ? .cancelled : .succeeded,
                          usage: reply.usage, at: .init(nanoseconds: now()))
        recordSettledRoute(reservation, usage: reply.usage)
        markLifecycleProgress(at: .init(nanoseconds: now()))
        ledgerDidChange?(ledger.snapshot)
        do {
            try Task.checkCancellation()
        } catch {
            _ = finish(reason: .cancelled)
            throw error
        }
        guard now() < deadline else {
            _ = finish(reason: .uncertainFailure)
            throw SessionError.deadlineReached
        }
        guard reply.text.utf8.count <= maximumReplyBytes else {
            _ = finish(reason: .failed)
            throw SessionError.responseTooLarge
        }
        return reply.text
    }

    /// Records the run's terminal outcome without discarding admitted work.
    /// The ledger's stop contract blocks another reservation while retaining
    /// any pending transport call for its normal later settlement. The
    /// coordinator owns the outcome classification because it knows whether a
    /// completed request was accepted, cancelled, or rejected by a later gate.
    @discardableResult
    func finish(reason: HarnessRunStopReason) -> Bool {
        guard ledger.isRunning else { return false }
        do {
            try ledger.stop(reason: reason, at: .init(nanoseconds: now()))
            let timestamp = HarnessMonotonicTime(nanoseconds: now())
            switch reason {
            case .completed:
                try taskLifecycle.complete(at: timestamp)
            case .cancelled, .userStopped:
                try taskLifecycle.cancel(at: timestamp)
            case .budgetLimited:
                try taskLifecycle.block(reason: "The task reached its measured resource allowance.", at: timestamp)
            case .failed, .uncertainFailure:
                try taskLifecycle.fail(reason: "The task ended before completion was confirmed.", at: timestamp)
            }
            lifecycleDidChange?(taskLifecycle.snapshot)
            ledgerDidChange?(ledger.snapshot)
            return true
        } catch {
            return false
        }
    }

    private func markLifecycleStarted(at timestamp: HarnessMonotonicTime) {
        guard taskLifecycle.snapshot.state == .dispatched else { return }
        guard (try? taskLifecycle.markStarted(at: timestamp)) != nil else { return }
        lifecycleDidChange?(taskLifecycle.snapshot)
    }

    private func markLifecycleProgress(at timestamp: HarnessMonotonicTime) {
        guard taskLifecycle.snapshot.state == .running else { return }
        guard (try? taskLifecycle.heartbeat(at: timestamp)) != nil else { return }
        lifecycleDidChange?(taskLifecycle.snapshot)
    }

    private func markLifecycleBlocked(reason: String, at timestamp: HarnessMonotonicTime) {
        guard !taskLifecycle.isTerminal else { return }
        guard (try? taskLifecycle.block(reason: reason, at: timestamp)) != nil else { return }
        lifecycleDidChange?(taskLifecycle.snapshot)
    }

    private func markLifecycleFailed(reason: String, at timestamp: HarnessMonotonicTime) {
        guard !taskLifecycle.isTerminal else { return }
        guard (try? taskLifecycle.fail(reason: reason, at: timestamp)) != nil else { return }
        lifecycleDidChange?(taskLifecycle.snapshot)
    }

    private func markLifecycleCancelled(at timestamp: UInt64) {
        guard !taskLifecycle.isTerminal else { return }
        guard (try? taskLifecycle.cancel(at: .init(nanoseconds: timestamp))) != nil else { return }
        lifecycleDidChange?(taskLifecycle.snapshot)
    }

    /// Record work completed by Iris's local executor. The policy decision is
    /// made at the call site so a tool event cannot be accidentally counted as
    /// a model turn; deterministic work has no reservation or token spend.
    @discardableResult
    func recordDeterministicOperation(_ operation: String) -> Bool {
        let decision = HarnessRoutingPolicy.decision(forLocalOperation: operation)
        guard decision.routeClass == .deterministic, !decision.usesModel else {
            return false
        }
        routeTelemetry.recordDeterministicOperation()
        routeTelemetryDidChange?(routeTelemetry)
        return true
    }

    private func recordSettledRoute(
        _ reservation: HarnessRunReservation,
        usage: HarnessMeasuredUsage?
    ) {
        guard let routeClass = reservation.routeClass else { return }
        routeTelemetry.recordModelCall(
            routeClass: routeClass,
            inputBytes: reservation.inputBytesReserved,
            inputTokens: usage?.inputTokens,
            cachedInputTokens: usage?.cachedInputTokens,
            outputTokens: usage?.outputTokens,
            reasoningTokens: usage?.reasoningOutputTokens
        )
        routeTelemetryDidChange?(routeTelemetry)
    }

    nonisolated private static func inputCounts(
        for request: HarnessModelRequest
    ) throws -> HarnessModelInputCounts {
        func count(_ value: Int) throws -> UInt64 {
            guard value >= 0, let converted = UInt64(exactly: value) else {
                throw SessionError.invalidLimits
            }
            return converted
        }

        func add(_ value: UInt64, to total: inout UInt64) throws {
            let next = total.addingReportingOverflow(value)
            guard !next.overflow else { throw SessionError.invalidLimits }
            total = next.partialValue
        }

        var conversationTextUTF8Bytes: UInt64 = 0
        var rawImageBytes: UInt64 = 0
        var imageCount: UInt64 = 0
        for message in request.conversation {
            try add(count(message.text.utf8.count), to: &conversationTextUTF8Bytes)
            if let imagePNG = message.imagePNG {
                try add(count(imagePNG.count), to: &rawImageBytes)
                try add(1, to: &imageCount)
            }
        }
        return HarnessModelInputCounts(
            systemPromptUTF8Bytes: try count(request.systemPrompt.utf8.count),
            conversationTextUTF8Bytes: conversationTextUTF8Bytes,
            rawImageBytes: rawImageBytes,
            imageCount: imageCount
        )
    }

    nonisolated private static func defaultSerializedInputByteCount(
        _ request: HarnessModelRequest
    ) throws -> UInt64 {
        var total: UInt64 = 0
        func add(_ count: Int, to total: inout UInt64) throws {
            guard let value = UInt64(exactly: count), count >= 0 else {
                throw SessionError.invalidLimits
            }
            let next = total.addingReportingOverflow(value)
            guard !next.overflow else { throw SessionError.invalidLimits }
            total = next.partialValue
        }

        try add(request.systemPrompt.utf8.count, to: &total)
        for message in request.conversation {
            try add(message.role.utf8.count, to: &total)
            try add(message.text.utf8.count, to: &total)
            try add(message.imagePNG?.count ?? 0, to: &total)
        }
        return total
    }
}
