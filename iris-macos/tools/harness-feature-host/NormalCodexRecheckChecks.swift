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
    let logs = root.appendingPathComponent("logs", isDirectory: true)
    guard let oldRunLog = OnDemandEditRunLog(
        appSlug: "old-run", kindLabel: "bug fix", scrubbedRequest: "scrubbed request",
        directoryPath: logs.path, now: Date(timeIntervalSinceReferenceDate: 1)
    ) else { throw NormalCodexRecheckCheckError.failed("old run log was unavailable") }
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
    var oldGenerationUIUpdates = 0
    let observer = OnDemandEditCoordinator.normalCodexUsageObserver(
        for: accounting, runLog: oldRunLog
    ) { oldGenerationUIUpdates += 1 }
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
    oldRunLog.record(accounting.summary)
    oldRunLog.finish(outcome: "request replaced before planning")

    // A replacement flow must own its own record and UI; an old process
    // completion must append only to the captured, closed original transcript.
    guard let replacementLog = OnDemandEditRunLog(
        appSlug: "replacement-run", kindLabel: "feature", scrubbedRequest: "new request",
        directoryPath: logs.path, now: Date(timeIntervalSinceReferenceDate: 2)
    ) else { throw NormalCodexRecheckCheckError.failed("replacement run log was unavailable") }
    let replacementUsage = CodexRunUsageAccounting(settings: try HarnessRunLedgerSettings(
        maxCalls: 2, maxInputBytes: 200
    ))
    var replacementGenerationUIUpdates = 0
    let replacementObserver = OnDemandEditCoordinator.normalCodexUsageObserver(
        for: replacementUsage, runLog: replacementLog
    ) { replacementGenerationUIUpdates += 1 }
    let replacementContext = CodexProcessAttemptContext(
        attemptID: UUID(), model: "new-model", reasoningEffort: nil,
        task: .intake, submittedInputBytes: 10
    )
    try await replacementObserver.beforeAttempt?(replacementContext)
    await observer.afterAttempt?(CodexProcessAttemptResult(
        context: late, outcome: .cancelled, usage: nil
    ))
    try require(accounting.snapshot.status == .stopped(.cancelled), "reset changed the terminal reason")
    try require(accounting.snapshot.admittedCallCount == 4 && accounting.snapshot.settledCallCount == 4,
                "late completion did not settle its pre-reset reservation")
    let oldRecord = try String(contentsOfFile: oldRunLog.filePath, encoding: .utf8)
    let replacementRecord = try String(contentsOfFile: replacementLog.filePath, encoding: .utf8)
    try require(oldRecord.contains("late usage settlement: model usage")
                    && oldRecord.contains("calls: 4/4 settled"),
                "late settlement did not update the original persisted usage record")
    try require(!replacementRecord.contains("late usage settlement")
                    && replacementUsage.snapshot.admittedCallCount == 1
                    && replacementGenerationUIUpdates == 1
                    && oldGenerationUIUpdates == 8,
                "late settlement touched the replacement run")

    // Intake calls occur before the old edit-start logging point. The normal
    // flow now opens its transcript before that probe so a cancelled intake is
    // still recorded with its admitted-but-unsettled state.
    guard let intakeLog = OnDemandEditRunLog(
        appSlug: "intake-run", kindLabel: "bug fix", scrubbedRequest: "intake request",
        directoryPath: logs.path, now: Date(timeIntervalSinceReferenceDate: 3)
    ) else { throw NormalCodexRecheckCheckError.failed("intake run log was unavailable") }
    let intakeUsage = CodexRunUsageAccounting(settings: try HarnessRunLedgerSettings(
        maxCalls: 2, maxInputBytes: 200
    ))
    let intakeObserver = OnDemandEditCoordinator.normalCodexUsageObserver(
        for: intakeUsage, runLog: intakeLog
    )
    let intakeContext = CodexProcessAttemptContext(
        attemptID: UUID(), model: "intake-model", reasoningEffort: nil,
        task: .intake, submittedInputBytes: 10
    )
    try await intakeObserver.beforeAttempt?(intakeContext)
    try require(intakeUsage.finish(reason: .cancelled), "cancelled intake did not close")
    intakeLog.record(intakeUsage.summary)
    intakeLog.finish(outcome: "flow reset before edit")
    let intakeRecord = try String(contentsOfFile: intakeLog.filePath, encoding: .utf8)
    try require(intakeRecord.contains("calls: 0/1 settled"),
                "cancelled intake before edit did not persist its admitted call")

    // Drive the public coordinator entrypoint twice without yielding between
    // calls, the shape a rapid replacement takes on the main actor. The first
    // intake must become a closed, terminal record before the second call
    // publishes a replacement ledger and transcript.
    let resubmitRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/iris-normal-resubmit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: resubmitRoot) }
    let resubmitClone = resubmitRoot.appendingPathComponent("clone", isDirectory: true)
    try FileManager.default.createDirectory(
        at: resubmitClone.appendingPathComponent(".git", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("{\"name\":\"resubmit-fixture\",\"scripts\":{\"build\":\"true\",\"test\":\"true\"}}\n".utf8)
        .write(to: resubmitClone.appendingPathComponent("package.json"))
    let resubmitSlug = "rapid-resubmit-\(UUID().uuidString)"
    let resubmitDefaultsName = "iris.normal-resubmit.\(UUID().uuidString)"
    let resubmitDefaults = UserDefaults(suiteName: resubmitDefaultsName)!
    let resubmitProvenance = InstallProvenanceStore(userDefaults: resubmitDefaults)
    resubmitProvenance.recordGuideSourceClone(
        appSlug: resubmitSlug, clonePath: resubmitClone.path, pinnedCommit: nil, canonicalRepo: nil
    )
    let resubmitCoordinator = OnDemandEditCoordinator(
        installProvenanceStore: resubmitProvenance,
        patchQueue: PatchQueue(baseDirectoryURL: resubmitRoot.appendingPathComponent("patches")),
        clonePathLock: MaintainClonePathLock(),
        topRequestsForApp: { _ in [] },
        probeRequestTriggers: { _, _ in .allQuiet },
        deliveredUndoRecoveryStore: DeliveredEditUndoRecoveryStore(
            recordURL: resubmitRoot.appendingPathComponent("recovery.json")
        ),
        appDeliveryReceiptStore: AppDeliveryReceiptStore(
            baseDirectory: resubmitRoot.appendingPathComponent("receipts")
        ),
        runLogDirectoryPath: resubmitRoot.appendingPathComponent("run-logs").path,
        editReadiness: { .ready }
    )
    let runDirectory = resubmitRoot.appendingPathComponent("run-logs").path
    let runFileSuffix = "-\(resubmitSlug).log"
    func resubmitRunPaths() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: runDirectory))?
            .filter { $0.hasSuffix(runFileSuffix) }
            .sorted()
            .map { (runDirectory as NSString).appendingPathComponent($0) } ?? []
    }
    for path in resubmitRunPaths() { try? FileManager.default.removeItem(atPath: path) }
    defer {
        // `describeRequest` launches a probe task. Cancel/reset it before
        // deleting the disposable directory so no delayed callback can outlive
        // this fixture or write into a later test's state.
        resubmitCoordinator.cancel()
        for path in resubmitRunPaths() { try? FileManager.default.removeItem(atPath: path) }
        resubmitDefaults.removePersistentDomain(forName: resubmitDefaultsName)
    }
    try require(
        resubmitCoordinator.pickApp(slug: resubmitSlug, name: "Rapid Resubmit", stack: .other),
        "clear-request fixture was not eligible"
    )
    try require(
        resubmitCoordinator.describeRequest(
            "the save button crashes when I click it", kind: .bugFix
        ),
        "clear request was rejected"
    )
    try require(resubmitCoordinator.phase == .presentingPlan,
                "clear local bug did not bypass the optional planner probe")
    try require(resubmitCoordinator.normalCodexRunSnapshot?.admittedCallCount == 0,
                "clear local bug admitted an unnecessary intake call")
    let clearRequestRecords = resubmitRunPaths().compactMap {
        try? String(contentsOfFile: $0, encoding: .utf8)
    }
    try require(clearRequestRecords.contains(where: {
        $0.contains("request probe: skipped for clear local bug fix")
    }), "clear-request routing decision was not recorded")
    resubmitCoordinator.cancel()
    for path in resubmitRunPaths() { try? FileManager.default.removeItem(atPath: path) }
    try require(
        resubmitCoordinator.pickApp(slug: resubmitSlug, name: "Rapid Resubmit", stack: .other),
        "rapid resubmit fixture was not eligible"
    )
    try require(
        resubmitCoordinator.describeRequest("first request \(resubmitSlug)", kind: .feature),
        "first rapid request was rejected"
    )
    try require(
        resubmitCoordinator.describeRequest("replacement request \(resubmitSlug)", kind: .feature),
        "replacement rapid request was rejected"
    )
    try require(resubmitCoordinator.normalCodexRunSnapshot?.status == .running,
                "rapid replacement did not publish a fresh current usage snapshot")
    let resubmitRuns = resubmitRunPaths()
    try require(resubmitRuns.count == 2, "rapid replacement did not retain two distinct run logs")
    let resubmitRecords = try resubmitRuns.map { try String(contentsOfFile: $0, encoding: .utf8) }
    guard let originalRecord = resubmitRecords.first(where: { $0.contains("Request: first request \(resubmitSlug)") }),
          let rapidReplacementRecord = resubmitRecords.first(where: { $0.contains("Request: replacement request \(resubmitSlug)") })
    else { throw NormalCodexRecheckCheckError.failed("rapid replacement logs did not retain request identity") }
    try require(originalRecord.contains("outcome: request replaced before planning")
                    && !rapidReplacementRecord.contains("request replaced before planning"),
                "rapid replacement did not terminalize only the original run")
    print("PASS normal Codex recheck: retries, late old-run settlement, rapid replacement isolation, and cancelled intake are recorded")
}
