### 2026-09-14 source-picker fallback after legacy refusal

The native guide exposed a usability gap: the source setup card was not reachable from the legacy guide's autopilot refusal. Iris now exposes **Choose source folder** directly in that refusal row whenever no binding exists, keeping the user on the same step and avoiding a dead end. The Test configuration rebuilt successfully and strict signing passed; the RC executable SHA-256 is `8031b8d34a80fc3ac26b0a7c41557c690725078a7f04a25fe51cf3120863b932`.

### 2026-09-14 native legacy autopilot gate

Computer use on the updated RC reached Kneecap step 5 and tapped “Let Iris run it.” Iris now surfaced the actionable gate “Choose and prepare the reviewed source workspace before Iris runs this older guide.” The prior generic marketplace-disabled response is gone. No command ran and no user folder changed because no validated binding had been selected.

### 2026-09-14 legacy guide autopilot implementation

The updated RC now permits the isolated Test bundle to run the legacy Kneecap guide only when a matching validated workspace binding exists. The runner rechecks the binding before each legacy command and maps `~/kneecap` references to that staged root. The source compiled and signed successfully; the next native gate is exercising this path after selecting the staged binding.

### 2026-09-14 legacy Kneecap workspace routing fix

The native run proved the public guide still used HOME-relative `~/kneecap` commands and blocked autopilot. Iris now requires a validated isolated source binding before allowing that legacy guide, then revalidates the binding at each command boundary and translates only the legacy project path to the staged workspace. Unrelated HOME commands remain unchanged. The Test configuration rebuilt successfully from `db779fc`; strict signing passed. The updated RC executable SHA-256 is `b8aab4504a52f6ea4f092c3f81d921641b0df5f069dc7f92342fa9860484bfd9`.

### 2026-09-14 native Kneecap guide computer-use check

The rebuilt signed RC was launched as the isolated Iris Test bundle. Through the native UI, Settings accepted `kneecap`, opened the real marketplace guide, and advanced from the initial terminal step to **step 5 of 15**. The guide reported that Terminal was open and that its prompt was inside the Kneecap folder. This proves guide admission, step progression, and terminal-state recognition in the native app. It does not prove installation completion, source mutation safety across all candidate folders, or physical-phone acceptance.

# Native RC evidence, 2026-09-14

### 2026-09-14 automated regression rerun

The integrated worktree passed the current lightweight checks without changing
the user checkout: the Iris harness completed **159 tests in 7 suites**,
`iris-mobile/test/*.test.mjs` completed **18/18**, and the source-workspace
package completed **5/5**. These checks cover routing/accounting, bounded
history and cleanup guards, source-root selection, and the mobile install-hub
logic. They do not replace native app, live-provider, or physical-device
acceptance.

The signed RC still reports that macOS has blocked its saved-login Keychain
read. Reconnect was triggered, but the secure macOS approval dialog is outside
the computer-use accessibility surface; the account-dependent native run is
therefore pending the owner selecting **Always Allow** for Iris Test.

### 2026-09-14 native acceptance-gated RC rebuild

The Test configuration rebuilt successfully from commit `1395f28`; strict code-signature verification passed. The named RC now contains executable SHA-256 `de9456684a2700cf03878aea46ac6f0eae3f9c5f7a4e0e09ac6063f08e33654d`. The launch environment remains opt-in for marketplace guide acceptance.

### 2026-09-14 explicit native marketplace-guide admission

Iris Test now admits the real marketplace guide engine only in the separately signed native Test acceptance boundary. Unit-test
hosts still refuse marketplace installations, and unit tests retain the
isolated offline-fixture path. The admission predicate has focused coverage in
`GuideSessionTests`; no user checkout or normal Iris profile is broadened.

### 2026-09-14 bounded in-flight-call cancellation

A second tightly scoped NitroAI Feature request reached the live composer and
admitted one Luna call. The UI remained on `Reviewing your request…` without a
provider-confirmed model, progress, or token counts. The run was then ended
without allowing another generation. Its usage record settled the admitted
call with `ledgerState: failed`, `settledCalls: 1`, `inFlightCalls: 0`, and
`productOutcome: unknown`; completion was not claimed and the clone remained
unchanged. This confirms the cancellation/late-usage accounting path, while
also leaving the provider convergence issue open.

### 2026-09-14 provider timeout and RC refresh

The provider step ceiling was reduced from 300 seconds to 120 seconds so a
wedged CLI cannot leave the UI and a reserved call open for five minutes. The
existing bounded retry and settlement ledger remains authoritative. The named
RC was rebuilt from commit `599907a` using the **Test** configuration (the
isolated bundle identity), strict code-signature verification passed, and the
native Settings panel relaunched successfully. The executable SHA-256 is
`5b6a6ca93aaa6bbaf1bd915c9e90238a5d551504e46d113b2699628e9438c8f3`.

The first native run on this refreshed RC used the frozen NitroAI transfer
request. After 120 seconds with no provider progress, the new ceiling ended it
and the usage record settled one call as failed with unknown product outcome;
no source or clone files changed. This validates the shorter bound but does not
yet satisfy the provider-backed feature-delivery gate.

### 2026-09-14 bounded complex transfer attempt

The signed RC was exercised through the native UI with an explicit **Feature** route. The request was intentionally scoped to the existing NitroAI transfer design: add Settings export/import controls, preserve folder and note identity, keep both copies on same-ID collisions, reject malformed or dangling references atomically, and run the focused tests/build.

Iris asked two concrete clarification questions. The live answers were **Notes and folders only** and **keep both copies**. The generated plan exposed the approach and technical checks, and the starting test check passed before editing. The model then spent eight setup steps rereading the same repository and transfer fixtures without changing a file. The user-facing Stop control was used; the RC reported “Stopped at your request — nothing was changed,” and the clone was reverted/left clean. No provider-generated feature, delivery, relaunch, or transfer acceptance is claimed from this run. This is evidence of a remaining complex-run convergence problem, not a completed transfer feature.

RC under test: `/Users/Shared/Iris-RC-20260914/Iris Test.app`.

The RC was rebuilt from the integrated worktree with the stable local identity
`Iris Local Code Signing` and verified with `codesign --verify --deep --strict`.
Its bundle identifier is `com.publikhq.iris.test` and its code-signing
authority is `Iris Local Code Signing`. This matters because macOS TCC grants
are tied to the signed client, not merely the display name.

## Observed native journeys

- Fresh launch opened the settings panel as **Iris · Active**, with no setup or
  revoked-permissions panel. The app catalog, installed test apps, and the
  `Refresh catalog` control were visible.
- Opening NitroAI's edit action produced an app-specific composer with the
  field `What should change in NitroAI Iris Test?`.
