import Foundation
import CoreGraphics

/// The smallest identity that can safely survive a pointing refresh.
///
/// A rectangle is deliberately absent. Two controls, tabs, or processes can
/// occupy the same rectangle while being different things. Optional fields
/// are retained as optional so a missing accessibility attribute is explicit
/// evidence of uncertainty rather than an invented stable identifier.
nonisolated struct GuideAccessibilityAncestor: Equatable, Sendable {
    let role: String?
    let identifier: String?
    let labelFingerprint: String?
}

nonisolated enum GuideSemanticEvidenceAvailability: String, Equatable, Sendable {
    case complete
    case partial
    case unavailable
}

nonisolated struct GuideTargetFingerprint: Equatable, Sendable {
    let processIdentifier: Int32?
    let bundleIdentifier: String?
    let windowIdentifier: String?
    let windowTitleFingerprint: String?
    let role: String?
    let identifier: String?
    let labelFingerprint: String?
    let ancestry: [GuideAccessibilityAncestor]
    let tabOrDocumentFingerprint: String?

    init(
        processIdentifier: Int32? = nil,
        bundleIdentifier: String? = nil,
        windowIdentifier: String? = nil,
        windowTitleFingerprint: String? = nil,
        role: String? = nil,
        identifier: String? = nil,
        labelFingerprint: String? = nil,
        ancestry: [GuideAccessibilityAncestor] = [],
        tabOrDocumentFingerprint: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.windowIdentifier = windowIdentifier
        self.windowTitleFingerprint = windowTitleFingerprint
        self.role = role
        self.identifier = identifier
        self.labelFingerprint = labelFingerprint
        self.ancestry = ancestry
        self.tabOrDocumentFingerprint = tabOrDocumentFingerprint
    }

    var availability: GuideSemanticEvidenceAvailability {
        guard processIdentifier != nil,
              bundleIdentifier != nil,
              windowIdentifier != nil,
              role != nil
        else {
            return hasAnyEvidence ? .partial : .unavailable
        }
        // AX windows are targets in their own right. They often omit a control
        // identifier, but their bounded window identity is still semantic
        // evidence. Other controls need their own identifier or ancestry.
        let hasControlIdentity = identifier != nil || !ancestry.isEmpty
            || (role == "AXWindow" && windowIdentifier != nil)
        return hasControlIdentity ? .complete : .partial
    }

    private var hasAnyEvidence: Bool {
        processIdentifier != nil || bundleIdentifier != nil || windowIdentifier != nil
            || windowTitleFingerprint != nil || role != nil || identifier != nil
            || labelFingerprint != nil || !ancestry.isEmpty || tabOrDocumentFingerprint != nil
    }
}

nonisolated struct GuideWindowFingerprint: Equatable, Sendable {
    let processIdentifier: Int32?
    let bundleIdentifier: String?
    let windowIdentifier: String?
    let titleFingerprint: String?

    init(
        processIdentifier: Int32? = nil,
        bundleIdentifier: String? = nil,
        windowIdentifier: String? = nil,
        titleFingerprint: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.windowIdentifier = windowIdentifier
        self.titleFingerprint = titleFingerprint
    }
}

/// One display in the coordinate topology used by an observation or capture.
/// `frame` and `visibleFrame` are AppKit global points. Pixel dimensions and
/// scale stay alongside them so a capture point is never mistaken for a point.
nonisolated struct GuideDisplayReference: Equatable, Sendable {
    let displayID: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let pixelSize: CGSize
    let scale: CGFloat
}

