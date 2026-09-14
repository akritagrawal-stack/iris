# Native RC evidence, 2026-09-14

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