- Selecting **Ask** changed the header to **General help**, removed the app
  selector, and changed the field to `Ask something else…` / `Ask Iris…`.
- Selecting **Edit** restored the NitroAI-specific selector and field.
- Selecting **New chat** from Edit switched to General help and cleared the
  app-specific draft surface.
- Expanding **Saved app versions** showed retained NitroAI and PlantGPT records,
  explicit previous-file status, and the read-only `Review cleanup…` action.
- Entering the real `cue` guide in the Test RC correctly refused to open it and
  said Test is for editing separate test copies; marketplace installation guides
  must be exercised through regular Iris. This is an explicit environment
  boundary, not evidence that spatial guidance works.

## Retention fix and live verification

The first RC run returned `No cleanup preview is available` because Finder's
`.DS_Store` inside the backup namespace was classified as corrupt inventory.
The retention validator now ignores only that harmless metadata file and still
fails closed on all other unexpected files. The focused harness suite passed
159/159 after the change. A fresh signed RC then produced live read-only
previews for both NitroAI and PlantGPT while their apps were stopped:
`No eligible obsolete restored backups ... Logical bytes: 0. Allocated bytes:
0`. No files were removed.

The current receipt-owned cleanup scope contains newer `edit-delivery-backups`
records; older `installation-backup-*` bundles are outside that receipt-owned
scope and remain untouched.

The Test app support directory currently measures about 3.5 GB: roughly 2.5 GB
of copied project dependencies, 713 MB of delivery backups, and 258 MB of
command scratch. The cleanup control only owns receipt-backed app bundles; it
does not silently delete project dependencies or scratch data.

## Kneecap catalog boundary

After `Refresh catalog`, the signed RC's deliberate search showed `kneecap`
with both `Guide available` and `Install with Iris`. Selecting that action was
then refused with the explicit Test-only message that marketplace guides must
use regular Iris. The public guide endpoint is live and identifies commit
`fc48ba487a1e0d0cd10b30d6600acd2895ffdbed`; the local `/Users/akrit/kneecap`
checkout is detached at that commit but has a modified `bun.lock` and two
untracked `.DS_Store` files. No reset, stash, deletion, or install was done.

The live composer preserved a realistic complex transfer draft while switching
modes: `Move my notes into a folder and let me import them back without losing
anything` was staged in NitroAI Edit, switching to Ask cleared the
app-specific field, and switching back to Edit restored the exact draft. No
provider request was sent during this check.

Spatial pointing, a delivered complex transfer through the live composer, and
physical iPhone install/open/restart still require their respective live
acceptance runs. Offline suites remain separate evidence.

## Kneecap source-root guard

Commit `ae44885` adds a production workspace check that runs `git rev-parse
--show-toplevel` and refuses a selected nested folder with `select the Git
repository root`. The focused service harness exercised the actual dirty
`/Users/akrit/kneecap` checkout and recorded: nested folder refused, dirty
pinned source required isolation, and detached staging used the exact
`fc48ba487a1e0d0cd10b30d6600acd2895ffdbed` revision. The original checkout was
left unchanged. The live guide remains a proposal and has no served device
handoff, so this proves source selection and staging only, not iPhone
installation.

## Signed RC refresh after source-root fix

The named RC was rebuilt from the integrated worktree after `ae44885` with
`xcodebuild` (`BUILD SUCCEEDED`) and the stable `Iris Local Code Signing`
identity. Strict verification passed. The current executable SHA-256 is
`a7f1b364a65f3ee86cfbda235e69f95c8a8c3864f1202e25d9cf10849caa85d8` and is
also recorded in `/Users/Shared/Iris-RC-20260914/ARTIFACT_SHA256.txt`. Native
computer use relaunched the refreshed RC, opened Settings, and showed the
expected active state, catalog, saved versions, and cleanup preview controls.
The previous RC was retained beside it as a rollback copy.

## Signed RC refresh after legacy recovery-action fix

Commits `fe778da`, `5204d01`, and `5debe73` keep the source-workspace recovery
action available when a legacy guide refuses automation because its saved
binding is stale or invalid. The RC was rebuilt with `xcodebuild` (`BUILD
SUCCEEDED`), passed `codesign --verify --deep --strict`, and was relaunched from
`/Users/Shared/Iris-RC-20260914/Iris Test.app`. The current executable SHA-256 is
`9aad5671ed251d9f3f29eaac2bb450a2d28029bc2ecfe0f28aea1da33d7a7bf2`.

Native computer use re-opened the Kneecap guide and reproduced the refusal
message, confirming the guard still prevents an unvalidated legacy path from
running. The picker affordance is present in the rebuilt source but the final
picker interaction and isolated-copy preparation remain a live acceptance gate;
the existing `/Users/akrit/kneecap` checkout was not modified.

Focused verification after this change: harness `159/159` tests in 7 suites,
source-workspace `5/5`, and mobile catalog `18/18` passed. These are unit and
service checks; they do not substitute for the pending native picker,
device-install, or physical iPhone acceptance evidence.

## Recovery-state follow-through

Commits `7977747`, `8e23ace`, and `b163bf0` make the legacy-workspace refusal
state explicit and keep the recovery affordance attached to that refusal. The
final rebuilt RC passed strict signing and is installed at
`/Users/Shared/Iris-RC-20260914/Iris Test.app`; executable SHA-256:
`1ae7b2c9e1df4f443422155af8d8110aea710d0d9f0f7c01fb2e2a1827d2e91b`.

Computer-use testing reached the live Kneecap step and reproduced the refusal
message on this RC. The remaining acceptance action is selecting
`/Users/Shared/Iris-RC-20260914/Kneecap-validated-fc48ba48`, preparing its
isolated copy, and verifying the mapped commands and device handoff. That
interaction has not been claimed complete.

## Overlay recovery action and picker selection

Commit `a9cd228` adds the source picker action to the actual overlay control,
where the native guide exposes `Let Iris run it`. The RC was rebuilt
successfully, strictly signed, and relaunched. Computer use reproduced the
legacy refusal; the same visible control then changed to `Choose source
folder`. The native `NSOpenPanel` opened, and the validated path
`/Users/Shared/Iris-RC-20260914/Kneecap-validated-fc48ba48` was selected through
the panel and submitted.

The overlay does not render the subsequent source-inspection state, so the
inspection result and isolated-copy choice still need to be observed through
the guide panel before commands can be run. No command was started and the
original `/Users/akrit/kneecap` tree remains unchanged.
### 2026-09-14 native RC follow-up: isolated source setup and install admission

