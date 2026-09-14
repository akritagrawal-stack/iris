import Foundation

/// The externally visible state of one dispatched harness task. A task is
/// never represented as an unqualified idle value after dispatch: it must
/// report progress, wait on an explicit reader decision, or end in a terminal
/// state.
public nonisolated enum HarnessTaskLifecycleState: String, Codable, CaseIterable, Sendable {
    case dispatched
    case running
    case awaitingReader
    case completed
    case failed
    case blocked
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .blocked, .cancelled: return true
        case .dispatched, .running, .awaitingReader: return false
        }
    }
}

public nonisolated enum HarnessTaskLifecycleAction: Equatable, Sendable {
    case none
    case heartbeatDue
    case awaitingReader
    case blocked(reason: String)
}

public nonisolated enum HarnessTaskLifecycleError: Error, Equatable, Sendable {
    case invalidTaskID
    case invalidPolicy
    case timestampWentBackwards
    case taskAlreadyTerminal(HarnessTaskLifecycleState)
    case invalidTransition(from: HarnessTaskLifecycleState, to: HarnessTaskLifecycleState)
    case emptyReason
    case integerOverflow
}

public nonisolated struct HarnessTaskLifecyclePolicy: Codable, Equatable, Sendable {
    /// The dispatch acknowledgement window. If no start or heartbeat arrives
    /// before this deadline, reconciliation marks the task blocked.
    public let dispatchStartGraceNanoseconds: UInt64
    /// How often Mission Control should be refreshed while work is running.
    public let heartbeatIntervalNanoseconds: UInt64
    /// A bounded silence window. Repeated missed heartbeats eventually become
    /// an explicit blocker instead of leaving the task apparently idle.
    public let maximumSilenceNanoseconds: UInt64

    public static let `default` = Self(
        dispatchStartGraceNanoseconds: 30_000_000_000,
        heartbeatIntervalNanoseconds: 10_000_000_000,
        maximumSilenceNanoseconds: 60_000_000_000
    )

    public init(
        dispatchStartGraceNanoseconds: UInt64,
        heartbeatIntervalNanoseconds: UInt64,
        maximumSilenceNanoseconds: UInt64
    ) {
        self.dispatchStartGraceNanoseconds = dispatchStartGraceNanoseconds
        self.heartbeatIntervalNanoseconds = heartbeatIntervalNanoseconds
        self.maximumSilenceNanoseconds = maximumSilenceNanoseconds
    }

    fileprivate func validate() throws {
        guard dispatchStartGraceNanoseconds > 0,
              heartbeatIntervalNanoseconds > 0,
              maximumSilenceNanoseconds >= heartbeatIntervalNanoseconds else {
            throw HarnessTaskLifecycleError.invalidPolicy
        }
    }
}

public nonisolated struct HarnessTaskLifecycleSnapshot: Codable, Equatable, Sendable {
    public let taskID: String
    public let state: HarnessTaskLifecycleState
    public let sequence: UInt64
    public let dispatchedAt: HarnessMonotonicTime
    public let lastTransitionAt: HarnessMonotonicTime
    public let lastProgressAt: HarnessMonotonicTime?
    public let nextHeartbeatAt: HarnessMonotonicTime?
    public let missedHeartbeats: UInt64
    /// A reader blocker or terminal explanation. It is always bounded and is
    /// safe to expose to status consumers because callers provide only a
    /// scrubbed, user-facing sentence.
    public let statusMessage: String?

    public var terminalReason: String? { state.isTerminal ? statusMessage : nil }
}

