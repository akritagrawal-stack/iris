import Foundation

/// Host-owned work-shape classification for the lightweight harness intake.
/// The planner may describe a brief, but it cannot select this route.
nonisolated enum HarnessTaskComplexity: String, Codable, Equatable, Sendable {
    case small
    case scoped
    case complex
    case highRisk
    case blocked
}

/// Deterministic metadata supplied to the planner before it writes a brief.
/// These values are routing facts, not model claims and not user-visible copy.
nonisolated struct HarnessIntakeProfile: Codable, Equatable, Sendable {
    static let currentRoutePolicyVersion = "iris.harness.intake.v1"
    static let currentPlannerOutputTokenCap = 2_400
    static let localControlSurface = "localControl"
    static let crossSurfaceTransferSurface = "crossSurfaceTransfer"

    let complexity: HarnessTaskComplexity
    let surface: String
    let reservedTopics: [HarnessClarificationTopic]
    let targetIsBound: Bool
    let plannerRequired: Bool
    let plannerOutputTokenCap: Int
    let routePolicyVersion: String

    init(
        complexity: HarnessTaskComplexity,
        surface: String,
        reservedTopics: [HarnessClarificationTopic],
        targetIsBound: Bool,
        plannerRequired: Bool,
        plannerOutputTokenCap: Int,
        routePolicyVersion: String
    ) {
        self.complexity = complexity
        self.surface = surface
        self.reservedTopics = reservedTopics
        self.targetIsBound = targetIsBound
        self.plannerRequired = plannerRequired
        self.plannerOutputTokenCap = plannerOutputTokenCap
        self.routePolicyVersion = routePolicyVersion
    }

    /// Builds a profile from the exact request and bounded host observations.
    /// The request is only inspected for routing signals and is never rewritten.
    static func classify(
        request: String,
        repositorySummary: String = "",
        targetAppIsBound: Bool = false,
        reservedTopics: [HarnessClarificationTopic]? = nil
    ) -> HarnessIntakeProfile {
        let topics = deduplicatedTopics(
            reservedTopics ?? requiredProductChoiceTopics(for: request)
        )
        let normalized = normalizedRequest(request)
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let wordSet = Set(words)

        let surface = inferredSurface(
            normalized: normalized,
            words: wordSet,
            reservedTopics: topics
        )
        let highRisk = hasHighRiskAction(normalized: normalized, words: words)
        let complex = hasComplexShape(
            normalized: normalized,
            words: wordSet,
            repositorySummary: repositorySummary,
            reservedTopics: topics
        )
        let blocked = !targetAppIsBound
            || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || repositorySummary.utf8.count > 32_000

        let complexity: HarnessTaskComplexity
        if blocked {
            complexity = .blocked
        } else if highRisk {
            complexity = .highRisk
        } else if complex {
            complexity = .complex
        } else if isClearLocalFix(normalized: normalized, words: wordSet),
                  !repositorySuggestsUnknownRecipe(repositorySummary) {
            complexity = .small
        } else {
            complexity = .scoped
        }

        return HarnessIntakeProfile(
            complexity: complexity,
            surface: surface,
            reservedTopics: topics,
            targetIsBound: targetAppIsBound,
            plannerRequired: complexity != .blocked,
            plannerOutputTokenCap: currentPlannerOutputTokenCap,
            routePolicyVersion: currentRoutePolicyVersion
        )
    }

    /// Label variant for callers that name the binding fact `targetIsBound`.
    static func classify(
        request: String,
        repositorySummary: String = "",
        targetIsBound: Bool,
        reservedTopics: [HarnessClarificationTopic]? = nil
    ) -> HarnessIntakeProfile {
        classify(
            request: request,
            repositorySummary: repositorySummary,
            targetAppIsBound: targetIsBound,
            reservedTopics: reservedTopics
        )
    }

    /// Construction spelling for host call sites that prefer a factory name.
    static func make(
        request: String,
        repositorySummary: String = "",
        targetAppIsBound: Bool = false,
        reservedTopics: [HarnessClarificationTopic]? = nil
    ) -> HarnessIntakeProfile {
        classify(
            request: request,
            repositorySummary: repositorySummary,
            targetAppIsBound: targetAppIsBound,
            reservedTopics: reservedTopics
        )
    }

    /// The existing planner guard remains the source of truth for this topic.
    /// Keeping the detector here lets direct profile tests and workflow metadata
    /// use the same deterministic result.
    static func requiredProductChoiceTopics(for request: String) -> [HarnessClarificationTopic] {
        requestNeedsDestinationChoice(request) ? [.destination] : []
    }

    /// Conservative lexical detection for movement requests whose destination
    /// behavior is not stated. It does not infer a target or implementation.
    static func requestNeedsDestinationChoice(_ request: String) -> Bool {
        let normalized = normalizedRequest(request)
        let transferIntentWords: Set<String> = [
            "paste", "type", "send", "insert", "move", "transfer", "open", "switch",
            "put", "write",
        ]
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let copyNeedsCrossSurfaceTarget: Bool = {
            guard let copyIndex = words.firstIndex(of: "copy") else { return false }
            guard copyIndex < words.index(before: words.endIndex) else { return false }
            for marker in ["into", "to", "in"] {
                guard let markerIndex = words[words.index(after: copyIndex)...]
                    .firstIndex(of: Substring(marker)) else {
                    continue
                }
                let suffix = words[words.index(after: markerIndex)...].prefix(3)
                if suffix.contains(where: {
                    ["tab", "window", "browser", "app", "screen", "page", "document"]
                        .contains(String($0))
                }) {
                    return true
                }
            }
            return false
        }()
        guard let transferIntentIndex = words.firstIndex(where: {
            transferIntentWords.contains(String($0))
        }) ?? (copyNeedsCrossSurfaceTarget ? words.firstIndex(of: "copy") : nil) else {
            return false
        }

        let explicitSelectionLanguage = [
            "current app", "this app", "selected app", "active app", "focused app",
            "current tab", "this tab", "selected tab", "active tab", "focused tab",
            "current window", "this window", "selected window", "active window", "focused window",
            "current note", "this note", "selected note", "active note",
            "choose the app", "choose a tab", "choose the tab", "specific app",
            "specific tab", "destination", "where i choose", "app i choose", "app i select",
            "tab i choose", "tab i select", "window i choose", "window i select",
        ]
        if explicitSelectionLanguage.contains(where: normalized.contains) { return false }

        let genericDestinationWords: Set<String> = [
            "the", "a", "an", "right", "correct", "proper", "appropriate",
            "target", "desired", "same", "another", "tab", "window", "app",
            "browser", "chat", "page", "document", "screen", "place", "location", "one", "it", "i", "my",
            "your", "this", "that", "choose", "select", "selected", "current",
            "active", "focused", "first", "next", "best", "matching", "to", "into",
        ]
        for marker in ["into", "to", "in"] {
            guard let markerIndex = words.firstIndex(of: Substring(marker)) else { continue }
            guard markerIndex > transferIntentIndex else { continue }
            let suffix = words.dropFirst(words.distance(
                from: words.startIndex, to: markerIndex
            ) + 1)
            if suffix.prefix(6).contains(where: {
                !genericDestinationWords.contains(String($0))
            }) {
                return false
            }
        }
        return true
    }

    private static func normalizedRequest(_ request: String) -> String {
        request.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func deduplicatedTopics(
        _ topics: [HarnessClarificationTopic]
    ) -> [HarnessClarificationTopic] {
        var seen = Set<HarnessClarificationTopic>()
        return topics.filter { seen.insert($0).inserted }
    }

    private static func inferredSurface(
        normalized: String,
        words: Set<String>,
        reservedTopics: [HarnessClarificationTopic]
    ) -> String {
        if reservedTopics.contains(.destination)
            || words.contains(where: [
                "paste", "transfer", "insert", "send", "move", "switch",
            ].contains)
            || normalized.contains("another computer")
            || normalized.contains("other computer")
            || normalized.contains("between apps")
            || normalized.contains("between tabs")
            || normalized.contains("external app") {
            return crossSurfaceTransferSurface
        }
        return localControlSurface
    }

    private static func hasHighRiskAction(normalized: String, words: [String]) -> Bool {
        let directRiskWords: Set<String> = [
            "send", "delete", "publish", "payment", "pay", "purchase", "charge",
            "credential", "credentials", "password", "token", "permission", "permissions",
            "authorize", "authorise", "revoke", "withdraw",
        ]
        if words.contains(where: directRiskWords.contains) {
            return true
        }
        let riskPhrases = [
            "screen recording", "microphone permission", "camera permission",
            "system settings", "cannot be undone", "can't be undone", "not reversible",
            "irreversible", "permanently", "permanent deletion", "without an undo",
            "without undo", "publish publicly", "external side effect",
        ]
        if riskPhrases.contains(where: normalized.contains) { return true }

        let destructiveWords: Set<String> = ["overwrite"]
        for word in destructiveWords where words.contains(word) {
            if !isNegated(word: word, in: words) { return true }
        }
        return false
    }

    private static func isNegated(word: String, in words: [String]) -> Bool {
        for index in words.indices where words[index] == word {
            let prior = words[..<index].suffix(3)
            if prior.contains(where: ["never", "not", "don't", "dont", "no"].contains) {
                continue
            }
            return false
        }
        return true
    }

    private static func hasComplexShape(
        normalized: String,
        words: Set<String>,
        repositorySummary: String,
        reservedTopics: [HarnessClarificationTopic]
    ) -> Bool {
        if reservedTopics.contains(.destination) { return true }
        if words.contains(where: [
            "transfer", "sync", "migrate", "migration", "import", "export", "backup", "restore",
            "persist", "persistence", "restart", "relaunch", "session", "sessions",
        ].contains) {
            return true
        }
        let multiSurfaceMarkers: Set<String> = [
            "tab", "window", "browser", "computer", "device", "screen", "document",
        ]
        if words.intersection(multiSurfaceMarkers).count > 1 { return true }
        if normalized.contains("another computer") || normalized.contains("other computer")
            || normalized.contains("across computers") || normalized.contains("across devices")
            || normalized.contains("multiple targets") || normalized.contains("more than one") {
            return true
        }
        return repositorySuggestsUnknownRecipe(repositorySummary)
    }

    private static func isClearLocalFix(normalized: String, words: Set<String>) -> Bool {
        let fixWords: Set<String> = [
            "fix", "bug", "repair", "typo", "larger", "smaller", "color", "colour",
            "spacing", "padding", "alignment", "label", "button", "font", "text",
            "visual", "style", "rename",
        ]
        return words.contains(where: fixWords.contains)
            && !normalized.contains("another app")
            && !normalized.contains("another computer")
    }

    private static func repositorySuggestsUnknownRecipe(_ summary: String) -> Bool {
        let normalized = normalizedRequest(summary)
        let unknownSignals = [
            "unknown", "not specified", "not supported", "unsupported", "missing",
            "no existing", "no implementation", "not implemented", "absent",
        ]
        return unknownSignals.contains(where: normalized.contains)
    }
}
