import Foundation
@testable import IrisHarnessNative

private enum SpatialGuidanceCheckError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Headless, linked checks for the narrow spatial-guidance seams.
///
/// The locator is a deterministic seam, not a screen or application. These
/// checks prove resolver ordering and refusal behavior without launching or
/// observing any GUI application.
@main
struct SpatialGuidanceChecks {
    @MainActor
    static func main() async {
        do {
            try await run()
            print("SPATIAL GUIDANCE CHECKS PASS: sanitizer, focused-window ordering, bounded fallback, refusal and disabled model rung")
        } catch {
            print("SPATIAL GUIDANCE CHECKS FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        try checkSanitizer()
        try checkSemanticFreshness()
        try checkOutlineEligibility()
        try checkWindowIdentityFactory()
        try checkCoordinateTransforms()
        try await checkInitialEvidenceValidation()
        try await checkFocusedWindowWins()
        try await checkWindowListIsOneBoundedFallback()
        try await checkMissingAllRefuses()
        try await checkDisabledInferredTargetDoesNotAskTheModel()
        try await checkDuplicateEvidenceRefuses()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SpatialGuidanceCheckError.failed(message) }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw SpatialGuidanceCheckError.failed(message) }
        return value
    }

    private static func checkSanitizer() throws {
        try require(
            CompanionManager.sanitizedPointingBubbleText(from: "  Save\n settings  ")
                == "Save settings",
            "label whitespace was not collapsed to one line"
        )
        try require(
            CompanionManager.sanitizedPointingBubbleText(
                from: String(repeating: "x", count: 41)
            ) == String(repeating: "x", count: 40),
            "label was not bounded to 40 characters"
        )
        try require(
            CompanionManager.sanitizedPointingBubbleText(from: "save\u{0007}now") == nil,
            "control-bearing label was not rejected"
        )
        try require(
            CompanionManager.sanitizedPointingBubbleText(from: "   ") == nil
                && CompanionManager.sanitizedPointingBubbleText(from: nil) == nil,
            "empty label was not cleared"
        )
        print("PASS sanitizer")
    }

