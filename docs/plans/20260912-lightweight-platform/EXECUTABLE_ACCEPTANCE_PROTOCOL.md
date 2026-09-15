# Iris executable acceptance protocol

This is the short, repeatable field protocol for the current Iris Test build.
It turns the larger contracts in [ACCEPTANCE.md](ACCEPTANCE.md) into three
real user journeys. It is not a synthetic click test, a source-only test, or a
claim that a model's “applied” message means the app works.

## Run rules

Run only against a disposable registered Test app and a named Iris Test build.
The operator uses the native app with computer use, reads each visible state,
and takes a screenshot at every `CHECKPOINT`. Do not use DOM scripts, replayed
screenshots, or a fake provider for the three journeys. Use one foreground
desktop owner; headless checks may run separately.

Before a run, record:

- Iris source revision and the exact `Iris Test.app` path plus executable
  digest;
- selected Test project slug, registered clone/artifact/installed paths,
  bundle identifier, pinned source commit, and `git status --porcelain`;
- whether the app is already running, whether the target app has unsaved user
  data, and the current receipt/version-history IDs;
- requested model/effort and the provider-resolved model/usage fields. If the
  provider omits a field, record `unknown`; never infer it from a picker label.

Do not continue a journey after a failed identity or source preflight. A
permission, signing, missing-device, or unavailable-provider problem blocks
only the affected acceptance row; record it and continue any independent
headless work. Never delete backups or reset permissions as part of a pass.

## Workflow 1 — “Help me set this up” (novice install and spatial guidance)

User input, verbatim: `I want to get Kneecap running on my Mac and iPhone. I
don't know which folder or button to use. Please show me what to do.`

Setup: use the current published/owned Test guide revision and a disposable
dirty matching source checkout with spaces in its path. Keep a second browser
tab or Xcode window visible so navigation can be tested. Do not use the
canonical user checkout as the writable worktree.

1. Open Iris Test, open Settings, and choose the guide/app. 
   **CHECKPOINT:** the UI names the selected guide and the current revision;
   it does not silently fall back to a generic chat or invent a local folder.
2. Continue until the dirty-source decision is visible, then choose the
   isolated-copy action. 
   **CHECKPOINT:** the card explains that the original source stays unchanged
   and gives the next action. The staged path is Test-owned and visibly tied
   to the selected guide/project.
3. Cancel once, resume once, and observe the next step through the real guide
   surface. 
   **CHECKPOINT:** cancel leaves no running child or editor call; resume uses
   the same owned workspace, not a second worktree. A refused or unavailable
   step says what the user must do next.
4. On a step that names a visible control, ask Iris to show where it is, then
   switch the foreground tab/window before asking again. 
   **CHECKPOINT:** a small outline appears only around the current semantic
   target; it clears after the app/window changes and either reacquires the
   new target or says it stopped pointing. A same rectangle is not accepted
   as the same control.
5. Follow the real device/build prerequisite until Iris reaches the first
   missing external requirement. 
   **CHECKPOINT:** missing signing, trust, phone, or distribution support is
   stated as incomplete. Iris does not label a source copy, simulator, or
   guide card as an installed phone app.

Data and source assertions:

- original checkout HEAD, tracked diff, untracked paths, index, and sampled
  file hashes are identical before/after; only the owned linked-worktree
  administrative record may be added;
- the prepared workspace is detached at the pinned commit, clean, inside the
  Test-owned root, and reused after resume;
- no command runs when workspace metadata is absent, contradictory, outside
  the root, symlinked, stale, or tied to another guide revision;
- no screenshot, raw AX label, credential, or full chat body is persisted in
  the acceptance record.

Evidence: screenshots at each checkpoint; source-workspace inspection and
resume log; `GuideSessionController` and `GuideAutopilotRunner` state; and the
focused source checks in
[`SourceWorkspaceChecks.swift`](../../../iris-macos/tools/source-workspace-tests/SourceWorkspaceChecks.swift),
[`SpatialGuidanceChecks.swift`](../../../iris-macos/tools/harness-feature-host/SpatialGuidanceChecks.swift),
and [`run-guide-regressions.mjs`](../../../iris-macos/tools/harness-feature-host/run-guide-regressions.mjs).

## Workflow 2 — “Make this useful” (nontechnical intake to real feature)

User input, verbatim: `I want my notes and folders to move to my other
computer without losing anything that is already there.`

Setup: select the disposable registered `nitroai-test` app first. Seed the
real app with a populated folder, an empty folder, an existing destination
note, and two same-name folders from different origins. Freeze the prompt and
the expected behavior before the model call. The independent oracle must not
be supplied to the generating model.

1. Submit the words above through Iris's actual Edit surface. 
   **CHECKPOINT:** the card names NitroAI, shows the selected Edit mode, and
   displays a short clarification batch rather than guessing a file format,
   destination, overwrite policy, or framework. A clear visual request would
   skip this card; this request must not.
2. Answer the visible questions in plain language: include notes and folders;
   skip confirmed identical items; preserve same-name folders from different
   origins; retain changed content separately; never overwrite existing work.
   **CHECKPOINT:** selected answers are visibly retained in the same question
   order, the desired result is stated in user language, and any technical
   assumption is labeled uncertain rather than presented as a decision.
3. Review the plan and approve it once. 
   **CHECKPOINT:** the plan includes concrete before/action/after acceptance
   criteria and the chosen app. It does not claim tests, packaging, install,
   or success before those have happened. Record the physical call ledger,
   route, requested/resolved model, attempts, and returned usage.
