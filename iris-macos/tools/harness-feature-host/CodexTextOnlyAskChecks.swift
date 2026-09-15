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

    let contextualAsk = try requireValue(
        CodexTextOnlyAskContext.render(
            selectedProjectName: "WhimprFlow",
            taskSummary: "Paste into the chosen destination without sending it.",
            taskKind: "feature"
        ),
        "selected project context was unexpectedly absent"
    )
    try require(contextualAsk.contains("Selected project: WhimprFlow"),
                "Ask lost the reader-selected project")
    try require(contextualAsk.contains("Current task summary: Paste into the chosen destination without sending it."),
                "Ask lost the bounded task summary")
    try require(contextualAsk.contains("not screen, file, terminal, or machine access"),
                "Ask context did not state its capability boundary")
    try require(contextualAsk.contains("permission to edit") && contextualAsk.contains("claim the project is on screen"),
                "Ask context could be mistaken for editing or screen access")
    let redactedContext = try requireValue(CodexTextOnlyAskContext.render(
        selectedProjectName: "PlantGPT",
        taskSummary: "Compare /Users/example/project and [POINT:12,28:save] before deciding.",
        taskKind: "bug fix"
    ), "path-bearing session context was unexpectedly absent")
    try require(!redactedContext.contains("/Users/") && !redactedContext.contains("[POINT:")
                && redactedContext.contains("[redacted path]")
                && redactedContext.contains("[redacted coordinate]"),
                "Ask context admitted a path or coordinate")

    let prompt = CompanionManager.codexTextOnlyQuestionPrompt(sessionContext: contextualAsk)
    try require(prompt.contains(contextualAsk),
                "the Codex Ask prompt did not carry approved session context")
    try require(prompt.contains("no screenshot") && prompt.contains("no access to the user's files")
                && prompt.contains("no terminal"),
                "approved session context weakened the text-only capability boundary")
    try require(CodexTextOnlyAskContext.render(
        selectedProjectName: nil, taskSummary: nil, taskKind: nil
    ) == nil, "empty session state created invented Ask context")
}

private func requireValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw CheckFailure(message: message) }
    return value
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