nonisolated struct GuideDisplayTopology: Equatable, Sendable {
    let displays: [GuideDisplayReference]
    /// The actual top edge used by AX global top-left coordinates. On macOS
    /// this is the primary display's AppKit frame maxY, supplied by the live
    /// topology reader rather than guessed from the target rectangle.
    let accessibilityTopLeftReferenceY: CGFloat
    /// The top of the primary display's usable frame, retained so menu-bar
    /// exclusion stays part of the same coordinate reference.
    let menuBarReferenceY: CGFloat

    init(
        displays: [GuideDisplayReference],
        accessibilityTopLeftReferenceY: CGFloat,
        menuBarReferenceY: CGFloat
    ) {
        self.displays = displays
        self.accessibilityTopLeftReferenceY = accessibilityTopLeftReferenceY
        self.menuBarReferenceY = menuBarReferenceY
    }

    var isFiniteAndUsable: Bool {
        guard !displays.isEmpty,
              accessibilityTopLeftReferenceY.isFinite,
              menuBarReferenceY.isFinite else { return false }
        var seen: Set<UInt32> = []
        for display in displays {
            guard seen.insert(display.displayID).inserted,
                  GuidePointingFreshness.isFiniteAndUsable(display.frame),
                  GuidePointingFreshness.isFiniteAndUsable(display.visibleFrame),
                  display.frame.contains(display.visibleFrame),
                  GuidePointingFreshness.isFiniteAndUsable(display.pixelSize),
                  display.scale.isFinite, display.scale > 0 else { return false }
        }
        return true
    }

    func display(withID displayID: UInt32) -> GuideDisplayReference? {
        displays.first { $0.displayID == displayID }
    }
}

/// Coordinate metadata for one observed target. The crop fields are nil for
/// accessibility points and populated for a screenshot/model point.
nonisolated struct GuideCoordinateMetadata: Equatable, Sendable {
    let topology: GuideDisplayTopology
    let displayID: UInt32?
    let captureCropOriginInDisplayPixels: CGPoint?
    let captureCropSizeInDisplayPixels: CGSize?
    let captureImageSizeInPixels: CGSize?
    let scale: CGFloat?

    init(
        topology: GuideDisplayTopology,
        displayID: UInt32?,
        captureCropOriginInDisplayPixels: CGPoint? = nil,
        captureCropSizeInDisplayPixels: CGSize? = nil,
        captureImageSizeInPixels: CGSize? = nil,
        scale: CGFloat? = nil
    ) {
        self.topology = topology
        self.displayID = displayID
        self.captureCropOriginInDisplayPixels = captureCropOriginInDisplayPixels
        self.captureCropSizeInDisplayPixels = captureCropSizeInDisplayPixels
        self.captureImageSizeInPixels = captureImageSizeInPixels
        self.scale = scale
    }

    var isFiniteAndUsable: Bool {
        guard topology.isFiniteAndUsable else { return false }
        if let displayID, topology.display(withID: displayID) == nil { return false }
        if let crop = captureCropOriginInDisplayPixels,
           !GuidePointingFreshness.isFiniteAndUsable(crop) { return false }
        if let cropSize = captureCropSizeInDisplayPixels,
           !GuidePointingFreshness.isFiniteAndUsable(cropSize) { return false }
        if let imageSize = captureImageSizeInPixels,
           !GuidePointingFreshness.isFiniteAndUsable(imageSize) { return false }
        if let scale, !scale.isFinite || scale <= 0 { return false }
        return true
    }
}

nonisolated struct GuideObservationSnapshot: Equatable, Sendable {
    let monotonicNanoseconds: UInt64
    let frontmostProcessIdentifier: Int32?
    let frontmostBundleIdentifier: String?
    let focusedWindow: GuideWindowFingerprint?
    let coordinateMetadata: GuideCoordinateMetadata?

    init(
        monotonicNanoseconds: UInt64,
        frontmostProcessIdentifier: Int32?,
        frontmostBundleIdentifier: String?,
        focusedWindow: GuideWindowFingerprint?,
        coordinateMetadata: GuideCoordinateMetadata?
    ) {
        self.monotonicNanoseconds = monotonicNanoseconds
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.focusedWindow = focusedWindow
        self.coordinateMetadata = coordinateMetadata
    }
}

