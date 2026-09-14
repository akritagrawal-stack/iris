# Native acceptance, September 12 implementation wave

This is actual computer-use evidence for the new integration build. It does not
supersede the frozen Mann handoff or establish a completed Kneecap installation.

## Build and identity

- Source: `16e13cc` plus the guide fingerprint forwarding and loading/failure
  card changes committed with this report.
- Xcode GUI: current `iris-lightweight-20260912` project, `Iris Test` scheme,
  `My Mac` destination. Build Succeeded at 11:03 AM Pacific, September 12.
- Launched app:
  `/Users/akrit/Library/Developer/Xcode/DerivedData/leanring-buddy-dajsagjrurlvaigplzqblrdboant/Build/Products/Test/Iris Test.app`.
- `Contents/MacOS/Iris Test.debug.dylib` SHA-256:
  `c25f5ecfc97c20a00652d1699552cc57bb2d78c0a6e99e4a802d99b0d4000c5e`.
- The old paused upstream Test debug process was stopped through Xcode. The
  older `/Applications/Iris Test.app` process was quit through its UI. Process
  inspection confirmed no Test executable remained before the new build was
  launched. Neither installed app bundle was replaced.

## Journey and observed result

1. Opened Settings with the app's keyboard shortcut. The real Settings panel
   displayed the two registered fixture apps, a Refresh catalog control, and
   Last checked. Test inventory is registry-backed; this does not prove the
   production marketplace's complete catalog or icons.
2. Entered `kneecap` in the guide-name field and clicked Open. Before the final
   UI change this silently exposed general chat. The controller had a failure
   state, but the step-card renderer required a guide and step and omitted it.
3. Added a loading/failure card independent of step presentation. The first
   real screenshot exposed transparent text over the desktop. Applied the
   existing `IrisShellBackground` readable surface and repeated the build and
   exact UI journey.
4. The final actual screenshot and accessibility tree showed a legible dark
   card: "This guide could not be opened" followed by "Iris Test is for editing
   separate test copies. Use regular Iris for marketplace installations."
   Dismiss was visible above the normal compact composer.
5. Clicked Dismiss. A fresh screenshot and accessibility tree confirmed the
   failure card disappeared and general Ask, Connect screen help, Choose app
   to edit, History and New chat remained reachable.

These actions used the native app through `mcp__cua_repl`, including actual
screenshots. No model call or guide command ran. No user Kneecap source,
normal profile, credential or permission was changed.

## Still unproven

- Actual staged Kneecap setup and continuation, including device handoff.
- Live target outline and freshness after changing tabs or moving windows.
- Full public catalog refresh and icon behavior in the production profile.
- Screen-help authentication: this Test build still reports saved-login
  Keychain access denied and that the login was retained. No reconnect or
  credential-entry action was attempted.
- Candidate reuse, retention deletion, complex transfer correctness and
  update/restart/Undo of the latest combined build.

## Combined integration check at 11:11 AM Pacific

After integrating the reviewed candidate-store and workspace-schema commits,
source `8348f44` plus a comment-only style correction passed:

- 177-source headless native compilation, exit 0, with 266 existing and
  current warnings retained in the compiler log. No warning-cleanup work was
  attempted as part of this integration.
- The existing inert `--checks` suite, including accepted-candidate corruption,
  stale-identity and base/parent symlink checks, exit 0.
- 69 guide tests in five suites, exit 0, including the new unresolved-workspace
  refusal. Spatial checks also exited 0.

Logs are in `/Users/Shared/iris-harness-host-lightweight-final-6InQWI/`:
`build-invocation.log`, `native-compiler.log`, `checks.log`,
`guide-regressions-invocation.log`, `guide-regressions-run.log` and
`spatial-guidance-run.log`. Headless native module SHA-256:
`7503e3ec677903059463f6b6fa897d26151d47274c013bf033cdbba222b93469`.

The combined Xcode GUI build succeeded at 11:11 AM. The earlier Test process
was quit, process inspection confirmed it stopped, and this new Test binary
was launched. Clicking its eye opened the real compact Ask composer with
Choose app to edit, History and New chat. Its `Iris Test.debug.dylib` SHA-256
is `89a2d3eb0e6c5f7401211a53a268abfaf03a0da6d8bc17590a8503cacc93a520`.
Screen help still reported a separate connection requirement. The full guide
refusal/Dismiss journey above was not repeated because these later commits
did not change that UI path.

This final combined build and launch do not upgrade any of the remaining
user-journey or physical-device gaps to a pass.

## Repair-wave verification at 2:55 PM Pacific

