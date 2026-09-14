import Foundation
@testable import IrisHarnessNative

/// Verifies the local decision boundary behind Ask. This intentionally never
/// starts a provider request: the native UI remains responsible for the live
/// interaction and must not claim it has screen access when it does not.
@MainActor
func runCodexTextOnlyAskChecks() throws {
    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }

    try require(ComposerConnectionPresentation.canSendTypedRequest(
        hasText: true,
        requestIsBeingSizedUp: false,
        context: .screenHelp,
        helpIsAvailable: false,
        textOnlyHelpIsAvailable: true
    ), "a connected Codex login did not enable a typed, text-only Ask")
    try require(!ComposerConnectionPresentation.canSendTypedRequest(
        hasText: true,
        requestIsBeingSizedUp: true,
        context: .screenHelp,
        helpIsAvailable: false,
        textOnlyHelpIsAvailable: true
    ), "Ask became enabled while the request was still being sized")
    try require(!ComposerConnectionPresentation.canSendTypedRequest(
        hasText: false,
        requestIsBeingSizedUp: false,
        context: .screenHelp,
        helpIsAvailable: false,
        textOnlyHelpIsAvailable: true
    ), "an empty text-only Ask became enabled")

    let presentation = ComposerConnectionPresentation.resolve(
        context: .screenHelp,
        help: .codexTextOnly,
        editing: .codex,
        codexIsConnected: true
    )
    try require(presentation.connectionLabel == "General questions through Codex",
                "text-only Ask did not name its connected provider")
    try require(presentation.showsModelControl,
                "text-only Ask did not expose the available model control")
    try require(presentation.inlineMessage?.contains("typed questions") == true
                && presentation.inlineMessage?.contains("Connect screen help") == true,
                "text-only Ask did not disclose its screen-help limit")
    try require(presentation.settingsLinkLabel == "Connect screen help",
                "text-only Ask did not offer the relevant next action")
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
