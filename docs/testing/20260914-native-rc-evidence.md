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
