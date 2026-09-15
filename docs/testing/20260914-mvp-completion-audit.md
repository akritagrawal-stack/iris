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
| Integrated release candidate | `/Users/Shared/Iris-RC-20260914-v22/Iris Test.app`, signed with `Iris Local Code Signing` and deep-strict verified; executable SHA-256 `0b73d4205417c98112f9a6775fa0eb9599c5ede1496264bab52c1ed133aca8af` | Stable candidate exists; acceptance is incomplete until live/native/device gates close |

The unverified gates require actual provider-backed execution, Screen Recording
and Accessibility consent for the test bundle, and a connected trusted iPhone
with a verified distribution route. None of those states are inferred from
headless, browser, or package tests.
