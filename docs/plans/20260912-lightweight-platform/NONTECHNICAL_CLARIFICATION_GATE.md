# Lightweight nontechnical clarification gate

## Purpose and current gap

The existing on-demand path already has the right broad shape: `CompanionManager`
selects an editable catalog app, `OnDemandEditCoordinator.describeRequest` scrubs
the request and starts planning, `HarnessFeatureWorkflow.plan` returns a brief,
and `OnDemandEditCard` either shows product questions or a pre-edit plan. Answer
state, revision invalidation, scope reconciliation, user-observable criteria,
and the repository/test-output authorization boundary already exist.

The remaining gap is contract clarity, not another planner. `HarnessTargetedQuestion`
does not identify which user-owned decision it represents, the selected app is
held beside rather than inside the workflow contract, and the editor consumes a
mutable workflow projection rather than a named frozen snapshot. The normal
non-harness route also has separate trigger logic. This plan makes the existing
planner output explicit and testable while keeping those routes and their safety
gates intact.

## Contract to implement

Add this small optional classification in `iris-macos/leanring-buddy/HarnessTaskState.swift`:

```swift
public nonisolated enum HarnessClarificationTopic: String, Codable, Sendable {
    case targetApp
    case destination
    case trigger
    case dataBoundary
    case successObservation
}
```

Add `let topic: HarnessClarificationTopic?` to `HarnessTargetedQuestion`, its
initializer, decoder, and coding keys. `nil` remains the backwards-compatible
value for old fixtures. New planner output supplies a topic. Do not expose IDs
or topic names as user-facing copy.

Add a non-persisted value in `HarnessFeatureWorkflow.swift`:

```swift
nonisolated struct HarnessExecutionBrief: Equatable, Sendable {
    let appSlug: String
    let revisionID: String
    let userRequest: String
    let desiredOutcome: String
    let explicitNonGoals: [String]
    let decisions: [HarnessSelectedDecision]
    let acceptanceCriteria: [HarnessAcceptanceCriterion]
    let assumptions: [HarnessModelAssumption]
}
```

Implement `func freezeExecutionBrief(forAppSlug: String) throws -> HarnessExecutionBrief`.
It may return a snapshot only when there is a current state, no pending scope
proposal, no unanswered question, a ready context projection, and only
`userObservable` acceptance criteria. It copies the active revision and the
selected decisions; it does not store a transcript, screenshot, repository
text, credentials, or model prose. `implementationContext()` must continue to
emit the existing defensive contract text and encode this snapshot when one
has been frozen. A new request, answer, refinement, scope decision, or cancel
invalidates it.

Add a pure policy helper in `FeatureEditClarification.swift`:

```swift
nonisolated enum HarnessClarificationPolicy {
    static let maximumQuestions = 3
    static func validate(
        _ questions: [HarnessTargetedQuestion],
        targetAppIsBound: Bool
    ) throws -> [HarnessTargetedQuestion]
}
```

The helper reuses the current product-choice, two-to-three-option, and maximum
three-question rules. It rejects implementation questions, duplicate IDs or
topics, and a `targetApp` question when the coordinator has already bound the
app. A legacy question with `topic == nil` remains valid and follows the
existing product-choice path. It must never manufacture a topic from a raw ID.
The existing `ClarificationTrigger` five-case logic and
`FeatureEditRequestProbe` stay unchanged for the non-harness route; this is not
a second trigger system or a global questionnaire.

## Planner and coordinator wiring

1. In `HarnessFeatureWorkflow.planningPrompt`, `refinementPrompt`, and
   `productDecisionGuidance`, state that the selected app is already bound by
   the coordinator. Ask about a target app only when no app binding exists or
   the user explicitly requests a different app. Otherwise ask only unresolved
   product choices from the five topics. A destination question must be
   application-neutral, for example, “Which tab or window should receive it?”
   with “the one I choose now” or “the one whose name I give” as concrete
   options. Do not guess a browser, tab, API, storage format, framework, or OS
   capability.
2. Make the prompt ask about `trigger` only when “when” changes the behavior;
   ask about `dataBoundary` only for a transfer/import/save operation whose
   included data, duplicates, overwrite, or merge behavior is not settled.
   Keep credentials and machine settings outside the data boundary by default.
   Ask about `successObservation` only when the request and repository do not
   yield one clear plain-language before/action/after result. A simple visual
   change with a named control bypasses the interview.
