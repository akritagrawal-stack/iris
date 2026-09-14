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
