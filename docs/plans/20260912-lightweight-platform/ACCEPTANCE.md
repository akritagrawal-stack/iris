# Whole-product acceptance and measurement

These cases are declared before implementation to prevent adapting success to whatever the code happens to do. Use disposable Test data and name the exact fixture/app/build before every live run. The operator uses the actual product via computer use, reads the screen and records screenshots at meaningful transitions. Unit fixtures are deliberately controlled, but are not substitutes for these user journeys.

## J1: first-time install and help

Persona: someone who does not know Git or Xcode. Select Kneecap from a refreshed catalog, choose Mac+iPhone, start setup with the known dirty source present, follow the isolated-copy action, ask for help part way through, cancel and resume, and reach the real build/device prerequisite.

Pass: app/guide/source identity stays consistent, every executable step uses the intended root, original user copies remain unchanged, repeated clicks create no duplicate work, Ask is general help with optional guide context, and the UI gives the next action. A missing signing team or physical phone is a specific incomplete step, not installed success. For a real phone test continue through trusted device, build, install, launch and a real import/export workflow. Absence of phone access leaves that row unverified.

Counterexamples: four similarly named folders; dirty lockfile at correct pin; origin mismatch; `.git` file linked worktree; spaces and symlink paths; guide changes during setup; cancelled child still producing output; offline refresh; icon failure; missing commit; phone disconnect; trust/signing refusal. Observe source HEAD/diff and file hashes before/after separately from UI screenshots.

## J2: exact guidance while a person moves around

Persona: novice following the Xcode run-destination step, then power user switching windows/tabs while Iris thinks. Ask where to click, inspect the highlighted control, move the window, switch the browser tab or Xcode document, return, and ask again. Never use the real signing dropdown as an oracle unless the guide's intended action names that exact control.

Pass: the outline names and encloses the correct semantic control, clears stale answers, reacquires after navigation, never steals focus/clicks, and stays silent for sensitive/no-target steps. Missing AX or capture permission produces an actionable unavailable state. A confident highlight of the wrong target is a failed case regardless of pixel error.

Metrics: correct semantic highlights / attempts, wrong-target count, stale-answer rejections, AX lookup and fallback counts, response time, screenshot/model bytes, UI frame/CPU observations. First collect actual baselines; do not assert 100% universal accuracy or a 60fps/p95 claim from visual inspection. Test multi-display hardware only if present; keep simulated transforms labeled unit evidence.

## J3: update while working, retention and Undo

Persona: user with an open note and unsaved work requesting a feature. Select an existing accepted candidate; recheck without generating; deliver; use the feature; restart; inspect version history; Undo; reopen and verify newer notes remain. During a second disposable run cancel an over-budget cleanup, then explicitly clean eligible superseded fixtures and retry.

Pass: one installed app identity, user data and valid permissions preserved, truthful restart/unsaved-work behavior, exact saved-candidate revalidation, no LLM generation for lifecycle replay, working rollback protected, bounded owned payload storage, older pruned entries state that full Undo is unavailable. If macOS signing causes new permission prompts, report the exact cause and evidence instead of promising preserved grants. Do not clear data or reset global permission state to make a pass.

Counterexamples: interrupted swap/relaunch; stale accepted record; changed binary with same timestamp; missing Info.plist/helper; current app changed outside Iris; old pending recovery; corrupt record; alias/shared path; partially failed cleanup; disk full before second swap check; protected backups alone exceed cap. Cheap identity/recovery checks precede the actual native lifecycle.

## J4: one meaningful complex feature, measured end to end

Persona: a normal user asks for a transfer/export behavior spanning folders and existing content, with follow-up constraints. The final fixture request must be written and frozen before the model run using the existing previously failing transfer case, not invented after seeing an answer. Include folder ownership, duplicate names, empty and populated folders, nested content, cancel/retry and persistence. Independent oracle authors may read the requested behavior; the generating model may not see oracle/reference code.

Pass: useful requested behavior is demonstrated in the actual fixture UI, survives restart, and preserves unrelated work. Independent semantic checks pass. The same candidate is used for delivery/recovery checks. A simple search feature, generated tests alone, code build, or `appliedAndRebuilt` status does not establish complex-feature capability.

Record before spending: exact prompt, target project/source baseline, allowed files and side effects, admitted route/capabilities, effort, maximum attempts/calls/bytes/time and independent review reserve. On failure classify requirement loss, missing context, generation, review escape, environment/permission, packaging/delivery, or stale UI observation. Make one relevant correction before another expensive run. An unrelated permission failure cannot be presented as model-quality failure.

## J5: mobile installation discovery

Persona: user on a phone who expects to open or install Kneecap without learning a developer toolchain. Through the actual browser UI choose device and app, inspect available route, open the real destination if verified, or follow Setup needed. Switch device, refresh repeatedly, go offline and return.

Pass for hub prototype: honest route availability, concise next actions, no fabricated install button, accessible touch/keyboard navigation, bounded network/cache, and a clear difference between web preview and native app. Pass for native distribution requires a separate signed build on a physical phone, working first use and update/data continuity. A local hub screenshot or simulator launch is not that evidence.

## Measurement ledger

| Measure | Unit and provenance | Required distinction |
| --- | --- | --- |
| Development instructions | exact UTF-8 bytes and words before/after | not provider-token savings |
| Runtime use | provider input, cache, output and reasoning per physical call | requested vs returned model; subset fields vs extra fields; unknown stays unknown |
| Cost | verified model price revision times normalized supplied usage | estimate vs provider bill; include rejected/failed attempts |
| Efficiency outcome | all spend and elapsed per accepted complete user journey | report denominator and failures, not only winner |
| Storage | managed logical and allocated bytes; observed free-space difference | hardlinked/cloned data and user data are separate |
| Friction | required user actions, repeated prompts, restart, lost draft/view | unavoidable system action vs preventable app action |
| Spatial | semantic correctness, stale/ambiguous response, local and model calls | unavailable differs from wrong-target success |
| Mobile hub | static served bytes, request count, route result | prototype differs from signed native install |

Use median/range for small samples; leave p95 unclaimed until the sample supports it. Screenshots/logs are minimal, local and redacted for private data. No always-on usage tracking is introduced merely to measure the test.

## Completion and stopping rules

- Unit and integration checks must correspond to a real failure risk or user outcome, not source-text presence or implementation-mirroring assertions.
- Build the integrated native candidate once after related fixes pass, using GUI Xcode. Verify its Test identity/artifact before UI work.
- Only one agent owns foreground computer use. Others can run isolated local Git/Swift/Node checks or work in independent browser tabs.
- A pass stops that test family unless relevant code changes. Two occurrences of the same live failure require a causal trace/review before another paid attempt.
- External credentials, hardware or signing blockers hold only that acceptance row. Continue unaffected authorized work.
- Every handoff states changed, automatically verified, actual UI verified and unverified. Never promote a proposal, source test or historical success into current installed acceptance.
