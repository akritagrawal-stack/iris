# Bounded implementation work orders

All paths below are relative to the new Iris worktree. The integrator assigns separate `codex/iris-*` branches; no agent edits the frozen PR worktree or an unassigned file. Every handoff gives commit, changed files, exact tests, unresolved cases and expected UI evidence. Work orders define outcomes and interfaces, not permission to add an unneeded framework. If the named seam already implements the contract, extend it instead of duplicating it.

## D0: compact recurring instructions

Owner: root implementation; Terra invariant review. Scope: root `AGENTS.md`, `iris-macos/AGENTS.md`, `iris-macos/leanring-buddy/AGENTS.md`, and `docs/history/agent-instructions-20260912/` only.

Archive each original byte-for-byte, record SHA-256/byte/word counts, and keep the archives out of automatically loaded AGENTS filenames. Replace active instructions with current isolation, model/transport, build, UI, source/provenance, credential, cancellation, native execution, recovery and evidence rules. Move completed run narratives and file inventories to the archive. Keep precise specialist instructions linked for the relevant subsystem. Preserve original historical evidence. Measure the new combined instruction bytes. No model savings claim or code tests are needed for a text-only change; Terra checks a rule mapping against the archive.

## I1: safe source staging and installation continuation

Owner: Luna High. Initial owned files: new `iris-macos/leanring-buddy/GuideSourceWorkspace.swift`, optional focused `GuideSourceWorkspaceStore.swift`, `GuideAutopilotRunner.swift`, and new headless checks under `iris-macos/tools/source-workspace-tests/`. Coordinator wiring into `GuideSessionController.swift` is reserved for the integrator after spatial's API is stable.

1. Inspect the existing refusal types and `IrisTestProjectRegistry` path/identity contract. Define typed source offer/result and an injected executor. Reuse existing command runner and stop/process isolation where possible.
2. Inspect origin, full commit and dirty state. Dirty matching source yields an isolated-copy offer, never a mutation of the user's checkout. Verify an existing commit locally before staging.
3. Create a detached linked worktree in a unique Test-owned destination after explicit setup choice. Fixed Git argv, validated path/ref, no shell interpolation, no destructive flags, no credentials, no automatic fetch. Verify containment, HEAD, origin and clean status before returning a workspace. Preserve a recoverable owned record on interrupted creation. Restrict any cleanup to owned empty/incomplete fixture destinations.
4. Expose a typed workspace binding with guide revision, common Git directory, linked-worktree administrative identity and original/staged identity. Step metadata is versioned `workspace: { kind: "prepared-project", relativePath: "apps/mobile" }`, with `.` for root. Resolve within the bound stage, reject traversal/absolute/empty/symlink paths, pass the directory directly, and never rewrite command text. Do not claim a bound guide if hard-coded commands still point home.
5. Add real local Git fixture tests: dirty lockfile and spaces; same pin; wrong origin; absent commit; duplicate destination; linked-worktree `.git` file; symlink destination; source mutation between inspect/stage; cancellation and resume. Assert original HEAD, tracked diff, untracked files and local file hashes remain unchanged. Confirm shared objects, without claiming a hard disk saving from logical size alone.
6. Run the focused headless checks. No native builds or model runs. Hand off the callable service plus proof and exact UI wiring required; do not call this full Kneecap installation.

I2 follow-through, same owner after I1 review: integrate safe offer/action, persist the selected workspace, propagate it to dependency checks/run/watch/resume, and add supported guide schema metadata rather than editing arbitrary command text. Add catalog refresh/status using `AppInventoryService.swift` and `AppInventorySectionView.swift`; preserve existing icon loader policy. Real installed acceptance is J1 in ACCEPTANCE.md.

## S1: semantic target identity and highlight

Owner: Luna High. Initial owned files: `GuidePointingFreshness.swift`, `GuidePointing.swift`, `GuideStepPointing.swift`, new focused observation/transform value types if needed, and `SpatialGuidanceChecks.swift` or a focused headless runner. Root/integrator owns `GuideSessionController.swift`, `CompanionManager.swift` and `OverlayWindow.swift` until a reviewed interface is handed off.

1. Keep existing public call sites compiling with a small adapter. Return target evidence containing PID/window/role/identifier/label/ancestry and coordinate metadata. Represent absent identity explicitly; no hash of rectangle alone.
2. Centralize and test coordinate transforms. Carry points versus pixels, crop, menu-bar reference and display identity. Refuse invalid geometry/topology. Keep AX traversal/time/node limits.
3. Add semantic freshness/ambiguity results alongside existing geometric checks. Identical coordinates with different PID/tab/window/control must invalidate; a moved same control requires re-resolution. Do not compare full screenshot hashes for normal animations or add constant capture work.
4. Tighten duplicate-label resolution: prefer authored role/context only when evidence actually distinguishes candidates. Ambiguous remains unavailable. No sensitive screenshots.
5. Test same rectangle/different control; duplicate sidebar and toolbar labels; new process with same bundle; tab/document change; window movement; off-screen/minimized target; negative monitor origins; mixed scale; crop and topology change; cancelled late result.
6. Hand off a precise render/revalidation API and tests. S2 wires live reacquisition and a click-through outline, using existing generation guards and eye UI. Do not claim a button highlight merely because pure geometry tests pass. Native acceptance is J2.

## M1: lightweight mobile install hub

