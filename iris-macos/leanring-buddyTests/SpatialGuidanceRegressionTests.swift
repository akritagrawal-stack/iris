import AppKit
import Foundation
import Testing
#if canImport(Iris)
@testable import Iris
#else
@testable import IrisUsability
#endif

@MainActor
struct SpatialGuidanceRegressionTests {

    @Test("same rectangle with different semantic identity is stale")
    func semanticIdentityWinsOverRectangleEquality() {
        let topology = GuideDisplayTopology(
            displays: [GuideDisplayReference(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 22, width: 1440, height: 878),
                pixelSize: CGSize(width: 2880, height: 1800),
                scale: 2
            )],
            accessibilityTopLeftReferenceY: 900,
            menuBarReferenceY: 878
        )
        let first = Self.evidence(
            processIdentifier: 101,
            windowIdentifier: "window-a",
            controlIdentifier: "button-a",
            tabFingerprint: "tab-a",
            rectangle: CGRect(x: 100, y: 200, width: 80, height: 24),
            topology: topology
        )
        let sameTargetMoved = Self.evidence(
            processIdentifier: 101,
            windowIdentifier: "window-a",
            controlIdentifier: "button-a",
            tabFingerprint: "tab-a",
            rectangle: CGRect(x: 160, y: 240, width: 80, height: 24),
            topology: topology
        )
        let differentProcess = Self.evidence(
            processIdentifier: 202,
            windowIdentifier: "window-a",
            controlIdentifier: "button-a",
            tabFingerprint: "tab-a",
            rectangle: first.rectangle,
            topology: topology
        )
        let differentTab = Self.evidence(
            processIdentifier: 101,
            windowIdentifier: "window-a",
            controlIdentifier: "button-a",
            tabFingerprint: "tab-b",
            rectangle: first.rectangle,
            topology: topology
        )
        let differentControl = Self.evidence(
            processIdentifier: 101,
            windowIdentifier: "window-a",
            controlIdentifier: "button-b",
            tabFingerprint: "tab-a",
            rectangle: first.rectangle,
            topology: topology
        )
        let differentWindow = Self.evidence(
            processIdentifier: 101,
            windowIdentifier: "window-b",
            controlIdentifier: "button-a",
            tabFingerprint: "tab-a",
            rectangle: first.rectangle,
            topology: topology
        )

