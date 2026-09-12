# Terra review: first-wave corrections

## Blocking issues and corrections

### P0: `PendingEditCandidateIdentity` cannot be the accepted-candidate record

`PendingEditCandidateIdentity` is intentionally a dirty, staged, pre-commit recovery identity. It requires `HEAD == baseCommit`, a staged tree, and a clean index-to-worktree relationship. `MaintainSavedChangeRechecker` then verifies, independently reviews, and commits that current candidate. Neither represents a previously accepted clean source/artifact after the coordinator state has gone. Binding the new feature to those types alone would recreate the PlantGPT gap.

**Correction:** add one minimal `AcceptedCandidateRecord`, persisted under the existing Test receipt-store lock, not a new coordinator or dispatcher. It must refer to the registered Test project, existing `SourceIdentity`, exact artifact content digest, verification/review evidence IDs, and optional `uiAccepted` receipt/run ID. It is valid only when all identities revalidate at invocation and immediately before swap. Legacy candidates lacking this record are visible but not reusable. The recheck path may run deterministic build and delivery checks without planner/editor/repair generation; a separately requested fresh review remains a distinct, metered stage.

### P0: workspace binding needs a structural guide contract

Existing guides carry absolute `workingDirectory` values and may include hard-coded `cd` commands. Replacing text in either field can redirect an untrusted command; accepting an arbitrary staged path breaks the guide’s source identity. The design says not to substitute strings but does not define the actual allowed transformation.

**Correction:** introduce a versioned guide step field such as `workspace: { kind: "prepared-project", relativePath: "apps/mobile" }`. Resolve it only against a validated binding: `guideID + revision + projectID + canonical original root + canonical staged root + expected origin + commit`. Canonicalize the relative path, reject empty, absolute, traversal, symlinked, or out-of-root paths, and pass the resolved directory directly to the existing command runner. Do not rewrite `command`. Legacy absolute-path guides remain blocked with an explicit setup explanation until republished with the new field. The existing controller remains the owner of guide progress, cancellation, consent, and terminal lifecycle; source preparation returns a validated value only.

### P1: retention cannot protect “known good” without durable linkage

`AppDeliveryReceipt` currently models prepared/installed/restored file transitions, and cleanup deliberately considers only restored backups. A pure classifier cannot infer that a receipt’s replacement completed the named native UI workflow. Without an explicit durable acceptance pointer, a later cleanup could retire the only rollback associated with the last actually accepted app.

**Correction:** persist, under the existing receipt-store lock, a small mapping from Test project/bundle to `currentUIAcceptedReceiptID` and, while a replacement is unaccepted, its preceding accepted receipt ID. Update it only after an operator-observed named workflow, never on build, signature, install, launch, or receipt transition. All legacy/incomplete/unknown records remain protected. The classifier may offer only complete, unreferenced `restored` or explicitly `superseded` payloads. It must recheck identity, recovery references, and overlap under the lock before each unlink. Preserve receipt metadata after removal and report partial deletion exactly; receipt locking does not make multi-file cleanup transactional.

### P1: worktree staging must state and test its shared-Git effect

`git worktree add --detach` is the appropriate preservation route, but it modifies the source repository’s common Git administrative metadata even while leaving the user’s files, index, and branch untouched. Do not describe it as a zero-effect copy or make cleanup/prune decisions against the user’s repository.

**Correction:** the source-preparation record should include the common Git directory and the owned linked-worktree administrative identity. Before adding, confirm the original checkout’s canonical path, origin, required commit, and porcelain state; after adding, confirm the original has the same HEAD and porcelain output, while the owned staged worktree is detached at the required commit and clean. The only permitted shared mutation is the linked-worktree administrative entry created by `git worktree add`. Stop should leave an owned interrupted stage for review; removal is an explicit later operation that first revalidates ownership. Never run `reset`, `clean`, `stash`, `prune`, `--force`, or branch-moving flags.

### Resolved: mobile hub is a Publik/Iris entry module

The hub is used before Kneecap is installed, so it must not be embedded in or
modify the user’s dirty separate Kneecap product. First wave adds a tiny
`iris-mobile` static module owned by Publik/Iris, using a shared versioned route
manifest and existing catalog identity. It introduces no native bridge, second
runtime, signing/distribution framework, or deployment. A later platform route
may host the same static assets.