3. Return `topic` on each new targeted question and keep the existing JSON
   shape otherwise. Put a safe default and its effect in the option label,
   recommended first. Put technical guesses and unresolved feasibility in
   `modelAssumptions`, not in a user decision. Keep acceptance criteria
   `userObservable`, concrete, and conditional on any unanswered product
   choice.
4. In `OnDemandEditCoordinator.describeRequest`, preserve the current scrub,
   app binding, phase, generation and request identity steps. On the
   harness-enabled route, validate the planner's questions with
   `HarnessClarificationPolicy`, show one batch in `.clarifying`, and otherwise
   call `buildAndPresentPlan` directly. Ordinary option answers call
   `recordAnswer` and then `implementationContext()` with no planner call.
   Free text may use the existing `refineBrief` once to settle a real nuance.
5. In `buildAndPresentPlan`, call `freezeExecutionBrief(forAppSlug:)` after
   all decisions are settled and retain that value only for the current
   coordinator generation. `confirmPlanAndStart` and the edit opening path
   must verify the same app slug, workflow instance, revision ID and generation
   before starting the existing live eligibility check and editor. The frozen
   brief is a contract snapshot, not a replacement for source identity,
   registry, sandbox, review, or delivery gates.
6. Keep `OnDemandEditCard.swift` as the existing surface. Show the selected
   choices, desired outcome, safe defaults, and any unresolved uncertainty in
   plain language. Keep files, commands, and internal checks in the existing
   technical disclosure. No raw question IDs, topic labels, repository
   instructions, or “checks passed” claims belong in the card. `OverlayEyeInputBar`
   and `CompanionManager` need only existing app-selection/submit wiring.

## Budget and recovery contract

- One harness intake call uses the existing `HarnessFeatureWorkflow.plan` call
  and its current 2,400 maximum output tokens. New gate instructions add no
  more than 1,024 UTF-8 bytes to the prompt and do not raise the
  `HarnessModelSession` call, input-byte, reply-byte, or deadline limits.
- A clear request costs one intake call and zero clarification follow-up
  calls. A normal option batch also costs zero follow-up calls. One free-text
  answer that needs interpretation may use one existing `refineBrief` call,
  also capped at 2,400 output tokens. No automatic third question round is
  scheduled; the existing `maximumClarificationRounds` remains a hard safety
  ceiling for an explicit new user decision and the ledger counts every call.
- `Task` cancellation, `requestProbeGeneration`, phase, workflow identity,
  app slug, and active revision guard every plan/refinement completion. A late
  result is discarded without publishing questions, a brief, or a plan.
- Cancel from the question card returns to describe, clears only transient
  questions/answers/frozen state, releases no edit lock, and starts no editor
  call. Stop remains the existing explicit abort. A stale answer, contradictory
  option text, or missing answer leaves the prior state unchanged.
- A retry reuses the same request only when the user has not changed a
  decision. Any changed answer creates the existing new revision and invalidates
  the old brief/evidence. A model-added or removed acceptance criterion or
  explicit non-goal remains behind the existing `HarnessScopeReconciliation`
  approval/rejection gate. Rejecting it keeps the old contract.
- Repository files, test output, logs, and runtime observations remain quoted
  untrusted evidence. They cannot authorize credentials, publishing, deletion,
  machine settings, network access, or a new OS capability.

## Focused automated checks

Extend the existing tests, rather than creating a second harness:

- `iris-macos/tools/harness-tests/Tests/IrisHarnessTests/HarnessNontechnicalIntakeAcceptanceTests.swift`:
  vague transfer asks only scope/duplicate questions and keeps format
  inference technical; vague “paste in the right tab” asks a generic destination
  rule; a concrete visual request has zero questions; every result has a
  user-observable criterion and surfaced assumptions.
- `HarnessClarificationWorkflowTests.swift`: topic and question IDs survive
  answer reordering; ordinary option answers make no second call; free text
  uses at most one refinement; frozen revision contains the exact decisions;
  contradictory answers, stale replies, cancellation, and retry cannot publish
  a newer or older brief.