/// Small value state machine for task dispatch and Mission Control updates.
/// Hosts can call `reconcile(at:)` from a bounded timer or heartbeat loop. A
/// missed update becomes either `.heartbeatDue` or an explicit `.blocked`
/// action; it never silently becomes idle.
public nonisolated struct HarnessTaskLifecycle: Sendable {
    public let policy: HarnessTaskLifecyclePolicy
    public private(set) var snapshot: HarnessTaskLifecycleSnapshot

    public init(
        taskID: String,
        dispatchedAt: HarnessMonotonicTime,
        policy: HarnessTaskLifecyclePolicy = .default
    ) throws {
        let trimmed = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 256,
              !taskID.unicodeScalars.contains(where: {
                  $0.value < 0x20 || $0.value == 0x7F
              }) else {
            throw HarnessTaskLifecycleError.invalidTaskID
        }
        try policy.validate()
        let nextHeartbeat = try Self.add(
            dispatchedAt,
            policy.dispatchStartGraceNanoseconds
        )
        self.policy = policy
        self.snapshot = HarnessTaskLifecycleSnapshot(
            taskID: taskID,
            state: .dispatched,
            sequence: 0,
            dispatchedAt: dispatchedAt,
            lastTransitionAt: dispatchedAt,
            lastProgressAt: nil,
            nextHeartbeatAt: nextHeartbeat,
            missedHeartbeats: 0,
            statusMessage: "Task dispatched; waiting for a start checkpoint."
        )
    }

    public var isTerminal: Bool { snapshot.state.isTerminal }

    public mutating func markStarted(at timestamp: HarnessMonotonicTime) throws {
        try markProgress(at: timestamp, transitionFromDispatch: true)
    }

    /// Records a live progress checkpoint. A first heartbeat also acknowledges
    /// dispatch, so a worker does not need a separate start RPC.
    public mutating func heartbeat(at timestamp: HarnessMonotonicTime) throws {
        try markProgress(at: timestamp, transitionFromDispatch: true)
    }

    public mutating func markProgress(at timestamp: HarnessMonotonicTime) throws {
        try markProgress(at: timestamp, transitionFromDispatch: false)
    }

    public mutating func awaitReader(
        reason: String,
        at timestamp: HarnessMonotonicTime
    ) throws {
        try transition(to: .awaitingReader, reason: reason, at: timestamp)
        snapshot = Self.updated(snapshot, sequence: try nextSequence(),
            state: .awaitingReader,
            lastTransitionAt: timestamp, lastProgressAt: timestamp,
            nextHeartbeatAt: nil, missedHeartbeats: 0, statusMessage: reason)
    }

    public mutating func complete(
        reason: String? = nil,
        at timestamp: HarnessMonotonicTime
    ) throws {
        try transition(to: .completed, reason: reason, at: timestamp)
        snapshot = Self.updated(snapshot, sequence: try nextSequence(),
            state: .completed,
            lastTransitionAt: timestamp, lastProgressAt: timestamp,
            nextHeartbeatAt: nil, statusMessage: reason ?? "Task completed.")
    }

    public mutating func fail(
        reason: String,
        at timestamp: HarnessMonotonicTime
    ) throws {
        try transition(to: .failed, reason: reason, at: timestamp)
        snapshot = Self.updated(snapshot, sequence: try nextSequence(),
            state: .failed,
            lastTransitionAt: timestamp, lastProgressAt: snapshot.lastProgressAt,
            nextHeartbeatAt: nil, missedHeartbeats: snapshot.missedHeartbeats,
            statusMessage: reason)
    }

    public mutating func block(
        reason: String,
        at timestamp: HarnessMonotonicTime
    ) throws {
        try transition(to: .blocked, reason: reason, at: timestamp)
        snapshot = Self.updated(snapshot, sequence: try nextSequence(),
            state: .blocked,
            lastTransitionAt: timestamp, lastProgressAt: snapshot.lastProgressAt,
            nextHeartbeatAt: nil, missedHeartbeats: snapshot.missedHeartbeats,
            statusMessage: reason)
    }

    public mutating func cancel(
        reason: String? = nil,
        at timestamp: HarnessMonotonicTime
    ) throws {
        try transition(to: .cancelled, reason: reason, at: timestamp)
        snapshot = Self.updated(snapshot, sequence: try nextSequence(),
            state: .cancelled,
            lastTransitionAt: timestamp, lastProgressAt: snapshot.lastProgressAt,
            nextHeartbeatAt: nil, missedHeartbeats: snapshot.missedHeartbeats,
            statusMessage: reason ?? "Task cancelled.")
    }

    /// Reconcile a timer tick with the last acknowledged progress. Hosts can
    /// call this at most once per heartbeat interval. Startup silence blocks at
    /// the dispatch deadline; running silence blocks only after the larger
    /// maximum window has elapsed, with intermediate ticks requesting a
    /// heartbeat refresh.
    @discardableResult
    public mutating func reconcile(
        at timestamp: HarnessMonotonicTime
    ) throws -> HarnessTaskLifecycleAction {
        try validateTimestamp(timestamp)
        switch snapshot.state {
        case .completed, .failed, .blocked, .cancelled:
            return .none
        case .awaitingReader:
            return .awaitingReader
        case .dispatched:
            guard let deadline = snapshot.nextHeartbeatAt, timestamp >= deadline else {
                return .none
            }
            let reason = "Task was dispatched but did not report a start checkpoint."
            try block(reason: reason, at: timestamp)
            return .blocked(reason: reason)
        case .running:
            guard let next = snapshot.nextHeartbeatAt, timestamp >= next else {
                return .none
            }
            if let lastProgress = snapshot.lastProgressAt,
               timestamp.nanoseconds >= lastProgress.nanoseconds,
               timestamp.nanoseconds - lastProgress.nanoseconds >= policy.maximumSilenceNanoseconds {
                let reason = "Task stopped reporting progress within its allowed heartbeat window."
                try block(reason: reason, at: timestamp)
                return .blocked(reason: reason)
            }
            let sequence = try nextSequence()
            let missed = snapshot.missedHeartbeats == .max
                ? .max : snapshot.missedHeartbeats + 1
            let following = try Self.add(timestamp, policy.heartbeatIntervalNanoseconds)
            snapshot = Self.updated(snapshot, sequence: sequence,
                lastTransitionAt: timestamp, nextHeartbeatAt: following,
                missedHeartbeats: missed)
            return .heartbeatDue
        }
    }

    private mutating func markProgress(
        at timestamp: HarnessMonotonicTime,
        transitionFromDispatch: Bool
    ) throws {
        try validateTimestamp(timestamp)
        switch snapshot.state {
        case .dispatched where transitionFromDispatch:
            let sequence = try nextSequence()
            snapshot = Self.updated(snapshot, sequence: sequence, state: .running,
                lastTransitionAt: timestamp, lastProgressAt: timestamp,
                nextHeartbeatAt: try Self.add(
                    snapshot.dispatchedAt, policy.heartbeatIntervalNanoseconds
                ),
                missedHeartbeats: 0, statusMessage: "Task is running.")
        case .running:
            let sequence = try nextSequence()
            snapshot = Self.updated(snapshot, sequence: sequence,
                lastTransitionAt: timestamp, lastProgressAt: timestamp,
                nextHeartbeatAt: try Self.add(timestamp, policy.heartbeatIntervalNanoseconds),
                missedHeartbeats: 0, statusMessage: "Task is running.")
        case .dispatched:
            throw HarnessTaskLifecycleError.invalidTransition(from: .dispatched, to: .running)
        case .completed, .failed, .blocked, .cancelled:
            throw HarnessTaskLifecycleError.taskAlreadyTerminal(snapshot.state)
        default:
            throw HarnessTaskLifecycleError.invalidTransition(
                from: snapshot.state, to: .running
            )
        }
    }

    private mutating func transition(
        to nextState: HarnessTaskLifecycleState,
        reason: String?,
        at timestamp: HarnessMonotonicTime
    ) throws {
        try validateTimestamp(timestamp)
        guard !snapshot.state.isTerminal else {
            throw HarnessTaskLifecycleError.taskAlreadyTerminal(snapshot.state)
        }
        if [.failed, .blocked].contains(nextState) {
            guard let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HarnessTaskLifecycleError.emptyReason
            }
        }
    }

    private func validateTimestamp(_ timestamp: HarnessMonotonicTime) throws {
        guard timestamp >= snapshot.lastTransitionAt else {
            throw HarnessTaskLifecycleError.timestampWentBackwards
        }
    }

    private func nextSequence() throws -> UInt64 {
        guard snapshot.sequence < .max else { throw HarnessTaskLifecycleError.integerOverflow }
        return snapshot.sequence + 1
    }

    private static func add(
        _ timestamp: HarnessMonotonicTime,
        _ nanoseconds: UInt64
    ) throws -> HarnessMonotonicTime {
        let result = timestamp.nanoseconds.addingReportingOverflow(nanoseconds)
        guard !result.overflow else { throw HarnessTaskLifecycleError.integerOverflow }
        return HarnessMonotonicTime(nanoseconds: result.partialValue)
    }

    private static func updated(
        _ snapshot: HarnessTaskLifecycleSnapshot,
        sequence: UInt64,
        state: HarnessTaskLifecycleState? = nil,
        lastTransitionAt: HarnessMonotonicTime,
        lastProgressAt: HarnessMonotonicTime? = nil,
        nextHeartbeatAt: HarnessMonotonicTime? = nil,
        missedHeartbeats: UInt64? = nil,
        statusMessage: String? = nil
    ) -> HarnessTaskLifecycleSnapshot {
        HarnessTaskLifecycleSnapshot(
            taskID: snapshot.taskID,
            state: state ?? snapshot.state,
            sequence: sequence,
            dispatchedAt: snapshot.dispatchedAt,
            lastTransitionAt: lastTransitionAt,
            lastProgressAt: lastProgressAt ?? snapshot.lastProgressAt,
            nextHeartbeatAt: nextHeartbeatAt,
            missedHeartbeats: missedHeartbeats ?? snapshot.missedHeartbeats,
            statusMessage: statusMessage ?? snapshot.statusMessage
        )
    }
}