- RC: `/Users/Shared/Iris-RC-20260914/Iris Test.app`; latest executable hash `286e03e3164597a3f5e5d3f1d0eff691189f7800240fb8bb644165973cdfe13d`.
- Native UI path: opened the Kneecap guide in the signed RC, used the visible `Choose source folder` recovery action, selected `/Users/Shared/Iris-RC-20260914/Kneecap-validated-fc48ba48` through the macOS folder picker, and observed `Inspecting the selected source folder...` followed by `Preparing an isolated copy...`.
- Preparation succeeded after the owned workspace root fix. A new ready record was written at `/Users/akrit/Library/Application Support/Iris Test/GuideSourceWorkspaces/records/106CBA35-A170-431E-B9E8-9745549C43FB.json`; its staged path is `/Users/akrit/Library/Application Support/Iris Test/GuideSourceWorkspaces/kneecap-106CBA35-A170-431E-B9E8-9745549C43FB`, reviewed commit `fc48ba487a1e0d0cd10b30d6600acd2895ffdbed`, and expected origin `https://github.com/Blueturboguy07/kneecap`.
- The original checkout remained separate and unchanged at the known dirty-state boundary (`bun.lock` modified plus existing `.DS_Store` files). No source folder was moved or deleted.
- Reopened guide resumed at step 6 with the validated binding, then the native `Let Iris run it` action changed the overlay to `Installing kneecap 6/15` with `Show terminal` and `Stop`, proving the command was admitted to the isolated workspace. The run then exited the guide surface before terminal transcript capture; command success and downstream device/install completion are still unverified.

### 2026-09-14 implementation follow-up

- Spatial lifecycle fix `2113226`: stale target outlines now clear when a step disappears, refresh cannot reacquire the target, or the guide tears down. Focused guide regressions passed 72 tests across 5 suites; native movement/tab-switch acceptance remains open.
- Version-history bound `bbe3530`: saved-version preview uses the 1,024-record cleanup ceiling consistently, with over-cap assertions preserving newest and rollback records. Focused retention and offline harness checks passed; a pre-existing exact-cap write-boundary check remains separately tracked.
- A broad macOS `xcodebuild test` invocation was terminated after its test app remained live for more than six minutes at sustained CPU without producing completion output. It is not counted as a pass; focused suites remain the authoritative automated evidence for these changes.
- Rebuilt RC v2 at `/Users/Shared/Iris-RC-20260914-v2/Iris Test.app` with executable SHA-256 `8c8308954bc1c915aff7910bb4b9b111e4a9de4dd4042f3abec4e78756d3a6fa`; strict code-signature verification passed.
- Native relaunch check with RC v2 reopened Kneecap, reloaded to step 6, and admitted the persisted staged workspace without asking for the source folder again. This verifies binding persistence across relaunch. Clicking `Let Iris run it` again reached `Installing kneecap 6/15`; opening `Show terminal` closed the guide surface without exposing a terminal transcript, so command exit and device handoff remain unverified.
- RC v4 at `/Users/Shared/Iris-RC-20260914-v4/Iris Test.app` includes the command-boundary fix that rewrites legacy `~/kneecap` references even when a structural workspace binding is present. Native computer-use rerun reached `Installing kneecap 6/15` and returned to the normal `Let Iris run it` state without the prior `Install paused. A step failed.` surface. This is evidence that the mapped step completed; terminal transcript and later mobile/device steps remain open.

### 2026-09-14 native RC v5: mapped install/build and Xcode handoff

- RC v5 at `/Users/Shared/Iris-RC-20260914-v5/Iris Test.app` was rebuilt from
  the integrated worktree and passed strict `codesign --verify --deep --strict`.
  Executable SHA-256: `2891efd9812d9cf697b8e58ce30ac0cc0714d6c2c54c941615b8065320954789`.
- Native computer use relaunched the guide from the persisted Kneecap binding.
  Step 7 (`bun install`) was admitted and completed in the staged worktree;
  the original `/Users/akrit/kneecap` checkout retained its prior dirty state.
  Step 8 (editor build) then completed and advanced the guide to step 9.
- Step 9 is a manual Xcode handoff. The reader-facing card identified Xcode as
  the required action; clicking `Let Iris run it` handed the step to the reader.
  Computer use confirmed Xcode was open on the real `leanring-buddy` workspace.
  This proves app launch/handoff, but not licence acceptance, signing, or a
  physical iPhone install. Those native/device gates remain open.
- The Xcode test navigator currently shows an unrelated broad historical test
  run with failures (1427 tests, 147 issues); it is not counted as evidence for
  the RC. The broad run was not used to claim a pass. Focused spatial and
  offline-harness suites remain the authoritative automated checks.
- While the RC was open, computer use clicked the real `Refresh catalog` action
  in Settings. The live `Last checked` timestamp advanced from 3:35 PM to
  3:43 PM and the catalog remained usable, providing native evidence for the
  refresh path and icon/catalog surface. This does not prove every published
  app has a valid guide or close the phone-device gate.
- Mobile hub continuity commit `ba28ff2` persists the selected device target
  across browser restarts, rejects invalid stored targets, and allows catalog
  discovery when storage is unavailable. Its focused Node suite passed `19/19`.
  This is code and browser-hub evidence only; signed physical iPhone install,
  launch, restart, and data continuity remain unverified.
- Spatial integration commit `c33ed52` adds a bounded 900 ms revalidation loop
  while a guide remains visible. The loop reuses the existing target identity,
  ambiguity, minimization, cancellation, and model-budget gates and stops when
  the guide is hidden or closed. Native build succeeded; spatial checks passed
  `11/11` and guide regressions passed `72` tests in `5` suites. The integrated
  RC still needs a fresh native movement/tab-switch run after rebuilding with
  this commit.
- Integrated RC v6 was built through the Xcode GUI, copied to
  `/Users/Shared/Iris-RC-20260914-v6/Iris Test.app`, re-signed with the local
  test identity, and passed strict signature verification. Its executable
  SHA-256 is `787870e782e4696523f4bcca0a41e3692c22887b4f714ce9ff424a6fa14f9b96`.
  On launch, the real
  app reported that Accessibility and Screen Recording permissions had been
  revoked and presented its native `Grant`/`Show Iris` controls. This is an
  explicit environment gate: no TCC reset or permission claim is made, and
  fresh native spatial acceptance must resume after those permissions are
  restored through the normal macOS flow.
- Post-integration focused rerun: mobile hub `19/19` and source-workspace
  identity `5/5` passed. A harness-host invocation without its required scratch
  environment failed fast; rerunning it with an explicit fresh scratch root
  passed all reported checks, including usage attribution, review reserve,
  cancellation, command freshness, and accepted-candidate identity checks.

### 2026-09-14 routing budget follow-up

