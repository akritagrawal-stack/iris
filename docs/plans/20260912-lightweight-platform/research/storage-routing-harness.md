# Iris low-bloat storage, routing, and harness review

**Scope:** read-only review of immutable Mann handoff `080ba93`. This plan targets Iris Test. It is not a release, model run, or claim that a complex feature works. Normal Iris and user data remain outside scope.

## Blocking design errors

1. **Critical: 2 GiB admission is not retention.** The current check measures managed backups plus the next snapshot and correctly refuses an over-budget swap, but it never reclaims. Successful installed deliveries intentionally accumulate, while cleanup intentionally excludes them. This becomes a safe permanent delivery stop, not a bounded version store. See [admission](https://github.com/akritagrawal-stack/iris/blob/080ba93f74de78d7d64ca8c5d92887546d384973/iris-macos/leanring-buddy/AppDeliveryReceiptStore.swift#L542-L602), [cleanup](https://github.com/akritagrawal-stack/iris/blob/080ba93f74de78d7d64ca8c5d92887546d384973/iris-macos/leanring-buddy/AppDeliveryReceiptStore.swift#L604-L717), and the recorded installed-backup growth regression.

2. **Critical: an accepted artifact lacks a reusable coordinator route.** PlantGPT `0db25ba…` and its matching artifact remain, but the registered checkout is at base and no current accepted-edit coordinator state binds the old branch to delivery. Calling it missing is false; treating it as replayable would skip registry, source, receipt, and revision gates. [`INTEGRATED_CANDIDATE.md`](https://github.com/akritagrawal-stack/iris/blob/080ba93f74de78d7d64ca8c5d92887546d384973/research/pr-review-20260912/INTEGRATED_CANDIDATE.md) records the distinction.

3. **High: installed, known-good, and UI-accepted are different.** Receipts model prepared/installed/restored files and identity, not completion of the requested visible workflow. Retention must not retire the sole rollback of the latest UI-accepted version based only on a build, signature, or receipt.

4. **High: current routing cannot select by accepted outcome.** The harness can record requested route, admitted bytes, settled input/cache/output/reasoning tokens, and unknowns, but does not bind route/effort, retry class, and verified outcome to one comparable record. Trials 19–21 rejected complex candidates; Trial 21 reported 681,899 input tokens including 186,240 cached, with no provider-confirmed cost or model identity. [Source audit](https://github.com/akritagrawal-stack/iris/blob/080ba93f74de78d7d64ca8c5d92887546d384973/research/pr-review-20260912/SOURCE_SCOPE_AUDIT.md#L285-L303).

5. **High: development instruction context is bloated.** Current hierarchy is 115,517 bytes / 16,407 words across root and native instructions. Historical acceptance prose and long file tables compete with live invariants before any runtime request. This is development-agent context, not measured Iris provider-token usage.

6. **Medium: bounded context has a known false-negative path.** Forward import selection can omit consumers, and broad `false`/`error` matching can retain successful source reads as failure evidence. Resolve this before crediting a runtime model for outcome changes.

## Minimal reusable candidate contract

Add one durable **AcceptedCandidate** record to the existing coordinator. Do not add another planner, agent, database, or updater. Create it only after source identity, artifact digest/launchability, verification receipt, and independent-review identity agree. Store no prompt, response, credential, source payload, or user data.

Fields: candidate ID; registered Test project slug/bundle/path; existing `SourceIdentity` (clone, branch, edit/base commits, change ID); exact artifact path and content digest; verification/review receipt digest and status; timestamps; lifecycle `ready | delivering | installed | uiAccepted | superseded | invalid`. Any source, registry, artifact, or receipt mismatch invalidates it. It is an identity binding, never an acceptance claim.

Expose two existing-flow actions:

* **Recheck and deliver saved candidate** runs build/package identity checks and the existing delivery path with no planner/editor/repair generation. It starts only at `ready` and stops on mismatch.
* **Record Test acceptance** follows an operator-completed named UI workflow and stores run ID, candidate ID, observable steps, and result. It alone marks `uiAccepted` and current known-good.

Use `MaintainSavedChangeRechecker`, `PendingEditCandidateIdentity`, `IrisTestProjectRegistry`, and `AppDeliveryReceiptStore` as the seams. Do not create a parallel artifact registry. The existing preview-delivery gate already establishes the needed tap-time and pre-swap revalidation pattern. This permits a future fresh PlantGPT recheck only after all current target/identity preconditions are recreated; it does not retrofit old evidence into a delivery run.

## Bounded retention, preserving recovery

Keep the logical-byte admission and second pre-swap check. Add a pure classifier before admission, then extend the existing explicit Test-only confirmation action. Classify every payload using receipt, candidate, and recovery references:

| Class | Rule |
| --- | --- |
| Current installed app | Never cleanup target. |
| Prepared/installed/pending Undo, interrupted or archived recovery | Always protected. |
| Newest rollback of current `uiAccepted` candidate | Always protected. |
| Prior UI-accepted rollback while current has no observed acceptance | Always protected. |
| Restored or superseded payload | Eligible only with complete matching identity, no newest/recent/recovery/overlap reference, and a displayed confirmation. |
| Unknown, corrupt, symlinked, shared, external, user-data path | Refuse cleanup and delivery. |

When the next backup exceeds 2 GiB, show bytes required, eligible identities, and protected versions. A confirmed cleanup deletes only `restored`/`superseded` items under the existing exclusive receipt lock; otherwise refuse before swap. Never delete source clones, build caches, receipt JSON, normal Iris, or app data. This avoids automatic GC and delivers bounded managed backup storage only after explicit cleanup. Record logical bytes removed and allocated bytes measured separately: hard links mean logical reclaim is not physical-free-space proof.

## First-wave instruction compaction

Run this only in `/Users/akrit/Documents/iris-lightweight-20260912`; frozen Mann PR #1 remains untouched. Produce an on-demand `docs/history/` record for historical run narratives, superseded status prose, long file tables, and dated model-direction rationale. Replace instructions with a compact current contract containing every actual safety, identity, consent, UI, isolation, no-terminal-Xcode-build, source/build, and acceptance invariant. Update obsolete Astra/Luna deferral text to the user’s current routing direction.

Do not delete first and hope tests reconstruct intent. A Luna High reviewer compares compact instructions against the archive and checks each operative invariant has an exact surviving instruction or a source-of-truth link. Measure only source bytes/words and agent task completeness in this phase. Do not claim actual provider-token savings until a controlled before/after Iris runtime measurement exists.

## Bounded units and ownership

| Unit | Owner | Owns | Acceptance |
| --- | --- | --- | --- |
| Compact instructions | Luna Medium | new-worktree AGENTS/history split | invariant mapping review; no blind deletion |
| Candidate identity | Luna Medium | codec/store, rechecker adapter | legacy/corrupt/mismatch and no-generation tests |
| Retention classifier | Luna Medium | receipt pure classification and fixtures | cap, alias, symlink, corrupt, recovery, known-good tests |
| Coordinator/UI | Luna Medium | saved-candidate actions and Test-only confirmation | revalidate at tap/pre-swap; Cancel has no mutation |
| Adversarial integration | Luna High | combined-diff review and test additions | stale registry/source/artifact, failed relaunch, interrupted swap |
| Escalation/final review | Terra | contract changes, integration review, actual UI acceptance | evidence-tier and invariant audit |

No two implementation agents edit the same storage/coordinator file. Integrate compact instructions, candidate identity, retention, then UI; Luna High reviews the combined diff. The root builds and operates the actual UI. Luna Medium/High and Terra are **development agents**, not Iris runtime model selections.

## Runtime model and effort measurement

Retain the current runtime baseline until a frozen comparison is authorized. For every real runtime run, write a payload-free outcome row keyed by run/candidate IDs: requested route/effort; provider-confirmed model if returned; phase (intake/edit/review/repair/recheck); physical attempt and retry cause; admitted input bytes; settled input/cache-read/cache-write/output/reasoning tokens; elapsed time; verification, delivery, and UI result. Unknown stays unknown. Pricing remains display-only until tied to provider-confirmed model and price revision.

Count every physical attempt once, including transient failure/cancellation. Preserve independent review capacity before edit/repair as the ledger does; a failed suite cannot spend review reserve. Compare **accepted UI lifecycle per token/dollar and wall time**, rejection rate, and retry rate, never green fixtures or model prose. Cache-read stays distinct from normal input and reasoning output.

Starting gates, not measured savings: one planner, at most two edit/repair attempts, one code-admission review, and one final behavior review. Existing byte/time/identity stops remain enforceable. Run at least five frozen comparable acceptance cases per route/effort before changing defaults; report median, p95, all failures, provider identity coverage, and denominator. Do not enforce a dollar cap before provider-confirmed model/pricing exists.

## Evidence sequence and metrics

1. Unit-first: classifier, candidate transitions, ledger/usage, delivery revalidation. Add a deterministic mid-cleanup unlink-failure test before claiming transactional cleanup.
2. Combined isolated build and harness/receipt checks, each tied to source commit and artifact digest.
3. Actual Iris Test: recheck a saved candidate with no generation; deliver; launch; complete named workflow; restart; inspect saved version; Undo; relaunch restored app; verify disposable user data survives.
4. Retention UI: over-cap cancel with zero deletions, then confirmed disposable superseded cleanup; restart and reread records. Do not claim physical-space gain without a physical measurement.

Track managed logical bytes with protected/eligible breakdown; delivery/restore and uncertain-state rates; accepted full-lifecycle and actual UI-completion rates; median/p95 elapsed; token categories per accepted lifecycle; cache ratio; retry/review-reserve exhaustion; and false-acceptance escapes. Put denominator and evidence tier beside each metric.

## External patterns and license boundary

Borrow ideas, not code. [Sparkle](https://github.com/sparkle-project/Sparkle) is an MIT-licensed macOS updater with signed-update practices; retain Iris’s narrower registered-Test, receipt-bound replacement instead of importing a general updater. [GitHub cache guidance](https://docs.github.com/en/actions/concepts/workflows-and-actions/dependency-caching) distinguishes reproducible caches from artifacts and treats restored cache contents as untrusted, supporting exclusion of source/build caches from version retention. [OpenAI usage reference](https://platform.openai.com/docs/api-reference/usage) exposes cached input separately, supporting separate cache-token accounting. [Harness Evals](https://github.com/harness/harness-evals) is Apache-2.0 and illustrates explicit outcome metrics; borrow the outcome-first evaluation concept only. Preserve notices and request separate license review before copying external code.
