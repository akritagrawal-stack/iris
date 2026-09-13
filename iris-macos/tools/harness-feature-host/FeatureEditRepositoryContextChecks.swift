import Foundation
@testable import IrisHarnessNative

@main
struct FeatureEditRepositoryContextChecks {
    enum Failure: Error { case assertion(String) }

    @MainActor static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure.assertion(message) }
    }

    @MainActor static func main() throws {
        try discoversParentDirectoryDependenciesInStableOrder()
        print("PASS review context: parent-directory imports, export-from, require and priority")
        try interleavesDependenciesBeforeTheByteBound()
        print("PASS review context: dependency fairness across changed sources")
        try prioritizesLateAddedHelperUnderBytePressure()
        print("PASS review context: late added helper is promoted ahead of large imports")
        try keepsPersistenceHintScopedToItsChangedFile()
        print("PASS review context: unrelated persistence hint cannot reorder another file")
        try refusesHintsAbsentFromCurrentSource()
        print("PASS review context: preferred hints cannot introduce unseen imports")
        try refusesExternalTraversalAndSymlinkReferences()
        print("PASS review context: package aliases, traversal and symlink candidates refused")
        try parsesAddedImportsAndFallsBackForUnsupportedDiffShapes()
        print("PASS review context: added-import parser handles hunks and safe fallback")
        try ignoresMalformedHunkHints()
        print("PASS review context: malformed hunks cannot supply import hints")
        try respectsDiffPrefixAndNoDependencyByteBounds()
        print("PASS review context: diff and context byte bounds remain truthful")
        try enforcesFileCountAndDuplicateBounds()
        print("PASS review context: duplicate paths removed and 24-file bound enforced")
        try prioritizesCrossDirectoryConsumersWithoutIncreasingThePromptBudget()
        print("PASS review context: cross-directory consumers fit before unrelated dependencies")
        try followsOnlyTwoReverseConsumerHopsWithinTheScannedCandidateSet()
        print("PASS review context: depth-two user-facing consumer traversal is bounded")
        try preservesRealNitroConsumerBodiesThroughNativeReviewContext()
        print("PASS review context: recorded Nitro save/download bodies reach native evidence and reviewer prompt")
        try prioritizesUserFacingConsumersAndHelpersOverGenericLibraryFallbacks()
        print("PASS review context: user-facing callers and their helpers win bounded review context")
        try refusesUnsafeConsumerCandidatesAndBoundsDiscovery()
        print("PASS review context: consumer candidates remain confined and count-bounded")
        try boundsConsumerDiscoveryBytes()
        print("PASS review context: reverse-source scan has a separate local byte ceiling")
        print("FEATURE EDIT REPOSITORY CONTEXT CHECKS PASS: 16 groups")
    }

    @MainActor static func preservesRealNitroConsumerBodiesThroughNativeReviewContext() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // These are the seven recovered changed-file byte sizes. Their bodies
        // are represented by recorded source snippets plus deterministic
        // padding; no app source is executed or read from a live user path.
        let changedSizes: [(String, Int)] = [
            ("src/lib/db/idb.ts", 2900), ("src/lib/db/index.ts", 4640),
            ("src/lib/db/memory.ts", 2674), ("src/lib/transfer.test.ts", 6225),
            ("src/lib/transfer.ts", 4917), ("src/lib/types.ts", 4350),
            ("src/pages/Settings.tsx", 20207),
        ]
        for (path, size) in changedSizes {
            try writePaddedSource(path, body: "export const recovered = true;\n", byteCount: size, under: root)
        }
        try writePaddedSource("src/pages/Settings.tsx", body: """
        import { useApp } from "../lib/app";
        import { exportMarkdown, downloadText } from "../lib/export";
        import type { EngineMode } from "../lib/types";
        export const Settings = () => useApp() && downloadText && (null as EngineMode | null);
        """, byteCount: 20207, under: root)

        let noteSaveBody = """
        import { useApp } from "../lib/app";
        import { downloadText } from "../lib/export";
        import type { Block, Note } from "../lib/types";
        export function persist(note: Note, patch: Partial<Note>, onNote: (n: Note) => void) {
            const next = { ...note, ...patch, updatedAt: now() };
            onNote(next);
            if (saveTimer.current) clearTimeout(saveTimer.current);
            saveTimer.current = setTimeout(() => repo?.putNote(next), 400);
        }
        export const saveBody = "repo?.putNote(next)";
        """
        let downloadBody = """
        import type { Block, Note } from "./types";
        export function downloadText(filename: string, text: string, mime = "text/plain"): void {
            if (typeof window === "undefined" || typeof document === "undefined") return;
            const blob = new Blob([text], { type: mime });
            const url = URL.createObjectURL(blob);
            const a = document.createElement("a");
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        }
        """
        try writePaddedSource("src/pages/NoteView.tsx", body: noteSaveBody, byteCount: 8605, under: root)
        try writePaddedSource("src/lib/export.ts", body: downloadBody, byteCount: 4588, under: root)
        try writePaddedSource("src/lib/app.tsx", body: "import { Repo } from \"./db\"; export const app = Repo;\n", byteCount: 3843, under: root)
        try writePaddedSource("src/pages/Dashboard.tsx", body: "import { useApp } from \"../lib/app\"; export const dashboard = useApp;\n", byteCount: 19715, under: root)
        try writePaddedSource("src/lib/markdown.ts", body: "import type { Note } from \"./types\"; export const markdown = true;\n", byteCount: 12607, under: root)

        let changedPaths = changedSizes.map(\.0)
        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: root.path,
            changedTestPaths: ["src/lib/transfer.test.ts"],
            declaredNativeTestPaths: [],
            changedPaths: changedPaths,
            sameDirectoryNeighborPaths: [],
            candidateSourcePaths: [
                "src/lib/markdown.ts", "src/pages/Dashboard.tsx", "src/lib/app.tsx",
                "src/lib/export.ts", "src/pages/NoteView.tsx",
            ],
            isNativeFinalReview: true,
            maxFileCount: 24,
            maxBytes: FeatureEditRepositoryContext.maximumPermittedByteBudget
        )
        let note = context.files.first { $0.repoRelativePath == "src/pages/NoteView.tsx" }
        let download = context.files.first { $0.repoRelativePath == "src/lib/export.ts" }
        try require(note?.utf8Text.contains("repo?.putNote(next)") == true
            && download?.utf8Text.contains("const blob = new Blob([text]") == true,
            "recorded NoteView save or export download body was omitted or partial")
        try require(context.includedByteCount == 62949,
            "recorded Nitro context changed size: expected 62,949 complete UTF-8 bytes")
        try require(context.includedByteCount <= FeatureEditRepositoryContext.maximumPermittedByteBudget
            && context.omittedFileCount > 0,
            "real-shaped context escaped its unchanged byte ceiling or hid omitted sources")

        let diff = "diff --git a/src/lib/transfer.ts b/src/lib/transfer.ts\n+export const changed = true;"
        guard let evidence = HarnessNativeVerificationSequence.NativeAdmissionEvidence.capture(
            diff: diff, context: context
        ), let handoff = evidence.matchingPrompt(forDiff: diff, repoRootPath: root.path) else {
            throw Failure.assertion("real-shaped context could not form a native admission handoff")
        }
        let nativeNote = evidence.selectedFiles.first { $0.path == "src/pages/NoteView.tsx" }
        let nativeDownload = evidence.selectedFiles.first { $0.path == "src/lib/export.ts" }
        try require(nativeNote?.bytes == note?.utf8ByteCount
            && nativeNote?.sha256 == note.map { HarnessFrozenComparison.digest(Data($0.utf8Text.utf8)) }
            && nativeDownload?.bytes == download?.utf8ByteCount
            && nativeDownload?.sha256 == download.map { HarnessFrozenComparison.digest(Data($0.utf8Text.utf8)) }
            && handoff.contains("FINAL NATIVE BEHAVIOR REVIEW HANDOFF"),
            "native admission evidence lost required consumer body identity")
        let reviewer = FeatureEditAdversarialReviewer.reviewPrompt(
            request: "Add notes and folders export/import",
            kind: .feature,
            unifiedDiff: diff,
            evidenceLog: ["native checks: passed"],
            repositoryContext: context
        )
        try require(reviewer.user.contains("repo?.putNote(next)")
            && reviewer.user.contains("const blob = new Blob([text]"),
            "reviewer prompt received paths but not the required consumer bodies")
    }

    @MainActor static func followsOnlyTwoReverseConsumerHopsWithinTheScannedCandidateSet() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("src/data/store.ts", "export const store = true;", under: root)
        try write("src/state/storeFacade.ts", "import { store } from '../data/store'; export const facade = store;", under: root)
        try write("src/pages/Editor.tsx", "import { facade } from '../state/storeFacade'; export const save = () => facade;", under: root)
        try write("src/pages/TooFar.tsx", "import { save } from './Editor'; export const tooFar = save;", under: root)
        try write("src/data/neighbor.ts", "export const unrelated = true;", under: root)

        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: root.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: ["src/data/store.ts"],
            sameDirectoryNeighborPaths: ["src/data/neighbor.ts"],
            candidateSourcePaths: [
                "src/state/storeFacade.ts", "src/pages/Editor.tsx", "src/pages/TooFar.tsx",
            ],
            maxBytes: 4096
        )

        let paths = context.files.map(\.repoRelativePath)
        try require(paths.contains("src/state/storeFacade.ts") && paths.contains("src/pages/Editor.tsx"),
            "two reverse consumer hops were not discovered")
        try require(!paths.contains("src/pages/TooFar.tsx"),
            "reverse consumer discovery exceeded its depth-two bound")
        try require(paths.last == "src/data/neighbor.ts",
            "generic same-directory fallback displaced a bounded consumer")
        try require(context.files.first(where: { $0.repoRelativePath == "src/pages/Editor.tsx" })?.utf8Text.contains("facade") == true,
            "transitive user-facing body was not included completely")
        try require(context.includedByteCount <= 4096 && context.omittedFileCount == 0,
            "depth-two traversal changed byte or omission accounting")
    }

    @MainActor static func prioritizesUserFacingConsumersAndHelpersOverGenericLibraryFallbacks() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("src/lib/types.ts", "export type Note = { id: string };", under: root)
        try write("src/pages/Settings.tsx", "import { downloadText } from '../lib/export'; export const save = () => downloadText('library.json');", under: root)
        try write("src/pages/NoteView.tsx", "import type { Note } from '../lib/types'; export const view = (_: Note) => null;", under: root)
        try write("src/lib/markdown.ts", "import type { Note } from './types'; export const markdown = (_: Note) => '';", under: root)
        try write("src/lib/export.ts", "export const downloadText = (_: string) => undefined;", under: root)

        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: root.path, changedTestPaths: [], declaredNativeTestPaths: [],
            changedPaths: ["src/lib/types.ts", "src/pages/Settings.tsx"],
            sameDirectoryNeighborPaths: [],
            candidateSourcePaths: ["src/lib/markdown.ts", "src/pages/NoteView.tsx"],
            maxBytes: 16 * 1024
        )

        try require(context.files.map(\.repoRelativePath) == [
            "src/pages/Settings.tsx",
            "src/lib/types.ts",
            "src/lib/export.ts",
            "src/pages/NoteView.tsx",
            "src/lib/markdown.ts",
        ], "review context did not prioritize the user-facing caller, its helper, and user-facing consumer: \(context.files.map(\.repoRelativePath))")
        try require(context.includedByteCount <= 16 * 1024,
            "user-facing context ranking raised the model prompt budget")
    }

    @MainActor static func prioritizesCrossDirectoryConsumersWithoutIncreasingThePromptBudget() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("src/data/store.ts", "import { helper } from './helper'; export const store = helper;", under: root)
        try write("src/data/helper.ts", String(repeating: "// dependency\n", count: 90), under: root)
        try write("src/screens/List.tsx", "import { store } from '../data/store'; export const list = store;", under: root)
        try write("src/screens/Editor.tsx", "const store = require('../data/store.js'); export const editor = store;", under: root)
        try write("tests/store.test.ts", "// unchanged assertions remain first", under: root)
        let candidates = ["src/screens/List.tsx", "src/screens/Editor.tsx"]
        let baseline = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: root.path, changedTestPaths: ["tests/store.test.ts"],
            declaredNativeTestPaths: [], changedPaths: ["src/data/store.ts"],
            sameDirectoryNeighborPaths: [], maxBytes: 256
        )
        let revised = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: root.path, changedTestPaths: ["tests/store.test.ts"],
            declaredNativeTestPaths: [], changedPaths: ["src/data/store.ts"],
            sameDirectoryNeighborPaths: [], candidateSourcePaths: candidates, maxBytes: 256
        )
        try require(!baseline.files.contains { candidates.contains($0.repoRelativePath) }, "baseline unexpectedly found reverse consumers")
        try require(revised.files.map(\.repoRelativePath) == ["tests/store.test.ts", "src/data/store.ts"] + candidates,
            "tests and changed source must stay first, followed by complete cross-directory consumers")
        try require(revised.maxBytes == baseline.maxBytes && revised.includedByteCount <= 256,
            "consumer selection raised the prompt budget")
        try require(revised.hasUnseenRequestedContext, "the displaced dependency must remain explicitly unseen")
    }

    @MainActor static func refusesUnsafeConsumerCandidatesAndBoundsDiscovery() throws {
        let root = try makeFixtureRoot()
        let outside = try makeFixtureRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try write("src/store.ts", "export const store = 1;", under: root)
        try write("outside.ts", "import { store } from './store';", under: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("src/linked.ts"),
            withDestinationURL: outside.appendingPathComponent("outside.ts")
        )
        try write("src/late.ts", "import { store } from './store';", under: root)
        let candidates = ["src/linked.ts", "../outside.ts", "/outside.ts"]
            + (0..<97).map { "missing\($0).ts" } + ["src/late.ts"]
        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: root.path, changedTestPaths: [], declaredNativeTestPaths: [],
            changedPaths: ["src/store.ts"], sameDirectoryNeighborPaths: [], candidateSourcePaths: candidates
        )
        try require(context.files.map(\.repoRelativePath) == ["src/store.ts"],
            "unsafe source or a candidate beyond the 100-path scan entered review")
    }

    @MainActor static func boundsConsumerDiscoveryBytes() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("src/store.ts", "export const store = 1;", under: root)
        var candidates: [String] = []
        for index in 0..<8 {
            let path = "src/full\(index).ts"
            try writeSizedSource(path, byteCount: 64 * 1024, under: root)
            candidates.append(path)
        }
        try write("src/late.ts", "import { store } from './store';", under: root)
        candidates.append("src/late.ts")
        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: root.path, changedTestPaths: [], declaredNativeTestPaths: [],
            changedPaths: ["src/store.ts"], sameDirectoryNeighborPaths: [], candidateSourcePaths: candidates
        )
        try require(context.files.map(\.repoRelativePath) == ["src/store.ts"],
            "consumer discovery read past its 512 KiB local ceiling")
        try require(context.maxBytes == 64 * 1024, "local scan allowance changed the model prompt allowance")
    }

    @MainActor static func discoversParentDirectoryDependenciesInStableOrder() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try write("src/db/changed.ts", """
        import type {
            Note
        } from "../types";
        export { helper } from "../helpers";
        const runtime = require("../runtime");
        const runtimeFromJavaScript = require("../runtime.js");
        import { App } from "../app";
        import "../only.ts";
        """, under: fixtureRoot)
        try write("src/other/changed2.ts", "import { runtime } from \"../runtime.js\";\n", under: fixtureRoot)
        try write("src/db/changed.test.ts", """
        import type { Note } from "../types";
        """, under: fixtureRoot)
        try write("src/types.ts", "export type Note = { id: string };\n", under: fixtureRoot)
        try write("src/helpers/index.ts", "export function helper() { return true; }\n", under: fixtureRoot)
        try write("src/runtime.ts", "export const runtime = true;\n", under: fixtureRoot)
        try write("src/runtime.tsx", "export const runtime = false;\n", under: fixtureRoot)
        try write("src/app.tsx", "export function App() { return null; }\n", under: fixtureRoot)
        try write("src/only/index.ts", "export const onlyIndex = true;\n", under: fixtureRoot)
        try write("src/db/neighbor.ts", "export function neighbor() { return false; }\n", under: fixtureRoot)
        try write("native/persistence.test.mjs", "test('persistence', () => true);\n", under: fixtureRoot)

        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: ["src/db/changed.test.ts", "src/db/changed.test.ts"],
            declaredNativeTestPaths: ["native/persistence.test.mjs", "native/persistence.test.mjs"],
            changedPaths: ["src/db/changed.ts", "src/other/changed2.ts", "src/db/changed.test.ts", "src/db/changed.ts"],
            sameDirectoryNeighborPaths: ["src/db/neighbor.ts", "src/db/changed.ts", "src/db/neighbor.ts"]
        )

        try require(context.files.map(\.repoRelativePath) == [
            "src/db/changed.test.ts",
            "native/persistence.test.mjs",
            "src/db/changed.ts",
            "src/other/changed2.ts",
            "src/types.ts",
            "src/runtime.ts",
            "src/helpers/index.ts",
            "src/app.tsx",
            "src/db/neighbor.ts",
        ], "review context priority or one-hop resolution changed")
        try require(context.files.filter { $0.repoRelativePath == "src/types.ts" }.count == 1,
            "duplicate parent dependency was included")
        try require(!context.files.contains { $0.repoRelativePath == "src/only/index.ts" },
            "explicit TypeScript extension incorrectly fell back to an index module")
        try require(!context.files.contains { $0.repoRelativePath == "src/runtime.tsx" },
            "a previously resolved JavaScript module was retargeted to an alternate extension")
        try require(context.omittedFileCount == 0, "resolved fixture paths were reported omitted")
    }

    @MainActor static func interleavesDependenciesBeforeTheByteBound() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try write("src/ui.ts", """
        import { first } from "./uiDependencyA";
        import { second } from "./uiDependencyB";
        import { third } from "./uiDependencyC";
        export const ui = [first, second, third];
        """, under: fixtureRoot)
        try write("src/helper.ts", """
        import type { RequiredType } from "./requiredType";
        export const helper: RequiredType = { required: true };
        """, under: fixtureRoot)

        let largeDependencyByteCount = 900
        let requiredDependencyByteCount = 400
        for dependencyName in ["uiDependencyA", "uiDependencyB", "uiDependencyC"] {
            try writeSizedSource(
                "src/\(dependencyName).ts",
                byteCount: largeDependencyByteCount,
                under: fixtureRoot
            )
        }
        try writeSizedSource(
            "src/requiredType.ts",
            byteCount: requiredDependencyByteCount,
            under: fixtureRoot
        )

        var changedSourceByteCount = 0
        for path in ["src/ui.ts", "src/helper.ts"] {
            changedSourceByteCount += try byteCount(of: path, under: fixtureRoot)
        }
        let maxBytes = changedSourceByteCount
            + (largeDependencyByteCount * 2)
            + requiredDependencyByteCount
            - 1
        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: ["src/ui.ts", "src/helper.ts"],
            sameDirectoryNeighborPaths: [],
            maxBytes: maxBytes
        )

        let paths = context.files.map(\.repoRelativePath)
        try require(paths == [
            "src/ui.ts",
            "src/helper.ts",
            "src/uiDependencyA.ts",
            "src/requiredType.ts",
        ], "a first changed source exhausted the byte budget before the second source dependency")
        try require(context.includedByteCount <= maxBytes,
            "round-robin dependency context exceeded its byte bound")
    }

    @MainActor static func prioritizesLateAddedHelperUnderBytePressure() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let changedPath = "src/editor.ts"
        try write(changedPath, """
        import { render } from "./largeUI";
        import { persist } from "./largePersistence";
        import { helper } from "./newHelper";
        export const result = [render, persist, helper];
        """, under: fixtureRoot)
        try writeSizedSource("src/largeUI.ts", byteCount: 900, under: fixtureRoot)
        try writeSizedSource("src/largePersistence.ts", byteCount: 900, under: fixtureRoot)
        try write("src/newHelper.ts", "export const helper = true;\n", under: fixtureRoot)

        let changedByteCount = try byteCount(of: changedPath, under: fixtureRoot)
        let largeUIByteCount = try byteCount(of: "src/largeUI.ts", under: fixtureRoot)
        let maxBytes = changedByteCount + largeUIByteCount
        let unifiedDiff = """
        diff --git a/src/editor.ts b/src/editor.ts
        index 1111111..2222222 100644
        --- a/src/editor.ts
        +++ b/src/editor.ts
        @@ -1,3 +1,4 @@
         import { render } from "./largeUI";
         import { persist } from "./largePersistence";
        +import { helper } from "./newHelper";
         export const result = [render, persist, helper];
        """
        let preferred = FeatureEditRepositoryContext.addedDependencySourceByPath(in: unifiedDiff)
        try require(preferred[changedPath]?.contains("./newHelper") == true,
            "added helper import was not extracted from the diff")

        let baseline = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: [changedPath],
            sameDirectoryNeighborPaths: [],
            maxBytes: maxBytes
        )
        try require(baseline.files.map(\.repoRelativePath) == [changedPath, "src/largeUI.ts"],
            "baseline dependency order did not demonstrate byte-pressure displacement")
        try require(!baseline.files.contains { $0.repoRelativePath == "src/newHelper.ts" },
            "late helper was already selected without a preferred diff hint")

        let hinted = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: [changedPath],
            sameDirectoryNeighborPaths: [],
            preferredDependencySourceByPath: preferred,
            maxBytes: maxBytes
        )
        try require(hinted.files.map(\.repoRelativePath) == [changedPath, "src/newHelper.ts"],
            "late added helper was not promoted ahead of large imports")
        try require(!hinted.files.contains { $0.repoRelativePath == "src/largePersistence.ts" },
            "unrelated large persistence import displaced the promoted helper")
        try require(hinted.includedByteCount <= maxBytes,
            "preferred dependency context exceeded its byte bound")
    }

    @MainActor static func keepsPersistenceHintScopedToItsChangedFile() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try write("src/editor.ts", """
        import { oldEditor } from "./oldEditor";
        import { helper } from "./editorHelper";
        export const editor = [oldEditor, helper];
        """, under: fixtureRoot)
        try write("src/persistence.ts", """
        import { oldPersistence } from "./oldPersistence";
        export const persistence = oldPersistence;
        """, under: fixtureRoot)
        try writeSizedSource("src/oldEditor.ts", byteCount: 700, under: fixtureRoot)
        try writeSizedSource("src/oldPersistence.ts", byteCount: 700, under: fixtureRoot)
        try write("src/editorHelper.ts", "export const helper = true;\n", under: fixtureRoot)

        let editorByteCount = try byteCount(of: "src/editor.ts", under: fixtureRoot)
        let persistenceByteCount = try byteCount(of: "src/persistence.ts", under: fixtureRoot)
        let oldEditorByteCount = try byteCount(of: "src/oldEditor.ts", under: fixtureRoot)
        let maxBytes = editorByteCount + persistenceByteCount + oldEditorByteCount
        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: ["src/editor.ts", "src/persistence.ts"],
            sameDirectoryNeighborPaths: [],
            preferredDependencySourceByPath: [
                "src/persistence.ts": "import { helper } from \"./editorHelper\";\n",
            ],
            maxBytes: maxBytes
        )
        let paths = context.files.map(\.repoRelativePath)
        try require(paths == [
            "src/editor.ts",
            "src/persistence.ts",
            "src/oldEditor.ts",
        ], "a persistence hint reordered dependencies for another changed file")
        try require(!paths.contains("src/editorHelper.ts"),
            "unrelated persistence hint introduced an editor dependency")
        try require(context.includedByteCount <= maxBytes,
            "persistence-scoped preferred context exceeded its byte bound")
    }

    @MainActor static func refusesHintsAbsentFromCurrentSource() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let changedPath = "src/editor.ts"
        try write(changedPath, "import { safe } from \"./safe\";\nexport { safe };\n", under: fixtureRoot)
        try write("src/safe.ts", "export const safe = true;\n", under: fixtureRoot)
        try write("src/ghost.ts", "export const ghost = true;\n", under: fixtureRoot)

        let changedByteCount = try byteCount(of: changedPath, under: fixtureRoot)
        let safeByteCount = try byteCount(of: "src/safe.ts", under: fixtureRoot)
        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: [changedPath],
            sameDirectoryNeighborPaths: [],
            preferredDependencySourceByPath: [
                changedPath: "import { ghost } from \"./ghost\";\n",
                "src/not-changed.ts": "import { ghost } from \"./ghost\";\n",
            ],
            maxBytes: changedByteCount + safeByteCount
        )
        let paths = context.files.map(\.repoRelativePath)
        try require(paths == [changedPath, "src/safe.ts"],
            "preferred hint introduced a dependency absent from current source")
        try require(!paths.contains("src/ghost.ts"),
            "an absent current import was allowed to introduce a repository file")
    }

    @MainActor static func refusesExternalTraversalAndSymlinkReferences() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try write("src/changed.ts", """
        import "./types";
        import "react";
        import "@/types";
        const outside = require("../../outside");
        const linked = require("./linked");
        """, under: fixtureRoot)
        try write("src/types.ts", "export type Note = { id: string };\n", under: fixtureRoot)
        try write("src/real.ts", "export const real = true;\n", under: fixtureRoot)
        let symlinkURL = fixtureRoot.appendingPathComponent("src/linked.ts")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: fixtureRoot.appendingPathComponent("src/real.ts")
        )

        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: ["src/changed.ts"],
            sameDirectoryNeighborPaths: [],
            preferredDependencySourceByPath: [
                "src/changed.ts": """
                import "../../outside";
                import "/tmp/external";
                import "./linked";
                import "./types";
                """,
            ]
        )
        let paths = context.files.map(\.repoRelativePath)
        try require(paths == ["src/changed.ts", "src/types.ts"],
            "external, traversal or symlink reference escaped review context")
        try require(!paths.contains("src/linked.ts") && !paths.contains("src/real.ts"),
            "symlink target entered review context")
    }

    @MainActor static func parsesAddedImportsAndFallsBackForUnsupportedDiffShapes() throws {
        let diff = """
        diff --git a/src/entry.ts b/src/entry.ts
        index 1111111..2222222 100644
        --- a/src/entry.ts
        +++ b/src/entry.ts
        @@ -1,2 +1,4 @@
         import "./existing";
        +import "./added";
        +export { value } from '../exported';
         export const entry = true;
        diff --git "a/src/quoted.ts" "b/src/quoted.ts"
        --- "a/src/quoted.ts"
        +++ "b/src/quoted.ts"
        @@ -1,1 +1,2 @@
        +import "./quoted";
        diff --git a/src/deleted.ts /dev/null
        --- a/src/deleted.ts
        +++ /dev/null
        @@ -1,1 +0,0 @@
        -import "./deleted";
        diff --git a/src/binary.ts b/src/binary.ts
        Binary files a/src/binary.ts and b/src/binary.ts differ
        diff --git a/src/old.ts b/src/new.ts
        similarity index 100%
        rename from src/old.ts
        rename to src/new.ts
        diff --git a/src/truncated.ts b/src/truncated.ts
        --- a/src/truncated.ts
        +++ b/src/truncated.ts
        """
        let preferred = FeatureEditRepositoryContext.addedDependencySourceByPath(in: diff)
        try require(Array(preferred.keys) == ["src/entry.ts"],
            "unsupported diff shapes produced an unsafe preferred path")
        let entrySource = preferred["src/entry.ts"] ?? ""
        try require(entrySource.contains("./added") && entrySource.contains("../exported"),
            "added imports were not retained from a normal hunk")
        try require(!entrySource.contains("@@") && !entrySource.contains("./quoted"),
            "hunk or quoted-header text leaked into a preferred source hint")

        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let changedPath = "src/entry.ts"
        try write(changedPath, """
        import { first } from "./first";
        import { second } from "./second";
        export const entry = [first, second];
        """, under: fixtureRoot)
        try write("src/first.ts", "export const first = true;\n", under: fixtureRoot)
        try write("src/second.ts", "export const second = true;\n", under: fixtureRoot)
        let changedByteCount = try byteCount(of: changedPath, under: fixtureRoot)
        let firstByteCount = try byteCount(of: "src/first.ts", under: fixtureRoot)
        let fallbackContext = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: [changedPath],
            sameDirectoryNeighborPaths: [],
            preferredDependencySourceByPath: FeatureEditRepositoryContext.addedDependencySourceByPath(
                in: """
                diff --git \"a/src/entry.ts\" \"b/src/entry.ts\"
                --- \"a/src/entry.ts\"
                +++ \"b/src/entry.ts\"
                @@ -1,2 +1,3 @@
                +import { second } from \"./second\";
                """
            ),
            maxBytes: changedByteCount + firstByteCount
        )
        try require(fallbackContext.files.map(\.repoRelativePath) == [changedPath, "src/first.ts"],
            "quoted diff header did not fall back to current-source dependency order")
    }

    @MainActor static func ignoresMalformedHunkHints() throws {
        let hints = FeatureEditRepositoryContext.addedDependencySourceByPath(in: """
        diff --git a/src/entry.ts b/src/entry.ts
        --- a/src/entry.ts
        +++ b/src/entry.ts
        @@ invalid hunk @@
        +import "./not-a-hint";
        """)
        try require(hints.isEmpty, "malformed hunk supplied a preferred import")
    }

    @MainActor static func respectsDiffPrefixAndNoDependencyByteBounds() throws {
        let oversizedPrefix = String(
            repeating: "x",
            count: FeatureEditRepositoryContext.maximumPermittedByteBudget
        )
        let laterHintDiff = oversizedPrefix + "\n" + """
        diff --git a/src/late.ts b/src/late.ts
        --- a/src/late.ts
        +++ b/src/late.ts
        @@ -1,0 +1,1 @@
        +import "./lateHelper";
        """
        try require(
            FeatureEditRepositoryContext.addedDependencySourceByPath(in: laterHintDiff).isEmpty,
            "diff parser read a hint beyond its bounded prefix"
        )

        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let changedPath = "src/entry.ts"
        try write(changedPath, "import { dependency } from \"./dependency\";\n", under: fixtureRoot)
        try write("src/dependency.ts", "export const dependency = true;\n", under: fixtureRoot)
        let changedByteCount = try byteCount(of: changedPath, under: fixtureRoot)
        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: [],
            declaredNativeTestPaths: [],
            changedPaths: [changedPath],
            sameDirectoryNeighborPaths: [],
            maxBytes: changedByteCount
        )
        try require(context.files.map(\.repoRelativePath) == [changedPath],
            "a dependency was included after changed files consumed the byte budget")
        try require(context.includedByteCount == changedByteCount,
            "changed-file byte accounting drifted at a zero-dependency budget")
        try require(context.omittedFileCount == 1 && context.hasUnseenRequestedContext,
            "omitted dependency was not reported as unseen context")
    }

    @MainActor static func enforcesFileCountAndDuplicateBounds() throws {
        let fixtureRoot = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try write("src/entry.ts", "import { dependency } from \"./dependency\";\n", under: fixtureRoot)
        try write("src/dependency.ts", "export const dependency = true;\n", under: fixtureRoot)
        try write("tests/entry.test.ts", "test('entry', () => true);\n", under: fixtureRoot)
        try write("native/persistence.test.mjs", "test('native', () => true);\n", under: fixtureRoot)

        var neighbors: [String] = []
        for index in 0..<30 {
            let path = "src/neighbor\(index).ts"
            try write(path, "export const value\(index) = \(index);\n", under: fixtureRoot)
            neighbors.append(path)
        }
        neighbors.append("src/neighbor0.ts")

        let context = FeatureEditRepositoryContext.collectReviewContext(
            repoRootPath: fixtureRoot.path,
            changedTestPaths: ["tests/entry.test.ts"],
            declaredNativeTestPaths: ["native/persistence.test.mjs"],
            changedPaths: ["src/entry.ts"],
            sameDirectoryNeighborPaths: neighbors,
            maxFileCount: 99,
            maxBytes: 4096
        )
        let paths = context.files.map(\.repoRelativePath)
        try require(paths.count == FeatureEditRepositoryContext.maximumPermittedReviewFileCount,
            "review context exceeded the hard file bound")
        try require(paths.prefix(4).elementsEqual([
            "tests/entry.test.ts",
            "native/persistence.test.mjs",
            "src/entry.ts",
            "src/dependency.ts",
        ]), "a fallback neighbor displaced a required dependency")
        try require(Set(paths).count == paths.count, "final context contains duplicate paths")
        try require(context.includedByteCount <= 4096, "final context exceeded byte bound")
    }

    @MainActor static func makeFixtureRoot() throws -> URL {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-review-context-selector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        return fixtureRoot
    }

    @MainActor static func write(_ relativePath: String, _ contents: String, under root: URL) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    @MainActor static func writeSizedSource(
        _ relativePath: String,
        byteCount: Int,
        under root: URL
    ) throws {
        try write(relativePath, String(repeating: "x", count: byteCount), under: root)
    }

    @MainActor static func writePaddedSource(
        _ relativePath: String,
        body: String,
        byteCount: Int,
        under root: URL
    ) throws {
        let bodyByteCount = body.utf8.count
        guard bodyByteCount <= byteCount else {
            throw Failure.assertion("fixture body exceeds its recorded byte size: \(relativePath)")
        }
        try write(relativePath, body + String(repeating: "x", count: byteCount - bodyByteCount), under: root)
    }

    @MainActor static func byteCount(of relativePath: String, under root: URL) throws -> Int {
        try Data(contentsOf: root.appendingPathComponent(relativePath)).count
    }
}
