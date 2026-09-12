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