nonisolated struct GuideTargetEvidence: Equatable, Sendable {
    let rectangle: CGRect
    let fingerprint: GuideTargetFingerprint
    let observation: GuideObservationSnapshot?

    static func geometryOnly(_ rectangle: CGRect) -> GuideTargetEvidence {
        GuideTargetEvidence(
            rectangle: rectangle,
            fingerprint: GuideTargetFingerprint(),
            observation: nil
        )
    }
}

nonisolated enum GuideTargetLookup: Equatable, Sendable {
    case found(GuideTargetEvidence)
    case ambiguous(GuidePointingAmbiguityReason)
    case unavailable(GuidePointingUnavailableReason)
}

nonisolated enum GuidePointingFreshnessReason: String, Equatable, Sendable {
    case processChanged
    case bundleChanged
    case windowChanged
    case controlRoleChanged
    case controlIdentityChanged
    case ancestryChanged
    case tabOrDocumentChanged
    case displayTopologyChanged
    case observationExpired
}

nonisolated enum GuidePointingAmbiguityReason: String, Equatable, Sendable {
    case duplicateCandidates
    case missingSemanticIdentity
}

nonisolated enum GuidePointingUnavailableReason: String, Equatable, Sendable {
    case geometryOnly
    case missingSemanticIdentity
    case missingForegroundObservation
    case missingFocusedWindowObservation
    case missingCoordinateMetadata
    case invalidCoordinateMetadata
    case noCurrentDisplay
    case cancelled
}

nonisolated enum GuidePointingFreshnessVerdict: Equatable, Sendable {
    case fresh
    case movedSameTarget
    case stale(GuidePointingFreshnessReason)
    case ambiguous(GuidePointingAmbiguityReason)
    case unavailable(GuidePointingUnavailableReason)
}

