# Iris Harness Production Plan

## Product outcome

Iris should turn an everyday request into a safe, reviewable change to the
right app, then make the updated app usable without making the person learn
Git, build tooling, models, or macOS recovery. A successful run is not a
green command: it is a change in the intended app, an observable behavior
check, and a trustworthy way back if the result is wrong.

## One integrated flow

1. **Understand the request.** A local classifier recognizes a clear, small
   local bug and avoids a needless model call. For an ambiguous, cross-app, or
   feature request, Iris captures only consequential intent gaps: the thing to
   change, target app/surface, destination rule, trigger, data boundary, and
   what success looks like.
2. **Clarify in normal language.** Ask no more than three questions at once.
   Infer technical implementation details where possible; never invent a
   target, permission, data boundary, or side effect. A free-text answer can
   be summarized back for confirmation before it becomes execution authority.
3. **Plan and obtain consent.** Show the target, plain-language outcome,
   non-goals, verification, model route, and any elevated machine action.
   Editing begins only after the displayed plan is accepted.
4. **Build in an isolated clone.** Keep model context bounded, record the
   actual requested and confirmed model identity, measured calls/bytes/tokens
   when available, and maintain the existing independent review/verification
   ladder. Treat logs and model output as untrusted data.
5. **Deliver without lying.** A clone build may be launched for evaluation,
   but it is never presented as an installed update. Replacing an installed
   app requires an exact registered target, a retained backup, a durable
   receipt, and the required live consent. The receipt identity—not a path
   search—links delivery to recovery.
6. **Check behavior and recover.** After relaunch, Iris asks whether the
   original symptom is resolved. Undo is available only for a real installed
   replacement with matching backup and receipt; restore verifies bytes before
   swapping and reopening. Failed package, launch, or receipt steps leave the
   previous installed app unchanged and make the failure precise.

## Acceptance loop

The release gate is deliberately mixed; no single test type substitutes for
another.

| Lane | What it proves | Representative cases |
| --- | --- | --- |
| Deterministic source checks | Contract and regression behavior | intent routing, wrong target/stale evidence rejection, receipt identity, backup retention, redaction, command approvals |
| Disposable app journey | Actual screen-level behavior | vague Whisper Flow destination request, app/model selection, dirty-clone refusal, failed build, delivery/relaunch/Undo |
| Adversarial reliability | The harness refuses unsafe ambiguity | stale tab/window, source changed mid-run, duplicate receipt/app paths, malformed packaging recipes, cancelled/replaced requests |
| Defensive security | Inputs cannot silently broaden authority | prompt-injected logs/review output, secret redaction, command separator/allowlist bypass attempts, cross-app target mismatch |
| Cost and quality | The harness stays lightweight | zero model calls for clear small bugs; necessary-question precision; calls/bytes/tokens/time per completed flow; repair/review rate |

An item passes only at the level observed. Source checks do not prove installed
app behavior; a launched build does not prove replacement; an app replacement
does not prove a physical-device path; missing provider usage is unknown rather
than zero.

## Release scenarios

Freeze these as a compact, high-signal suite before broadening functionality:

1. **Whisper Flow to the right tab.** Iris asks for destination rule and
   success cue, rejects stale/wrong tab evidence, and never chooses a tab from
   geometry alone.
2. **Recurring sign-out.** Iris distinguishes restart/session/Keychain failure
   without logging credentials and gives a plain-language recovery action.
3. **Small local bug.** Iris retains the fast path, produces a reviewable plan,
   and does not spend an intake call merely to restate the request.
4. **Astro on macOS.** Iris reads the recipe, identifies a missing macOS
   package declaration honestly, and never labels a source checkout an install.
5. **Feature delivery and Undo.** On a registered disposable app, test clean
   delivery, exact receipt, replacement, restart, behavior check, Undo, and
   recovery after a deliberately failed build. Do not run this against a normal
   user app.

## Operating rule

Broaden capability by adding scenarios and evidence gates, not a parallel
orchestrator. Keep one workflow state machine, bounded context, durable
receipts, and a small number of meaningful questions. This is the path to
complex changes without turning everyday requests into a slow technical form.
