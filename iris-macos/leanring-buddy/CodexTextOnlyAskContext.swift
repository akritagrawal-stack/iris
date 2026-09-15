//
//  CodexTextOnlyAskContext.swift
//  leanring-buddy
//
//  The Codex Ask route has no screen or machine capability. It can still be
//  useful when the reader has already selected a project or described work in
//  Iris: that is conversation context, not an observation of the Mac.
//

import Foundation

/// A deliberately small, truthful supplement for general Ask.
///
/// It never carries screenshots, file paths, terminal output, coordinates, or
/// inferred foreground-app state. A selected project only gives a question
/// useful conversational context; it never turns Ask into an edit request.
nonisolated enum CodexTextOnlyAskContext {
    /// Prevent a long edit brief from consuming the normal question's context
    /// budget. This is characters rather than tokens so it is deterministic at
    /// the call site; the provider retains its own input accounting.
    static let maximumTaskSummaryCharacters = 360

    static func render(
        selectedProjectName: String?,
        taskSummary: String?,
        taskKind: String?
    ) -> String? {
        let project = compact(selectedProjectName, limit: 120)
        let summary = compact(taskSummary, limit: maximumTaskSummaryCharacters)
        let kind = compact(taskKind, limit: 32)

        guard project != nil || summary != nil else { return nil }

        var lines = [
            "Relevant Iris session context (it comes from what the reader selected or told Iris; it is not screen, file, terminal, or machine access):"
        ]
        if let project {
            lines.append("- Selected project: \(project)")
        }
        if let kind, let project {
            lines.append("- The reader is considering a \(kind) for that project.")
        }
        if let summary {
            lines.append("- Current task summary: \(summary)")
        }
        lines.append("Use this only to make general help relevant. Do not treat it as permission to edit, run anything, inspect the Mac, or claim the project is on screen.")
        return lines.joined(separator: "\n")
    }

    private static func compact(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { token -> String in
                let text = String(token)
                // A general Ask does not need local paths or a prior visual
                // pointer to answer helpfully. Do this again here rather than
                // relying solely on the edit egress scrubber: this type is the
                // final boundary before the text-only provider prompt.
                if text.hasPrefix("/") || text.hasPrefix("~/") || text.hasPrefix("file://") {
                    return "[redacted path]"
                }
                if text.hasPrefix("[POINT:") {
                    return "[redacted coordinate]"
                }
                return text
            }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}