- Commit `016053f` enforces per-route model budgets in `HarnessModelSession`: input-byte ceilings are checked before admission or transport, caller output requests are capped to route policy, and oversized input produces an explicit blocked lifecycle result without sending a model request.
- Focused harness suite passed `161/161` tests across `7` suites after the change. This is source-level routing evidence only; live provider, packaged UI, installed-app, and physical-device acceptance remain separate gates.

### 2026-09-14 native RC v7: routing-budget integration build

- Xcode GUI built the integrated `Iris Test` scheme after routing commit `016053f`; the resulting app was copied to `/Users/Shared/Iris-RC-20260914-v7/Iris Test.app`.
- Strict code-signature verification passed. Executable SHA-256: `bc572ec21ceafe003cf4ee4950de0b57a0f45334087a1afffde39f3c66f73b14`.
- The build was launched through Xcode and then stopped cleanly. This establishes a named integrated artifact, but does not close native spatial permissions, live-provider transfer, or physical-device acceptance.

### 2026-09-14 NitroAI transfer lane checkpoint

- The NitroAI source remains clean at `6d4209c`. Settings exposes `Export notes and folders` and `Import notes and folders`; the database import path validates v1 envelopes, preserves existing records, copies changed same-ID notes, rejects dangling or duplicate folders, and restores atomically on failure.
- The isolated transfer oracle passed `2/2` with private temporary roots. Iris harness remains `161/161`.
- This does not close the Iris-mediated complex-feature gate. The last native provider attempt made eight setup calls that reread repository/oracle context without producing an edit or delivery; the next action is a single convergent provider run followed by native delivery, relaunch, and readback.

### 2026-09-14 provider convergence guard

- Commit `d86e435` bounds pre-edit investigation for on-demand feature work. After three unchanged investigation steps Iris nudges the provider toward a source edit; after three more unchanged steps it stops honestly and restores the candidate instead of looping.
- Commit `4aed5fd` aligns the regression fixture with the production `CodexMaintainProvider` capability surface. The focused source test parses successfully; the existing harness remains `161/161` across `7` suites.
- This closes the production-path convergence guard at source level. A live provider run, packaged delivery, relaunch, and native complex-feature acceptance are still required before claiming the full journey.
- Xcode GUI produced a fresh signed integration artifact at `/Users/Shared/Iris-RC-20260914-v8-162216/Iris Test.app`; strict verification passed. Executable SHA-256: `6857194386a6ffe6d0ae0147a864affd5bdb41924d4bdb3525b9ccc1e45731cb`. This artifact build is recorded, but it does not by itself prove a live provider edit or device acceptance.
- A fresh mobile hub run on this worktree passed all `19/19` Node tests. The live catalog still correctly exposes Kneecap with no verified iOS destination, so the UI keeps the iPhone route at `Setup needed` and hands off to the signed-build guide rather than inventing an install link.
- Native RC v8 computer-use observation: the menu-bar eye opened the Iris panel and the `New chat` action switched the composer to an unbound general `Ask Iris` state. The panel accurately reported that Codex was connected for app edits while screen help was separate; with no usable text-only help connection, the Send control stayed disabled. This is truthful capability gating, but it is not a completed live conversation or screen-aware acceptance.
- Native RC v9 computer-use observation: after rebuilding from the integrated tree with the Codex capability-state fix, the menu-bar composer showed `Codex general help` consistently. A realistic request asking what to do next while looking at the app enabled Send, dispatched through the native Ask path, and returned a truthful response asking which app and goal were involved while stating that screen help requires a separate connection. This proves native Ask dispatch and label/button consistency for the available text-only route; it does not prove screen capture, spatial guidance, or device acceptance.

### 2026-09-14 retry environment refresh implementation

- Commit `f0ba4bb` simplified the in-place retry refresh for the persistent guide shell. It now tolerates reader rc errors, reloads the rc, adds existing standard per-user tool locations (`~/.bun/bin`, `~/.local/bin`, `~/.cargo/bin`), restores the prior working directory, and clears the shell command hash in one bounded command. This keeps retries in the same shell while allowing a tool installed during a surfaced step to become discoverable without relaunching Iris.
- The focused harness remains `161/161`; Xcode's Bug 3 native subset still needs a completed post-change run before this lane can be called accepted. Existing stale failures remain evidence, not a pass.
- Xcode GUI rebuilt the updated app into `/Users/Shared/Iris-RC-20260914-v10/Iris Test.app`; `codesign --verify --deep --strict` passed and the executable SHA-256 is `d470595ba8197f7fe2f6e195354cfe1b494c5b3f49a7e92738edea78435c8653`. This is a fresh candidate artifact only; the Bug 3 retry tests and native install journey remain open.

### 2026-09-14 focused native Bug 3 verification after refresh fix

- Xcode GUI ran the focused native tests against the integrated tree, one at a time rather than relying on the stale historical navigator summary. All three relevant tests passed: `tryAgainAfterAMidRunToolInstallStillCannotFindTheTool()` (3.737s), `theInstallFinishesAfterTheReaderInstallsTheToolAndTapsTryAgain()` (1.301s), and `theShippedShellSurvivesTheRetryPathOnThisMacsOwnDotfiles()` (0.742s).
- The tests exercised the actual controller retry path and real pty shell. The first test proved a mid-run Bun install becomes discoverable on retry while keeping one shell process; the end-to-end test proved the real Bun and Node build completed and wrote the editor page; the continuity control proved earlier exports and pager settings survived the refresh.
- This closes the focused native Bug 3 retry evidence for RC v10. It does not close the broader Kneecap phone handoff, physical iPhone install/restart, spatial movement/tab-switch, or Iris-mediated complex transfer gates.

### 2026-09-14 focused native spatial verification

- Xcode GUI ran `a reader who moves a window mid-install is asked about once and pointed at where the control is` against the integrated tree. It passed in 2.374s after driving the real guide to the manual Xcode gate, using two real AppKit panels, moving the focused panel during the simulated capture round trip, and observing one model ask. The final eye point was 0.0pt from the moved control; the untouched same-app window was not used.
- The test initially exposed a runner setup problem because Xcode itself was frontmost. The test now activates the already-running Finder app before checking its frontmost-app premise, using an async bounded wait without deprecated activation or run-loop calls. The corrected test passed with no new compiler warnings.
- This is native macOS movement and activation evidence for the focused spatial path. Full product acceptance still requires live screen-capture/provider behavior and the remaining minimize, cancellation, tab-switch, ambiguity, and physical-device gates.

### 2026-09-14 RC v11 artifact