public nonisolated struct HarnessTaskStateLimits: Codable, Equatable, Sendable {
    public var maxJSONBytes: Int
    public var maxStringUTF8Bytes: Int
    public var maxNonGoalCount: Int
    public var maxAcceptanceCriteriaCount: Int
    public var maxQuestionCount: Int
    public var maxQuestionOptionsPerQuestion: Int
    public var maxMilestoneCount: Int
    public var maxDependenciesPerMilestone: Int
    public var maxModelAssumptionCount: Int
    public var maxUserDecisionCount: Int
    public var maxEvidenceCount: Int
    public var maxResolvedAcceptanceCount: Int
    public var maxProjectionBytes: Int

    public static let `default` = HarnessTaskStateLimits()

    public init(
        maxJSONBytes: Int = 64_000,
        maxStringUTF8Bytes: Int = 8_192,
        maxNonGoalCount: Int = 32,
        maxAcceptanceCriteriaCount: Int = 32,
        maxQuestionCount: Int = 9,
        maxQuestionOptionsPerQuestion: Int = 8,
        maxMilestoneCount: Int = 32,
        maxDependenciesPerMilestone: Int = 8,
        maxModelAssumptionCount: Int = 32,
        maxUserDecisionCount: Int = 32,
        maxEvidenceCount: Int = 128,
        maxResolvedAcceptanceCount: Int = 32,
        maxProjectionBytes: Int = 32_000
    ) {
        self.maxJSONBytes = maxJSONBytes
        self.maxStringUTF8Bytes = maxStringUTF8Bytes
        self.maxNonGoalCount = maxNonGoalCount
        self.maxAcceptanceCriteriaCount = maxAcceptanceCriteriaCount
        self.maxQuestionCount = maxQuestionCount
        self.maxQuestionOptionsPerQuestion = maxQuestionOptionsPerQuestion
        self.maxMilestoneCount = maxMilestoneCount
        self.maxDependenciesPerMilestone = maxDependenciesPerMilestone
        self.maxModelAssumptionCount = maxModelAssumptionCount
        self.maxUserDecisionCount = maxUserDecisionCount
        self.maxEvidenceCount = maxEvidenceCount
        self.maxResolvedAcceptanceCount = maxResolvedAcceptanceCount
        self.maxProjectionBytes = maxProjectionBytes
    }

    fileprivate func validate() throws {
        let values = [
            maxJSONBytes,
            maxStringUTF8Bytes,
            maxNonGoalCount,
            maxAcceptanceCriteriaCount,
            maxQuestionCount,
            maxQuestionOptionsPerQuestion,
            maxMilestoneCount,
            maxDependenciesPerMilestone,
            maxModelAssumptionCount,
            maxUserDecisionCount,
            maxEvidenceCount,
            maxResolvedAcceptanceCount,
            maxProjectionBytes
        ]
        guard values.allSatisfy({ $0 > 0 }) else {
            throw HarnessTaskStateError.invalidLimits
        }
    }
}

public nonisolated enum HarnessTaskStateError: Error, Equatable, Sendable {
    case malformedJSON
    case rootMustBeObject
    case unknownField(path: String)
    case invalidLimits
    case oversizedRecord(actualBytes: Int, maximumBytes: Int)
    case emptyField(name: String)
    case fieldTooLong(name: String, actualBytes: Int, maximumBytes: Int)
    case invalidIdentifier(String)
    case tooManyItems(name: String, actualCount: Int, maximumCount: Int)
    case duplicateID(scope: String, id: String)
    case invalidReference(scope: String, id: String)
    case invalidQuestionOptionCount(questionID: String, actualCount: Int, maximumCount: Int)
    case cyclicMilestoneDependencies([String])
    case invalidRevision(String)
    case duplicateEvidence(revisionID: String, checkID: String)
    case staleEvidence(expectedRevisionID: String, actualRevisionID: String)
    case acceptanceCriterionNotFound(String)
    case evidenceNotFound(HarnessEvidenceKey)
    case evidenceDidNotPass(HarnessEvidenceKey)
    case invalidCorrection(String)
    case projectionOverflow(
        requiredBytes: Int,
        maximumBytes: Int,
        userDecisionIDs: [String],
        unresolvedAcceptanceCriterionIDs: [String]
    )
}

public nonisolated enum HarnessAcceptanceCriterionKind: String, Codable, Equatable, Sendable {
    case userObservable
    case implementationDetail
}

public nonisolated struct HarnessAcceptanceCriterion: Codable, Equatable, Sendable {
    public let id: String
    public let statement: String
    public let kind: HarnessAcceptanceCriterionKind

    public init(
        id: String,
        statement: String,
        kind: HarnessAcceptanceCriterionKind = .userObservable
    ) {
        self.id = id
        self.statement = statement
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.statement = try container.decode(String.self, forKey: .statement)
        // Briefs written before the kind field existed remain readable. New
        // planner output includes the field so the workflow can reject
        // implementation-only checks before they become a user contract.
        self.kind = try container.decodeIfPresent(
            HarnessAcceptanceCriterionKind.self,
            forKey: .kind
        ) ?? .userObservable
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case statement
        case kind
    }
}

public nonisolated struct HarnessQuestionOption: Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// The user-owned product decision represented by a targeted question.
///
/// This is intentionally optional so briefs written before the intake gate
/// gained typed topics remain readable. A topic is a routing hint for the
/// clarification policy, not user-facing copy and never a substitute for the
/// question's plain-language prompt.
public nonisolated enum HarnessClarificationTopic: String, Codable, Equatable, Sendable {
    case targetApp
    case destination
    case trigger
    case dataBoundary
    case successObservation
}

public nonisolated enum HarnessTargetedQuestionKind: String, Codable, Equatable, Sendable {
    case productChoice
    case implementationDetail
}

public nonisolated struct HarnessTargetedQuestion: Codable, Equatable, Sendable {
    public let id: String
    public let prompt: String
    public let options: [HarnessQuestionOption]
    public let kind: HarnessTargetedQuestionKind
    public let topic: HarnessClarificationTopic?

    public init(
        id: String,
        prompt: String,
        options: [HarnessQuestionOption] = [],
        kind: HarnessTargetedQuestionKind = .productChoice,
        topic: HarnessClarificationTopic? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.kind = kind
        self.topic = topic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.options = try container.decode([HarnessQuestionOption].self, forKey: .options)
        // Old fixture briefs omitted the kind. Treat those as the ordinary
        // product-choice shape; planner output is required to be explicit.
        self.kind = try container.decodeIfPresent(
            HarnessTargetedQuestionKind.self,
            forKey: .kind
        ) ?? .productChoice
        self.topic = try container.decodeIfPresent(
            HarnessClarificationTopic.self,
            forKey: .topic
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case options
        case kind
        case topic
    }
}

public nonisolated struct HarnessMilestone: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let dependencies: [String]

    public init(id: String, title: String, dependencies: [String] = []) {
        self.id = id
        self.title = title
        self.dependencies = dependencies
    }
}

public nonisolated struct HarnessModelAssumption: Codable, Equatable, Sendable {
    public let id: String
    public let statement: String

    public init(id: String, statement: String) {
        self.id = id
        self.statement = statement
    }
}

