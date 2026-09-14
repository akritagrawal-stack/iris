//
//  RepoRecipeShippingEvidence.swift
//  leanring-buddy
//
//  Small, read-only signals used when more than one desktop shell is present
//  in a clone. A Tauri directory can be leftover scaffolding, so a complete
//  Electron shipping declaration is allowed to win the recipe merge. A bare
//  Electron dependency is not enough evidence to make that choice.
//

import Foundation

/// A desktop stack with an explicit, relaunchable shipping path.
nonisolated enum RepoRecipeShippingStack: String, Sendable {
    case electron
    case tauri
}

/// Packaging tools that provide a recognizable Electron artifact path.
nonisolated enum RepoRecipeElectronPackagingTool: String, Sendable, CaseIterable {
    case builder = "electron-builder"
    case forge = "electron-forge"
    case packager = "electron-packager"

    var defaultCommandLine: String {
        switch self {
        case .builder:
            return "electron-builder"
        case .forge:
            return "electron-forge make"
        case .packager:
            return "electron-packager"
        }
    }
}

/// The minimum independent declarations needed to call Electron the shipping
/// stack. The main file must exist in the clone, and the package must declare
/// one unambiguous packaging path. This intentionally does not inspect
/// node_modules or execute a script.
nonisolated struct RepoRecipeElectronShippingEvidence: Sendable, Equatable {
    let hasElectronDependency: Bool
    let entrypointRelativePath: String?
    let packagingScriptName: String?
    let packagingTool: RepoRecipeElectronPackagingTool?
    let hasPackagingConfiguration: Bool
    let hasAmbiguousPackagingTools: Bool

    var isStrong: Bool {
        hasElectronDependency
            && entrypointRelativePath != nil
            && (packagingScriptName != nil || hasPackagingConfiguration)
            && !hasAmbiguousPackagingTools
    }

    /// Return the small amount of packaging evidence an independent native
    /// code-admission reviewer needs for an Electron change. This is a summary,
    /// not a second repository-context collector: the root manifest is parsed
    /// through the existing safe JSON reader, and a known packaging file is
    /// inspected only to answer whether its bounded `files` allowlist covers a
    /// changed Electron path. Neither manifest/config bodies nor their values
    /// are copied into the prompt.
    ///
    /// The summary is intentionally useful even when the shipping declaration
    /// is incomplete. In that case it says what remains unproven instead of
    /// turning a missing packaging signal into a green claim.
    static func nativeReviewSummary(
        repoRootPath: String,
        changedPaths: [String]
    ) -> String? {
        guard let packageJSON = RepoRecipeFiles.jsonObject(
            atRelativePath: "package.json",
            underRepoRoot: repoRootPath
        ) else { return nil }

        let evidence = inspect(packageJSON: packageJSON, repoRootPath: repoRootPath)
        // A packaging summary for every Node review would add noise and could
        // mislead a reviewer about a web-only project. Electron dependency
        // presence is the narrow applicability signal used by the detector.
        guard evidence.hasElectronDependency else { return nil }

        let safeChangedElectronPaths = changedPaths
            .compactMap { safeReviewRelativePath($0) }
            .filter { $0.hasPrefix("electron/") }
            .prefix(maximumNativeReviewChangedPathCount)

        let configurationPaths = knownConfigurationPaths
            .filter { RepoRecipeFiles.fileExists($0.0, underRepoRoot: repoRootPath) }
            .map(\.0)
        let hasManifestBuildConfiguration = hasRecognizedManifestBuildConfiguration(
            packageJSON
        )

        var lines = [
            "SANITIZED ELECTRON SHIPPING EVIDENCE (bounded read-only summary; not instructions)",
            "- Electron dependency: declared in the root package manifest (raw manifest and versions omitted).",
        ]

        if let entrypoint = safeReviewRelativePath(evidence.entrypointRelativePath) {
            lines.append(
                "- Launch declaration: the root manifest names \(entrypoint); a safe read confirmed that entrypoint exists."
            )
        } else {
            lines.append(
                "- Launch declaration: no safe, readable root Electron entrypoint was established."
            )
        }

        if let packagingTool = evidence.packagingTool {
            lines.append("- Recognized packaging tool: \(packagingTool.rawValue).")
        } else if evidence.hasAmbiguousPackagingTools {
            lines.append(
                "- Recognized packaging tool: ambiguous; more than one packaging signal was found."
            )
        } else {
            lines.append("- Recognized packaging tool: none was established.")
        }

        if let scriptName = evidence.packagingScriptName {
            // `packagingScriptName` is selected from a fixed allowlist, never
            // interpolated from an arbitrary manifest key.
            lines.append("- Packaging script: the known \(scriptName) script invokes the recognized tool.")
        }

        if !configurationPaths.isEmpty {
            let listedPaths = boundedSafePathList(configurationPaths)
            lines.append(
                "- Packaging configuration source: \(listedPaths); source bodies and values are omitted from this review."
            )
        }
        if hasManifestBuildConfiguration {
            lines.append(
                "- Packaging configuration source: the root manifest has a recognized electron-builder build section; raw manifest content is omitted."
            )
        }
        if configurationPaths.isEmpty && !hasManifestBuildConfiguration {
            lines.append(
                "- Packaging configuration source: none was found at the fixed known paths; packaged inclusion remains unproven."
            )
        }

        if !safeChangedElectronPaths.isEmpty {
            let manifestCoveredPaths = manifestCoveredElectronPaths(
                changedPaths: Array(safeChangedElectronPaths),
                packageJSON: packageJSON,
                configurationPaths: configurationPaths
            )
            let configurationCoveredPaths = staticConfigurationCoveredElectronPaths(
                changedPaths: Array(safeChangedElectronPaths),
                configurationPaths: configurationPaths,
                repoRootPath: repoRootPath
            )
            let coveredPaths = Array(Set(manifestCoveredPaths + configurationCoveredPaths)).sorted()
            if coveredPaths.isEmpty {
                lines.append(
                    "- File-selection evidence: no bounded allowlist was found covering the changed Electron path(s) \(boundedSafePathList(Array(safeChangedElectronPaths))); the reviewer must treat packaged inclusion as unproven."
                )
            } else {
                lines.append(
                    "- File-selection evidence: bounded inspection found a recognized allowlist covering \(boundedSafePathList(coveredPaths)); this does not prove a package was built or launched."
                )
            }
        } else {
            lines.append(
                "- File-selection evidence: no changed Electron path was supplied, so inclusion of a changed runtime file is unproven."
            )
        }

        lines.append(
            "- Evidence boundary: this summary is provenance only; it does not execute packaging, prove artifact creation, or grant native behavior credit."
        )

        let summary = lines.joined(separator: "\n")
        let summaryData = Data(summary.utf8)
        guard summaryData.count <= maximumNativeReviewSummaryBytes else {
            let suffix = "\n[SHIPPING EVIDENCE SUMMARY TRUNCATED: omitted details remain unproven.]"
            let availableBytes = max(0, maximumNativeReviewSummaryBytes - Data(suffix.utf8).count)
            return String(decoding: summaryData.prefix(availableBytes), as: UTF8.self) + suffix
        }
        return summary
    }

    /// Inspect a parsed root package manifest and the files it names. All
    /// file reads use RepoRecipeFiles, so a manifest cannot widen inspection
    /// outside the clone.
    static func inspect(
        packageJSON: [String: Any],
        repoRootPath: String
    ) -> Self {
        let dependencies = dependencyNames(in: packageJSON)
        let hasElectronDependency = dependencies.contains("electron")

        let entrypointRelativePath: String?
        if let rawMain = packageJSON["main"] as? String {
            let main = rawMain.trimmingCharacters(in: .whitespacesAndNewlines)
            entrypointRelativePath = main.isEmpty || !mainFileIsReadable(
                main,
                repoRootPath: repoRootPath
            ) ? nil : main
        } else {
            entrypointRelativePath = nil
        }

        var declaredConfigurationTools: [RepoRecipeElectronPackagingTool] = []
        for (relativePath, tool) in knownConfigurationPaths {
            if RepoRecipeFiles.fileExists(relativePath, underRepoRoot: repoRootPath) {
                declaredConfigurationTools.append(tool)
            }
        }

        // electron-builder also accepts a `build` object in package.json.
        // Restrict this check to its distinctive keys so an ordinary lifecycle
        // script or arbitrary metadata cannot become packaging evidence.
        if let buildConfiguration = packageJSON["build"] as? [String: Any],
           buildConfiguration.keys.contains(where: builderConfigurationKeys.contains) {
            declaredConfigurationTools.append(.builder)
        }

        let scripts = (packageJSON["scripts"] as? [String: Any]) ?? [:]
        var scriptTools: [RepoRecipeElectronPackagingTool] = []
        var scriptToolByName: [(name: String, tools: [RepoRecipeElectronPackagingTool])] = []
        for (name, rawScript) in scripts {
            guard let script = rawScript as? String else { continue }
            let tools = packagingTools(inScript: script)
            guard !tools.isEmpty else { continue }
            scriptTools.append(contentsOf: tools)
            scriptToolByName.append((name: name, tools: tools))
        }

        let allTools = declaredConfigurationTools + scriptTools
        let distinctToolRawValues = Set(allTools.map(\.rawValue))
        let packagingTool = distinctToolRawValues.count == 1
            ? allTools.first
            : nil
        let packagingScriptName = packagingScriptName(in: scriptToolByName, packagingTool: packagingTool)
        let hasTauriPackagingSignal = scripts.values
            .compactMap { $0 as? String }
            .contains(where: containsTauriPackagingInvocation)

        let hasAmbiguousPackagingTools = distinctToolRawValues.count > 1
            || scriptToolByName.contains { $0.tools.count > 1 }
            || hasTauriPackagingSignal
        let hasPackagingConfiguration = !declaredConfigurationTools.isEmpty

        return Self(
            hasElectronDependency: hasElectronDependency,
            entrypointRelativePath: entrypointRelativePath,
            packagingScriptName: packagingScriptName,
            packagingTool: packagingTool,
            hasPackagingConfiguration: hasPackagingConfiguration,
            hasAmbiguousPackagingTools: hasAmbiguousPackagingTools
        )
    }

    // MARK: - Declarative signal parsing

    private static let knownConfigurationPaths: [(String, RepoRecipeElectronPackagingTool)] = [
        ("electron-builder.yml", .builder),
        ("electron-builder.yaml", .builder),
        ("electron-builder.json", .builder),
        ("electron-builder.js", .builder),
        ("electron-builder.cjs", .builder),
        ("electron-builder.mjs", .builder),
        ("forge.config.js", .forge),
        ("forge.config.cjs", .forge),
        ("forge.config.mjs", .forge),
        ("forge.config.ts", .forge),
    ]

    private static let builderConfigurationKeys: Set<String> = [
        "appId", "appImage", "artifactName", "directories", "dmg", "files",
        "linux", "mac", "nsis", "productName", "publish", "win"
    ]

    private static let preferredPackagingScriptNames = ["dist:mac", "build:mac", "package:mac", "dist", "package", "make"]

    private static let maximumNativeReviewSummaryBytes = 4 * 1024
    private static let maximumNativeReviewChangedPathCount = 8
    private static let maximumNativeReviewPathBytes = 512

    /// `electron-builder` accepts a `build` object in package.json. Keep this
    /// predicate identical to the detector's distinctive-key rule so the
    /// review summary cannot claim a packaging source the recipe would ignore.
    private static func hasRecognizedManifestBuildConfiguration(
        _ packageJSON: [String: Any]
    ) -> Bool {
        guard let buildConfiguration = packageJSON["build"] as? [String: Any] else {
            return false
        }
        return buildConfiguration.keys.contains(where: builderConfigurationKeys.contains)
    }

    /// `nil` means the declared array cannot safely be used as affirmative
    /// evidence. Do not compact or truncate malformed entries: doing so could
    /// hide a later exclusion or unsupported rule behind an earlier prefix.
    private static func manifestFilesPatterns(_ packageJSON: [String: Any]) -> [String]? {
        guard let buildConfiguration = packageJSON["build"] as? [String: Any] else { return [] }
        let values: [Any]
        if let array = buildConfiguration["files"] as? [Any] {
            values = array
        } else if let string = buildConfiguration["files"] as? String {
            values = [string]
        } else {
            return []
        }
        guard values.count <= maximumManifestFilePatternCount else { return nil }
        var patterns: [String] = []
        for value in values {
            guard let string = value as? String,
                  string.utf8.count <= 256,
                  !containsPromptUnsafeScalars(string) else { return nil }
            patterns.append(string)
        }
        return patterns
    }

    /// Only an inline JSON `build.files` declaration, with no competing config
    /// file and no exclusion rule, may establish packaged inclusion. JavaScript
    /// and YAML configs remain unparsed: comments, expressions, ordering, and
    /// overrides make a partial parser less trustworthy than "not proven".
    private static func manifestCoveredElectronPaths(
        changedPaths: [String],
        packageJSON: [String: Any],
        configurationPaths: [String]
    ) -> [String] {
        guard configurationPaths.isEmpty else { return [] }
        guard let patterns = manifestFilesPatterns(packageJSON),
              !patterns.isEmpty,
              !patterns.contains(where: { $0.hasPrefix("!") }) else { return [] }
        return changedPaths.filter { path in
            patterns.contains { manifestPattern($0, covers: path) }
        }
    }

    /// A configuration file is normally too expressive to parse as proof. The
    /// narrow exception is a single, same-line, literal `files: ["..."]`
    /// property in an Electron Builder config. That is enough to cover the
    /// common static configuration shape without evaluating JavaScript,
    /// interpolating config contents into a prompt, or treating a comment or
    /// computed array as package evidence. Every other configuration remains
    /// deliberately unproven.
    private static func staticConfigurationCoveredElectronPaths(
        changedPaths: [String],
        configurationPaths: [String],
        repoRootPath: String
    ) -> [String] {
        guard configurationPaths.count == 1,
              let configurationPath = configurationPaths.first,
              ["electron-builder.js", "electron-builder.cjs", "electron-builder.mjs"].contains(configurationPath),
              let text = RepoRecipeFiles.readText(configurationPath, underRepoRoot: repoRootPath),
              let patterns = staticSameLineFilesArray(in: text),
              !patterns.isEmpty,
              !patterns.contains(where: { $0.hasPrefix("!") })
        else { return [] }
        return changedPaths.filter { path in
            patterns.contains { manifestPattern($0, covers: path) }
        }
    }

    /// Parse only `files: ["literal", "literal"]` on one configuration line.
    /// The parser refuses escapes, non-string expressions, duplicate `files`
    /// properties, comments before the property, and multiline values.
    private static func staticSameLineFilesArray(in configuration: String) -> [String]? {
        let candidates = configuration.split(whereSeparator: \.isNewline).compactMap { rawLine -> String? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("files:") else { return nil }
            return String(line.dropFirst("files:".count)).trimmingCharacters(in: .whitespaces)
        }
        guard candidates.count == 1,
              let opening = candidates[0].firstIndex(of: "["),
              opening == candidates[0].startIndex,
              let closing = candidates[0].firstIndex(of: "]")
        else { return nil }
        let suffix = candidates[0][candidates[0].index(after: closing)...]
            .trimmingCharacters(in: .whitespaces)
        guard suffix.isEmpty || suffix == "," || suffix.hasPrefix("//") else { return nil }
        let body = String(candidates[0][candidates[0].index(after: opening)..<closing])
        guard body.utf8.count <= 4_096 else { return nil }
        var remaining = body[...]
        var patterns: [String] = []
        while true {
            remaining = remaining.drop(while: { $0.isWhitespace })
            if remaining.isEmpty { break }
            guard remaining.first == "\"" else { return nil }
            remaining = remaining.dropFirst()
            guard let quote = remaining.firstIndex(of: "\"") else { return nil }
            let pattern = String(remaining[..<quote])
            guard !pattern.contains("\\"),
                  pattern.utf8.count <= 256,
                  !containsPromptUnsafeScalars(pattern) else { return nil }
            patterns.append(pattern)
            guard patterns.count <= maximumManifestFilePatternCount else { return nil }
            remaining = remaining[remaining.index(after: quote)...]
            remaining = remaining.drop(while: { $0.isWhitespace })
            if remaining.isEmpty { break }
            guard remaining.first == "," else { return nil }
            remaining = remaining.dropFirst()
        }
        return patterns
    }

    /// This is intentionally not a general glob engine. Exact files and a
    /// full directory inclusion are enough for a reliable affirmative signal;
    /// every other pattern remains unproven.
    private static func manifestPattern(_ pattern: String, covers path: String) -> Bool {
        guard pattern.utf8.count <= 256,
              !containsPromptUnsafeScalars(pattern) else { return false }
        if pattern == path { return true }
        guard pattern.hasSuffix("/**") else { return false }
        let directory = String(pattern.dropLast(3))
        return safeReviewRelativePath(directory) != nil && path.hasPrefix(directory + "/")
    }

    private static func boundedSafePathList(_ paths: [String]) -> String {
        let selected = paths.compactMap(safeReviewRelativePath).prefix(maximumNativeReviewChangedPathCount)
        let joined = selected.joined(separator: ", ")
        let data = Data(joined.utf8)
        return data.count <= maximumNativeReviewPathBytes
            ? joined
            : String(decoding: data.prefix(maximumNativeReviewPathBytes), as: UTF8.self)
                + "…"
    }

    private static func safeReviewRelativePath(_ path: String?) -> String? {
        guard let path,
              !path.isEmpty,
              path.utf8.count <= 256,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !containsPromptUnsafeScalars(path) else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        return path
    }

    private static func containsPromptUnsafeScalars(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                || bidiFormattingControlValues.contains(scalar.value)
        }
    }

    private static let maximumManifestFilePatternCount = 32

    private static let bidiFormattingControlValues: Set<UInt32> = [
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    private static func dependencyNames(in packageJSON: [String: Any]) -> Set<String> {
        var names = Set<String>()
        for section in ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"] {
            guard let dependencies = packageJSON[section] as? [String: Any] else { continue }
            names.formUnion(dependencies.keys)
        }
        return names
    }

    private static func mainFileIsReadable(_ relativePath: String, repoRootPath: String) -> Bool {
        // readText distinguishes a regular UTF-8 entry file from a directory,
        // while retaining the detector's size and containment checks.
        RepoRecipeFiles.readText(relativePath, underRepoRoot: repoRootPath) != nil
    }

    private static func packagingTools(
        inScript script: String
    ) -> [RepoRecipeElectronPackagingTool] {
        var foundTools = [RepoRecipeElectronPackagingTool]()
        for segment in commandSegments(in: script) {
            let words = shellWords(in: segment)
            guard let firstWord = words.first?.lowercased(),
                  firstWord != "echo",
                  firstWord != ":" else { continue }
            for tool in RepoRecipeElectronPackagingTool.allCases
            where toolInvocationIsFirstCommand(tool, words: words) {
                if !foundTools.contains(tool) { foundTools.append(tool) }
            }
        }
        return foundTools
    }

    private static func packagingScriptName(
        in scriptTools: [(name: String, tools: [RepoRecipeElectronPackagingTool])],
        packagingTool: RepoRecipeElectronPackagingTool?
    ) -> String? {
        guard let packagingTool else { return nil }
        let candidates = scriptTools.filter { $0.tools.contains(packagingTool) }
        for preferredName in preferredPackagingScriptNames {
            if candidates.contains(where: { $0.name == preferredName }) {
                return preferredName
            }
        }
        // Do not interpolate an arbitrary manifest key into a shell command.
        // A recognized name is optional because the safe tool default remains
        // usable when a project calls its packaging script something unusual.
        return nil
    }

    private static func commandSegments(in script: String) -> [String] {
        // This is a conservative evidence detector, not a shell parser.
        // Quoted commands require investigation rather than guessing whether
        // a tool name is executable code or merely printed text.
        guard !script.contains("\""), !script.contains("'"), !script.contains("`"),
              !script.contains("$(") else { return [] }
        return script.split { $0 == ";" || $0 == "&" || $0 == "|" || $0.isNewline }
            .map(String.init)
    }

    private static func shellWords(in segment: String) -> [String] {
        segment.split { $0.isWhitespace || $0 == "'" || $0 == "\"" }
            .map(String.init)
    }

    private static func toolInvocationIsFirstCommand(
        _ tool: RepoRecipeElectronPackagingTool,
        words: [String]
    ) -> Bool {
        guard !words.isEmpty else { return false }
        let normalizedWords = words.map { word in
            (word as NSString).lastPathComponent.lowercased()
        }
        if normalizedWords.first == tool.rawValue { return true }
        // Package runners may invoke a local binary as the next meaningful
        // word. Keep this allowlist narrow so prose such as `echo tool` does
        // not become shipping evidence.
        let launcherWords: Set<String> = ["npx", "pnpm", "yarn", "bun", "npm", "exec", "run", "--"]
        guard let launcher = normalizedWords.first, launcherWords.contains(launcher),
              normalizedWords.dropFirst().drop(while: launcherWords.contains).first == tool.rawValue
        else { return false }
        return true
    }

    private static func containsTauriPackagingInvocation(_ script: String) -> Bool {
        for segment in commandSegments(in: script) {
            let words = shellWords(in: segment).map { ($0 as NSString).lastPathComponent.lowercased() }
            guard !words.isEmpty, words.first != "echo" else { continue }
            let launchers: Set<String> = ["npx", "pnpm", "yarn", "bun", "npm", "exec", "run", "--"]
            let invocation = words.drop(while: launchers.contains)
            if invocation.first == "tauri" && invocation.dropFirst().contains("build") { return true }
            if words.first == "cargo",
               words.dropFirst().contains("tauri"),
               words.dropFirst().contains("build") { return true }
        }
        return false
    }
}
