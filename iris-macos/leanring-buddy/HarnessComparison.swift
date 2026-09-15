import Foundation
import CryptoKit

/// Fixed requested roles for the first experiment. This is not automatic routing.
nonisolated enum HarnessImplementationArm: String, Codable, CaseIterable, Sendable {
    /// Retained only to decode and compare the completed Astra experiment.
    /// New harness work is normalized to Luna before a provider request.
    case astraLow
    case lunaXHigh
    case lunaMax
    case gpt55Medium
    case terraHigh

    var route: HarnessModelRoute {
        switch self {
        case .astraLow: return HarnessModelRoute(model: "gpt-6-astra", effort: "low")
        case .lunaXHigh: return HarnessModelRoute(model: "gpt-5.6-luna", effort: "xhigh")
        case .lunaMax: return HarnessModelRoute(model: "gpt-5.6-luna", effort: "max")
        case .gpt55Medium: return HarnessModelRoute(model: "gpt-5.5", effort: "medium")
        case .terraHigh: return HarnessModelRoute(model: "gpt-5.6-terra", effort: "high")
        }
    }
}

nonisolated struct HarnessModelRoute: Codable, Equatable, Sendable {
    let model: String
    let effort: String

    /// The route used for new planner reservations. Keep this derived from
    /// the implementation policy so usage documents cannot advertise the
    /// historical comparison model as if it handled a live Iris run.
    static let planner = HarnessImplementationArm.lunaMax.route

    /// Frozen baseline metadata for the completed model comparison. This is
    /// intentionally named so callers cannot mistake it for the live route.
    static let comparisonPlanner = HarnessModelRoute(model: "gpt-6-astra", effort: "medium")

    var description: String { "Requested: \(model), effort: \(effort)" }
}

/// The work class is selected by Iris before a provider is considered. Local
/// checks and tool execution do not need a model at all; bounded extraction can
/// use a fast, low-effort turn; only planning and complex implementation may
/// use a stronger model route. Keeping this classification separate from the
/// provider name prevents a default model from quietly becoming the executor
/// for work that should have stayed deterministic.
nonisolated public enum HarnessRouteClass: String, Codable, CaseIterable, Sendable {
    case deterministic
    case boundedExtraction
    case planning
    case complexImplementation
}

/// A code-authored routing decision. `modelRoute == nil` is intentional for a
/// deterministic operation and is the signal that the caller must use its
/// local executor instead of spending a model call.
nonisolated struct HarnessRouteDecision: Codable, Equatable, Sendable {
    let routeClass: HarnessRouteClass
    let modelRoute: HarnessModelRoute?
    let maximumOutputTokens: UInt64
    let maximumInputBytes: UInt64

    init(
        routeClass: HarnessRouteClass,
        modelRoute: HarnessModelRoute?,
        maximumOutputTokens: UInt64,
        maximumInputBytes: UInt64
    ) {
        self.routeClass = routeClass
        self.modelRoute = modelRoute
        self.maximumOutputTokens = maximumOutputTokens
        self.maximumInputBytes = maximumInputBytes
    }

    var usesModel: Bool { modelRoute != nil }

    /// A deterministic operation has no model reasoning or token allowance.
    /// This is useful to telemetry consumers that want to prove a local check
    /// stayed local without inventing a zero-token provider call.
    var reasoningBudgetTokens: UInt64 { routeClass == .deterministic ? 0 : maximumOutputTokens }
}

