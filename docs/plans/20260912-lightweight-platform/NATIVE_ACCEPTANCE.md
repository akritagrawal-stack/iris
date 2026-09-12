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

Later schema and candidate-record commits require a new combined build before
this report can be used as evidence for that later source revision. The UI
journey itself need only be repeated if integration changes its behavior.