- The integrated source was packaged as `/Users/Shared/Iris-RC-20260914-v11/Iris Test.app` after the native spatial test correction. Strict code-signature verification passed using `Iris Local Code Signing`; executable SHA-256 is `2a0f47f584a95d582eddb5cf6b5a3618bac240b17796308fe54f8c191c2f643c`.
- v11 is the current named candidate for subsequent native acceptance. The existing v10 artifact remains available for rollback.

### 2026-09-14 focused native pointing lifecycle verification

- Xcode GUI reran the three remaining Root cause C lifecycle guards directly
  against the integrated tree, rather than trusting the navigator's stale
  historical status. `going back into the same app on the same step does not
  point all over again` passed in 3.220s with zero extra flights across three
  settled activations; `leaving the app and coming back does not fly the eye
  out all over again` passed in 3.400s with zero extra flights across three
  out-and-back cycles; and `a step change still re-points — a debounce must not
  turn the eye off` passed in 1.884s with the new step receiving its own flight.
- These runs close the focused native lifecycle evidence for Root cause C. The
  navigator can still display old failures until its historical aggregate is
  refreshed; the direct results above are the authoritative post-change runs.
  Live provider-backed screen capture, the remaining complex transfer journey,
  and physical iPhone acceptance remain open gates.

### 2026-09-14 Codex capability refresh

- The native Ask bar now refreshes the published Codex login snapshot when it
  appears and whenever another application activates. This keeps the connection
  label, Send gate, and dispatch preflight aligned after an external
  `codex login` or `codex logout` while Iris remains open.
- The integrated `Iris Test` scheme compiled successfully with
  `xcodebuild ... build CODE_SIGNING_ALLOWED=NO`. Existing Swift concurrency
  warnings remain in unrelated legacy paths; no new warning was introduced by
  the refresh hook.

### 2026-09-14 RC v12 capability-refresh artifact

- The capability-refresh change was packaged as `/Users/Shared/Iris-RC-20260914-v12/Iris.app` and signed with the local test identity. Strict verification passed; executable SHA-256 is `02cb4e858c52c10ae671247768a5acd5d9c7118060ebb804448b0264886a3628`.
- v12 is a candidate artifact for the next native Ask acceptance pass. It does not close live screen capture, provider-backed transfer, or physical iPhone gates.

### 2026-09-14 integrated automated regression rerun

- The current integrated tree reran the harness suite with `161/161` tests
  passing across `7` suites, including route budgets, cancellation and late
  settlement accounting, review reserve, convergence bounds, and source-root
  guards.
- Source-workspace identity/storage checks passed `5/5`; the mobile install hub
  suite passed `19/19`, including cache timeout recovery, device preference
  persistence, safe route validation, icon validation, and bounded catalog
  handling.
- `system_profiler SPUSBDataType` found no connected iPhone or iPad. Physical
  install, launch, restart, and update continuity therefore remain an explicit
  device gate rather than a claimed result.

### 2026-09-14 NitroAI transfer regression rerun

- The current `/Users/akrit/NitroAI` source passed its complete Vitest suite:
  `14` files and `140` tests. The transfer-specific database checks passed as
  part of that run, including export/import envelopes, duplicate and dangling
  references, atomic failure behavior, and changed same-ID content retention.
- This is fresh source-level NitroAI evidence. It does not claim Iris generated
  or delivered the feature through a live provider, nor does it replace the
  pending packaged relaunch/readback acceptance.

### 2026-09-14 shared capability dispatch guard

- Commit `67ecf9c` closes a route contradiction: Edit Send now requires the
  resolved editing provider capability, and the shared `CompanionManager`
  dispatch entry refreshes Codex login state for callers outside the overlay.
- Focused `ComposerConnectionPresentationTests` passed `13/13`; Swift parsing
  and diff checks passed. This is source and focused-test evidence. A rebuilt
  native candidate still needs the live Ask/Edit interaction rerun.

### 2026-09-14 RC v13 capability dispatch build

- Xcode built the integrated `Iris Test` scheme from commit `67ecf9c` with
  `CODE_SIGNING_ALLOWED=NO`; the build completed successfully.
- The candidate was copied to `/Users/Shared/Iris-RC-20260914-v13/Iris Test.app`,
  signed with the local test identity, and passed strict deep signature
  verification. Executable SHA-256 is
  `946db8751918e8ce31d0acd9b8cd85b0945455a8ada47ebe2563605e6c784b50`.
- This names a current integrated candidate. It does not substitute for the
  live Ask/Edit interaction rerun, provider-backed transfer, or device gates.
- The first Xcode-only focused invocation ran zero tests because the project
  excluded `ComposerConnectionPresentationTests.swift`. Removing that single
  exclusion restored discovery: the same scheme then ran all `13/13` focused
  tests successfully. This closes the test-target wiring gap; it does not
  close the native permission, provider, or device gates.
- Computer-use launch of v13 reached Iris's native permissions panel and
  reported Accessibility and Screen Recording as revoked. The disposable RC
  was quit after observation; no permission state was changed. This is a live
  native environment gate, so Ask/Edit and spatial acceptance remain pending
  until the owner restores permissions through macOS settings.

### 2026-09-14 RC v14 test-target wiring build

- Xcode rebuilt the integrated `Iris Test` scheme after restoring native test
  discovery. The signed candidate is
  `/Users/Shared/Iris-RC-20260914-v14/Iris Test.app`.
- Strict deep signature verification passed with executable SHA-256
  `ed4e29428dd4545cba99b7e05d709135c340c062be67c292dbe9c9d2e65de927`.
- RC v14 is ready for the permission-restored native run; provider-backed
  transfer and physical-device acceptance remain open.

### 2026-09-14 spatial regression discovery and rerun

- Restored `SpatialGuidanceRegressionTests.swift` to the native Xcode test
  target. The focused scheme then discovered and passed all `7/7` spatial
  regression tests, covering semantic identity, process/window/tab changes,
  duplicate evidence, coordinate transforms, focused-window selection, and
  bounded fallback labels.
- This strengthens source/native test coverage. It is not a substitute for
  the permission-restored live screen-capture journey or physical-device
  acceptance.

### 2026-09-14 installed-delivery history regression rerun

- The native Xcode scheme ran `AppRelaunchInstalledDeliveryTests` with all
  `12/12` tests passing. The run covered clone-path exclusion, application
  copy selection, in-place replacement, injected Undo recovery, interrupted
  swap reconciliation, stale prepared delivery retention, and bundle-ID
  backup paths.
- This is focused native decision and filesystem evidence. It does not prove a
  live provider-generated feature or physical-device continuity.

### 2026-09-14 Kneecap install retry end-to-end rerun

- The native Xcode scheme ran `Bug3StaleShellPathEndToEndTests`; both end-to-end
  tests passed (`2/2`). The run exercised the real shell retry path after a
  tool is installed mid-run and confirmed the shipped shell preserves its
  working directory and user dotfile behavior.