/// Central policy for all harness request classes. The policy is intentionally
/// small and pure so every host and comparison can make the same decision.
nonisolated enum HarnessRoutingPolicy {
    static let currentVersion = "iris.harness.routing.v1"
    static let deterministic = HarnessRouteDecision(
        routeClass: .deterministic,
        modelRoute: nil,
        maximumOutputTokens: 0,
        maximumInputBytes: 0
    )

    static func decision(
        for phase: HarnessRunTaskKind,
        implementationArm: HarnessImplementationArm = .lunaMax
    ) -> HarnessRouteDecision {
        // Astra remains decodable for the completed comparison, but automatic
        // routing must never select it for a new Iris request.
        let executionArm: HarnessImplementationArm
        switch implementationArm {
        case .astraLow, .terraHigh:
            executionArm = .lunaMax
        case .lunaXHigh, .lunaMax, .gpt55Medium:
            executionArm = implementationArm
        }
        switch phase {
        case .intake:
            return HarnessRouteDecision(
                routeClass: .planning,
                modelRoute: HarnessImplementationArm.lunaMax.route,
                maximumOutputTokens: 2_400,
                maximumInputBytes: 256 * 1024
            )
        case .edit, .repair:
            return HarnessRouteDecision(
                routeClass: .complexImplementation,
                modelRoute: executionArm.route,
                maximumOutputTokens: 4_000,
                maximumInputBytes: 1_800_000
            )
        case .review, .recheck:
            // Terra is explicit and review-only. The normal review path stays
            // on Luna, while implementation requests never select Terra.
            let reviewRoute = implementationArm == .terraHigh
                ? HarnessImplementationArm.terraHigh.route
                : HarnessImplementationArm.lunaMax.route
            return HarnessRouteDecision(
                routeClass: .boundedExtraction,
                modelRoute: reviewRoute,
                maximumOutputTokens: 1_200,
                maximumInputBytes: 512 * 1024
            )
        }
    }

    static func decision(forLocalOperation operation: String) -> HarnessRouteDecision {
        // The operation label is telemetry only. It is deliberately not used
        // to infer a model route, so a future tool name cannot escape the local
        // first policy through string matching.
        _ = operation
        return deterministic
    }
}

/// Counts-only routing evidence. Model-call counts are separated from local
/// operations so cost reports can show calls avoided instead of treating a
/// deterministic check as an unmeasured provider request.
nonisolated public struct HarnessRouteTelemetry: Codable, Equatable, Sendable {
    public let policyVersion: String
    public private(set) var deterministicOperations: UInt64
    public private(set) var modelCallsByClass: [String: UInt64]
    public private(set) var inputBytesByClass: [String: UInt64]
    /// Provider-reported input token counts, kept separate from the admitted
    /// byte budget. A missing provider field stays absent rather than being
    /// inferred from UTF-8 bytes.
    public private(set) var inputTokensByClass: [String: UInt64]
    /// Provider-reported cache-read input tokens. These have different pricing
    /// and must not be folded into ordinary input tokens.
    public private(set) var cachedInputTokensByClass: [String: UInt64]
    public private(set) var outputTokensByClass: [String: UInt64]
    public private(set) var reasoningTokensByClass: [String: UInt64]

    public init(policyVersion: String = "iris.harness.routing.v1") {
        self.policyVersion = policyVersion
        self.deterministicOperations = 0
        self.modelCallsByClass = [:]
        self.inputBytesByClass = [:]
        self.inputTokensByClass = [:]
        self.cachedInputTokensByClass = [:]
        self.outputTokensByClass = [:]
        self.reasoningTokensByClass = [:]
    }

    public var modelCalls: UInt64 {
        modelCallsByClass.values.reduce(0, +)
    }

    public var modelCallsAvoided: UInt64 { deterministicOperations }

    public mutating func recordDeterministicOperation() {
        deterministicOperations = deterministicOperations == .max
            ? .max : deterministicOperations + 1
    }

    public mutating func recordModelCall(
        routeClass: HarnessRouteClass,
        inputBytes: UInt64,
        inputTokens: UInt64? = nil,
        cachedInputTokens: UInt64? = nil,
        outputTokens: UInt64? = nil,
        reasoningTokens: UInt64? = nil
    ) {
        let key = routeClass.rawValue
        increment(&modelCallsByClass[key])
        increment(&inputBytesByClass[key], by: inputBytes)
        if let inputTokens { increment(&inputTokensByClass[key], by: inputTokens) }
        if let cachedInputTokens { increment(&cachedInputTokensByClass[key], by: cachedInputTokens) }
        if let outputTokens { increment(&outputTokensByClass[key], by: outputTokens) }
        if let reasoningTokens { increment(&reasoningTokensByClass[key], by: reasoningTokens) }
    }

    private func increment(_ value: inout UInt64?, by amount: UInt64 = 1) {
        let current = value ?? 0
        value = current.addingReportingOverflow(amount).partialValue
    }
}