        #expect(GuidePointingFreshness.freshness(from: first, to: sameTargetMoved) == .movedSameTarget)
        #expect(GuidePointingFreshness.freshness(from: first, to: differentProcess) == .stale(.processChanged))
        #expect(GuidePointingFreshness.freshness(from: first, to: differentTab) == .stale(.tabOrDocumentChanged))
        #expect(GuidePointingFreshness.freshness(from: first, to: differentControl) == .stale(.controlIdentityChanged))
        #expect(GuidePointingFreshness.freshness(from: first, to: differentWindow) == .stale(.windowChanged))
        #expect(
            GuidePointingFreshness.freshness(
                from: .geometryOnly(first.rectangle), to: .geometryOnly(first.rectangle)
            ) == .unavailable(.missingSemanticIdentity)
        )
    }

    @Test("capture coordinates retain crop, mixed scale, and negative monitor origin")
    func captureCoordinatesUseTheMatchingDisplayTopology() throws {
        let topology = GuideDisplayTopology(
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
        let metadata = GuideCoordinateMetadata(
            topology: topology,
            displayID: 2,
            captureCropOriginInDisplayPixels: CGPoint(x: 200, y: 100),
            captureCropSizeInDisplayPixels: CGSize(width: 600, height: 400),
            captureImageSizeInPixels: CGSize(width: 300, height: 200),
            scale: 1
        )

        let point = try #require(
            GuidePointingFreshness.appKitPoint(
                fromCapturePixels: CGPoint(x: 50, y: 25),
                metadata: metadata,
                currentTopology: topology
            )
        )
        #expect(point == CGPoint(x: -980, y: 750))

        var changedTopology = topology
        changedTopology = GuideDisplayTopology(
            displays: topology.displays.dropLast(),
            accessibilityTopLeftReferenceY: topology.accessibilityTopLeftReferenceY,
            menuBarReferenceY: topology.menuBarReferenceY
        )
        #expect(
            GuidePointingFreshness.appKitPoint(
                fromCapturePixels: CGPoint(x: 50, y: 25),
                metadata: metadata,
                currentTopology: changedTopology
            ) == nil
        )
    }

    @Test("duplicate evidence refuses instead of choosing a control")
    func duplicateCandidatesRemainAmbiguous() async throws {
        let locator = AmbiguousTargetLocator()
        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(GuidePointTarget(
                descriptor: "the Save button",
                inApp: nil,
                isWindow: false,
                provenance: .authoredAndFound
            )),
            stepTitle: "Save",
            stepBody: "",
            mayAskTheModel: false,
            using: locator
        )
        guard case .doNotPoint(.pointingUnavailable(let message)) = outcome.decision else {
            Issue.record("duplicate candidate resolution did not refuse")
            return
        }
        #expect(message.contains("more than one"))
        #expect(outcome.screenLocation == nil)
        #expect(outcome.freshness == .ambiguous(.duplicateCandidates))
    }

    @Test("eye memo does not collapse distinct semantic targets at one point")
    func eyeMemoUsesSemanticIdentityWhenItIsAvailable() {
        let first = GuideTargetFingerprint(
            processIdentifier: 101,
            bundleIdentifier: "com.example.app",
            windowIdentifier: "window-a",
            role: "AXButton",
            identifier: "save-a",
            label: "Save"
        )
        let second = GuideTargetFingerprint(
            processIdentifier: 202,
            bundleIdentifier: "com.example.app",
            windowIdentifier: "window-a",
            role: "AXButton",
            identifier: "save-a",
            label: "Save"
        )
        let one = GuideEyeFlight(
            stepIdentity: "step",
            screenLocation: CGPoint(x: 200, y: 300),
            label: "Save",
            targetFingerprint: first
        )
        let other = GuideEyeFlight(
            stepIdentity: "step",
            screenLocation: one.screenLocation,
            label: one.label,
            targetFingerprint: second
        )
        #expect(!GuideEyeFlightMemo.isTheSameAnswer(one, other))
    }

    @Test("a chat point uses the model label as a bounded one-line cue")
    func modelLabelsAreSanitizedBeforeTheyReachTheOverlay() {
        #expect(
            CompanionManager.sanitizedPointingBubbleText(
                from: "  Save\n settings  "
            ) == "Save settings"
        )
        #expect(
            CompanionManager.sanitizedPointingBubbleText(
                from: String(repeating: "x", count: 41)
            ) == String(repeating: "x", count: 40)
        )
        #expect(
            CompanionManager.sanitizedPointingBubbleText(from: "save\u{0007}now") == nil
        )
        #expect(CompanionManager.sanitizedPointingBubbleText(from: "   ") == nil)
        #expect(CompanionManager.sanitizedPointingBubbleText(from: nil) == nil)
    }

    @Test("a guide window target prefers the focused non-minimized window")
    func focusedWindowWinsOverTheAppWindowList() async throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let focusedWindow = CGRect(
            x: visible.midX - 120,
            y: visible.midY - 70,
            width: 240,
            height: 140
        )
        let otherWindow = CGRect(
            x: visible.minX + 40,
            y: visible.minY + 40,
            width: 240,
            height: 140
        )
        let locator = WindowTargetLocator(
            focusedWindow: focusedWindow,
            windowListResult: otherWindow
        )

        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(
                GuidePointTarget(
                    descriptor: "the Terminal window",
                    inApp: "com.apple.Terminal",
                    isWindow: true,
                    provenance: .shellWindow
                )
            ),
            stepTitle: "Open Terminal",
            stepBody: "",
            mayAskTheModel: false,
            using: locator
        )

        #expect(locator.focusedWindowLookups == 1)
        #expect(locator.windowListLookups == 0)
        #expect(locator.accessibilityLookups == 0)
        #expect(
            outcome.screenLocation
                == GuideStepPointingCoordinator.aimPoint(in: focusedWindow, isWindow: true)
        )
        #expect(outcome.displayFrame == screen.frame)
    }

    @Test("a missing focused-window attribute gets one bounded compatibility fallback")
    func windowListFallbackRunsOnlyAfterFocusedLookupMisses() async throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let fallbackWindow = CGRect(
            x: visible.midX - 120,
            y: visible.midY - 70,
            width: 240,
            height: 140
        )
        let locator = WindowTargetLocator(
            focusedWindow: nil,
            windowListResult: fallbackWindow
        )

        let outcome = await GuideStepPointingCoordinator.resolve(
            decision: .pointAt(
                GuidePointTarget(
                    descriptor: "the Terminal window",
                    inApp: "com.apple.Terminal",
                    isWindow: true,
                    provenance: .shellWindow
                )
            ),
            stepTitle: "Open Terminal",
            stepBody: "",
            mayAskTheModel: false,
            using: locator
        )

        #expect(locator.focusedWindowLookups == 1)
        #expect(locator.windowListLookups == 1)
        #expect(outcome.screenLocation != nil)
    }

    @MainActor
    final class WindowTargetLocator: GuideTargetLocating {
        let focusedWindow: CGRect?
        let windowListResult: CGRect?
        private(set) var focusedWindowLookups = 0
        private(set) var windowListLookups = 0
        private(set) var accessibilityLookups = 0

        init(focusedWindow: CGRect?, windowListResult: CGRect?) {
            self.focusedWindow = focusedWindow
            self.windowListResult = windowListResult
        }

        func locateInAccessibilityTree(descriptor: String, inApp bundleIdentifier: String?) -> CGRect? {
            accessibilityLookups += 1
            return nil
        }

        func locateWindow(ofApp bundleIdentifier: String) -> CGRect? {
            windowListLookups += 1
            return windowListResult
        }

        func locateFocusedWindow(ofApp bundleIdentifier: String) -> CGRect? {
            focusedWindowLookups += 1
            return focusedWindow
        }

        func locateByAskingTheModel(stepTitle: String, stepBody: String) async -> CGRect? {
            nil
        }
    }

    @MainActor
    final class AmbiguousTargetLocator: GuideTargetEvidenceLocating {
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

    private static func evidence(
        processIdentifier: Int32,
        windowIdentifier: String,
        controlIdentifier: String,
        tabFingerprint: String,
        rectangle: CGRect,
        topology: GuideDisplayTopology
    ) -> GuideTargetEvidence {
        let fingerprint = GuideTargetFingerprint(
            processIdentifier: processIdentifier,
            bundleIdentifier: "com.example.app",
            windowIdentifier: windowIdentifier,
            windowTitleFingerprint: "window-title",
            role: "AXButton",
            identifier: controlIdentifier,
            label: "Save",
            ancestry: [GuideAccessibilityAncestor(role: "AXGroup", identifier: "toolbar", label: "Toolbar")],
            tabOrDocumentFingerprint: tabFingerprint
        )
        return GuideTargetEvidence(
            rectangle: rectangle,
            fingerprint: fingerprint,
            observation: GuideObservationSnapshot(
                monotonicNanoseconds: 10,
                frontmostProcessIdentifier: processIdentifier,
                frontmostBundleIdentifier: "com.example.app",
                focusedWindow: GuideWindowFingerprint(
                    processIdentifier: processIdentifier,
                    bundleIdentifier: "com.example.app",
                    windowIdentifier: windowIdentifier,
                    titleFingerprint: "window-title"
                ),
                coordinateMetadata: GuideCoordinateMetadata(
                    topology: topology,
                    displayID: 1,
                    scale: 2
                )
            )
        )
    }
}