public nonisolated struct HarnessTaskBrief: Codable, Equatable, Sendable {
    public let userRequest: String
    public let desiredOutcome: String
    public let explicitNonGoals: [String]
    public let acceptanceCriteria: [HarnessAcceptanceCriterion]
    public let targetedQuestions: [HarnessTargetedQuestion]
    public let milestones: [HarnessMilestone]
    public let modelAssumptions: [HarnessModelAssumption]

    public init(
        userRequest: String,
        desiredOutcome: String,
        explicitNonGoals: [String] = [],
        acceptanceCriteria: [HarnessAcceptanceCriterion] = [],
        targetedQuestions: [HarnessTargetedQuestion] = [],
        milestones: [HarnessMilestone] = [],
        modelAssumptions: [HarnessModelAssumption] = []
    ) throws {
        self.userRequest = userRequest
        self.desiredOutcome = desiredOutcome
        self.explicitNonGoals = explicitNonGoals
        self.acceptanceCriteria = acceptanceCriteria
        self.targetedQuestions = targetedQuestions
        self.milestones = milestones
        self.modelAssumptions = modelAssumptions
        try HarnessTaskStateValidator.validate(self, limits: .default)
    }

    public func validated(using limits: HarnessTaskStateLimits = .default) throws {
        try HarnessTaskStateValidator.validate(self, limits: limits)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            userRequest: container.decode(String.self, forKey: .userRequest),
            desiredOutcome: container.decode(String.self, forKey: .desiredOutcome),
            explicitNonGoals: container.decode([String].self, forKey: .explicitNonGoals),
            acceptanceCriteria: container.decode([HarnessAcceptanceCriterion].self, forKey: .acceptanceCriteria),
            targetedQuestions: container.decode([HarnessTargetedQuestion].self, forKey: .targetedQuestions),
            milestones: container.decode([HarnessMilestone].self, forKey: .milestones),
            modelAssumptions: container.decode([HarnessModelAssumption].self, forKey: .modelAssumptions)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case userRequest
        case desiredOutcome
        case explicitNonGoals
        case acceptanceCriteria
        case targetedQuestions
        case milestones
        case modelAssumptions
    }

    fileprivate func replacingModelAssumptions(
        _ modelAssumptions: [HarnessModelAssumption]
    ) throws -> HarnessTaskBrief {
        try HarnessTaskBrief(
            userRequest: userRequest,
            desiredOutcome: desiredOutcome,
            explicitNonGoals: explicitNonGoals,
            acceptanceCriteria: acceptanceCriteria,
            targetedQuestions: targetedQuestions,
            milestones: milestones,
            modelAssumptions: modelAssumptions
        )
    }
}

public nonisolated enum HarnessUserDecisionKind: String, Codable, Equatable, Sendable {
    case answer
    case correction
}

public nonisolated struct HarnessUserDecision: Codable, Equatable, Sendable {
    public let id: String
    public let questionID: String?
    public let optionID: String?
    public let answer: String
    public let kind: HarnessUserDecisionKind

    public init(
        id: String,
        questionID: String? = nil,
        optionID: String? = nil,
        answer: String,
        kind: HarnessUserDecisionKind = .answer
    ) {
        self.id = id
        self.questionID = questionID
        self.optionID = optionID
        self.answer = answer
        self.kind = kind
    }
}

/// A reader-facing rendering of a product choice already recorded in the
/// active task contract. This is deliberately derived from the brief and its
/// decisions, rather than from model prose, so the plan cannot display a
/// stale generic alternative after the reader chose a concrete option.
public nonisolated struct HarnessSelectedDecision: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let question: String
    public let answer: String
    public let optionID: String?
    public let kind: HarnessUserDecisionKind

    public init(
        id: String,
        question: String,
        answer: String,
        optionID: String? = nil,
        kind: HarnessUserDecisionKind = .answer
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.optionID = optionID
        self.kind = kind
    }
}

public nonisolated struct HarnessEvidenceKey: Codable, Equatable, Hashable, Sendable {
    public let revisionID: String
    public let checkID: String

    public init(revisionID: String, checkID: String) {
        self.revisionID = revisionID
        self.checkID = checkID
    }
}

public nonisolated enum HarnessEvidenceResult: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case skipped
    case unavailable
}

public nonisolated struct HarnessEvidenceRecord: Codable, Equatable, Sendable {
    public let key: HarnessEvidenceKey
    public let result: HarnessEvidenceResult
    public let summary: String

    public init(key: HarnessEvidenceKey, result: HarnessEvidenceResult, summary: String = "") {
        self.key = key
        self.result = result
        self.summary = summary
    }
}