    private static func checkSemanticFreshness() throws {
        let topology = testTopology
        let first = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: CGRect(x: 40, y: 60, width: 100, height: 24),
            topology: topology
        )
        let moved = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: CGRect(x: 70, y: 90, width: 100, height: 24),
            topology: topology
        )
        let changedTab = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-b",
            rectangle: first.rectangle,
            topology: topology
        )
        let changedControl = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-b",
            tabFingerprint: "tab-a",
            rectangle: first.rectangle,
            topology: topology
        )
        let changedForeground = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: first.rectangle,
            topology: topology,
            foregroundProcessIdentifier: 99,
            focusedWindowIdentifier: "window-a"
        )
        let changedFocus = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: first.rectangle,
            topology: topology,
            focusedWindowIdentifier: "window-b"
        )

        try require(GuidePointingFreshness.freshness(from: first, to: moved) == .movedSameTarget,
                    "moved target was not retained as the same semantic target")
        try require(GuidePointingFreshness.freshness(from: first, to: changedTab) == .stale(.tabOrDocumentChanged),
                    "same rectangle different tab was accepted")
        try require(GuidePointingFreshness.freshness(from: first, to: changedControl) == .stale(.controlIdentityChanged),
                    "same rectangle different control was accepted")
        try require(GuidePointingFreshness.freshness(from: first, to: changedForeground) == .stale(.processChanged),
                    "changed foreground process was accepted")
        try require(GuidePointingFreshness.freshness(from: first, to: changedFocus) == .stale(.windowChanged),
                    "changed focused window was accepted")
        try require(GuidePointingFreshness.validateCurrentObservation(changedForeground) == .stale(.processChanged),
                    "initial foreground validation was skipped")
        try require(GuidePointingFreshness.validateCurrentObservation(changedFocus) == .stale(.windowChanged),
                    "initial focused-window validation was skipped")
        try require(GuidePointingFreshness.privacyFingerprint(of: "Secret Document") != "Secret Document",
                    "raw AX label text was retained as its fingerprint")
        try require(GuidePointingFreshness.freshness(
            from: .geometryOnly(first.rectangle), to: .geometryOnly(first.rectangle)
        ) == .unavailable(.missingSemanticIdentity), "geometry-only evidence was treated as fresh")
        print("PASS semantic freshness, foreground/focus validation, and uncertainty")
    }

    /// This calls the production AX-window factory. It must never turn window
    /// geometry into an identity, and a missing AX identifier must not make
    /// every titled AX window unavailable.
    private static func checkWindowIdentityFactory() throws {
        let title = "Untitled Project"
        let titleFingerprint = try requireValue(
            GuidePointingFreshness.privacyFingerprint(of: title),
            "fixture title did not fingerprint"
        )
        let fallback = SystemGuideTargetLocator.windowFingerprint(
            processIdentifier: 11,
            bundleIdentifier: "com.example.app",
            accessibilityIdentifier: nil,
            title: title
        )
        try require(
            fallback.windowIdentifier == "title-fingerprint:\(titleFingerprint)",
            "window factory did not use the bounded title identity"
        )
        let explicit = SystemGuideTargetLocator.windowFingerprint(
            processIdentifier: 11,
            bundleIdentifier: "com.example.app",
            accessibilityIdentifier: "window-42",
            title: title
        )
        try require(explicit.windowIdentifier == "window-42",
                    "window factory did not prefer the AX identifier")
        let target = GuideTargetFingerprint(
            processIdentifier: 11,
            bundleIdentifier: "com.example.app",
            windowIdentifier: fallback.windowIdentifier,
            windowTitleFingerprint: fallback.titleFingerprint,
            role: "AXWindow"
        )
        try require(target.availability == .complete,
                    "titled AX window factory result remained unavailable")
        let observedWindow = GuideTargetEvidence(
            rectangle: CGRect(x: 40, y: 60, width: 100, height: 24),
            fingerprint: target,
            observation: GuideObservationSnapshot(
                monotonicNanoseconds: 10,
                frontmostProcessIdentifier: 11,
                frontmostBundleIdentifier: "com.example.app",
                focusedWindow: fallback,
                coordinateMetadata: nil
            )
        )
        try require(GuidePointingFreshness.validateCurrentObservation(observedWindow) == .fresh,
                    "factory result did not satisfy the focused-window gate")
        let missing = SystemGuideTargetLocator.windowFingerprint(
            processIdentifier: 11,
            bundleIdentifier: "com.example.app",
            accessibilityIdentifier: nil,
            title: nil
        )
        try require(missing.windowIdentifier == nil,
                    "window factory invented an identity without AX evidence")
        print("PASS production AX-window identity factory")
    }

    private static func checkOutlineEligibility() throws {
        let current = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: CGRect(x: 40, y: 60, width: 100, height: 24),
            topology: testTopology
        )
        let changedWindow = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: current.rectangle,
            topology: testTopology,
            focusedWindowIdentifier: "window-b"
        )

        let outline = CompanionManager.freshGuideTargetOutline(from: current)
        try require(outline?.rectangle == current.rectangle,
                    "fresh semantic evidence did not produce an outline")
        try require(CompanionManager.freshGuideTargetOutline(from: changedWindow) == nil,
                    "changed window retained an outline from the prior target")
        print("PASS final outline freshness gate")
    }

    private static func checkCoordinateTransforms() throws {
        let topology = testTopology
        let metadata = GuideCoordinateMetadata(
            topology: topology,
            displayID: 2,
            captureCropOriginInDisplayPixels: CGPoint(x: 200, y: 100),
            captureCropSizeInDisplayPixels: CGSize(width: 600, height: 400),
            captureImageSizeInPixels: CGSize(width: 300, height: 200),
            scale: 1
        )
        guard let point = GuidePointingFreshness.appKitPoint(
            fromCapturePixels: CGPoint(x: 50, y: 25),
            metadata: metadata,
            currentTopology: topology
        ) else {
            throw SpatialGuidanceCheckError.failed("scaled negative-origin capture did not transform")
        }
        try require(point == CGPoint(x: -980, y: 750), "crop or negative-origin transform was incorrect")
        try require(
            GuidePointingFreshness.appKitRectangle(
                fromAccessibilityTopLeft: CGRect(x: -1200, y: 20, width: 100, height: 40),
                topology: topology
            ) == CGRect(x: -1200, y: 840, width: 100, height: 40),
            "AX top-left transform did not use the topology reference"
        )
        print("PASS coordinate topology, crop, scale, and negative origin")
    }

    @MainActor
    private static func checkInitialEvidenceValidation() async throws {
        let target = GuidePointTarget(
            descriptor: "the Save button", inApp: nil, isWindow: false, provenance: .authoredAndFound
        )
        let foregroundMismatch = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: CGRect(x: 40, y: 60, width: 100, height: 24),
            topology: testTopology,
            foregroundProcessIdentifier: 99
        )
        let focusMismatch = evidence(
            processIdentifier: 11,
            windowIdentifier: "window-a",
            controlIdentifier: "save-a",
            tabFingerprint: "tab-a",
            rectangle: foregroundMismatch.rectangle,
            topology: testTopology,
            focusedWindowIdentifier: "window-b"
        )
        for (lookup, expected, label) in [
            (GuideTargetLookup.found(foregroundMismatch), GuidePointingFreshnessVerdict.stale(.processChanged), "foreground"),
            (GuideTargetLookup.found(focusMismatch), GuidePointingFreshnessVerdict.stale(.windowChanged), "focused window"),
        ] {
            let outcome = await GuideStepPointingCoordinator.resolve(
                decision: .pointAt(target),
                stepTitle: "Save",
                stepBody: "",
                mayAskTheModel: false,
                using: EvidenceLocator(lookup: lookup)
            )
            try require(outcome.screenLocation == nil, "initial (label) mismatch still produced a point")
            try require(outcome.freshness == expected, "initial (label) mismatch lost its freshness verdict")
        }
        print("PASS initial evidence validation")
    }

    @MainActor
    private static func checkFocusedWindowWins() async throws {
        let focused = CGRect(x: 100, y: 120, width: 600, height: 400)
        let other = CGRect(x: 800, y: 160, width: 600, height: 400)
        let locator = Locator(focusedWindow: focused, windowList: other)
        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(windowTarget),
            stepTitle: "Open Terminal",
            stepBody: "",
            mayAskTheModel: false,
            using: locator
        )

        try require(locator.focusedWindowLookups == 1, "focused-window seam was not consulted once")
        try require(locator.windowListLookups == 0, "window-list fallback ran despite a focused window")
        try require(locator.accessibilityLookups == 0, "accessibility walk ran after focused-window success")
        try require(locator.modelLookups == 0 && !outcome.theModelWasAsked,
                    "focused-window resolution spent the model rung")
        print("PASS focused-window ordering")
    }

    @MainActor
    private static func checkWindowListIsOneBoundedFallback() async throws {
        let fallback = CGRect(x: 100, y: 120, width: 600, height: 400)
        let locator = Locator(focusedWindow: nil, windowList: fallback)
        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(windowTarget),
            stepTitle: "Open Terminal",
            stepBody: "",
            mayAskTheModel: false,
            using: locator
        )

        try require(locator.focusedWindowLookups == 1, "focused-window miss was not observed")
        try require(locator.windowListLookups == 1, "compatibility fallback did not run exactly once")
        try require(locator.accessibilityLookups == 0, "accessibility walk ran after fallback success")
        try require(locator.modelLookups == 0 && !outcome.theModelWasAsked,
                    "window-list fallback spent the model rung")
        print("PASS bounded window-list fallback")
    }

    @MainActor
    private static func checkMissingAllRefuses() async throws {
        let locator = Locator(focusedWindow: nil, windowList: nil)
        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(windowTarget),
            stepTitle: "Open Terminal",
            stepBody: "",
            mayAskTheModel: false,
            using: locator
        )

        try require(locator.focusedWindowLookups == 1 && locator.windowListLookups == 1,
                    "missing window evidence did not exhaust the bounded window seams")
        try require(locator.accessibilityLookups == 1, "missing window evidence did not check accessibility")
        try require(locator.modelLookups == 0 && !outcome.theModelWasAsked,
                    "missing target asked the model despite a disabled model rung")
        guard case .doNotPoint(.couldNotFindIt(descriptor: windowTarget.descriptor)) = outcome.decision else {
            throw SpatialGuidanceCheckError.failed("missing target did not return couldNotFindIt")
        }
        try require(outcome.screenLocation == nil, "missing target invented a screen coordinate")
        print("PASS missing-all refusal")
    }

    @MainActor
    private static func checkDisabledInferredTargetDoesNotAskTheModel() async throws {
        let target = GuidePointTarget(
            descriptor: "the Save button",
            inApp: nil,
            isWindow: false,
            provenance: .inferred
        )
        let locator = Locator(focusedWindow: nil, windowList: nil)
        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(target),
            stepTitle: "Save the file",
            stepBody: "",
            mayAskTheModel: false,
            using: locator
        )

        try require(locator.focusedWindowLookups == 0 && locator.windowListLookups == 0,
                    "non-window inferred target entered a window seam")
        try require(locator.accessibilityLookups == 1, "inferred target did not try the free accessibility rung")
        try require(locator.modelLookups == 0 && !outcome.theModelWasAsked,
                    "disabled inferred target still asked the model")
        guard case .doNotPoint(.couldNotFindIt(descriptor: target.descriptor)) = outcome.decision else {
            throw SpatialGuidanceCheckError.failed("disabled inferred target did not refuse honestly")
        }
        try require(outcome.screenLocation == nil, "disabled inferred target invented a coordinate")
        print("PASS disabled inferred model rung")
    }

    @MainActor
    private static func checkDuplicateEvidenceRefuses() async throws {
        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(GuidePointTarget(
                descriptor: "the Save button", inApp: nil, isWindow: false, provenance: .authoredAndFound
            )),
            stepTitle: "Save",
            stepBody: "",
            mayAskTheModel: false,
            using: AmbiguousEvidenceLocator()
        )
        guard case .doNotPoint(.pointingUnavailable(let message)) = outcome.decision else {
            throw SpatialGuidanceCheckError.failed("duplicate evidence did not refuse")
        }
        try require(message.contains("more than one"), "duplicate refusal did not explain ambiguity")
        try require(outcome.freshness == .ambiguous(.duplicateCandidates),
                    "duplicate refusal lost its ambiguity verdict")
        print("PASS duplicate evidence refusal")
    }

    private static let windowTarget = GuidePointTarget(
        descriptor: "the Terminal window",
        inApp: "com.apple.Terminal",
        isWindow: true,
        provenance: .shellWindow
    )

    private static let testTopology = GuideDisplayTopology(
        displays: [
            GuideDisplayReference(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 22, width: 1440, height: 878),
                pixelSize: CGSize(width: 2880, height: 1800),
                scale: 2
            ),
            GuideDisplayReference(
                displayID: 2,
                frame: CGRect(x: -1280, y: 100, width: 1280, height: 800),
                visibleFrame: CGRect(x: -1280, y: 100, width: 1280, height: 800),
                pixelSize: CGSize(width: 1280, height: 800),
                scale: 1
            ),
        ],
        accessibilityTopLeftReferenceY: 900,
        menuBarReferenceY: 878
    )

    private static func evidence(
        processIdentifier: Int32,
        windowIdentifier: String,
        controlIdentifier: String,
        tabFingerprint: String,
        rectangle: CGRect,
        topology: GuideDisplayTopology,
        foregroundProcessIdentifier: Int32? = nil,
        focusedWindowIdentifier: String? = nil
    ) -> GuideTargetEvidence {
        let fingerprint = GuideTargetFingerprint(
            processIdentifier: processIdentifier,
            bundleIdentifier: "com.example.app",
            windowIdentifier: windowIdentifier,
            windowTitleFingerprint: "window-title",
            role: "AXButton",
            identifier: controlIdentifier,
            labelFingerprint: GuidePointingFreshness.privacyFingerprint(of: "Save"),
            ancestry: [GuideAccessibilityAncestor(
                role: "AXGroup",
                identifier: "toolbar",
                labelFingerprint: GuidePointingFreshness.privacyFingerprint(of: "Toolbar")
            )],
            tabOrDocumentFingerprint: tabFingerprint
        )
        return GuideTargetEvidence(
            rectangle: rectangle,
            fingerprint: fingerprint,
            observation: GuideObservationSnapshot(
                monotonicNanoseconds: 10,
                frontmostProcessIdentifier: foregroundProcessIdentifier ?? processIdentifier,
                frontmostBundleIdentifier: "com.example.app",
                focusedWindow: GuideWindowFingerprint(
                    processIdentifier: processIdentifier,
                    bundleIdentifier: "com.example.app",
                    windowIdentifier: focusedWindowIdentifier ?? windowIdentifier,
                    titleFingerprint: "window-title"
                ),
                coordinateMetadata: GuideCoordinateMetadata(topology: topology, displayID: 1, scale: 2)
            )
        )
    }

    @MainActor
    private final class Locator: GuideTargetLocating {
        let focusedWindow: CGRect?
        let windowList: CGRect?
        private(set) var focusedWindowLookups = 0
        private(set) var windowListLookups = 0
        private(set) var accessibilityLookups = 0
        private(set) var modelLookups = 0

        init(focusedWindow: CGRect?, windowList: CGRect?) {
            self.focusedWindow = focusedWindow
            self.windowList = windowList
        }

        func locateInAccessibilityTree(descriptor: String, inApp bundleIdentifier: String?) -> CGRect? {
            accessibilityLookups += 1
            return nil
        }

        func locateWindow(ofApp bundleIdentifier: String) -> CGRect? {
            windowListLookups += 1
            return windowList
        }

        func locateFocusedWindow(ofApp bundleIdentifier: String) -> CGRect? {
            focusedWindowLookups += 1
            return focusedWindow
        }

        func locateByAskingTheModel(stepTitle: String, stepBody: String) async -> CGRect? {
            modelLookups += 1
            return nil
        }
    }

    @MainActor
    private final class AmbiguousEvidenceLocator: GuideTargetEvidenceLocating {
        func locateInAccessibilityTree(descriptor: String, inApp bundleIdentifier: String?) -> CGRect? { nil }
        func locateWindow(ofApp bundleIdentifier: String) -> CGRect? { nil }
        func locateFocusedWindow(ofApp bundleIdentifier: String) -> CGRect? { nil }
        func locateByAskingTheModel(stepTitle: String, stepBody: String) async -> CGRect? { nil }

        func locateInAccessibilityTreeEvidence(
            descriptor: String,
            inApp bundleIdentifier: String?
        ) -> GuideTargetLookup {
            .ambiguous(.duplicateCandidates)
        }
    }

    @MainActor
    private final class EvidenceLocator: GuideTargetEvidenceLocating {
        let lookup: GuideTargetLookup

        init(lookup: GuideTargetLookup) {
            self.lookup = lookup
        }

        func locateInAccessibilityTree(descriptor: String, inApp bundleIdentifier: String?) -> CGRect? { nil }
        func locateWindow(ofApp bundleIdentifier: String) -> CGRect? { nil }
        func locateFocusedWindow(ofApp bundleIdentifier: String) -> CGRect? { nil }
        func locateByAskingTheModel(stepTitle: String, stepBody: String) async -> CGRect? { nil }

        func locateInAccessibilityTreeEvidence(
            descriptor: String,
            inApp bundleIdentifier: String?
        ) -> GuideTargetLookup {
            lookup
        }
    }
}
