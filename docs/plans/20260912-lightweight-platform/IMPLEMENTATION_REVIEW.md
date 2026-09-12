# Implementation review

Reviewed integration `d07488c` and native commit `4b29636` against the compact
contracts and first-wave work orders. **No blocking or material findings.**

- `guideSlug` is now decoded from the catalog; the visible force refresh reuses
  the bounded existing service, preserves cached rows on failure, and publishes
  the observed last-success time. The Test-only guide refusal also surfaces the
  existing card without starting a guide.
- Test usage records the configured implementation arm, reservation ID,
  physical attempt, settled ledger state, and unknown provider/UI facts without
  retaining request content. It does not convert requested routing into a
  provider-confirmed model or accepted result.
- `iris-mobile` is a self-contained static prototype. Its strict manifest
  validation, bounded cache and localhost-only server leave all present routes
  unavailable until a verified destination exists; it introduces no native
  wrapper, signing path, deployment, or fabricated install claim.

This is source review only. Reported Node tests and upcoming browser acceptance
remain separate evidence; neither proves native installation or device use.

## S1 spatial seam review: merge gates for `26f590a`

### P0: freshness does not validate the observation it stores

`GuidePointingFreshness.freshness` compares target fingerprints and coordinate
metadata, but never compares `GuideObservationSnapshot.frontmost*` or
`focusedWindow`. `SystemGuideTargetLocator.evidence` captures those fields, yet
`resolve` labels any complete fingerprint as `.fresh`. A control found in the
named but now-background process, or in a changed focused window, can therefore
be treated as current semantic evidence. This contradicts the intended
app/PID/window freshness contract.

Before live wiring, add one small consistency check: an evidence snapshot must
agree with its target process/bundle and focused-window identity, and a refresh
must reject or report stale when those current observations differ. Keep the
existing locator seam; do not add a second observer or capture loop. Cover
foreground-process and focused-window change separately from same-rectangle
control/tab changes.

### P1: raw AX labels are retained in the evidence object

`GuideTargetFingerprint.label` and every `GuideAccessibilityAncestor.label`
hold raw AX text through the outcome. Window titles are hashed, but AX labels
can expose document, message, or form content and are only needed for equality.
Replace retained labels with the existing bounded fingerprint form (or omit
them where role/identifier already identify the element). Keep raw text only
inside the immediate matcher and never in an outcome, memo, trace, or later
revalidation record.

### P1: no supported headless test currently runs the new behavior

The synchronized Xcode test target will discover
`SpatialGuidanceRegressionTests.swift`, but it is not an existing headless
runner. `harness-feature-host/build.mjs` compiles every production source with
the supported `IRIS_HARNESS_HEADLESS` flags, but neither its executable nor
`run-guide-regressions.mjs` compiles/runs `SpatialGuidanceChecks.swift` or the
new regression tests. The usability package links
`GuidePointingFreshness.swift` but has no test covering its new API.

Do not accept parse output as S1 testing. After the two corrections, use the
existing headless module build as the compile proof and add the narrow pure
freshness/coordinate checks to a supported headless runner. Run the Xcode Test
target and the installed UI journey later as distinct evidence.

The additive evidence-locator protocol and strict ambiguity result are the
right low-bloat boundary. `GuideSessionController` still constructs
`GuideEyeFlight` without `outcome.targetEvidence?.fingerprint`; root's planned
live wiring must pass it before claiming semantic memo behavior in the app.

## I1 source-workspace review: merge gates for `8a9b403`

The standalone Swift 6 fixture suite passed. It exercises bounded child output,
cancellation, dirty-source inspection where the expected commit is locally
present but is not `HEAD`, detached-worktree creation, disabled repository
hooks, and preservation of the original checkout and its shared Git metadata.
It is useful unit evidence only; it does not establish the registered Test
build/delivery path.

### P0: the shared executor does not own one invocation atomically