public nonisolated struct HarnessTaskState: Codable, Equatable, Sendable {
    public let brief: HarnessTaskBrief
    public let activeRevisionID: String
    public let userDecisions: [HarnessUserDecision]
    public let evidence: [HarnessEvidenceRecord]
    public let resolvedAcceptanceCriterionIDs: [String]

    public init(
        brief: HarnessTaskBrief,
        activeRevisionID: String,
        userDecisions: [HarnessUserDecision] = [],
        evidence: [HarnessEvidenceRecord] = [],
        resolvedAcceptanceCriterionIDs: [String] = []
    ) throws {
        self.brief = brief
        self.activeRevisionID = activeRevisionID
        self.userDecisions = userDecisions
        self.evidence = evidence
        self.resolvedAcceptanceCriterionIDs = resolvedAcceptanceCriterionIDs
        try HarnessTaskStateValidator.validate(self, limits: .default)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            brief: container.decode(HarnessTaskBrief.self, forKey: .brief),
            activeRevisionID: container.decode(String.self, forKey: .activeRevisionID),
            userDecisions: container.decode([HarnessUserDecision].self, forKey: .userDecisions),
            evidence: container.decode([HarnessEvidenceRecord].self, forKey: .evidence),
            resolvedAcceptanceCriterionIDs: container.decode(
                [String].self,
                forKey: .resolvedAcceptanceCriterionIDs
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case brief
        case activeRevisionID
        case userDecisions
        case evidence
        case resolvedAcceptanceCriterionIDs
    }

    public var modelAssumptions: [HarnessModelAssumption] {
        brief.modelAssumptions
    }

    public var currentEvidence: [HarnessEvidenceRecord] {
        evidence.filter { $0.key.revisionID == activeRevisionID }
    }

    public var unresolvedAcceptanceCriteria: [HarnessAcceptanceCriterion] {
        let resolved = Set(resolvedAcceptanceCriterionIDs)
        return brief.acceptanceCriteria.filter { !resolved.contains($0.id) }
    }

    public func applyingUserDecision(_ decision: HarnessUserDecision) throws -> HarnessTaskState {
        try HarnessTaskStateValidator.validate(decision: decision, brief: brief, limits: .default)
        var updatedDecisions = userDecisions
        if let index = updatedDecisions.firstIndex(where: { $0.id == decision.id }) {
            updatedDecisions[index] = decision
        } else {
            updatedDecisions.append(decision)
        }
        return try HarnessTaskState(
            brief: brief,
            activeRevisionID: activeRevisionID,
            userDecisions: updatedDecisions,
            evidence: evidence,
            resolvedAcceptanceCriterionIDs: resolvedAcceptanceCriterionIDs
        )
    }

    public func applyingUserCorrection(
        _ correction: HarnessUserDecision,
        advancingTo revisionID: String
    ) throws -> HarnessTaskState {
        guard correction.kind == .correction else {
            throw HarnessTaskStateError.invalidCorrection(correction.id)
        }
        let revisedState = try advancingRevision(to: revisionID)
        return try revisedState.applyingUserDecision(correction)
    }

    public func applyingModelAssumption(
        _ assumption: HarnessModelAssumption
    ) throws -> HarnessTaskState {
        var updatedAssumptions = brief.modelAssumptions
        if let index = updatedAssumptions.firstIndex(where: { $0.id == assumption.id }) {
            updatedAssumptions[index] = assumption
        } else {
            updatedAssumptions.append(assumption)
        }
        let updatedBrief = try brief.replacingModelAssumptions(updatedAssumptions)
        return try HarnessTaskState(
            brief: updatedBrief,
            activeRevisionID: activeRevisionID,
            userDecisions: userDecisions,
            evidence: evidence,
            resolvedAcceptanceCriterionIDs: resolvedAcceptanceCriterionIDs
        )
    }

    public func recordingEvidence(_ record: HarnessEvidenceRecord) throws -> HarnessTaskState {
        guard record.key.revisionID == activeRevisionID else {
            throw HarnessTaskStateError.staleEvidence(
                expectedRevisionID: activeRevisionID,
                actualRevisionID: record.key.revisionID
            )
        }
        guard !evidence.contains(where: { $0.key == record.key }) else {
            throw HarnessTaskStateError.duplicateEvidence(
                revisionID: record.key.revisionID,
                checkID: record.key.checkID
            )
        }
        var updatedEvidence = evidence
        updatedEvidence.append(record)
        return try HarnessTaskState(
            brief: brief,
            activeRevisionID: activeRevisionID,
            userDecisions: userDecisions,
            evidence: updatedEvidence,
            resolvedAcceptanceCriterionIDs: resolvedAcceptanceCriterionIDs
        )
    }

    public func advancingRevision(to revisionID: String) throws -> HarnessTaskState {
        try HarnessTaskStateValidator.validateIdentifier(revisionID, scope: "revision")
        guard revisionID != activeRevisionID else {
            throw HarnessTaskStateError.invalidRevision(revisionID)
        }
        return try HarnessTaskState(
            brief: brief,
            activeRevisionID: revisionID,
            userDecisions: userDecisions,
            evidence: evidence,
            resolvedAcceptanceCriterionIDs: []
        )
    }

    public func resolvingAcceptanceCriterion(
        _ criterionID: String,
        using evidenceKey: HarnessEvidenceKey
    ) throws -> HarnessTaskState {
        guard brief.acceptanceCriteria.contains(where: { $0.id == criterionID }) else {
            throw HarnessTaskStateError.acceptanceCriterionNotFound(criterionID)
        }
        guard evidenceKey.revisionID == activeRevisionID else {
            throw HarnessTaskStateError.staleEvidence(
                expectedRevisionID: activeRevisionID,
                actualRevisionID: evidenceKey.revisionID
            )
        }
        guard let record = evidence.first(where: { $0.key == evidenceKey }) else {
            throw HarnessTaskStateError.evidenceNotFound(evidenceKey)
        }
        guard record.result == .passed else {
            throw HarnessTaskStateError.evidenceDidNotPass(evidenceKey)
        }
        guard !resolvedAcceptanceCriterionIDs.contains(criterionID) else {
            return self
        }
        var updatedIDs = resolvedAcceptanceCriterionIDs
        updatedIDs.append(criterionID)
        return try HarnessTaskState(
            brief: brief,
            activeRevisionID: activeRevisionID,
            userDecisions: userDecisions,
            evidence: evidence,
            resolvedAcceptanceCriterionIDs: updatedIDs
        )
    }
}

/// The durable, pre-execution portion of a feature contract. A recovery record
/// may carry this projection so a held candidate can be independently reviewed
/// after relaunch without asking the planner to recreate the user's decisions.
/// Evidence and model conversation remain run-local and are intentionally not
/// persisted here.
nonisolated struct HarnessSavedFeatureContract: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumEncodedBytes = 32_000

    let version: Int
    let brief: HarnessTaskBrief
    let activeRevisionID: String
    let userDecisions: [HarnessUserDecision]
    let resolvedAcceptanceCriterionIDs: [String]
    let candidateBindingDigest: String

    init(state: HarnessTaskState, candidateBindingDigest: String) throws {
        self.version = Self.currentVersion
        self.brief = state.brief
        self.activeRevisionID = state.activeRevisionID
        self.userDecisions = state.userDecisions
        self.resolvedAcceptanceCriterionIDs = state.resolvedAcceptanceCriterionIDs
        self.candidateBindingDigest = candidateBindingDigest
        try validate()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.brief = try container.decode(HarnessTaskBrief.self, forKey: .brief)
        self.activeRevisionID = try container.decode(String.self, forKey: .activeRevisionID)
        self.userDecisions = try container.decode([HarnessUserDecision].self, forKey: .userDecisions)
        self.resolvedAcceptanceCriterionIDs = try container.decode(
            [String].self, forKey: .resolvedAcceptanceCriterionIDs
        )
        self.candidateBindingDigest = try container.decode(String.self, forKey: .candidateBindingDigest)
        guard Set(container.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.stringValue)) else {
            throw HarnessTaskStateError.malformedJSON
        }
        try validate()
    }

    func restoredState() throws -> HarnessTaskState {
        try HarnessTaskState(
            brief: brief,
            activeRevisionID: activeRevisionID,
            userDecisions: userDecisions,
            evidence: [],
            resolvedAcceptanceCriterionIDs: resolvedAcceptanceCriterionIDs
        )
    }

    /// Compare a persisted contract with the already-captured candidate digest.
    /// Keeping this boundary to stable data lets the standalone harness target
    /// validate contracts without importing the app-only Git recovery type.
    func isBound(toCandidateDigest candidateBindingDigest: String, request: String) -> Bool {
        brief.userRequest == request && self.candidateBindingDigest == candidateBindingDigest
    }

    private func validate() throws {
        guard version == Self.currentVersion,
              candidateBindingDigest.utf8.count == 64,
              candidateBindingDigest.allSatisfy({ $0.isHexDigit }),
              !activeRevisionID.isEmpty,
              activeRevisionID.utf8.count <= HarnessTaskStateLimits.default.maxStringUTF8Bytes,
              resolvedAcceptanceCriterionIDs.count <= HarnessTaskStateLimits.default.maxResolvedAcceptanceCount,
              Set(resolvedAcceptanceCriterionIDs).count == resolvedAcceptanceCriterionIDs.count else {
            throw HarnessTaskStateError.malformedJSON
        }
        _ = try restoredState()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else {
            throw HarnessTaskStateError.malformedJSON
        }
        guard data.count <= Self.maximumEncodedBytes else {
            throw HarnessTaskStateError.oversizedRecord(
                actualBytes: data.count, maximumBytes: Self.maximumEncodedBytes
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, brief, activeRevisionID, userDecisions
        case resolvedAcceptanceCriterionIDs, candidateBindingDigest
    }
}

public nonisolated enum HarnessTaskBriefParser {
    public static func parse(
        _ data: Data,
        limits: HarnessTaskStateLimits = .default
    ) throws -> HarnessTaskBrief {
        try limits.validate()
        guard data.count <= limits.maxJSONBytes else {
            throw HarnessTaskStateError.oversizedRecord(
                actualBytes: data.count,
                maximumBytes: limits.maxJSONBytes
            )
        }
        try HarnessTaskBriefParserSupport.validateStrictShape(data)
        let brief: HarnessTaskBrief
        do {
            brief = try JSONDecoder().decode(HarnessTaskBrief.self, from: data)
        } catch let error as HarnessTaskStateError {
            throw error
        } catch {
            throw HarnessTaskStateError.malformedJSON
        }
        try brief.validated(using: limits)
        return brief
    }

    public static func parse(
        _ json: String,
        limits: HarnessTaskStateLimits = .default
    ) throws -> HarnessTaskBrief {
        try parse(Data(json.utf8), limits: limits)
    }
}

public nonisolated struct HarnessContextProjection: Codable, Equatable, Sendable {
    public let revisionID: String
    public let userRequest: String
    public let desiredOutcome: String
    public let explicitNonGoals: [String]
    public let targetedQuestions: [HarnessTargetedQuestion]
    public let milestones: [HarnessMilestone]
    public let modelAssumptions: [HarnessModelAssumption]
    public let currentUserDecisions: [HarnessUserDecision]
    public let unresolvedAcceptanceCriteria: [HarnessAcceptanceCriterion]
    public let currentEvidence: [HarnessEvidenceRecord]
    public let encodedUTF8ByteCount: Int

    fileprivate init(
        revisionID: String,
        userRequest: String,
        desiredOutcome: String,
        explicitNonGoals: [String],
        targetedQuestions: [HarnessTargetedQuestion],
        milestones: [HarnessMilestone],
        modelAssumptions: [HarnessModelAssumption],
        currentUserDecisions: [HarnessUserDecision],
        unresolvedAcceptanceCriteria: [HarnessAcceptanceCriterion],
        currentEvidence: [HarnessEvidenceRecord],
        encodedUTF8ByteCount: Int
    ) {
        self.revisionID = revisionID
        self.userRequest = userRequest
        self.desiredOutcome = desiredOutcome
        self.explicitNonGoals = explicitNonGoals
        self.targetedQuestions = targetedQuestions
        self.milestones = milestones
        self.modelAssumptions = modelAssumptions
        self.currentUserDecisions = currentUserDecisions
        self.unresolvedAcceptanceCriteria = unresolvedAcceptanceCriteria
        self.currentEvidence = currentEvidence
        self.encodedUTF8ByteCount = encodedUTF8ByteCount
    }
}

public nonisolated struct HarnessContextProjectionOverflow: Codable, Equatable, Sendable {
    public let requiredBytes: Int
    public let maximumBytes: Int
    public let userDecisionIDs: [String]
    public let unresolvedAcceptanceCriterionIDs: [String]

    fileprivate init(
        requiredBytes: Int,
        maximumBytes: Int,
        userDecisionIDs: [String],
        unresolvedAcceptanceCriterionIDs: [String]
    ) {
        self.requiredBytes = requiredBytes
        self.maximumBytes = maximumBytes
        self.userDecisionIDs = userDecisionIDs
        self.unresolvedAcceptanceCriterionIDs = unresolvedAcceptanceCriterionIDs
    }
}

public nonisolated enum HarnessContextProjectionResult: Codable, Equatable, Sendable {
    case ready(HarnessContextProjection)
    case overflow(HarnessContextProjectionOverflow)

    private enum CodingKeys: String, CodingKey {
        case kind
        case projection
        case overflow
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ready(let projection):
            try container.encode("ready", forKey: .kind)
            try container.encode(projection, forKey: .projection)
        case .overflow(let overflow):
            try container.encode("overflow", forKey: .kind)
            try container.encode(overflow, forKey: .overflow)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "ready":
            self = .ready(try container.decode(HarnessContextProjection.self, forKey: .projection))
        case "overflow":
            self = .overflow(try container.decode(HarnessContextProjectionOverflow.self, forKey: .overflow))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown harness context projection result"
            )
        }
    }
}