- This closes the focused macOS retry continuity check. It does not prove the
  full phone handoff or physical-device install journey.

### 2026-09-14 Kneecap stale-shell reproduction rerun

- The native scheme ran `Bug3StaleShellPathReproTests`; both reproduction tests
  passed (`2/2`). This confirms the retry refresh makes a tool installed during
  a run discoverable without incorrectly relying on a stale shell path, while
  the fresh-shell control remains explicit.
- This is focused native shell evidence and does not prove the physical phone
  installation or device handoff.

### 2026-09-14 saved-version Undo presentation rerun

- The native scheme ran `SavedAppVersionsSectionTests`; all `4/4` tests passed.
  They cover missing project identity, unregistered projects, changed project
  identity refusal, and exact identity allowing Undo.
- This is focused native UI decision evidence for safe version-history recovery;
  it does not prove live provider delivery or device continuity.

### 2026-09-14 progress durability and cleanup rerun

- The native scheme ran `Test6ProgressDurabilityReproTests`; all `6/6` tests
  passed. This covered carrying versioned keys forward, cleaning obsolete
  keys, rescuing stranded keys, keeping branches separate, preserving the
  stopped step across republish, and restarting safely after a renamed step.
- This is focused native persistence and cleanup evidence. Live provider
  delivery and physical-device continuity remain separate gates.

### 2026-09-14 spend and usage accounting rerun

- The native scheme ran `AssistantSpendLedgerTests`; all `10/10` tests passed.
  They cover provider ownership, OAuth zero-cost handling, published model
  pricing, unknown-model honesty, sub-cent precision, relaunch persistence,
  empty usage, split stream usage, and duplicate-delta protection.
- This is focused native accounting evidence. Live provider execution and
  physical-device acceptance remain separate gates.

### 2026-09-14 native cancellation regression rerun

- The native scheme ran `ChatActionCancellationTests`; all `6/6` tests passed.
  They cover cancellation during approval, superseding an older pending
  approval, preserving the normal approved path, preventing clipboard writes
  after cancellation, retaining the autonomy safety floor, and avoiding extra
  approval work for persisted behavior.
- This is focused native cancellation evidence. Live provider late-settlement
  and physical-device acceptance remain separate gates.

### 2026-09-14 candidate-evidence receipt rerun

- The native scheme ran `EditVerificationReceiptTests`; all `6/6` tests
  passed. These checks ensure skipped checks, build-only results, partial
  passes, and failures remain explicit, and that packaging or installation
  never gets reported as behavior proof without the required evidence.
- This is focused native verification-boundary evidence. Live provider
  delivery and physical-device acceptance remain separate gates.

### 2026-09-14 model selection and routing regression rerun

- The native scheme ran `CodexEditModelSelectionTests`; all `9/9` tests passed,
  including catalog filtering, malformed or oversized cache rejection, safe
  model identifier validation, honest runtime defaults, and persisted valid
  selection behavior.
- This is focused native routing evidence. It does not prove live provider
  execution or physical-device acceptance.

### 2026-09-14 guide setup recovery regression rerun

Ran the native Xcode `Iris Test` scheme against `leanring-buddyTests/GuideSetupRecoveryTests` with signing disabled. Swift Testing executed 7 tests in 1 suite and all passed. Coverage includes diversion into setup when prerequisites are missing, skip/setup branching, recheck failure staying in setup, successful recheck returning to the saved guide step, and setup progress preserving guide progress. This verifies the state transition contract in the harness; it does not establish live provider, installed-app, or physical-device acceptance.

### 2026-09-14 NitroAI transfer oracle rerun

- The transfer oracle ran against the explicitly approved `/Users/akrit/NitroAI`
  target using the repository's installed Electron and Vitest runtime. Both
  tests passed (`2/2` in `1` file, 21.2 seconds): readiness through the real
  note/folder UI and the compound transfer journey covering identity collisions,
  equal-name/equal-time folders, repeated import, malformed and unsupported
  envelopes, dangling relationships, atomic abort, restart persistence, and
  changed same-ID content.
- The oracle now has a dependency-free config in
  `iris-macos/tools/transfer-native-oracle/vitest.config.mjs`, so the external
  test file is discoverable without changing NitroAI's test configuration.
- This is fresh direct NitroAI computer-process/oracle evidence. It proves the
  target app's transfer contract and edge cases, but does not prove that Iris's
  live provider generated, delivered, relaunched, or rechecked the feature.
  Provider-mediated Iris transfer and native installed-app readback remain open
  gates.

### 2026-09-14 pre-edit reply convergence regression

The harness feature host `--checks` run now covers four completed pre-edit reply classes: duplicate/read command, prose-only response, malformed edit block, and an inert shell write attempt. Each scenario is bounded to six model replies, emits one convergence nudge after three, restores the fixture cleanly, and reports the honest no-source-edit outcome. The affected harness build and command-freshness checks passed; this is headless executor evidence, not live provider or installed-app acceptance.

### 2026-09-14 integrated package regression rerun

The integrated harness package ran `swift test --package-path iris-macos/tools/harness-tests`: Swift Testing executed 161 tests in 7 suites and all passed. The mobile install hub ran `node --test iris-mobile/test/*.test.mjs`: 20/20 passed after the handoff-label regression fix. These are source/package regressions; they do not establish live provider, installed-app, or physical-device acceptance.

### 2026-09-14 install and spatial focused rerun

The native `Iris Test` scheme executed the combined `GuideSetupRecoveryTests` and `SpatialGuidanceRegressionTests` selection: 14 tests in 2 suites, all passed. This rerun confirms setup diversion/resume/recheck behavior and semantic spatial target freshness across the integrated source. It remains source/native test evidence only; live provider screen capture, permissions, and physical-device install are still open gates.

### 2026-09-14 mobile handoff wording fix

The mobile hub previously labeled every verified non-web destination “Install,”
including the `mac-assisted` route kind whose contract is a guide handoff. The
hub now labels that route “Open guide” while retaining “Open” for web routes and
“Install” for App Store, TestFlight, and Android package routes. The focused
mobile suite passed `20/20`, including the route-label regression check. The
live catalog still has no verified iPhone or Android destination, so this is
handoff wording evidence only and does not establish a signed build or physical
device acceptance.

### 2026-09-14 failed review retention bound

The headless harness native module compiled successfully after adding bounded
failed-review archival: at most 256 records and 8 MiB of record bytes, with
oversized or non-regular entries rejected before any write. The accompanying
focused harness regression fills the archive and confirms the active
review-held candidate remains on disk when the cap is reached. This protects failed-candidate
continuity across restart; it does not establish installed-app or physical
device behavior.