`GuideSourceWorkspaceProcessExecutor.run` overwrites its single `process` and
`activeInvocation` for a second caller. Cancelling the first task then marks
and terminates the second child, while the first child can remain running. The
comment that probes are serial only applies within one `inspectIdentity` call;
the `@unchecked Sendable` service exposes separate `inspect` and `prepare`
calls concurrently. Reject or serialize a second invocation before replacing
the active state, and add the narrow two-task cancellation regression. Do not
rely on a UI caller being serial for process ownership.

### P0: isolation can proceed with no recoverable record

`GuideSourceWorkspaceStore` is optional and both initial and later saves use
optional chaining (`try store?.save` / `saveRecord`). A production service made
with its default initializer creates a worktree with no record at all, so a
cancelled or failed operation cannot be recovered truthfully. Require a store
for `.createIsolatedWorktree` before `git worktree add`; keep the existing
atomic store rather than adding a new coordinator. Cover the no-store request
as a refusal.

### P0: Git inherits process-level `GIT_*` routing

The fixed argv disables repository hooks, but the child never assigns a
sanitized `Process.environment`. An inherited `GIT_DIR`, `GIT_WORK_TREE`,
`GIT_INDEX_FILE`, or config environment can redirect probes and worktree
creation away from the checked source even with `-C`. Strip inherited `GIT_*`
variables and set the small required noninteractive configuration explicitly
(including no system/global config and no prompt), while retaining the fixed
argv. Add one fixture with inherited `GIT_DIR` proving the request source still
wins.

### Integration acceptance gate: a staged worktree is not yet a registered Test project

The code correctly records the linked-worktree admin directory and the fixture
proves the original `.git` stays a directory while its common metadata gains a
`worktrees` entry. It can therefore preserve the dirty original clone. But the
new `Projects/<project>-<run>` path cannot pass the current
`IrisTestProjectRegistry.permitsEdit` or delivery checks until it is explicitly
registered: the registry is read-only over `test-projects.json`, and its
registered `clonePath` must equal the staged path. Root's wiring must use a
small atomic typed registration update, then re-read and validate the exact
entry before build/delivery. It must never replace the original registered
clone or treat shared `.git/worktrees` metadata as ownership of that clone.

## S1 follow-up review: `1a31d7c`

The earlier foreground/focused-window validation is now called both for a
fresh comparison and before an initial point is emitted. AX labels and
ancestor labels are retained only as fingerprints. The existing headless
runner now compiles and runs `SpatialGuidanceChecks.swift` against the native
module, so the P1 test-runner gap is closed in source.

### P0: real window evidence omits the window identity that its new gate requires

`SystemGuideTargetLocator.locateFocusedWindowEvidence` and
`locateWindowEvidence` call `evidence(for: windowThatIsActuallyUp, ...)` with
the default `window: nil`. `evidence` consequently constructs a fingerprint
with `windowIdentifier: nil`. Its availability is partial, and
`GuideStepPointingCoordinator.resolve` now calls `validateCurrentObservation`,
which refuses it as missing semantic identity. Thus real authored window steps
(including the focused-window path that this change is meant to prefer) stop
pointing even when AX has supplied the window.

Build the `GuideWindowFingerprint` from the AX-window element in `evidence`
when its caller has not supplied one, and use that same value in both the
target fingerprint and snapshot. Add a narrow headless regression for a
window-evidence result with the real locator's structural shape. This is a
small completion of the present seam, not a new observer or routing layer.

Follow-up `4b01f05` retained linked evidence at
`/Users/Shared/iris-harness-host-s1-window-evidence-20260912/`: its 175-source
native module compiled, 68 guide regressions passed, and the spatial checks
passed. This remains headless source evidence, not installed-app or live AX/UI
acceptance.

## V1 accepted-candidate record review: `ba1f844` and `fbeccba`