public nonisolated enum HarnessContextProjector {
    /// Returns the current reader decisions in the question order shown by
    /// intake. Reading these recorded choices never creates a model request.
    public static func selectedDecisionSummaries(
        for state: HarnessTaskState
    ) -> [HarnessSelectedDecision] {
        var decisionsByQuestionID: [String: HarnessUserDecision] = [:]
        for decision in state.userDecisions {
            if let questionID = decision.questionID {
                decisionsByQuestionID[questionID] = decision
            }
        }
        return state.brief.targetedQuestions.compactMap { question in
            guard question.kind == .productChoice,
                  let decision = decisionsByQuestionID[question.id] else { return nil }
            return HarnessSelectedDecision(
                id: decision.id,
                question: question.prompt,
                answer: decision.answer,
                optionID: decision.optionID,
                kind: decision.kind
            )
        }
    }

    /// Option selection does not ask the planner to rewrite its conditional
    /// criteria. Keep each exact choice as a separate coverage obligation so
    /// broad pre-answer coverage cannot silently stand in for that choice.
    /// These are derived review IDs, not mutations of the user's saved brief.
    public static func verificationCriteria(for state: HarnessTaskState) throws -> [HarnessAcceptanceCriterion] {
        var criteria = state.brief.acceptanceCriteria
        var usedIDs = Set(criteria.map(\.id))
        for question in state.brief.targetedQuestions where question.kind == .productChoice {
            guard let decision = state.userDecisions.last(where: { $0.questionID == question.id }) else { continue }
            // Lossless question identity stays stable across answer order and
            // question reordering; a planner cannot impersonate this namespace.
            let identifier = "user-decision-" + Data(question.id.utf8).base64EncodedString()
            guard usedIDs.insert(identifier).inserted else {
                throw HarnessTaskStateError.duplicateID(scope: "verificationCriteria", id: identifier)
            }
            criteria.append(HarnessAcceptanceCriterion(id: identifier,
                statement: "Honor the user's exact choice for \(question.prompt) Answer: \(decision.answer)"))
        }
        return criteria
    }

    public static func project(
        _ state: HarnessTaskState,
        limits: HarnessTaskStateLimits = .default
    ) throws -> HarnessContextProjectionResult {
        try limits.validate()
        try HarnessTaskStateValidator.validate(state, limits: limits)

        let decisionCriteria = try verificationCriteria(for: state)
            .dropFirst(state.brief.acceptanceCriteria.count)
        let unresolvedAcceptanceCriteria = state.unresolvedAcceptanceCriteria + decisionCriteria
        let currentEvidence = state.currentEvidence
        let payload = HarnessContextProjectionPayload(
            revisionID: state.activeRevisionID,
            userRequest: state.brief.userRequest,
            desiredOutcome: state.brief.desiredOutcome,
            explicitNonGoals: state.brief.explicitNonGoals,
            targetedQuestions: state.brief.targetedQuestions,
            milestones: state.brief.milestones,
            modelAssumptions: state.brief.modelAssumptions,
            currentUserDecisions: state.userDecisions,
            unresolvedAcceptanceCriteria: unresolvedAcceptanceCriteria,
            currentEvidence: currentEvidence
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedPayload = try encoder.encode(payload)
        guard encodedPayload.count <= limits.maxProjectionBytes else {
            return .overflow(HarnessContextProjectionOverflow(
                requiredBytes: encodedPayload.count,
                maximumBytes: limits.maxProjectionBytes,
                userDecisionIDs: state.userDecisions.map(\.id),
                unresolvedAcceptanceCriterionIDs: unresolvedAcceptanceCriteria.map(\.id)
            ))
        }

        return .ready(HarnessContextProjection(
            revisionID: state.activeRevisionID,
            userRequest: state.brief.userRequest,
            desiredOutcome: state.brief.desiredOutcome,
            explicitNonGoals: state.brief.explicitNonGoals,
            targetedQuestions: state.brief.targetedQuestions,
            milestones: state.brief.milestones,
            modelAssumptions: state.brief.modelAssumptions,
            currentUserDecisions: state.userDecisions,
            unresolvedAcceptanceCriteria: unresolvedAcceptanceCriteria,
            currentEvidence: currentEvidence,
            encodedUTF8ByteCount: encodedPayload.count
        ))
    }
}

fileprivate nonisolated struct HarnessContextProjectionPayload: Codable, Sendable {
    let revisionID: String
    let userRequest: String
    let desiredOutcome: String
    let explicitNonGoals: [String]
    let targetedQuestions: [HarnessTargetedQuestion]
    let milestones: [HarnessMilestone]
    let modelAssumptions: [HarnessModelAssumption]
    let currentUserDecisions: [HarnessUserDecision]
    let unresolvedAcceptanceCriteria: [HarnessAcceptanceCriterion]
    let currentEvidence: [HarnessEvidenceRecord]
}

fileprivate nonisolated enum HarnessTaskBriefParserSupport {
    private static let rootKeys: Set<String> = [
        "userRequest",
        "desiredOutcome",
        "explicitNonGoals",
        "acceptanceCriteria",
        "targetedQuestions",
        "milestones",
        "modelAssumptions"
    ]
    private static let acceptanceKeys: Set<String> = ["id", "statement", "kind"]
    private static let questionKeys: Set<String> = ["id", "prompt", "options", "kind", "topic"]
    private static let optionKeys: Set<String> = ["id", "label"]
    private static let milestoneKeys: Set<String> = ["id", "title", "dependencies"]
    private static let assumptionKeys: Set<String> = ["id", "statement"]

    static func validateStrictShape(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw HarnessTaskStateError.malformedJSON
        }
        guard let root = object as? [String: Any] else {
            throw HarnessTaskStateError.rootMustBeObject
        }
        try validateKeys(root, allowed: rootKeys, path: "root")

        if let values = root["acceptanceCriteria"] as? [Any] {
            for (index, value) in values.enumerated() {
                if let object = value as? [String: Any] {
                    try validateKeys(object, allowed: acceptanceKeys, path: "acceptanceCriteria[\(index)]")
                }
            }
        }
        if let values = root["targetedQuestions"] as? [Any] {
            for (index, value) in values.enumerated() {
                guard let object = value as? [String: Any] else { continue }
                try validateKeys(object, allowed: questionKeys, path: "targetedQuestions[\(index)]")
                if let options = object["options"] as? [Any] {
                    for (optionIndex, option) in options.enumerated() {
                        if let optionObject = option as? [String: Any] {
                            try validateKeys(
                                optionObject,
                                allowed: optionKeys,
                                path: "targetedQuestions[\(index)].options[\(optionIndex)]"
                            )
                        }
                    }
                }
            }
        }
        if let values = root["milestones"] as? [Any] {
            for (index, value) in values.enumerated() {
                if let object = value as? [String: Any] {
                    try validateKeys(object, allowed: milestoneKeys, path: "milestones[\(index)]")
                }
            }
        }
        if let values = root["modelAssumptions"] as? [Any] {
            for (index, value) in values.enumerated() {
                if let object = value as? [String: Any] {
                    try validateKeys(object, allowed: assumptionKeys, path: "modelAssumptions[\(index)]")
                }
            }
        }
    }

    private static func validateKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        if let unexpectedKey = object.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw HarnessTaskStateError.unknownField(path: "\(path).\(unexpectedKey)")
        }
    }
}