The standalone `SavedEditDeliveryChecks` executable was then compiled against
the same `IrisHarnessNative` module and ran to completion. It passed all eight
focused checks, including failed/unavailable/truncated repository status,
dirty-source retention across reload, the 256-record/8 MiB archive cap with
the active candidate preserved, runtime-image retirement, clean-source retry
gates, branch/newer-commit invalidation, and queue-save durability. This is
direct executable evidence for the retention path; live provider delivery and
physical-device acceptance remain open.

The full harness package was rerun after the workspace revalidation fix:
`swift test --package-path iris-macos/tools/harness-tests` passed `161/161`
tests across 7 suites. This confirms the production change did not regress the
headless lifecycle, routing, retention, or clarification contracts.

### 2026-09-14 workspace revalidation and cancellation fix

An isolated rerun exposed two issues in `GuideSourceWorkspaceServiceTests`:
revalidation refreshed the staged fingerprint internally but returned the old
binding, and the cancellation tests could observe the scripted executor before
its suspended probe was scheduled. Revalidation now returns the refreshed
binding, and the tests wait for the suspension deterministically. The suite
then passed `8/8`. The correction was rebuilt into
`/Users/Shared/Iris-RC-20260914-v18/Iris Test.app`.

### 2026-09-14 review-context wording regression fix

The review/context rerun initially caught a stale assertion: omitted repository
paths no longer stated plainly that they had not been inspected. The prompt
now includes that explicit disclaimer. `EditVerificationReceiptTests` and
`FeatureEditRepositoryContextTests` then passed `19/19` together. The fix was
rebuilt into `/Users/Shared/Iris-RC-20260914-v17/Iris Test.app` with the Xcode
scheme completing successfully and signing disabled.

### 2026-09-14 run usage attribution rerun

The native scheme reran `IrisTestRunUsageTests`; all `7/7` tests passed. These
checks preserve route and lifecycle dimensions, admitted versus rejected
requests, reserved input bytes, failed transport counts, and unknown usage
measurements without converting them to false zero-cost results. This is
source/native accounting evidence; live provider pricing and settlement remain
open.

### 2026-09-14 cancellation and spend regression rerun

The native scheme reran `ChatActionCancellationTests` and
`AssistantSpendLedgerTests`; all `16/16` tests passed. Coverage includes
approval cancellation, superseding stale work, clipboard safety, autonomy
floor preservation, relaunch persistence, split-stream usage, duplicate-delta
protection, dated model pricing, unknown-cost honesty, and sub-cent precision.
This is native accounting/safety evidence; live provider settlement remains
open.

### 2026-09-14 installed-delivery and Undo regression rerun

The native scheme reran `AppRelaunchInstalledDeliveryTests`; all `12/12`
tests passed. Coverage includes in-place bundle replacement, backup path
identity, startup reconciliation after interrupted swaps, retry-record
restoration, clone-copy exclusion, and injected Undo recovery. This confirms
the delivery/recovery state machine at native test level; installed-app live
continuity remains an acceptance gate.

### 2026-09-14 Kneecap installation regression rerun

The native Xcode scheme reran `Bug7MissingToolSelfInstallEndToEndTests` and
`Bug3StaleShellPathEndToEndTests` together. All `4/4` tests passed, covering
self-install through completion, reader-installed-tool retry, shipped-shell
continuity, and real-tool execution against the Kneecap workspace shape. This
is native fixture evidence; a live install into a selected user workspace and
the phone handoff remain separate acceptance gates.

### 2026-09-14 NitroAI transfer oracle rerun

Using NitroAI's pinned Vitest runtime and the explicitly approved
`/Users/akrit/NitroAI` target, the transfer oracle passed `2/2` tests in 13.12
seconds. The compound case still covers identity collisions, repeated import,
malformed and unsupported envelopes, dangling relationships, atomic abort,
restart persistence, and changed same-ID content. This remains direct target
app evidence; Iris provider generation and delivered-app readback are still
open.

### 2026-09-14 local mobile hub refresh smoke

The integrated `iris-mobile/server.mjs` served the hub successfully at
`http://127.0.0.1:4173/`; the live catalog endpoint returned the expected
bounded app records and the HTML route returned `200`. This confirms the
refresh path is wired in the integrated tree. It is local web evidence only;
it does not establish an App Store/TestFlight destination or physical-phone
installation.

### 2026-09-14 focused native setup and spatial rerun

The Xcode `Iris Test` scheme reran `GuideSetupRecoveryTests` and
`SpatialGuidanceRegressionTests` together. All `14/14` tests passed, covering
setup diversion and return, saved progress, focused-window preference,
semantic target staleness, duplicate refusal, coordinate transforms, and
bounded cues. This remains native test evidence rather than live screen
capture or physical-device acceptance.

The post-routing full regression was rerun on the integration branch: Swift
package tests passed `161/161` across 7 suites and the mobile install hub
passed `20/20`. These results confirm no package-level regression after the
telemetry change; they remain distinct from live-provider and device evidence.

### 2026-09-14 per-route token telemetry regression

The routing lifecycle suite passed all 11 tests after adding provider-reported
input and cached-input token retention for settled, failed, and cancelled
calls. A fresh harness-feature-host build and `--checks` run exited
successfully, including usage-attribution serialization of both token
families. This improves cost and efficiency measurement but does not prove
provider pricing or live-provider execution.

The subsequent per-route token telemetry fix was rebuilt into
`/Users/Shared/Iris-RC-20260914-v16/Iris Test.app`; the Xcode `Iris Test`
scheme again completed successfully with signing disabled. Its executable
hash is `712dcf81f18c7bc024fa77fc9c5374a9d3ab3d88a6cae5239b5671e83db23a65`.

### 2026-09-14 fresh integrated RC build

The current integration branch built successfully with Xcode's `Iris Test`
scheme and signing disabled. The resulting candidate is
`/Users/Shared/Iris-RC-20260914-v15/Iris Test.app` (executable SHA-256
`712dcf81f18c7bc024fa77fc9c5374a9d3ab3d88a6cae5239b5671e83db23a65`). This
ties the latest source and test changes to a named artifact. It does not close
the live-provider, macOS permission, or physical-iPhone acceptance gates.

### 2026-09-14 long-running autonomy-gate regression

The isolated native `GuideAutopilotRunnerTests` suite passed `36/36` after
fixing a safety and reliability gap: a risky long-running command is assessed
with the runner's actual autonomy grant before it can claim the side-session
ownership lane. A refused command therefore leaves the lane available for the
next legitimate step, and process-wide grant state cannot leak into tests.
This is focused native evidence; it does not replace live UI or device
acceptance.