The manifest may show only validated HTTPS routes or `Setup needed`/
`Unavailable`; it never represents a TestFlight, App Store, APK, or hardware
installation as complete without a real published route. Browser rendering
validates the contract. Installed native UI acceptance, signing/upload, and
physical-phone acceptance remain separate evidence lanes.

## Bounded first-wave acceptance

1. **Instruction compaction:** in this worktree only, map every live safety/identity/consent/UI/build invariant from the historical instructions to either the compact active instruction or a linked on-demand history source. Reviewer checks the mapping before deletion. Report bytes/words only, with no runtime-token-savings claim.

2. **Source preparation and binding:** use a disposable Git fixture with a dirty original matching the required commit. Verify `git worktree add --detach` creates a clean owned stage at that commit, preserves the original HEAD and porcelain exactly, and records the expected common-Git administrative change. Verify a new structured workspace step runs in the staged path, while a legacy absolute path, traversal, symlink, mismatched revision/origin, or changed stage is refused without command execution.

3. **Candidate and retention unit path:** verify a saved accepted-candidate record revalidates and starts deterministic recheck with zero generation calls; stale artifact/source/registry/evidence blocks before delivery. Verify current UI-accepted and preceding rollback records, pending/recovery/overlap paths, and all legacy records are retained. Exercise successful eligible deletion and a forced later unlink failure; assert truthful deleted-path/partial-failure state, not atomic multi-file deletion.

4. **Mobile hub:** validate malformed/duplicate IDs, non-HTTPS destinations, credential-shaped URLs, unsupported native claims, and absent routes. Browser acceptance proves route rendering and `Setup needed`; it does not prove a native install, signing, launch, or phone workflow.

Only after these checks pass should integration proceed to one actual Iris Test candidate recheck/delivery/restart/Undo journey. A native installed-app result and a physical-phone result must be reported separately.

## D0 compact-instruction review: pass with one correction

Verified the three archived originals against their manifest SHA-256, byte, and
word counts. The active rules retain the operative Test isolation, credential,
consent, guide provenance, cancellation, UI, source identity, build,
verification, recovery, and evidence distinctions. The required correction was
added to the active macOS contract: pending recovery blocks affected
edit/publish actions and uncertain bundle swaps are never automatically
replayed. `manifest.json` now records the resulting active macOS count of
7,547 bytes and 884 words; total active instructions are 12,027 bytes and
1,426 words. These are development-context measurements only, not Iris runtime
token savings. The original archives remain unchanged and hash-verified.

## Harness-context correction: existing wiring, bounded remaining limit

The earlier research note incorrectly described two already-landed fixes as
missing. `FeatureEditRepositoryContext.collectReviewContext` already sends
reverse local-import consumers after changed tests and changed paths. Both
callers construct and pass the bounded `mappedSourcePaths` list:
`MaintainTierCFixer` for phase-aware independent review and
`MaintainSavedChangeRechecker` for saved-candidate review. Do not add another
selector, repository walk, or coordination layer.

`HarnessConversationProjection` also already preserves nonzero exits and
explicit diagnostics while allowing source-like successful text such as
`return false` and `throw new Error(...)` to compact. The harness test suite
contains direct coverage for both the source-like success and an `Error:`
diagnostic. The previously proposed reproduction is therefore not a valid
first-wave defect.

The real, intentionally bounded limit is narrower: consumer selection only
examines the first 100 declaration-bearing files from the six-language repo
map, and only static relative JS/TS-family imports. A real consumer can be
outside that map, use an alias or dynamic import, have no recognized top-level
declaration, or be in another language. Treat this as a selection hint, never
as evidence of complete dependency coverage. First wave needs no generalized
indexer: retain the stated ceilings and add a regression only for an observed
miss in a supported static-relative import within the supplied map. A missing
consumer outside that boundary must remain an explicit review limitation, not
a claimed false-negative fix.

## Guide-status evidence correction

The current published Kneecap guide is external guide revision 5 with status
`pilot` at source commit `fc48ba4`, according to the freshly fetched guide
record. The local `docs/guides/ios-xcode-build.md` is a draft document and is
not approval-status evidence for that published guide. Plans and acceptance
records must label those as separate sources; neither establishes signing,
native installation, launch, or phone acceptance.