fileprivate nonisolated enum HarnessTaskStateValidator {
    static func validate(
        _ brief: HarnessTaskBrief,
        limits: HarnessTaskStateLimits
    ) throws {
        try limits.validate()
        try validateString(brief.userRequest, name: "userRequest", limits: limits)
        try validateString(brief.desiredOutcome, name: "desiredOutcome", limits: limits)

        try validateCount(
            brief.explicitNonGoals.count,
            name: "explicitNonGoals",
            maximum: limits.maxNonGoalCount
        )
        for (index, nonGoal) in brief.explicitNonGoals.enumerated() {
            try validateString(nonGoal, name: "explicitNonGoals[\(index)]", limits: limits)
        }

        try validateUniqueIDs(
            brief.acceptanceCriteria.map(\.id),
            scope: "acceptanceCriteria",
            maximum: limits.maxAcceptanceCriteriaCount,
            limits: limits
        )
        for (index, criterion) in brief.acceptanceCriteria.enumerated() {
            try validateString(criterion.statement, name: "acceptanceCriteria[\(index)].statement", limits: limits)
        }

        try validateCount(
            brief.targetedQuestions.count,
            name: "targetedQuestions",
            maximum: limits.maxQuestionCount
        )
        try validateUniqueIDs(
            brief.targetedQuestions.map(\.id),
            scope: "targetedQuestions",
            maximum: limits.maxQuestionCount,
            limits: limits
        )
        for (index, question) in brief.targetedQuestions.enumerated() {
            try validateString(question.prompt, name: "targetedQuestions[\(index)].prompt", limits: limits)
            try validateCount(
                question.options.count,
                name: "targetedQuestions[\(index)].options",
                maximum: limits.maxQuestionOptionsPerQuestion
            )
            try validateUniqueIDs(
                question.options.map(\.id),
                scope: "targetedQuestions.\(question.id).options",
                maximum: limits.maxQuestionOptionsPerQuestion,
                limits: limits
            )
            for (optionIndex, option) in question.options.enumerated() {
                try validateString(option.label, name: "targetedQuestions[\(index)].options[\(optionIndex)].label", limits: limits)
            }
        }

        try validateCount(brief.milestones.count, name: "milestones", maximum: limits.maxMilestoneCount)
        try validateUniqueIDs(
            brief.milestones.map(\.id),
            scope: "milestones",
            maximum: limits.maxMilestoneCount,
            limits: limits
        )
        let milestoneIDs = Set(brief.milestones.map(\.id))
        for (index, milestone) in brief.milestones.enumerated() {
            try validateString(milestone.title, name: "milestones[\(index)].title", limits: limits)
            try validateCount(
                milestone.dependencies.count,
                name: "milestones[\(index)].dependencies",
                maximum: limits.maxDependenciesPerMilestone
            )
            var dependencyIDs = Set<String>()
            for dependency in milestone.dependencies {
                try validateIdentifier(dependency, scope: "milestone dependency")
                guard dependencyIDs.insert(dependency).inserted else {
                    throw HarnessTaskStateError.duplicateID(
                        scope: "milestones.\(milestone.id).dependencies",
                        id: dependency
                    )
                }
                guard milestoneIDs.contains(dependency) else {
                    throw HarnessTaskStateError.invalidReference(
                        scope: "milestones.\(milestone.id).dependencies",
                        id: dependency
                    )
                }
            }
        }
        try validateMilestoneAcyclic(brief.milestones)

        try validateUniqueIDs(
            brief.modelAssumptions.map(\.id),
            scope: "modelAssumptions",
            maximum: limits.maxModelAssumptionCount,
            limits: limits
        )
        for (index, assumption) in brief.modelAssumptions.enumerated() {
            try validateString(assumption.statement, name: "modelAssumptions[\(index)].statement", limits: limits)
        }
    }

    static func validate(
        _ state: HarnessTaskState,
        limits: HarnessTaskStateLimits
    ) throws {
        try validate(state.brief, limits: limits)
        try validateIdentifier(state.activeRevisionID, scope: "revision")

        try validateUniqueIDs(
            state.userDecisions.map(\.id),
            scope: "userDecisions",
            maximum: limits.maxUserDecisionCount,
            limits: limits
        )
        for decision in state.userDecisions {
            try validate(decision: decision, brief: state.brief, limits: limits)
        }

        try validateCount(state.evidence.count, name: "evidence", maximum: limits.maxEvidenceCount)
        var evidenceKeys = Set<HarnessEvidenceKey>()
        for record in state.evidence {
            try validateIdentifier(record.key.revisionID, scope: "evidence revision")
            try validateIdentifier(record.key.checkID, scope: "evidence check")
            try validateString(record.summary, name: "evidence summary", limits: limits, mayBeEmpty: true)
            guard evidenceKeys.insert(record.key).inserted else {
                throw HarnessTaskStateError.duplicateEvidence(
                    revisionID: record.key.revisionID,
                    checkID: record.key.checkID
                )
            }
        }

        try validateUniqueIDs(
            state.resolvedAcceptanceCriterionIDs,
            scope: "resolvedAcceptanceCriterionIDs",
            maximum: limits.maxResolvedAcceptanceCount,
            limits: limits
        )
        let acceptanceIDs = Set(state.brief.acceptanceCriteria.map(\.id))
        for criterionID in state.resolvedAcceptanceCriterionIDs {
            guard acceptanceIDs.contains(criterionID) else {
                throw HarnessTaskStateError.invalidReference(
                    scope: "resolvedAcceptanceCriterionIDs",
                    id: criterionID
                )
            }
        }
    }

    static func validate(
        decision: HarnessUserDecision,
        brief: HarnessTaskBrief,
        limits: HarnessTaskStateLimits
    ) throws {
        try validateIdentifier(decision.id, scope: "user decision")
        try validateString(decision.answer, name: "user decision answer", limits: limits)
        if let questionID = decision.questionID {
            try validateIdentifier(questionID, scope: "decision question")
            guard let question = brief.targetedQuestions.first(where: { $0.id == questionID }) else {
                throw HarnessTaskStateError.invalidReference(scope: "user decision question", id: questionID)
            }
            if let optionID = decision.optionID {
                try validateIdentifier(optionID, scope: "decision option")
                guard question.options.contains(where: { $0.id == optionID }) else {
                    throw HarnessTaskStateError.invalidReference(scope: "decision option", id: optionID)
                }
            }
        } else if let optionID = decision.optionID {
            throw HarnessTaskStateError.invalidReference(scope: "decision option without question", id: optionID)
        }
    }

    static func validateIdentifier(_ identifier: String, scope: String) throws {
        guard !identifier.isEmpty,
              identifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              identifier.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw HarnessTaskStateError.invalidIdentifier(identifier.isEmpty ? scope : identifier)
        }
        guard identifier.utf8.count <= HarnessTaskStateLimits.default.maxStringUTF8Bytes else {
            throw HarnessTaskStateError.fieldTooLong(
                name: scope,
                actualBytes: identifier.utf8.count,
                maximumBytes: HarnessTaskStateLimits.default.maxStringUTF8Bytes
            )
        }
    }

    private static func validateUniqueIDs(
        _ identifiers: [String],
        scope: String,
        maximum: Int,
        limits: HarnessTaskStateLimits
    ) throws {
        try validateCount(identifiers.count, name: scope, maximum: maximum)
        var seen = Set<String>()
        for identifier in identifiers {
            try validateIdentifier(identifier, scope: scope)
            if !seen.insert(identifier).inserted {
                throw HarnessTaskStateError.duplicateID(scope: scope, id: identifier)
            }
            if identifier.utf8.count > limits.maxStringUTF8Bytes {
                throw HarnessTaskStateError.fieldTooLong(
                    name: scope,
                    actualBytes: identifier.utf8.count,
                    maximumBytes: limits.maxStringUTF8Bytes
                )
            }
        }
    }

    private static func validateCount(_ count: Int, name: String, maximum: Int) throws {
        guard count <= maximum else {
            throw HarnessTaskStateError.tooManyItems(name: name, actualCount: count, maximumCount: maximum)
        }
    }

    private static func validateString(
        _ value: String,
        name: String,
        limits: HarnessTaskStateLimits,
        mayBeEmpty: Bool = false
    ) throws {
        if !mayBeEmpty && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HarnessTaskStateError.emptyField(name: name)
        }
        guard value.utf8.count <= limits.maxStringUTF8Bytes else {
            throw HarnessTaskStateError.fieldTooLong(
                name: name,
                actualBytes: value.utf8.count,
                maximumBytes: limits.maxStringUTF8Bytes
            )
        }
    }

    private static func validateMilestoneAcyclic(_ milestones: [HarnessMilestone]) throws {
        let dependencies = Dictionary(uniqueKeysWithValues: milestones.map { ($0.id, $0.dependencies) })
        var complete = Set<String>()
        var stack = [String]()

        func visit(_ milestoneID: String) throws {
            if let cycleStart = stack.firstIndex(of: milestoneID) {
                throw HarnessTaskStateError.cyclicMilestoneDependencies(
                    Array(stack[cycleStart...]) + [milestoneID]
                )
            }
            guard !complete.contains(milestoneID) else { return }
            stack.append(milestoneID)
            for dependency in dependencies[milestoneID] ?? [] {
                try visit(dependency)
            }
            _ = stack.popLast()
            complete.insert(milestoneID)
        }

        for milestone in milestones {
            try visit(milestone.id)
        }
    }
}
