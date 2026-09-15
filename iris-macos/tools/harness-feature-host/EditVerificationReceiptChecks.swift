import Foundation
@testable import IrisHarnessNative

/// Focused regression coverage for the receipt that gates saved delivery and
/// recovery. This runs with local values only; it never launches or replaces
/// an app.
@MainActor
func runEditVerificationReceiptChecks() throws {
    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }

    let failedConfined = EditVerificationReceipt(
        buildPassed: true,
        testsPassed: true,
        confinedTestsPassed: false,
        nativeTestsPassed: nil,
        nativeTestsRequired: false
    )
    try require(failedConfined.hasFailure,
                "a failed confined check was hidden by a passing suite")
    try require(failedConfined.testSummary == "Code: Failed; desktop: Not run",
                "a failed confined check was not visible in the receipt summary")
    try require(failedConfined.commitTrailer
                    == "Applied: build-green, suite-green, confined-failed, native-not-run",
                "the receipt trailer omitted a recorded confined failure")

    let failedNative = EditVerificationReceipt(
        buildPassed: true,
        testsPassed: true,
        confinedTestsPassed: true,
        nativeTestsPassed: false,
        nativeTestsRequired: true
    )
    try require(failedNative.hasFailure,
                "a failed native check was hidden by a passing suite")
    try require(failedNative.testSummary == "Code: Passed; desktop: Failed",
                "a failed native check was not visible in the receipt summary")

    let legacySuite = EditVerificationReceipt(buildPassed: true, testsPassed: true)
    try require(!legacySuite.hasFailure && legacySuite.testSummary == "Passed"
                    && legacySuite.commitTrailer == "Applied: build-green, suite-green",
                "legacy verification receipts changed without a separate rung")
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
