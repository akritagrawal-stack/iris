# Iris MVP completion audit

Updated 2026-09-15 from the integration branch and recorded test artifacts.

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Kneecap workspace selection, preservation, cancel/retry/resume | Native setup/recovery tests, Bug 3/7 harness coverage, and fresh focused rerun | Source/native flow covered; full installation and downstream device handoff still need live acceptance |
| Spatial click-through guidance | 14/14 native setup/spatial tests plus 12/12 structured spatial-model tests, including stale semantic targets, ambiguity refusal, focus ordering, transforms, action filtering, JSON/SSE parsing, and bounded cues | Source/native behavior covered; live provider-backed coordinate and actual click-through still open |
| Lightweight version history and safe Undo | Progress durability, cleanup, relaunch, Undo, failed-review retention, and standalone 8-check retention executable | Source/native behavior covered; installed-app continuity still open |
| Capability-correct routing and usage accounting | 161/161 package tests, 11 routing tests, host usage checks, per-route input/cache token telemetry | Source/package evidence covered; live provider pricing/execution remains open |
| Meaningful complex feature through Iris | NitroAI transfer oracle 2/2 with import/export edge cases | Target-app oracle passes; Iris live generation, delivery, relaunch, and readback remain open |
| Mobile install hub | 20/20 Node tests and local server/catalog smoke | Hub integration covered; no verified iPhone distribution route or physical-device journey |
| Integrated release candidate | `/Users/Shared/Iris-RC-20260915-v29/Iris Test.app`, signed with `Iris Local Code Signing` and deep-strict verified; executable SHA-256 `2fd8f97cb9da532c9f44d9a5e84fab8e3c4a71b2a4179cc3842bc2a1963ae46a` | Stable candidate exists; acceptance is incomplete until live/native/device gates close |

The unverified gates require actual provider-backed execution, Screen Recording
and Accessibility consent for the test bundle, and a connected trusted iPhone
with a verified distribution route. None of those states are inferred from
headless, browser, or package tests.

## Fresh automated rerun (2026-09-15)

- `swift test --package-path iris-macos/tools/harness-tests --parallel`: **161/161** tests passed across 7 suites.
- `node --test iris-mobile/test/*.test.mjs`: **20/20** tests passed.
- `IRIS_NITROAI_TARGET_ROOT=/Users/akrit/NitroAI npm test -- --run`: **140/140** tests passed across 14 files.
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

## Fresh native workspace probe (2026-09-14)

- After activating v23, a full desktop capture showed the Iris eye affordances over the live Discord `LARPslayers` workspace and the active Canvas/Chrome windows.
- Capture recorded at `/tmp/iris-live-recheck-20260914.png` (SHA-256 `e97efb4a6504aaca1497781afb1273d2f955daf63ecfeb6b139d628b66c56eae`).
- This confirms the overlay remains present while the user changes applications; it is observational evidence only and does not claim a completed target click or edit delivery.

## TCC database recheck (2026-09-14)

- The user TCC database contains a `DocumentsFolder` record for `com.publikhq.iris.test`, but no `Accessibility` or `ScreenCapture` record for that bundle.
- This independently confirms why the v23 process reports `accessibility: false` and `screen: false`; the missing records are the concrete external gate for live click-through.

## TCC consent verified after native UI enablement (2026-09-14)

- The macOS Privacy panes were opened and inspected with the actual desktop UI. `Iris Test` is visibly enabled in both Accessibility and Screen & System Audio Recording.
- The authoritative system TCC database now contains:
  `kTCCServiceAccessibility|com.publikhq.iris.test|auth_value=2|auth_reason=4` and
  `kTCCServiceScreenCapture|com.publikhq.iris.test|auth_value=2|auth_reason=4`.
- The signed v23 bundle was quit and relaunched after consent; the live process was observed as PID 46779. The post-consent desktop capture is `/tmp/iris-v23-after-tcc.png` (SHA-256 `d78e41dea2f6cb7b1b99d4f1c798a6d1328ec3af30b54e197c57845b63ab0f07`).
- This closes the macOS consent gate for the test bundle. A fresh live click-through and provider-backed edit are still separate acceptance checks; the earlier `false` startup line predates this consent change.

## Fresh live Ask and saved-login check (2026-09-14)

