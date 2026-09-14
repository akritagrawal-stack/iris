# Iris power-user harness evaluation matrix

Frozen for the September 13, 2026 acceptance pass. This is a compact release
matrix for ordinary requests that cross the question, plan, evidence and cost
boundaries. It separates deterministic harness evidence from the native Iris
Test journey. A passing row below does not claim that an installed app, a live
provider, or a physical device accepted the behavior.

## Operating contract

- User-journey rows must use a plausible task a person would actually bring to
  Iris, with a concrete app, state, or desired outcome. Toy prompts such as
  arithmetic questions only exercise text entry and are excluded from
  acceptance evidence.
- Fixture rows use `HarnessModelSession` with local replies. They make no
  provider calls, do not read credentials, and do not start an edit.
- An ordinary option answer has no refinement call. A free-text answer may use
  one bounded refinement. Every call, retry, input byte and settled outcome is
  counted by the run ledger.
- Record the exact request, bound app, active revision, phase, attempt, elapsed
  time, input bytes, reported token families and outcome. Missing provider
  model, usage or price remains unknown.
- Native rows use one registered disposable Test app and one shared desktop
  owner. Capture only the question or plan gate needed for review. Do not use a
  source checkout, a launched clone, or a model statement as installed-app
  evidence.

## Matrix

| ID | Real-world input and setup | Deterministic oracle | Native acceptance gate | Current result and metric fields |
| --- | --- | --- | --- | --- |
| PU-01 | **Vague cross-surface:** “Whisper Flow paste to right tab.” Planner reply is valid but omits the destination rule. | The host reserves one `destination` choice, preserves the request exactly, blocks implementation while it is unanswered, and accepts the selected option without another call. Existing coverage: `HarnessNontechnicalIntakeAcceptanceTests` destination guard and novice intake cases. | Observe the actual question or plan card with two real tabs. Switch app, window or tab while Iris is thinking. The old target must not be chosen and paste must not send. | Package evidence is passing. Capture intake calls, clarification calls, input bytes, revision and unanswered IDs. Provider tokens and native card are currently unverified. |
| PU-02 | **Clear local bug:** “The Save button is broken after reopening; fix it without changing saving.” Known local app and recipe. | No destination interview, no optional ambiguity probe for the clear bug path, one bounded plan, and a user-visible before/action/after check. Existing coverage: `clearLocalFixDoesNotRequireAnIntakeInterview` and `FeatureEditRequestProbe` fast-path tests. | The plan is visible without a needless question, names the selected app, keeps saving as a no-change boundary, and waits for consent before any editor call. | Package evidence is passing. Measure planner versus optional-probe calls separately. Zero optional-probe calls are not proof of zero planner calls. Native plan and behavior remain unverified. |
| PU-03 | **Conflicting intent:** Start with “Paste into the right tab, but never send it,” then correct the outcome to “Send automatically after paste.” | The changed no-send criterion becomes a scope proposal. Implementation is blocked until explicit approval; rejecting it retains the original criterion and makes no editor call. Existing coverage: `HarnessClarificationWorkflowTests` scope reconciliation and contradictory-answer cases. | Show the changed check in plain language, reject it, and confirm the old plan remains active. No source or external action may occur at either gate. | Package evidence is passing. Record proposal ID, revision transition and editor-call count. Native scope card is unverified. |
| PU-04 | **Stale foreground or screen evidence:** Capture a target in one tab/window, then change foreground app, focused window, tab identity or display geometry. | `GuidePointingFreshness` rejects process, window and tab changes; geometry-only evidence is unavailable. Focused-window resolution is attempted once, bounded fallback is attempted once, and disabled model fallback makes no model call. Existing coverage: `SpatialGuidanceChecks.swift` and guide stale-work suites. | The old outline disappears, no click is synthesized, and a fresh request reacquires only the current semantic target. Missing AX or capture permission is shown as unavailable, not success. | Headless spatial evidence is passing. Native outline/reacquisition and screenshot bytes remain unverified. Record stale verdict, lookup/fallback counts and response time. |
| PU-05 | **Cancellation and retry:** Start planning, cancel while a reply is in flight, let a valid late reply arrive, then retry the same request. | The canceled ledger stays terminal, the late reply cannot publish a plan, and retry owns a new generation with one new physical call. Existing coverage: `HarnessModelSessionTests`, `OnDemandEditPlanningTests` and stale-plan workflow tests. | Cancel returns to the request surface without an editor call or source mutation. Retry shows only the new plan and does not duplicate work. | Headless evidence is passing. Record admitted and settled calls, retry count, late-result count, terminal reason and elapsed time. Native cancel/retry UI is unverified. |
| PU-06 | **Cost and accounting:** Simulate intake, repair/retry and a cancellation whose provider usage is late or absent. | Settled failed/canceled attempts remain accounted; input, cached, output and reasoning tokens stay separate; requested model is not provider identity; unknown usage or USD is rendered as unknown. Existing coverage: `CodexRunUsageAccountingTests` and `HarnessRunLedgerTests`. | If a live run is admitted, show the ledger receipt separately from the plan and outcome. Never infer a dollar amount from a model label or a subscription. | Deterministic accounting is passing. Record per-phase attempts, admitted/settled counts, input bytes, token families, requested/provider model and price status. Live provider accounting is unverified. |
| PU-07 | **Catalog search finding:** In Settings > Discover apps, search `Kneecap`. The public catalog has `slug/name = kneecap` and `guideSlug = kneecap`; its current guide is a mobile iOS build route. | Exact name/slug matching is case-insensitive. Deliberate search may find `.mobileOnly` entries with an honest phone-only label, while starter recommendations still exclude them. | On the refreshed current Test app, `Kneecap` was visible as `kneecap — Guide available`; the guide control then stated that marketplace installation belongs in regular Iris, so no commands or app replacement ran. | Native catalog discovery is accepted. The entry still does not label the mobile limitation, and the installed journey is intentionally unavailable in Iris Test; test neither proves nor attempts a marketplace installation. |
| PU-08 | **Typed question with Codex but no screen help:** “What is a USB-C cable?” followed by a screen-dependent request such as “Which Kneecap folder is open?” | A usable Codex login enables only a non-empty, unsized typed request. The route sends no screenshot, local files, terminal output, or claimed current-app facts; screen-dependent requests remain explicitly unavailable until screen help connects. Existing coverage: `CodexTextOnlyAskChecks.swift` plus `ComposerConnectionPresentationTests`. | In the freshly built Iris Test app, enter a safe typed question and observe Send enabled with “General questions through Codex.” Then verify the visible copy says to connect screen help for the current Mac or screen. Do not send a provider request merely to test button state. | Deterministic host evidence passes. A fresh Xcode Test app build and focused clarification suite completed, but the live UI run is blocked by stale debug-server sessions and a macOS nonresponsive-app alert; provider behavior remains unverified. |

## Metric record

For each run, keep one bounded record with:

`scenario ID`, exact request, target app identity, source/revision identity,
phase and attempt, admitted and settled calls, retry/cancel count, input bytes,
reported input/cache/output/reasoning tokens, requested and provider model,
price status, elapsed time, native screenshot path if any, and the final evidence
class (`deterministic`, `native`, `provider`, `installed`, `device`, or
`unknown`).

Do not aggregate an unknown field into zero. Report median and range for small
samples, and do not claim a percentile from a single run. The matrix is an
evaluation harness, not an authorization to broaden app targeting, run guide
commands, publish changes, or replace an installed app.
