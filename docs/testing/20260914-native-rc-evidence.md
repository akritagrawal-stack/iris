# Native RC evidence, 2026-09-14

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

Spatial pointing, a delivered complex transfer through the live composer, and
physical iPhone install/open/restart still require their respective live
acceptance runs. Offline suites remain separate evidence.