### 2026-09-14 integrated RC v19

The autonomy-gate fix was built with the `Iris Test` scheme and
`CODE_SIGNING_ALLOWED=NO`; Xcode reported `BUILD SUCCEEDED`. The named
artifact is `/Users/Shared/Iris-RC-20260914-v19/Iris Test.app` with executable
SHA-256 `712dcf81f18c7bc024fa77fc9c5374a9d3ab3d88a6cae5239b5671e83db23a65`.
This is an unsigned test candidate, so it is not evidence that macOS TCC or
installed-app acceptance is complete.

The post-fix regression pass also completed the Swift harness package at
`161/161` tests across 7 suites and the mobile hub Node suite at `20/20`.
These checks cover the retained routing, lifecycle, review, storage, and hub
contracts; they do not close native permission, live-provider, or physical
phone acceptance.

### 2026-09-14 signed integrated RC v20

The integration source was built with the available stable local identity
`Iris Local Code Signing`; Xcode reported `BUILD SUCCEEDED`. The candidate is
`/Users/Shared/Iris-RC-20260914-v20/Iris Test.app`. Deep strict signature
verification passed, with identifier `com.publikhq.iris.test` and executable
SHA-256 `df43bf18dcc5a1615f81f6cb02cd381e898283d3dde54b9e0e35d70042f78900`.
This makes a stable permission-bearing candidate available without replacing
the normal Iris installation; Screen Recording and Accessibility consent
still need to be granted and exercised by a native UI operator.

The signed candidate declares the required Screen Recording usage description,
network client, user-selected file access, and screen-capture picker exception
entitlements. This confirms the remaining permission gap is runtime consent
on this Mac, rather than a missing declaration in the bundle.

The fresh compile-gated feature-host run also completed successfully with its
explicit scratch directory and `IRIS_HARNESS_SCRATCH` binding. It reported
passing usage attribution, review-reserve, command-freshness, repair-window,
redaction, accepted-candidate, and pre-edit convergence checks. The host
reported 303 compiler warnings but no compile or check failure; its synthetic
byte reduction remains prompt-text accounting, not provider token savings.

The same fresh host then ran the guide and spatial regression driver. Its
bounded offline suites passed `72/72` across 5 suites in 19.267 seconds, with
the spatial checks exiting successfully. This verifies the retry, shell,
ownership, and spatial state-machine contracts in the integrated source; it
still does not substitute for live screen interaction.

The live Publik catalog was queried directly on 2026-09-14. It returned 27
metadata-only app records with `macBundleId`, release-tag, and guide fields;
it exposed no signed TestFlight/App Store destination, iOS package, or device
open/restart route. The mobile hub therefore correctly renders iPhone as
unavailable and explains the publisher action required. This confirms the
blocker is upstream catalog/distribution state, not a hidden browser test
failure.

The signed v20 candidate was launched from its shared RC path and produced a
live `Iris Test` process, then was quit cleanly. This is a bounded startup
smoke only; without native screen interaction it does not establish the
Kneecap, spatial, or permission journeys.

The signed RC was relaunched with its isolated Test onboarding state reset.
Using macOS UI scripting, the visible Setup panel's Start control was clicked;
the panel transitioned to the idle companion state and displayed the real
overlay eye with the “press control + option and ask me anything” guidance.
This is the first recorded native panel activation and start interaction on
v20. It does not yet prove a live provider response or a full click-through
spatial journey.

### 2026-09-14 native capture probe

The signed v20 candidate was launched and a native `screencapture` probe was
taken before quitting it. The probe produced a valid PNG container but the
entire 3024x1964 frame was black; System Events reported the app as not
frontmost with zero windows. The bundle is a menu-bar app, so this is
consistent with a launch smoke that never opened its panel, not proof of a
Screen Recording failure. Native panel activation and screen interaction
remain unverified and require the actual UI operator path.

The post-change native Kneecap subset was rerun against the integrated source:
`Bug7MissingToolSelfInstallEndToEndTests` and
`Bug3StaleShellPathEndToEndTests` passed `4/4` in 3.761 seconds. This closes
the stale subset evidence item for self-install, reader-installed-tool retry,
shell continuity, and real-tool execution in the fixture workspace. It remains
fixture/native evidence, not a live user-folder install or phone handoff.

### 2026-09-14 native Ask smoke and screen-permission boundary

After setup activation, the signed v20 overlay was summoned with the documented
Control+Option gesture. A user-like prompt, `What app is currently visible?`,
was entered and submitted through the live overlay. Iris returned the truthful
message: `I can't see your screen. Connecting screen help is required for Iris
to identify the app currently visible.` The native path therefore proves overlay
input and submission, plus truthful refusal when screen access is unavailable;
it does not prove screen capture, spatial targeting, or Kneecap guidance. The
visible permission panel still requires runtime Screen Recording and
Accessibility consent from macOS before those journeys can be accepted.

The integrated source also contains the bounded failed-review archive: at most
256 records and 8 MiB of record bytes, with oversized or non-regular entries
rejected before writing. Its focused regression confirms that the active
review-held candidate remains on disk when the archive cap is reached. This
protects failed-candidate continuity across restart without retaining an
unbounded history.

### 2026-09-14 screen-help handshake fix

The screen-help actions now invoke the one-time ScreenCaptureKit connection
handshake before opening the Connections panel. Previously they only navigated
to Settings, leaving `hasScreenContentPermission` false even when Screen
Recording was already enabled. The `Iris Test` scheme rebuilt successfully
with this change; the next native probe must verify that the picker/capture
result changes the status and that a subsequent Ask includes a real screen.

The signed v21 smoke launched the test bundle and displayed its permission
recovery panel. Because v21 has a fresh signing identity, macOS reports its
Accessibility and Screen Recording grants as revoked even though the older
v20 identity appears enabled in System Settings. The app correctly stops at
that gate instead of pretending screen capture is available. A native operator
must grant the current v21 identity and restart it; only then can the new
screen-help handshake and spatial journey be exercised.

The setup panel was also corrected to keep the Screen Content permission row
visible when Screen Recording is missing, with an explicit dependency message.
The prior UI said “Grant all three” while rendering only two controls. The
`Iris Test` scheme rebuilt successfully after this change; a native permission
recheck remains required on the signed candidate.

The signed integrated RC was rebuilt as v22 after the permission-row and
screen-help changes. Xcode reported `BUILD SUCCEEDED`; deep strict signature
verification passed. The artifact is `/Users/Shared/Iris-RC-20260914-v22/Iris
Test.app` with executable SHA-256
`0b73d4205417c98112f9a6775fa0eb9599c5ede1496264bab52c1ed133aca8af`.
