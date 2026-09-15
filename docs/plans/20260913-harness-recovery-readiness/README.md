# Iris harness and recovery readiness plan

## Purpose

Make Iris reliable enough that user testing measures product capability rather
than setup, stale state, or recovery confusion. This is one integrated product
loop, not a collection of UI changes. Iris should turn a short request into a
safe, understandable plan; make the change only after consent; deliver a
runnable app; and provide an honest, one-action route back when the result is
not wanted.

The plan keeps the existing lightweight harness. It does not add a second
orchestrator, recursive agent delegation, hidden model retries, or new
background permissions.

## Release outcomes

| Outcome | What a nontechnical person experiences | Required system behavior |
| --- | --- | --- |
| Clear request shaping | "Make Whisper Flow paste into the right tab" gets one useful question only when it changes the result. | A deterministic profile reserves consequential gaps, one planner call produces at most three product questions, option answers stay local, and a frozen brief prevents stale execution. |
| Reliable change delivery | A completed edit becomes a runnable copy without the user interpreting build jargon. | Delivery records saved code, package, replacement, relaunch, and behavior as separate facts. A failed or uncertain stage offers an exact recovery action rather than a misleading success claim. |
| Trustworthy history | A person can undo a delivered edit without losing their work or guessing whether it worked. | Undo revalidates the exact target, receipt, artifact, and revision before every destructive stage; interrupted recovery stays visible and protected after restart. |
| Predictable real-world operation | Power users can change context mid-run, and new users do not need to understand tabs, repositories, or model routing. | Stale target, changed request, changed source, cancelled work, and ambiguous destination all block or re-ask before an editor acts. |
| Safe, measurable execution | The harness remains economical and resistant to untrusted project text. | Calls, input bytes, latency, output tokens, model, price, and stop reason are recorded. Unknown values remain unknown. Repository text never authorizes a sensitive action. |

## Product loop

```text
plain request + bound app
        -> deterministic intake profile
        -> one bounded planning response, only if needed
        -> concise choice or free-text refinement
        -> frozen execution brief + explicit Start
        -> existing edit and independent review
        -> delivery receipt with separate stage facts
        -> relaunch check or protected Undo/recovery
        -> retained evidence feeds the next evaluation run
```

This makes the interface feel simple because the system does the technical
translation behind one visible decision at a time. It should never ask the
user to choose a selector, framework, model API, shell command, or repository
path. It can ask where "the right tab" is, when that is genuinely undecidable.

## Delivery workstreams

### 1. Harness capability

The intake profile and frozen execution brief are the sole new control plane.
Wire the bound target identity into the frozen brief before treating it as a
complete stale-target defense. Keep the current one-planner-call rule and
reserve the existing review budget. For a simple local visual fix, skip
unnecessary questions. For cross-surface work, ask about destination, trigger,
data boundary, or observable success in that order of consequence.

Worker instructions: add deterministic edge cases to the package suite, keep
planner fixtures offline, and assert physical call accounting separately from
model content. Do not add a second planner or modify legacy clarification
behavior while evaluating the harness route.

### 2. Delivery and version history

Exercise a disposable registered Test project through save, build, delivery,
relaunch, reopen, Undo, and recovery cleanup. The acceptance test must prove
that Iris either completes each declared stage or plainly says which one did
not happen. It must not infer replacement from a build, restoration from a
receipt, or behavior from an opened process.

Worker instructions: use only isolated test roots and registered fixtures.
Retain the original receipt and branch after Undo. Test stale or superseded
candidates, failed package declarations, interrupted Undo, relaunch failure,
and repeat delivery. Keep normal Iris, normal profiles, and user apps outside
the test.

### 3. Real interaction acceptance

Use the Iris Test identity through the actual desktop surface, not synthetic
click coordinates. Capture an initial, in-progress, result, failure, and Undo
screen for each journey. Repeat the same scenarios as a nontechnical user and
a power user:

- A vague cross-app request with no named destination.
- A named destination, then a tab or window change while planning.
- A small clear fix with no needless question.
- A delivery that needs relaunch, followed by Undo.
- A cancellation or failed delivery that leaves a recoverable explanation.

The shared-desktop owner is the only worker that opens or manipulates native
windows. A screenshot demonstrates what was seen, not provider correctness or
device acceptance.

### 4. Defensive quality evaluation

Run only defensive testing against Iris-owned fixtures and code. Include
untrusted repository instructions, malformed receipts, stale callbacks,
oversized state, credential-like text, permission requests, and attempts to
make the harness silently widen scope. The success condition is a bounded,
explainable refusal or recovery action. No tests attempt to bypass platform,
provider, or account safeguards.

### 5. Evidence and release decision

Every lane records four distinct states: source or package result, native Test
result, installed-app result, and live-provider or device result. The release
candidate may advance when all deterministic and disposable native lanes pass,
with any unavailable provider, publishing, or physical-device proof marked as
pending rather than assumed complete.

## Evaluation matrix

Use the following recurring cases as a small realistic corpus, not a synthetic
click benchmark:

| Request shape | Expected behavior |
| --- | --- |
| "Fix the button color" | Small local route, no destination question, consent before edit. |
| "Make Whisper Flow paste into the right tab" | Complex route, destination question, no target guess, frozen current target before edit. |
| "Paste into Gmail, but never send" | Destination and non-send acceptance criteria are explicit. |
| "Make it work everywhere" | Scope is narrowed before planning or execution. |
| Change request updated while plan is visible | Existing plan becomes stale and cannot start. |
| Candidate replaced by a newer delivery | Old Saved Version cannot Undo the newer candidate. |
| Package lacks a macOS command | No runnable-copy claim, a clear next action, recovery retained. |
| Undo interrupted after replacement | Recovery details persist; completion is not claimed until reopening succeeds. |

For each case, collect pass or refusal result, user-visible explanation,
planner call count, refinement call count, execution cost fields, and the
strongest evidence tier reached.

## Completion bar

Iris is ready for meaningful capability testing when:

1. The deterministic matrix covers all listed request and recovery shapes and
   passes without live model calls.
2. A disposable native Test journey proves delivery, reopen, Undo, and
   protected failure behavior using actual application surfaces.
3. A shared-desktop pass captures nontechnical and power-user use without
   overlay clutter or stale-target execution.
4. Defensive fixtures show that unsafe, malformed, stale, and untrusted input
   stays bounded and explainable.
5. The release note lists residual live-provider, signing, marketplace, and
   device gates exactly as pending if they were not exercised.

