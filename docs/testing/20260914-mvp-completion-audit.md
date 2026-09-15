# Iris MVP completion audit

Updated 2026-09-14 from the integration branch and recorded test artifacts.

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Kneecap workspace selection, preservation, cancel/retry/resume | Native setup/recovery tests, Bug 3/7 harness coverage, and fresh focused rerun | Source/native flow covered; full installation and downstream device handoff still need live acceptance |
| Spatial click-through guidance | 14/14 native setup/spatial tests, including stale semantic targets, ambiguity refusal, focus ordering, transforms, and bounded cues | Source/native behavior covered; live screen capture and actual click-through still open |
| Lightweight version history and safe Undo | Progress durability, cleanup, relaunch, Undo, failed-review retention, and standalone 8-check retention executable | Source/native behavior covered; installed-app continuity still open |
| Capability-correct routing and usage accounting | 161/161 package tests, 11 routing tests, host usage checks, per-route input/cache token telemetry | Source/package evidence covered; live provider pricing/execution remains open |
| Meaningful complex feature through Iris | NitroAI transfer oracle 2/2 with import/export edge cases | Target-app oracle passes; Iris live generation, delivery, relaunch, and readback remain open |
| Mobile install hub | 20/20 Node tests and local server/catalog smoke | Hub integration covered; no verified iPhone distribution route or physical-device journey |
| Integrated release candidate | `/Users/Shared/Iris-RC-20260914-v23/Iris Test.app`, signed with `Iris Local Code Signing` and deep-strict verified; executable SHA-256 `0fd55e4d4d468cc521dfa139aa4c5d3f320fbd3d1bcfc5364cebdcd77b037d5b` | Stable candidate exists; acceptance is incomplete until live/native/device gates close |

The unverified gates require actual provider-backed execution, Screen Recording
and Accessibility consent for the test bundle, and a connected trusted iPhone
with a verified distribution route. None of those states are inferred from
headless, browser, or package tests.

## Fresh automated rerun (2026-09-14)

- `swift test --package-path iris-macos/tools/harness-tests --parallel`: **161/161** tests passed across 7 suites.
- `node --test iris-mobile/test/*.test.mjs`: **20/20** tests passed.
- The rerun changes automated evidence only; it does not close the live provider, macOS permission, screen-capture, or physical-device gates above.

## Fresh native visual probe (2026-09-14)

- The signed v23 process was live (`Iris Test.app`, PID 35284) and displayed the real overlay over the active Canvas/Chrome workspace, including the current task context, model selector, edited-file receipt, and Ask input.
- `hasScreenContentPermission=1` for the test bundle, and the captured frame was recorded at `/tmp/iris-current-native-20260914.png` (SHA-256 `28d4099d86fa239cdc718bec796b1089bed25589f6800dafc15fbe2ff1fbed18`).
- This proves native overlay rendering and screen-context presentation for this run. It does not by itself prove a completed click-through action, provider-backed edit, or iPhone journey.

## Fresh Kneecap workspace check (2026-09-14)

- Compiled `GuideSourceWorkspace.swift` with `SourceWorkspaceChecks.swift` and ran the standalone executable successfully.
- The check passed structural origin/path guards, bounded command output and child cancellation, dirty-source isolation into a detached worktree, preservation of the original checkout, common-directory recording, and cancellation recovery records.
- This is local source-workspace evidence; it still does not replace the live Kneecap install and downstream phone handoff.

## Fresh integrated host checks (2026-09-14)

- Rebuilt the compile-gated host from the current source tree and ran `--checks` with an isolated scratch directory.
- Result: **exit 0**. Usage attribution, review reserve, command freshness, repair-window, receipt, redaction, and accepted-candidate checks all passed.
- The host remains an inert/headless verifier and does not close native provider execution or device acceptance.

## Fresh focused native spatial rerun (2026-09-14)

- `xcodebuild -project iris-macos/leanring-buddy.xcodeproj -scheme "Iris Test" -destination "platform=macOS" -only-testing:leanring-buddyTests/SpatialGuidanceRegressionTests test CODE_SIGNING_ALLOWED=NO` passed **7/7** tests.
- The run covered focused-window preference, target identity staleness, duplicate refusal, coordinate transforms, negative monitor origins, bounded compatibility fallback, and one-line cues.
- The launched test process reported `accessibility: false, screen: false, screenContent: true`; therefore live click-through remains permission-gated even though the semantic target suite passed.

## Fresh native install and delivery rerun (2026-09-14)

- The `Iris Test` scheme ran `Bug7MissingToolSelfInstallEndToEndTests`, `Bug3StaleShellPathEndToEndTests`, and `AppRelaunchInstalledDeliveryTests` together.
- Result: **16/16** tests passed in 3 suites, covering missing-tool self-install and retry, shipped-shell continuity, real-tool execution, bundle replacement, backup identity, startup reconciliation, retry-record restoration, clone exclusion, and Undo recovery.
- This strengthens source/native state-machine evidence; live user-workspace installation, provider execution, and phone handoff remain acceptance gates.

## Fresh native routing, cancellation, and usage rerun (2026-09-14)

- The `Iris Test` scheme ran `ChatActionCancellationTests`, `AssistantSpendLedgerTests`, `IrisTestRunUsageTests`, and `GuideAutopilotRunnerTests` together.
- Result: **59/59** tests passed across 4 suites, including cancellation before command execution, late/failed usage settlement, dated-model pricing, cache tiers, unknown-cost honesty, relaunch persistence, stale metadata invalidation, and long-running ownership.
- This is native accounting and safety evidence; live provider pricing and execution remain open.

## Fresh NitroAI transfer oracle rerun (2026-09-14)

- The pinned NitroAI Vitest oracle ran against `/Users/akrit/NitroAI` with `IRIS_NITROAI_TARGET_ROOT` set explicitly.
- Result: **2/2 tests passed** in 14.50 seconds, retaining coverage for the compound import/export edge cases and restart/atomicity behavior.
- This verifies the target application's transfer contract without claiming Iris generated or delivered the feature live.

## Permission-pane recheck (2026-09-14)

- macOS Accessibility settings visibly list both `Iris` and `Iris Test` as registered applications.
- The current v23 process still reports `accessibility: false` and `screen: false`, so registration in the pane is not treated as consent. A user must enable the current test bundle's controls and relaunch before live click-through can be accepted.