/// A point from an old screenshot must not become a confident arrow on a
/// different app or layout. This checks geometry, not whether a page scrolled.
nonisolated enum GuidePointingFreshness {
    static func isFiniteAndUsable(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    static func isFiniteAndUsable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    static func isFiniteAndUsable(_ rectangle: CGRect) -> Bool {
        rectangle.origin.x.isFinite && rectangle.origin.y.isFinite
            && rectangle.width.isFinite && rectangle.height.isFinite
            && rectangle.width > 0 && rectangle.height > 0
    }

    /// A short, one-way fingerprint for ephemeral window/tab text. The raw
    /// title never leaves the AX read or enters logs and is not used as the
    /// sole identity field.
    static func privacyFingerprint(of text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    /// Convert AX's global top-left rectangle into AppKit's global bottom-left
    /// points using the captured topology reference. This is the only AX to
    /// AppKit flip in the pointing lane.
    static func appKitRectangle(
        fromAccessibilityTopLeft rectangle: CGRect,
        topology: GuideDisplayTopology
    ) -> CGRect? {
        guard topology.isFiniteAndUsable, isFiniteAndUsable(rectangle) else { return nil }
        return CGRect(
            x: rectangle.minX,
            y: topology.accessibilityTopLeftReferenceY - rectangle.maxY,
            width: rectangle.width,
            height: rectangle.height
        )
    }

    /// Convert a point in the image sent to the model into AppKit global
    /// points. The crop origin is in display pixels and is applied before the
    /// per-display scale and Y flip. A missing display or topology change is a
    /// hard refusal, never a best-effort main-screen fallback.
    static func appKitPoint(
        fromCapturePixels point: CGPoint,
        metadata: GuideCoordinateMetadata,
        currentTopology: GuideDisplayTopology
    ) -> CGPoint? {
        guard metadata.isFiniteAndUsable,
              currentTopology.isFiniteAndUsable,
              metadata.topology == currentTopology,
              let displayID = metadata.displayID,
              let capturedDisplay = metadata.topology.display(withID: displayID),
              let currentDisplay = currentTopology.display(withID: displayID),
              isFiniteAndUsable(point) else { return nil }

        let imageSize = metadata.captureImageSizeInPixels ?? capturedDisplay.pixelSize
        guard isFiniteAndUsable(imageSize),
              point.x >= 0, point.y >= 0,
              point.x < imageSize.width, point.y < imageSize.height else { return nil }

        let cropOrigin = metadata.captureCropOriginInDisplayPixels ?? .zero
        let cropSize = metadata.captureCropSizeInDisplayPixels ?? capturedDisplay.pixelSize
        let pixelsPerPoint = metadata.scale ?? capturedDisplay.scale
        guard pixelsPerPoint.isFinite, pixelsPerPoint > 0 else { return nil }
        guard isFiniteAndUsable(cropSize) else { return nil }
        let pointInDisplayPixels = CGPoint(
            x: cropOrigin.x + point.x * cropSize.width / imageSize.width,
            y: cropOrigin.y + point.y * cropSize.height / imageSize.height
        )
        let xInDisplayPoints = pointInDisplayPixels.x / pixelsPerPoint
        let yInDisplayPoints = pointInDisplayPixels.y / pixelsPerPoint
        guard xInDisplayPoints >= 0,
              yInDisplayPoints >= 0,
              xInDisplayPoints <= currentDisplay.frame.width,
              yInDisplayPoints <= currentDisplay.frame.height else { return nil }
        return CGPoint(
            x: currentDisplay.frame.minX + xInDisplayPoints,
            y: currentDisplay.frame.maxY - yInDisplayPoints
        )
    }

    static func freshness(
        from previous: GuideTargetEvidence,
        to current: GuideTargetEvidence,
        maximumAgeNanoseconds: UInt64? = nil
    ) -> GuidePointingFreshnessVerdict {
        guard previous.fingerprint.availability == .complete,
              current.fingerprint.availability == .complete
        else { return .unavailable(.missingSemanticIdentity) }

        let previousObservationVerdict = validateCurrentObservation(previous)
        guard previousObservationVerdict == .fresh else { return previousObservationVerdict }
        let currentObservationVerdict = validateCurrentObservation(current)
        guard currentObservationVerdict == .fresh else { return currentObservationVerdict }

        guard let previousObservation = previous.observation,
              let currentObservation = current.observation,
              let previousCoordinates = previousObservation.coordinateMetadata,
              let currentCoordinates = currentObservation.coordinateMetadata
        else { return .unavailable(.missingCoordinateMetadata) }
        guard previousCoordinates.isFiniteAndUsable,
              currentCoordinates.isFiniteAndUsable else {
            return .unavailable(.invalidCoordinateMetadata)
        }

        if let maximumAgeNanoseconds,
           let observation = previous.observation,
           currentObservation.monotonicNanoseconds >= observation.monotonicNanoseconds,
           currentObservation.monotonicNanoseconds - observation.monotonicNanoseconds > maximumAgeNanoseconds {
            return .stale(.observationExpired)
        }

        let old = previous.fingerprint
        let new = current.fingerprint
        if old.processIdentifier != new.processIdentifier { return .stale(.processChanged) }
        if old.bundleIdentifier != new.bundleIdentifier { return .stale(.bundleChanged) }
        if old.windowIdentifier != new.windowIdentifier
            || old.windowTitleFingerprint != new.windowTitleFingerprint {
            return .stale(.windowChanged)
        }
        if old.role != new.role { return .stale(.controlRoleChanged) }
        if old.identifier != new.identifier { return .stale(.controlIdentityChanged) }
        if old.ancestry != new.ancestry { return .stale(.ancestryChanged) }
        if old.tabOrDocumentFingerprint != new.tabOrDocumentFingerprint {
            return .stale(.tabOrDocumentChanged)
        }

        if previousCoordinates != currentCoordinates {
            return .stale(.displayTopologyChanged)
        }
        return previous.rectangle == current.rectangle ? .fresh : .movedSameTarget
    }

    /// Validate the foreground process and focused window captured alongside a
    /// target. This is intentionally checked on the initial result as well as
    /// on a later comparison, so background or changed-window evidence never
    /// becomes a highlight merely because its rectangle is visible.
    static func validateCurrentObservation(_ evidence: GuideTargetEvidence) -> GuidePointingFreshnessVerdict {
        guard evidence.fingerprint.availability == .complete else {
            return .unavailable(.missingSemanticIdentity)
        }
        guard let observation = evidence.observation else {
            return .unavailable(.missingForegroundObservation)
        }
        guard let foregroundPID = observation.frontmostProcessIdentifier else {
            return .unavailable(.missingForegroundObservation)
        }
        guard let foregroundBundle = observation.frontmostBundleIdentifier else {
            return .unavailable(.missingForegroundObservation)
        }
        if evidence.fingerprint.processIdentifier != foregroundPID {
            return .stale(.processChanged)
        }
        if evidence.fingerprint.bundleIdentifier != foregroundBundle {
            return .stale(.bundleChanged)
        }
        guard let focusedWindow = observation.focusedWindow else {
            return .unavailable(.missingFocusedWindowObservation)
        }
        if focusedWindow.processIdentifier != evidence.fingerprint.processIdentifier
            || focusedWindow.bundleIdentifier != evidence.fingerprint.bundleIdentifier {
            return .stale(.processChanged)
        }
        if focusedWindow.windowIdentifier != evidence.fingerprint.windowIdentifier {
            return .stale(.windowChanged)
        }
        return .fresh
    }

    static func explicitScreenNumberIsValid(_ screenNumber: Int?, captureCount: Int) -> Bool {
        guard captureCount > 0 else { return false }
        guard let screenNumber else { return true }
        return screenNumber >= 1 && screenNumber <= captureCount
    }

    static func pointIsInsideScreenshot(_ point: CGPoint, width: Int, height: Int) -> Bool {
        width > 0 && height > 0
            && point.x.isFinite && point.y.isFinite
            && point.x >= 0 && point.y >= 0
            && point.x < CGFloat(width) && point.y < CGFloat(height)
    }

    static func rectangleIfStillUsable(
        _ rectangle: CGRect,
        capturedApplication: String?,
        currentApplication: String?,
        capturedWindow: CGRect?,
        currentWindow: CGRect?,
        capturedDisplays: [CGRect],
        currentDisplays: [CGRect]
    ) -> CGRect? {
        guard capturedApplication == currentApplication,
              capturedDisplays == currentDisplays,
              rectangle.origin.x.isFinite, rectangle.origin.y.isFinite,
              rectangle.width.isFinite, rectangle.height.isFinite,
              rectangle.width > 0, rectangle.height > 0 else { return nil }

        switch (capturedWindow, currentWindow) {
        case (nil, nil):
            return rectangle
        case (let capturedWindow?, let currentWindow?):
            let tolerance: CGFloat = 1
            guard abs(currentWindow.width - capturedWindow.width) <= tolerance,
                  abs(currentWindow.height - capturedWindow.height) <= tolerance else { return nil }
            let horizontalMovement = currentWindow.minX - capturedWindow.minX
            let verticalMovement = currentWindow.minY - capturedWindow.minY
            guard abs(horizontalMovement) > tolerance || abs(verticalMovement) > tolerance else {
                return rectangle
            }
            // The full-screen fallback can point outside the focused window.
            // Such a point does not move with that window.
            guard capturedWindow.contains(CGPoint(x: rectangle.midX, y: rectangle.midY)) else {
                return rectangle
            }
            return rectangle.offsetBy(dx: horizontalMovement, dy: verticalMovement)
        default:
            // Losing the focused window or gaining a different one invalidates
            // the old crop. Refuse instead of reusing the old coordinates.
            return nil
        }
    }
}
