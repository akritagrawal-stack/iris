# Iris macOS contract

SwiftUI/AppKit menu-bar companion (`LSUIElement=true`) derived from Clicky. Preserve NOTICE/LICENSE.upstream. Current plan: `../docs/plans/20260912-lightweight-platform/`. Historical contracts/evidence: `../docs/history/agent-instructions-20260912/README.md`.

## Build, style and UI

- Use Xcode GUI to build the correct Test scheme. Never run terminal `xcodebuild`, reset global TCC, rename the legacy leanring-buddy directory/scheme or fix unrelated known concurrency/deprecation warnings.
- SwiftUI unless AppKit is needed; UI state on `@MainActor`; async/await; descriptive names and same-name arguments; comments explain non-obvious reasons. Interactive controls need pointer/hover feedback and accessibility.
- Preserve compact dark composer, fixed eye artwork/colors/geometry/motion and Reduce Motion. No rejected unified shell/adaptive palette, extra prototypes, voice or analytics. Settings is one surface; History remains reachable through takeovers.
- Relevant offline suites: `swift test --package-path iris-macos/tools/usability-tests`, `chat-action-tests`, `account-session-tests`, or `harness-tests` from root. Read host README before invoking it. Serialize PTY/native-window tests; skipped is not passed. Installed identity and real UI/device behavior require separate evidence.

## Transport, identity and credentials

- Chat/screen help uses Anthropic Messages/SSE via funded Publik `/api/assistant/chat` with Supabase access token or BYO `api.anthropic.com/v1/messages`. Funded model is server-owned; requested is not resolved. Publik repo `docs/iris-assistant-protocol.md` is authoritative.
- BYO pasted key wins over imported Claude login via `AnthropicBringYourOwnCredential`. Keys/tokens stay in Keychain, never Publik/arbitrary hosts/logs/manifests. Codex CLI owns its login/refresh; never store or treat ChatGPT OAuth as an OpenAI API key. Codex picker controls edits, not chat/forced-tool guide repair.
- Preserve validated CLI model IDs, read-only sandbox, `--ephemeral`, `--ignore-user-config`, owned process groups, cancellable nonblocking input, bounded reader shutdown and per-descriptor SIGPIPE handling. Detached children are a failure. Do not weaken jail/network policy.
- Routine Keychain/availability/refresh is non-interactive. Only explicit reconnect/import permits auth UI. Missing/denied/unavailable differ. Failed save preserves existing credentials and rotated in-memory token; transient refresh never deletes login. Preserve single-flight/generation guards.
- Diagnostics contain categorical route/numeric status/allowlisted errors, not arbitrary bodies. Structured logs exclude prompts/source/screenshots/secrets. Existing user-visible edit transcripts remain scrubbed/local/bounded and open through delivery/verdict. Real transport observations beat model claims.
- Distinguish funded, metered BYO and subscription costs; do not invent a subscription per-call invoice. Token usage still counts. Unknown usage/model price remains unknown; historical rates/latency ratios are not current measurements.

## Guides, catalog and spatial help

- `GuideSessionController` owns progress, consent, cancellation and terminal lifetime. Deep links select but never execute. Commands use HTTPS-fetched, version-pinned pilot/approved guide content. Preserve current risk/autonomy rules and catastrophe floor. Honor existing grants. Sensitive steps are never executed, echoed, captured or sent to models. Scrub before truncation.
- Preserve step/funded budgets, BYO progress guard and capability-eligible fallback. No Codex fallback for forced Anthropic tools. Red Close stops the owned process before teardown in every state and preserves guide position. Manual handoff restores watch/pointing/retry/continue. Minimized work stays reachable; system permission dialogs stay above takeovers.
- Tool detours preserve progress and require an actual repair route. Reload environment on retries after installation. Never mutate a dirty user checkout or hard-code source roots. Staging validates origin/commit/canonical paths/ownership and uses a typed workspace binding, not shell-text substitution.
- Catalog `/api/iris/apps` refresh/enrichment/cache/concurrency stays bounded and truthful on failure. Missing bundle/platform metadata is unknown. Icons use installed or bounded verified HTTPS assets, never unrelated branding. Browser links do not prove installation.
- Capture is ephemeral under existing permissions. Secure input, sensitive steps, excluded apps and immediate global pause suppress it. Keep cheap local-first watch signals; visual watch calls at least 10 seconds apart and at most eight per step; guide pointing has separate coalescing/bounds. No persistent screen recording.
- Require fresh app/PID/window/target/display evidence. Preserve generation guards and discard late navigation/cancel results. Geometry is not semantic proof. Sensitive/no-target steps stay quiet. Distinguish AX/AppKit/pixels, actual displays/scales. Highlights never click, steal focus or obscure permission UI.

## Edits, verification and recovery

- Ask is general with optional context; Edit names an app. Preserve separate bounded in-memory drafts/attachments, conversation boundaries, request IDs and cancellation. New chat cannot inherit unrelated edit context. Clear history is separate, Cancel-default and excludes projects/edit logs.
- Reuse existing coordinator/engine; user edits do not inherit crash throttles. Preserve source identity/containment, build-file/dependency consent, confined commands and actual changed-file evidence. No hidden reset/stash/clean of user work. Do not retry unchanged commands/source as progress.
- Scope/free-text choices need exact-ID resolution and revisioned constraints. Compact history preserves user instructions and failures. Redact before bounded diagnostic/context selection. Preserve file/byte limits and independent-review reserve; failed suites cannot spend review capacity as another edit.
- Native verification uses captured trusted declarations, fixed argv, checked executable/fixture hashes, stripped environment/deadline after independent admission. Recheck exact reviewed source around native execution/final review. Native apps are same-user processes, not OS-contained by the shell jail. No arbitrary outside-jail retries.
- Receipts separate prepared/installed/restored app payloads from source/user data/UI acceptance. Revalidate registry/source/receipt/artifact/revision at invocation and before delivery/Undo. Wait for quit; force-quit uses existing consent. Recovery needs successful reopening; preserve branch/user data.
- Pending/archived Undo and failed-edit records protect affected paths and block affected edit/publish actions. Corrupt/unknown records fail closed visibly. Checked record/queue persistence precedes clearing or success. Interrupted reconciliation requires exact marker/source/payload. Stop Undo archives exact bounded recovery bytes without claiming restoration. Uncertain bundle swaps are never automatically replayed. Reject stale publish/delivery callbacks.
- Test publication/changelog/normal replacement stays disabled. Production fix/feature publication distinctions and public-listing consent stay unchanged. Never promise cancellation of already-dispatched external actions.

Read `leanring-buddy/AGENTS.md`. Consult relevant archived specialist contracts when changing behavior not fully summarized here; inspect current source. Keep status narratives and file inventories out of recurring instructions.