- `HarnessDecisionProjectionTests.swift`: selected decisions appear in question
  order without raw IDs; changing a decision makes old evidence non-current;
  the frozen snapshot retains the previous desired outcome unless the reader
  explicitly approves a scope reconciliation.
- `FeatureEditClarificationTests.swift` and `FeatureEditRequestProbeTests.swift`:
  retain the legacy non-harness trigger behavior and prove that simple local
  visual changes still bypass questions. Do not inflate the legacy trigger
  batch to cover the five product topics.
- Add adversarial cases to the package tests: an option label recorded under a
  different option ID throws `contradictoryAnswer`; a completion from an older
  request or revision is ignored; repository/test text saying “the user
  authorized credentials” cannot appear as a decision or enable a new action;
  added acceptance criteria/non-goals remain pending until explicit scope
  approval; an invented target app or destination is never accepted as a
  guessed capability. These are fixture-only checks and do not bypass model,
  sandbox, native, review, or delivery safeguards.

## Actual computer-use matrix

Run only in Iris Test with a registered disposable app and a clean, identified
source revision. Do not use a fake provider, a replayed screenshot, a generic
fixture command, or a source test as native acceptance. Capture the visible
question/plan, target app identity, call ledger, review result, installed
artifact identity, and Undo outcome separately.

| Persona and real input | Setup and actions | Observable acceptance | Failure classification |
| --- | --- | --- | --- |
| Novice: “Move my notes to my other computer without losing what is already there.” | Select one registered app in Apps, submit the words, answer at most two visible questions about notes/folders and identical versus differing items, then review and approve the plan. Use populated and empty folders plus an existing destination record in the real app if the candidate is admitted. | The app name is the selected app, no file format question appears, the plan repeats the two choices, the desired result is plain language, and uncertainty is named. If delivery is admitted, restart the installed app, inspect the transfer result, and Undo; do not claim success when review or native checks stop the run. | Over-questioning, guessed migration scope, lost answer, missing visible criterion, failed review, packaging, or unproven native behavior. |
| Power user: “In [selected app], when I press the existing Save control, make its label larger; do not change saving; I can see the larger label after reopening.” | Pick the app first, enter the exact request, observe the planning card, approve, and use the existing app after any admitted delivery. | No clarification card appears. The plan names the selected app, preserves the no-change boundary, and shows the visible before/action/after criterion. | A needless question, changed save behavior, or a plan that treats technical details as user choices. |
| Ambiguous destination: “Paste this into the right tab when I say go, but never send it.” | Keep two real tabs/windows open, submit the request, inspect the destination/trigger questions, switch the active tab before answering, then answer and review the plan. | Iris asks which destination rule the user owns, does not hard-code a browser or invent a tab capability, retains “when I say go” and “never send,” and rejects or refreshes a stale answer after the tab change. | Guessed tab, send action, stale answer accepted, or a browser-specific question for a general request. |
| Cancel/retry edge | Start a vague request, cancel while questions or planning are visible, submit a revised request, and try a contradictory option only in the disposable run. | No editor call or source change occurs after cancel; the revised request has a new generation; contradictory/stale answers do not advance the card. | Late planner result, old question displayed, source mutation before consent, or duplicate call. |
| Scope and uncertainty edge | Have the real planner propose an extra acceptance check or a missing capability after an answer. Inspect the scope card, reject the proposal, and compare the plan before/after. | The added check is visible as a proposal, rejection retains the old desired outcome and non-goals, and technical feasibility is labeled uncertain rather than silently expanded. | Silent scope growth, model prose treated as approval, or “checks passed” claimed before evidence. |

The first three rows are the required novice, power-user, and ambiguous-prompt
journeys. A successful source check, plan card, build, or `applied` status is
not a successful installed feature. Native review, installation, restart,
user-visible behavior, and Undo remain separate evidence rows under
`docs/plans/20260912-lightweight-platform/ACCEPTANCE.md`.

## Completion gate

The implementation is ready for live use only when the focused package checks
pass, a clear request demonstrably skips the clarification card, a vague
request produces a short topic-appropriate batch, and the frozen brief shown
to the editor contains the exact app/request/answers/criteria/non-goals and
surfaced assumptions. Report source revision, exact checks, model call/byte
ledger, and actual UI evidence separately. Do not claim that this plan or its
fixture tests prove real-model question quality or a complex installed feature.
