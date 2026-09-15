import Foundation

/// Per-flow accounting for Codex process attempts. It retains counts only: no
/// prompt, response, credential, or price is stored here. The process observer
/// owns admission and settlement, so an empty reply, failure, and cancellation
/// are all represented as physical calls.
@MainActor
final class CodexRunUsageAccounting {
    private var ledger: HarnessRunLedger
    private var reservations: [UUID: HarnessRunReservation] = [:]
    private var requestedRoutes = Set<String>()

    init(settings: HarnessRunLedgerSettings) {
        ledger = HarnessRunLedger(settings: settings, startedAt: Self.now())
    }

    var snapshot: HarnessRunLedgerSnapshot { ledger.snapshot }
    var isRunning: Bool { ledger.isRunning }

    func admit(
        attemptID: UUID,
        requestedModel: String?,
        requestedEffort: String?,
        task: HarnessRunTaskKind,
        submittedInputBytes: UInt64
    ) throws {
        let model = requestedModel ?? "CLI default (model not reported)"
        requestedRoutes.insert(model + (requestedEffort.map { ", effort: \($0)" } ?? ""))
        let reservation = try ledger.reserve(
            task: task,
            attempt: ledger.admittedCallCount + 1,
            inputBytes: submittedInputBytes,
            at: Self.now()
        )
        reservations[attemptID] = reservation
    }

    @discardableResult
    func settle(
        attemptID: UUID,
        outcome: HarnessCallOutcome,
        usage: HarnessMeasuredUsage?
    ) -> Bool {
        guard let reservation = reservations.removeValue(forKey: attemptID) else { return false }
        do {
            try ledger.settle(reservation, outcome: outcome, usage: usage, at: Self.now())
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func finish(reason: HarnessRunStopReason) -> Bool {
        guard ledger.isRunning else { return false }
        do {
            try ledger.stop(reason: reason, at: Self.now())
            return true
        } catch {
            return false
        }
    }

    /// Labels only what the client requested. The CLI event stream does not
    /// confirm a resolved model or an invoice, so both remain explicitly unknown.
    var summary: String {
        let snapshot = ledger.snapshot
        func count(_ value: UInt64?) -> String { value.map(String.init) ?? "unknown" }
        let routes = requestedRoutes.isEmpty
            ? "no Codex process admitted"
            : requestedRoutes.sorted().joined(separator: " | ")
        return "model usage: requested " + routes + "; provider-confirmed model: unknown; "
            + "calls: \(snapshot.settledCallCount)/\(snapshot.admittedCallCount) settled; "
            + "input tokens: \(count(snapshot.measuredInputTokens)); cached input tokens: "
            + "\(count(snapshot.measuredCachedInputTokens)); output tokens: "
            + "\(count(snapshot.measuredOutputTokens)); reasoning output tokens: "
            + "\(count(snapshot.measuredReasoningOutputTokens)); USD: unknown"
    }

    private nonisolated static func now() -> HarnessMonotonicTime {
        HarnessMonotonicTime(nanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
}
