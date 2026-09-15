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