The record/store is a useful source-only identity seam and introduces no live
delivery route. The inert harness checks passed and are retained at
`/Users/Shared/iris-v1-candidate-checks-20260912.log`; its native compile log
is retained at `/Users/Shared/iris-v1-candidate-native-compile-20260912.log`.
That evidence proves codec, receipt/project argument matching, bounded final
record reads, artifact-digest staleness, and the existing final-leaf symlink
case. It does not prove installation, UI acceptance, actual current Git source
state, or candidate delivery.

### P0: accepted-candidate parent symlinks can redirect storage and its lock

`saveAcceptedCandidate` creates `accepted-candidates` and only `lstat`s that
final directory. `loadAcceptedCandidateUnlocked` checks and opens only the
final JSON file with `O_NOFOLLOW`. Neither validates symlink components of the
base directory or `accepted-candidates`; `withExclusiveStoreLock` likewise
opens only the final `.lock` leaf. A symlinked parent can therefore redirect
the candidate read, write, and lock while every current final-leaf check
passes.

Before merge, reuse the existing `pathHasNoSymlinkComponents` policy under the
store lock for the base and accepted-candidates directories, and apply it to
unlocked candidate reads before opening the leaf. Treat an unsafe parent as a
refusal/storage failure rather than absence. Add the two narrow fixtures:
symlinked base directory and symlinked `accepted-candidates` directory. This
is not a claim of transactional directory traversal against arbitrary local
filesystem races; it closes the present unchecked parent path.

### Boundary required for later wiring

`uiAcceptedRunID` and `uiAcceptedReceiptID` are paired only by UUID shape.
Verification/review IDs are also nonzero UUIDs, and revalidation compares them
only when callers supply expected values. The receipt is passed as an object,
not loaded from the receipt store. This is acceptable only while the code has
no delivery authority. A later delivery caller must load the exact persisted
receipt under the store boundary and resolve the verifier, reviewer, and UI
acceptance records by ID; missing records or arbitrary UUIDs must refuse.

`revalidateAcceptedCandidate` is also not a full source recheck. It compares
the passed registry pin and stored source metadata, then recomputes the
artifact digest. It does not inspect current Git origin, commit, branch, or
dirty state. Keep that distinction explicit when the source-workspace binding
is added.

## Final V1 and I2 inactive-scaffold review: `536e9c4`, `3be625c`, `d8b0100`

**Accepted for cherry-pick as inactive scaffolding.** No live delivery, install,
launch, or source-workspace execution route is introduced.

V1 now checks base and `accepted-candidates` path components before candidate
reads and writes, rechecks them after directory creation, and retains the
final-leaf `O_NOFOLLOW` read/write policy. The supplied fixtures prove base
and candidate-parent symlinks refuse reads, writes, and lock-backed
revalidation without modifying the outside fixture. This protects the
persistent parent-link case identified in the prior review. It does not claim
to make arbitrary same-user filesystem replacement transactional; no such
claim is needed for this inert record seam. Candidate revalidation still
compares supplied registry and receipt values plus the current artifact digest,
not current Git origin, HEAD, branch, or dirty state. Evidence UUID shape or
an injected receipt remains insufficient delivery evidence until later code
loads and validates the persisted evidence records.

I2 strictly decodes only a safe structural `prepared-project` path and
rejects a conflicting legacy `workingDirectory`. Until an integrator supplies
a validated binding, `GuideAutopilotRunner` refuses the ordinary command
entry, failure/retry ladder, and long-running entry before it moves a shell or
runs a command. The workspace service itself is not wired as execution
authority, so the scaffold cannot substitute HOME, shell state, or arbitrary
guide text for a binding.

Automated source evidence was inspected, not rerun:
`/tmp/iris-harness-host-candidate-symlink-20260912/checks.log` reports the
candidate base/parent symlink refusals and candidate record checks passed.
`/Users/Shared/iris-guide-schema-build-Mc8jhJ/schema-run.log` reports the
strict schema cases passed. These are source/headless checks only; installed
Iris Test UI, real prepared-workspace binding, app replacement, and delivery
remain separate unproven acceptance work.