- Through the real Iris overlay, the visible Chrome workspace was asked, “What is visible on my screen right now?” The submitted message and rendered response were captured at `/tmp/iris-ax-screen-result.png` (SHA-256 `af60a6b02f0311935a81814509f95d9024a151308cd2b970b4cb82f9e9e09d37`).
- The response correctly followed the capability boundary: `I can’t see your screen. Connect screen help so Iris can inspect what’s visible.` The composer showed `Codex general help`, and settings showed `Answers only — editing apps runs on Codex (your ChatGPT login)`. This is a provider/account gate, not evidence that TCC consent is missing.
- The real `Reconnect saved login` action opened the native Keychain authorization prompt for `com.publikhq.iris.test`; no password was entered during this run. Iris subsequently reported that macOS did not finish reconnecting and kept the saved login. A publik/Anthropic screen-help credential is still required before provider-backed screen capture and edit delivery can be accepted.

## Fresh native screen-capture and provider Ask check (2026-09-14)

- An independent ScreenCaptureKit probe, run outside Iris but on the same
  desktop, captured a non-empty 320x240 image from one display (`displays=1`,
  `windows=40`). This isolates the capture API and confirms that the current
  macOS consent rows are sufficient for ScreenCaptureKit itself.
- After the provider settled, the real Iris overlay rendered a screen-aware
  answer to `What is visible on my screen right now?`: it identified ChatGPT,
  the Mission Control chat, and the emulator at lower right. The final native
  frame is `/tmp/iris-scroll-screen.png` (SHA-256
  `1b14c8f9924ed0780eb3cea145fe8fa802db8b59a7de50d55b1c69d8619f9d32`).
- This closes the live screen-capture plus provider Ask check for this build.
  It does not close model-generated `[POINT]` click-through or a provider-backed
  edit and delivery; the first targeted point request returned a descriptive
  answer without a coordinate tag, so spatial click-through remains open.

## Fresh grounded live prompt gate (2026-09-14)

- The three-test `ChatPromptLiveTests` suite was run once with its documented
  `IRIS_CHAT_PROMPT_LIVE=1` and `TEST_RUNNER_IRIS_CHAT_PROMPT_LIVE=1` gates and
  one sample per scenario. The test host reported Accessibility and Screen
  Recording as enabled, then each real-prompt case stopped at
  `.noCredentialsAvailable` before a model call.
- Result: **0/3 scenarios reached grading**. This is a credential propagation
  failure in the isolated test host, not a permission failure and not a passing
  live prompt result. The signed app's successful screen-aware Ask check above
  remains separate evidence; the next fix is to provide a supported test-host
  transport or an explicitly scoped test credential without copying secrets.
- Raw result: `/tmp/iris-chat-prompt-live-derived/Logs/Test/Test-Iris Test-2026.09.14_23-15-03--0700.xcresult`.

## Dedicated spatial-model wiring (2026-09-14)

- `ElementLocationDetector` is now wired into both guide fallback pointing and
  explicit chat requests such as “where is the install button?” The detector
  sends Anthropic's structured Computer Use tool request; the conversational
  vision prompt no longer owns the pointer coordinate.
- Funded responses are parsed as SSE and direct Anthropic responses as JSON;
  model-specific tool versions are selected (including Haiku's legacy tool),
  scroll/drag coordinates are rejected, and OAuth beta headers are preserved.
- The new `ElementLocationDetectorTests` plus the focused spatial suite passed
  **12/12** native tests. This is source/native contract evidence. A fresh
  provider-backed point request on the rebuilt signed artifact is still needed
  to prove the server accepts Computer Use on the funded route and that the
  overlay lands on the intended live control.

## Signed spatial-model candidate (2026-09-15)

- The actual `Iris Test` configuration was rebuilt and signed with the stable
  `Iris Local Code Signing` identity, with the debug launcher disabled so the
  standalone candidate can run outside Xcode. Candidate: `/Users/Shared/Iris-RC-20260914-v28/Iris Test.app`; bundle `com.publikhq.iris.test`; executable SHA-256 `ed54f465fe0bd0de0bfca42032ca605585ab51b36ca239155ed06c041887a297`.
- A screenshot is only the spatial model's visual input. The coordinate comes
  from Anthropic's structured Computer Use model/tool call. Guide fallback,
  explicit UI questions, and the onboarding preview all use that detector;
  conversational text and legacy `[POINT]` tags cannot supply or override a
  coordinate for an explicit UI-location request.
- The detector makes one bounded model request only when a spatial target is
  requested, rejects screenshot/scroll/drag actions, and maps the returned
  model-space coordinate through the captured display's scale and origin. The
  source/native focused suite remains **12/12**.
- A fresh provider-backed point request is still needed to prove the server
  accepts Computer Use and that the overlay lands on the intended live control.
  No live point is claimed until that provider/runtime gate is observed.