Owner: next available Luna Medium/High; independent of native desktop code. Scope: new `iris-mobile/` only, plus an opt-in root test script if necessary. No edits in `/Users/akrit/kneecap`, no Capacitor scaffold, no new package dependencies, no account/signing/deployment actions.

Build a small static phone-sized web UI and pure route-manifest validator. Use native ES modules and CSS, Node built-in tests and a local HTTP server. Device selector: iPhone/Android/Computer. An app card shows compatibility and a genuine Open/Install link only when a verified destination exists; otherwise Setup needed with exact next actions. Provide refresh, offline/error/empty states and accessible focus/status text. A request counter/bounded cache test verifies refresh coalescing; do not predownload assets or register a service worker.

Define `schemaVersion`, app ID/title, public icon or fallback, OS, route kind, HTTPS destination or absent, verified/unavailable state, source guide/revision and prerequisite copy. Supply a clearly labeled local prototype manifest derived from observed Kneecap capabilities. No invented native distribution links or claim of a working web editor. A live catalog adapter is optional only after inspecting the actual documented `/api/iris/apps` response and mapping capabilities without guesses. Preserve unknown support.

Unit tests cover malformed/oversized/duplicate manifests, URL credential/scheme/host violations, incompatible OS, missing TestFlight URL, forged unsupported route, offline refresh with cached metadata and rapid repeated refresh. Browser acceptance through computer use: phone viewport, normal taps to choose Kneecap/iPhone, discover what is needed, switch Android/Computer, refresh, offline/error handling, keyboard navigation. This proves the hub prototype, not phone installation. Deliver static file sizes and request count, with no claim of runtime video/export support.

## V1: candidate reuse, then retention

Owner: Luna High, Terra reviews the storage contract before mutations. Scope first: new `AcceptedCandidateRecord.swift`, `MaintainSavedChangeRechecker.swift`, the existing receipt-store ownership/lock and tests. `PendingEditCandidateIdentity.swift` remains a staged pre-commit recovery identity, not the accepted record. Scope second: `AppDeliveryReceiptStore.swift`, `SavedUndoRecoverySection.swift` and `BackupRetentionChecks.swift`. One owner at a time; no shared storage edits.

Bind a saved candidate to current registry/source/artifact/verification/review identity. Implement a no-generation recheck route through the existing coordinator. Reject changed artifacts, stale registry roots, mismatched source and forged/legacy acceptance. Do not retrofit a historical accepted branch as a current accepted candidate. Add explicit observed UI acceptance metadata only where existing state lacks it.

After that contract passes review, add a pure retention preview classifying protected/eligible/unknown. Complete superseded installed versions can become eligible only after newest/current and prior known-good rollback references are correctly protected. Extend existing Test-only confirmation UI. Under exclusive store ownership, revalidate and remove only exact eligible payloads, then record per-item success/failure. Keep receipt history and app data. A dry run or cancel must not mutate.

Tests: legacy/corrupt records, pending/recovery/pinned references, alias/hardlink/symlink overlaps, over-cap protected set, candidate change between preview/delete, partial unlink failure, cancellation/restart, current target changed before swap and user data survival. Use fake small bundles for unit checks and reuse one accepted candidate for actual update/restart/Undo. Exact UI gates are J3.

## H1: routing, context and accepted-outcome efficiency

Owner: Luna High for bounded fixes; Terra takes over a justified cross-adapter contract change. Scope: `FeatureEditRepositoryContext.swift`, `HarnessConversationProjection.swift`, `HarnessRunLedger.swift`, `IrisTestRunUsage.swift`, `HarnessFeatureWorkflow.swift` and relevant Swift package/headless checks. Provider selection files change only after capability review.

First reproduce two causal context defects offline: a behavior depends on a consumer absent from forward-import traversal; successful file text containing `false` or `error` survives as a fake failed-command diagnostic. Correct the selection using bounded reverse-reference evidence and actual command result/provenance. Preserve instruction/failure summaries within current bytes, review reserve, cancellation and sandbox limits. No broad repository embedding index.

Extend usage/outcome records using existing run IDs, not a new telemetry service. Requested and resolved model/effort, physical attempt and retry class, provider-specific token fields and unknowns remain separate. Output/reasoning and input/cache subsets must not be double-counted. Add late settlement, duplicate settlement, failed/cancelled attempt, missing usage, counter overflow and review-reserve tests. Do not store prompts/screenshots/credentials in metrics.

Routing follows verified transport capabilities and explicit user preferences. A missing permission/model is an actionable error, not an automatic chain of retries or canned chat response. One evidence-backed Terra escalation at most for the bounded trial. Freeze the complex transfer request and independent behavioral oracle before running the real app. Run it only after a relevant defect fix, then inspect folder ownership, duplicate naming, persistence and update/recovery in the actual UI. Reuse the accepted artifact for lifecycle tests. Report all rejected-run spend. J4 is the acceptance contract.

## Integration and review ownership

Terra reviews interface changes, path/credential/recovery boundaries and the final combined diff. Root controls shared-file integration, native GUI build, installed Test identity and the foreground UI queue. Run independent Git/Swift/Node checks concurrently; serialize native desktop interaction and build resource contention. Rotate Luna work through I/S, M/V and H as slots free rather than spawning unbounded agents.

Do not amend PR #1. Commit each reviewed lane, merge into `codex/iris-lightweight-20260912`, and prepare a separate successor diff with tested/WIP file-backed evidence. Any blocker notification gives the action needed, the exact unresolved boundary and the work that can continue. No repeated status polling or repeated expensive test with unchanged code.
