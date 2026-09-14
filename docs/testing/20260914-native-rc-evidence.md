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

## Remaining native evidence

The cleanup preview returned: `No cleanup preview is available. No data was
changed. saved backup inventory is incomplete or corrupt`. This is a safe
refusal, not a successful cleanup result. The current receipt-owned cleanup
scope contains the newer `edit-delivery-backups` directories but no receipt
entries, while older `installation-backup-*` bundles are outside that scope.
No files were removed.

Spatial pointing, a delivered complex transfer through the live composer, and
physical iPhone install/open/restart still require their respective live
acceptance runs. Offline suites remain separate evidence.
