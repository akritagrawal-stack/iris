import Foundation
import Testing
@testable import IrisHarness

@Test
func clearLocalFixUsesTheSmallRoute() {
    let profile = HarnessIntakeProfile.classify(
        request: "make the Save button text larger",
        repositorySummary: "SaveButton.swift already owns the label style.",
        targetAppIsBound: true
    )

    #expect(profile.complexity == .small)
    #expect(profile.surface == HarnessIntakeProfile.localControlSurface)
    #expect(profile.reservedTopics.isEmpty)
    #expect(profile.targetIsBound)
    #expect(profile.plannerRequired)
    #expect(profile.plannerOutputTokenCap == 2_400)
}

@Test
func oneSurfaceFeatureUsesTheScopedRoute() {
    let profile = HarnessIntakeProfile.classify(
        request: "add a search filter to the notes list",
        repositorySummary: "The notes list already has one local view.",
        targetAppIsBound: true
    )

    #expect(profile.complexity == .scoped)
    #expect(profile.surface == HarnessIntakeProfile.localControlSurface)
    #expect(profile.reservedTopics.isEmpty)
    #expect(profile.plannerRequired)
}

@Test
func pasteIntoTheRightTabIsComplexAndReservesDestination() {
    let profile = HarnessIntakeProfile.classify(
        request: "paste into the right tab",
        repositorySummary: "The browser adapter exposes tab observations and insert-only actions.",
        targetAppIsBound: true
    )

    #expect(profile.complexity == .complex)
    #expect(profile.surface == HarnessIntakeProfile.crossSurfaceTransferSurface)
    #expect(profile.reservedTopics == [.destination])
    #expect(profile.plannerRequired)
}

@Test
func highRiskExternalActionUsesTheHighRiskRoute() {
    let profile = HarnessIntakeProfile.classify(
        request: "send this message to the customer",
        repositorySummary: "The existing composer can prepare a message.",
        targetAppIsBound: true
    )

    #expect(profile.complexity == .highRisk)
    #expect(profile.surface == HarnessIntakeProfile.crossSurfaceTransferSurface)
    #expect(profile.plannerRequired)
}

@Test
func unboundTargetBlocksTheProfileBeforeRouting() {
    let profile = HarnessIntakeProfile.classify(
        request: "make the Save button text larger",
        repositorySummary: "SaveButton.swift already owns the label style.",
        targetAppIsBound: false
    )

    #expect(profile.complexity == .blocked)
    #expect(profile.surface == HarnessIntakeProfile.localControlSurface)
    #expect(!profile.targetIsBound)
    #expect(!profile.plannerRequired)
    #expect(profile.plannerOutputTokenCap == 2_400)
}

@Test @MainActor
func plannerReceivesTheHostProfileAlongsideTheExactRequest() async throws {
    let request = "  make the Save button text larger  "
    let brief = try HarnessTaskBrief(
        userRequest: request,
        desiredOutcome: "Make the Save label easier to read",
        acceptanceCriteria: [
            .init(id: "larger-label", statement: "The Save label is visibly larger")
        ],
        milestones: [.init(id: "style", title: "Adjust the existing label style")]
    )
    let reply = String(decoding: try JSONEncoder().encode(brief), as: UTF8.self)
    var captured: [HarnessModelRequest] = []
    let session = try HarnessModelSession(
        implementationArm: .astraLow,
        settings: .init(maxCalls: 2, maxInputBytes: 80_000),
        maximumDurationNanoseconds: 1_000_000_000,
        now: { 100 }
    ) { input in
        captured.append(input)
        return HarnessModelReply(text: reply)
    }
    let workflow = HarnessFeatureWorkflow(modelSession: session, targetAppIsBound: true)

    _ = try await workflow.plan(
        request: request,
        repositorySummary: "SaveButton.swift already owns the label style."
    )

    let payload = try #require(
        try JSONSerialization.jsonObject(
            with: Data(captured[0].conversation[0].text.utf8)
        ) as? [String: Any]
    )
    let intakeProfile = try #require(payload["intakeProfile"] as? [String: Any])
    #expect(payload["userRequest"] as? String == request)
    #expect(intakeProfile["complexity"] as? String == "small")
    #expect(intakeProfile["surface"] as? String == "localControl")
    #expect(intakeProfile["reservedTopics"] as? [String] == [])
    #expect(intakeProfile["targetIsBound"] as? Bool == true)
    #expect(intakeProfile["plannerRequired"] as? Bool == true)
    #expect(intakeProfile["plannerOutputTokenCap"] as? Int == 2_400)
    #expect(intakeProfile["routePolicyVersion"] as? String == "iris.harness.intake.v1")
    #expect(captured.count == 1)
    #expect(session.ledger.snapshot.admittedCallCount == 1)
}