Source `e3fa21a` repaired three execution-boundary defects before another
desktop run: guide owner/repository metadata now canonicalizes to the real
`github.com` origin, source setup completions carry a generation so a cancelled
or superseded setup cannot publish late state, and every prepared-workspace
retry revalidates and moves into the current contained directory. The
retention preview also now opens an existing store read-only: an absent store
or lock returns an empty preview without creating either path.

- GUI Xcode build and launch: `iris-lightweight-20260912`, `Iris Test` scheme,
  `My Mac`, completed at approximately 2:54 PM Pacific.
- Launched artifact:
  `/Users/akrit/Library/Developer/Xcode/DerivedData/leanring-buddy-dajsagjrurlvaigplzqblrdboant/Build/Products/Test/Iris Test.app`.
- `Contents/MacOS/Iris Test.debug.dylib` SHA-256:
  `5ba5d20026cd5d5cf1a4394f27351b6e3789164a7986b97e97b2b4723baf9318`.
- The focused native run compiled the repaired module, passed 71 guide tests
  across five suites, passed spatial guidance checks, and passed the existing
  inert harness checks. The dedicated backup-retention executable also passed
  all 8 groups, including the absent-store non-mutation regression. Logs are in
  `/Users/Shared/iris-harness-host-repair-IJzSvG/`.

The app launched and the Iris eye was visible over the desktop. The initial
computer-use accessibility surface was opaque, but a real hover then click on
the eye opened the compact composer. The screenshot showed the expected
“Codex is connected for app edits” message, Connect screen help, Choose app to
edit, History, and New chat. This verifies the repaired build reaches the
normal entry surface. The saved-versions and app-edit controls were not
re-exercised after this repair, so that remains an observation limitation, not
a successful version-history UI acceptance. The earlier saved-versions
open/cancel observation remains evidence only for the existing cleanup screen;
it does not establish that the new retention preview is wired to that UI.

## Version-history preview build at 3:05 PM Pacific

The fresh-preview gate was then built and launched through the same Xcode GUI
scheme. The live artifact remained
`/Users/akrit/Library/Developer/Xcode/DerivedData/leanring-buddy-dajsagjrurlvaigplzqblrdboant/Build/Products/Test/Iris Test.app`;
its `Iris Test.debug.dylib` SHA-256 is
`8ccf741f04ae155e94ebaa33bd2023c1985f23cc3df9c34c915bbe4d6111373e`.

This build gates “Review cleanup…” behind a new async read-only preview for
the selected registered Test app. The destructive confirmation is shown only
when the preview finds eligible obsolete backups, and its text reports the
fresh count plus logical and allocated bytes. The app UI route itself has not
yet been clicked through after this wiring, so this is a build-and-launch fact,
not a completed preview/confirmation acceptance.

## Current native Ask observation, September 14

The current derived `Iris Test.app` was launched through the native computer-use
surface after terminating a stale test process. The Iris eye opened the compact
composer. A real click on **New chat** changed the field to the general `Ask Iris…`
state; it did not bind the conversation to an app. A realistic Kneecap setup
question was entered and remained visible in the field. The Send control was
truthfully disabled because this Test profile reports Codex app editing as
connected but has no connected typed-question or screen-help provider. The
question was cleared without sending or changing user data. This is native UI
and mode-separation evidence; it is not a successful contextual model response.

## Current usability regression run, September 14

`swift test --package-path iris-macos/tools/usability-tests` passed **136 tests
in 17 suites**. This includes spatial target invalidation after app/window
changes, coordinate bounds and movement, retention/history bounds, relaunch and
Undo recovery failure paths, keychain permission boundaries, catalog cache
bounds, and chat reset/reopen behavior. These are source/package regressions;
they do not replace the missing live model, full delivery lifecycle, or
physical-iPhone acceptance evidence.

## Current guide and spatial regression run, September 14

The existing headless module `/tmp/iris-harness-host-A1WBRI` was reused without
building a second model or fixture. `run-guide-regressions.mjs` passed **71
 tests in 5 suites** and the dedicated spatial executable exited **0**. This
covers retry/cancellation/session freshness and the spatial invalidation,
movement, ambiguity, bounds, and app/window-change checks. It remains headless
source evidence; native AX target reacquisition still needs a connected
screen-help provider and live UI interaction.

## Current timeout outcome accounting, September 14

Commit `0885fbf` closes a timed-out or cancelled model session as an explicit
uncertain/failure lifecycle outcome after settling its admitted attempt exactly
once. The regression now asserts the stopped ledger state and terminal reason;
`swift test --package-path iris-macos/tools/harness-tests` passes **159 tests in
7 suites** after the fix. A fresh feature-host build and `--checks` run completed
through the accepted-candidate and repair-window checks; no duplicate-settlement
failure remains. This records bounded terminal accounting, not provider-side late
usage from a real network call.

