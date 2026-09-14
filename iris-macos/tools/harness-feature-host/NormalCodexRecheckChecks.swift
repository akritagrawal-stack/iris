import Foundation
@testable import IrisHarnessNative

private enum NormalCodexRecheckCheckError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): return message }
    }
}

/// Runs the real Codex process retry loop through the same observer factory the
/// normal coordinator uses after delivery. The shell stand-in replaces only the
/// signed-in CLI, so no billed call or account credential is needed.
@MainActor
func runNormalCodexRecheckChecks() async throws {
    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw NormalCodexRecheckCheckError.failed(message) }
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("iris-normal-recheck-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binary = root.appendingPathComponent("codex")
    let spawns = root.appendingPathComponent("spawns.log")
    let script = """
    #!/bin/sh
    cat >/dev/null 2>&1
    echo spawn >> '\(spawns.path)'
    output=""
    previous=""
    for argument in "$@"; do
      if [ "$previous" = "--output-last-message" ]; then output="$argument"; fi
      previous="$argument"
    done
    count=$(wc -l < '\(spawns.path)' | tr -d ' ')
    if [ "$count" -gt 2 ] && [ -n "$output" ]; then printf '%s' 'VERDICT: CANNOT-TELL' > "$output"; fi
    """
    try script.write(to: binary, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

    let accounting = CodexRunUsageAccounting(settings: try HarnessRunLedgerSettings(
        maxCalls: 8, maxInputBytes: 4_000
    ))
    let observer = OnDemandEditCoordinator.normalCodexUsageObserver(for: accounting)
    let answer = try await CodexMaintainProvider.runCodexExec(
        codexBinaryPath: binary.path,
        promptText: "check the delivered app symptom",
        attachedImagePNGDataList: [],
        model: "gpt-5.6-terra",
        webSearchEnabled: false,
        timeoutSeconds: 30,
        emptyReplyRetryWaitSecondsOverride: 0,
        attemptObserver: observer,
        runPhase: .recheck,
        submittedInputBytes: 77
    )
    let spawned = (try String(contentsOf: spawns, encoding: .utf8))
        .split(separator: "\n").count
    try require(answer == "VERDICT: CANNOT-TELL", "recheck did not return the final physical attempt")
    try require(spawned == 3, "empty recheck replies were not counted as physical retries")
    try require(accounting.snapshot.admittedCallCount == 3, "recheck attempts were not admitted")
    try require(accounting.snapshot.settledCallCount == 3, "recheck attempts were not settled")
    try require(accounting.snapshot.settledCalls.map(\.reservation.task) == [.recheck, .recheck, .recheck],
                "normal coordinator observer lost the recheck phase")

    let late = CodexProcessAttemptContext(
        attemptID: UUID(), model: "gpt-5.6-terra", reasoningEffort: nil,
        task: .recheck, submittedInputBytes: 77
    )
    try await observer.beforeAttempt?(late)
    try require(accounting.finish(reason: .cancelled), "reset could not finish the current generation")
    await observer.afterAttempt?(CodexProcessAttemptResult(
        context: late, outcome: .cancelled, usage: nil
    ))
    try require(accounting.snapshot.status == .stopped(.cancelled), "reset changed the terminal reason")
    try require(accounting.snapshot.admittedCallCount == 4 && accounting.snapshot.settledCallCount == 4,
                "late completion did not settle its pre-reset reservation")
    print("PASS normal Codex recheck: coordinator observer counts empty retries and late reset settlement")
}
