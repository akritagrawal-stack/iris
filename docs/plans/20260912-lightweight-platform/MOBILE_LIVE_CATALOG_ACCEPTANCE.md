# Live mobile catalog acceptance, September 12, 2026

Scope: the lightweight catalog and installation-route hub. This is not a new native runtime, a completed mobile installer, or physical-phone acceptance.

## Implemented and checked

Commits `cb65020` and `02b866d` replace the opt-in prototype feed with the public Publik catalog, through a fixed same-origin proxy. A Terra review of the final source found no remaining blocker in this scoped catalog path. All 18 focused Node tests passed; syntax checks and `git diff --check` passed. Final copy says no download is *listed here*, because missing catalog metadata does not prove a package does not exist elsewhere.

Real computer-use checks ran against the local server on port 4178, at 390 by 844 pixels:

- Loaded 26 current Publik entries, including Kneecap, from the real public API.
- Selected iPhone, Android, and Computer. Missing platform metadata remained unknown, including entries with only a Mac bundle ID. No unsupported Install button appeared.
- Switched the test tab offline, clicked Refresh, changed devices, and confirmed the saved-catalog warning remained visible. Restored network access and clicked Refresh; the live ready state returned.
- Expanded Kneecap publisher setup details and followed its visible setup link to the real `https://publikhq.com/kneecap` page, then used browser Back to return to the 26-entry catalog.
- Inspected screenshots and measured document width: 390 pixels, matching the viewport, with no horizontal overflow. Temporary network and viewport overrides were restored.

The failed first pass was useful: it reproduced a false ready status while offline and an incorrect unsupported-phone label. Both were corrected and retested through the UI. Browser Back currently returns to the default iPhone selection; retaining device choice across navigation is not implemented.

## Efficiency and failure behavior

The four served HTML/JS/CSS files total 36,060 bytes before compression. Including both local server modules, application source totals 42,547 bytes, excluding tests and documentation. No added dependencies, model API calls, native binaries, service worker, background downloads, or storage copies are used by the hub. Catalog responses have a 64 KiB input bound; only the first 32 entries render, with an explicit total/limited-view message if more exist. The browser cache has a 64 KiB storage bound and a one-day freshness window; older metadata can be displayed with an explicit stale/offline warning. Requests coalesce, have bounded deadlines, and recover on manual retry. The server metadata cache lasts five minutes, refuses redirects, and validates before caching.

## What remains before mobile completion

The current catalog supplies names, slugs, Mac bundle observations, release tags, and guide slugs. It does not supply verified phone distribution URLs or source pins. The hub therefore offers setup guidance, not an invented installer. An existing Kneecap Android debug artifact from successful CI run [34470109689](https://github.com/Blueturboguy07/kneecap/actions/runs/34470109689) was downloaded and inspected separately. That artifact is a test candidate, not a stable release or device pass. iOS CI built an unsigned Simulator target. No connected iPhone was returned by the current CoreDevice inventory.

Remaining acceptance is an actual supported distribution path plus phone install, launch, media import/edit/export, restart and data preservation, and update preservation. Signing-secret availability could not be established because repository secret-name access returned HTTP 403. No release tag, public distribution, production catalog, phone permissions, or publisher signing configuration was changed.