## Current native history observation, September 14

The live Iris Test panel opened History successfully. It exposes a bounded
Saved conversations area, a separate New chat control, and a visible `Clear
saved chat history` action. The current fixture contains many repeated legacy
"what is in this picture" rows plus two NitroAI guidance rows, making the
storage/retention concern observable in the UI. I did not invoke the destructive
clear action. This verifies discoverability and separation of new chat/history;
it does not prove the full versioned app-bundle lifecycle or cleanup deletion.

## Integrated macOS release-candidate build, September 14

`xcodebuild -project iris-macos/leanring-buddy.xcodeproj -scheme 'Iris Test'
-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` completed with
`BUILD SUCCEEDED`. The artifact was copied to
`/Users/Shared/Iris-RC-20260914/Iris Test.app`; executable SHA-256 is recorded
in `ARTIFACT_SHA256.txt`. This is the named integrated macOS release candidate
for further native UI checks. It is unsigned and therefore does not establish
phone installation or production distribution readiness.

## RC native launch observation, September 14

The named RC was launched through computer use. It opened Iris Setup and
truthfully displayed a permissions-needed state: Accessibility and Screen
Recording grants are missing or revoked, with `Grant`, `Show Iris`, and `Quit
Iris` controls. No permission-setting action was taken. This proves the RC
launches and exposes the required native gate; screen-help/spatial acceptance
remains pending until the owner grants those macOS permissions.

## RC permission destination observation, September 14

The RC's `Show Iris` control opened macOS System Settings to Accessibility.
The list shows `Iris` and `Iris Test (pre-rc-20260913)` enabled, but no entry for
`Iris-RC-20260914`. Screen Recording is also still a required grant in the RC
setup card. I did not add or toggle an application. The owner must add this
specific RC to Accessibility and grant Screen Recording before live spatial
acceptance can proceed.

## NitroAI transfer oracle observation, September 14

The isolated native transfer oracle was run against the explicit `/Users/akrit/NitroAI`
fixture using its Vitest/Electron runtime. The readiness case passed, but the full
round-trip suite stopped during `seed-export`: the fixture could not locate the
`Export notes and folders` control. This is a meaningful complex-feature failure,
not a passed transfer claim. No user NitroAI profile was modified; failure artifacts
were retained for diagnosis. The next bounded action is to reconcile the fixture's
current UI contract with the oracle, then rerun the same round-trip and atomic-failure
cases without generating a second implementation.

The target fixture now exposes both controls and valid/invalid import feedback;
the oracle advanced through all import and rejection cases. The current failure is
an assertion after the journey: the exported destination snapshot contains five
notes/folders where the contract expects six, indicating that an existing seeded
record is being lost during the transfer sequence. This is now a data-preservation
failure to fix, rather than a missing-control or test-setup failure.

After adding an explicit additive-preservation invariant, the oracle advanced
past the record-count assertion and now fails in native visible readback when
reopening the second note with the duplicate title `Same title`. The exported
data contains both records; the remaining defect is UI navigation/readback
stability after the first duplicate-title note is opened and its last-opened
grouping changes.

A controlled repeat after stabilizing dashboard grouping returned to the earlier
record-count failure (five instead of six), confirming that the persistence loss
is independent of duplicate-title card ordering. The oracle is therefore still
red at the transfer journey's preservation boundary, and no complex-feature
acceptance claim is made.

Root cause isolation, September 14: NitroAI persists the repository in
origin-scoped IndexedDB, while the Electron shell and oracle bind the local HTTP
server to a new OS-assigned port on each process launch. A relaunch therefore
opens a fresh origin and cannot see the prior profile's records. The transfer
algorithm itself is additive within one origin; durable cross-relaunch storage
requires a stable origin or a filesystem/native persistence bridge before this
journey can pass.

The stable-origin change is now implemented in NitroAI's Electron shell and the
isolated oracle, using a deterministic profile-derived port. The oracle no longer
loses the destination record and advances through relaunch, collision, duplicate,
malformed, dangling-reference, and atomic-abort checks. The remaining red result
is duplicate-title card reopening after restart; the data snapshot is intact, but
the frozen visible readback cannot reliably select the second matching card.

## Current Iris model-route policy, September 14

New planner and implementation work uses Luna by default. GPT-5.5 is available
for bounded coding and Terra is review-only. Astra remains in the source only as
decodable historical comparison metadata and fixtures; the current composer label
now shows `Luna Max plan · GPT-5.5 edit`. Fresh harness and usability runs passed
159 and 136 tests respectively after this policy was applied.