4. Let the existing review/build/delivery gates run. If admitted, use the
   resulting app through its real Settings, export/import, folder, and note
   controls; restart it and repeat the import. 
   **CHECKPOINT:** the app exposes both `Export notes and folders` and `Import
   notes and folders`, retains the existing Markdown export, and shows a fresh
   completion or rejection status. No silent timer or stale alert counts.

Behavior and data assertions:

- unchanged notes and folders appear once after the first import and remain
  once after the second import and after restart;
- a changed same-origin item is retained as a separate copy; same-name
  folders with distinct origins remain distinct and preserve membership;
- existing destination work is never overwritten or deleted, including when
  the import transaction aborts; malformed/wrong-format input produces a new
  visible error and no partial records;
- the generated candidate, source commit, artifact digest, review evidence,
  installed bundle identity, and post-restart readback all refer to the same
  Test project. “Build passed” alone is a failure of this workflow.

Evidence: redacted screenshots/video-free checkpoint captures; Iris run log,
`plan.json`, `usage.json`, review/delivery receipts, and post-restart app
readback. The independent behavioral reference is
[`transfer-native-oracle/README.md`](../../../iris-macos/tools/transfer-native-oracle/README.md)
and its `transfer.test.mjs`; the current app's persistence test and oracle
must both pass. Usage records come from
[`HarnessRunLedger.swift`](../../../iris-macos/leanring-buddy/HarnessRunLedger.swift)
and [`UsageAttributionChecks.swift`](../../../iris-macos/tools/harness-feature-host/UsageAttributionChecks.swift).

## Workflow 3 — “I don't like the update” (version, relaunch, retention, Undo)

User input, verbatim: `Add one small visible improvement to the selected test
app, keep my current notes, and let me undo it if I don't like it.`

Setup: reuse the accepted candidate from Workflow 2 or another already
accepted Test candidate. Do not generate a second paid feature just to test
its lifecycle. Open the target app with an unsaved note and record the current
installed bundle digest, receipt ID, and user-data count.

1. Reopen the saved candidate in Iris and choose the no-generation recheck.
   **CHECKPOINT:** the UI names the same project and says it is checking the
   saved change; it does not call the planner/editor again. A stale source,
   changed artifact, dirty checkout, missing review/UI evidence, or wrong
   registry entry is refused with a specific explanation.
2. Deliver the candidate through the normal Test route. 
   **CHECKPOINT:** the status distinguishes source saved, build passed,
   installed copy replaced, and relaunch; it never collapses these into one
   “done” label. The installed bundle has the expected identity and a new
   content digest while the backup pins the prior digest.
3. Confirm relaunch and inspect the feature in the actual app. Quit/relaunch
   the app once more and reopen the note. 
   **CHECKPOINT:** the updated app is visible after relaunch, the note and
   unrelated records remain, and version history shows the candidate and its
   rollback relationship. If relaunch is not completed, the card says so and
   does not claim user-visible success.
4. Press Undo once from Saved Versions and wait for the result. 
   **CHECKPOINT:** the previous bundle is restored and relaunched, the card
   says `Previous version restored`, and the note remains. If recovery is
   interrupted, the card says `Undo was interrupted`/`Undo needs attention`,
   retains recovery details, and offers retry without silently changing the
   installed app.
5. Reopen Settings and review cleanup without deleting anything unless a
   fresh preview has explicitly identified eligible obsolete Test backups.
   **CHECKPOINT:** preview is read-only, reports count and logical/allocated
   bytes, and an absent/locked/uncertain store yields no destructive action.

Version and data assertions:

- one registered installed identity is used throughout; the source branch,
  receipt, artifact digest, backup digest, and app bundle ID agree;
- user data is outside the app-bundle swap and survives update, restart, Undo,
  and an interrupted recovery; no receipt transition alone proves this;
- a candidate changed after acceptance, same-size payload tampering, stale
  source, symlink/alias overlap, duplicate receipt, or uncertain backup blocks
  delivery/recovery before a callback or unlink;
- a retry is idempotent: it does not create duplicate receipts, worktrees, or
  backups and does not run a new model call.

Evidence: screenshots for recheck, delivery, relaunch, Undo, and preview;
process/launch records; receipt-store JSON and digests before/after; app
readback after restart; and logs from
[`SavedVersionLifecycleChecks.swift`](../../../iris-macos/tools/harness-feature-host/SavedVersionLifecycleChecks.swift),
[`IrisTestAppDeliveryChecks.swift`](../../../iris-macos/tools/harness-feature-host/IrisTestAppDeliveryChecks.swift),
[`BackupRetentionChecks.swift`](../../../iris-macos/tools/harness-feature-host/BackupRetentionChecks.swift),
and [`AppRelaunchInstalledDeliveryTests.swift`](../../../iris-macos/leanring-buddyTests/AppRelaunchInstalledDeliveryTests.swift).

## Pass report

Report each workflow separately as `passed`, `blocked`, or `failed`, with:

1. source revision and installed artifact digest;
2. exact visible checkpoint screenshots and the action taken;
3. data/version/relaunch assertions with before/after values;
4. exact log paths and automated test commands/results;
5. requested versus provider-resolved model, physical calls, returned token
   families, elapsed time, and cost estimate. Unknown remains unknown;
6. one failure classification and one next correction, if needed.

The product is ready for broader power-user testing only when all three real
workflows have no unexplained failed checkpoint, the applicable headless
checks pass, and every remaining blocker is explicitly external (for example,
Apple signing or physical-device access). A source test, screenshot, model
success message, or build result cannot upgrade an unverified installed,
restarted, or user-visible outcome.