/// The evaluator owns these bytes. The builder cannot redefine success by
/// replacing its own plan, starting source or expected results mid-comparison.
nonisolated struct HarnessFrozenComparison: Codable, Equatable, Sendable {
    let caseID: String
    let sourceRevision: String
    let sourceDigest: String
    let acceptedBriefDigest: String
    let acceptanceContractDigest: String
    let plannerRoute: HarnessModelRoute

    enum ValidationError: Error, Equatable {
        case missingIdentity
        case oversizedMaterial
        case changedSource
        case changedBrief
        case changedAcceptanceContract
    }

    init(caseID: String, sourceRevision: String, sourceManifest: Data,
         acceptedBrief: Data, acceptanceContract: Data) throws {
        guard !caseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sourceRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sourceManifest.isEmpty, !acceptedBrief.isEmpty, !acceptanceContract.isEmpty else {
            throw ValidationError.missingIdentity
        }
        guard caseID.utf8.count <= 256, sourceRevision.utf8.count <= 256,
              sourceManifest.count <= 1_000_000, acceptedBrief.count <= 64_000,
              acceptanceContract.count <= 256_000 else {
            throw ValidationError.oversizedMaterial
        }
        self.caseID = caseID
        self.sourceRevision = sourceRevision
        self.sourceDigest = Self.digest(sourceManifest)
        self.acceptedBriefDigest = Self.digest(acceptedBrief)
        self.acceptanceContractDigest = Self.digest(acceptanceContract)
        self.plannerRoute = .comparisonPlanner
    }

    func validate(sourceManifest: Data, acceptedBrief: Data, acceptanceContract: Data) throws {
        guard Self.digest(sourceManifest) == sourceDigest else { throw ValidationError.changedSource }
        guard Self.digest(acceptedBrief) == acceptedBriefDigest else { throw ValidationError.changedBrief }
        guard Self.digest(acceptanceContract) == acceptanceContractDigest else {
            throw ValidationError.changedAcceptanceContract
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Builder statements are deliberately absent from the evidence inputs.
/// A host evaluator supplies observed results from outside the editable tree.
nonisolated enum HarnessAcceptanceGate {
    enum Result: String, Codable, Sendable { case passed, failed, notRun }
    struct Check: Codable, Equatable, Sendable {
        let id: String
        let revision: String
        let result: Result
    }
    enum Verdict: Equatable, Sendable {
        case accepted
        case incomplete([String])
        case rejected([String])
    }

    static func evaluate(requiredIDs: [String], revision: String,
                         observed: [Check], scopeIsIntact: Bool) -> Verdict {
        guard scopeIsIntact else { return .rejected(["The allowed edit scope changed."]) }
        guard !revision.isEmpty, !requiredIDs.isEmpty,
              requiredIDs.allSatisfy({ !$0.isEmpty }), Set(requiredIDs).count == requiredIDs.count else {
            return .rejected(["The acceptance contract is missing or invalid."])
        }
        guard Set(observed.map(\.id)).count == observed.count else {
            return .rejected(["Duplicate check results require reconciliation."])
        }
        let failed = observed.filter { requiredIDs.contains($0.id) && $0.revision == revision && $0.result == .failed }
        if !failed.isEmpty { return .rejected(failed.map(\.id)) }
        let missing = requiredIDs.filter { id in
            !observed.contains { $0.id == id && $0.revision == revision && $0.result == .passed }
        }
        return missing.isEmpty ? .accepted : .incomplete(missing)
    }
}
