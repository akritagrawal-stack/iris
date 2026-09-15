import Foundation
import Testing
@testable import Iris

/// Regression coverage for the actual spatial model seam. These are deliberately
/// response-contract tests, not synthetic click tests: the important failure was
/// that the production app never invoked the structured Computer Use path and
/// silently relied on conversational `[POINT]` text instead.
struct ElementLocationDetectorTests {
    @Test func toolVariantMatchesTheSelectedModel() {
        #expect(ElementLocationDetector.computerUseVariant(forModel: "claude-haiku-4-5").toolType == "computer_20250124")
        #expect(ElementLocationDetector.computerUseVariant(forModel: "claude-haiku-4-5").betaHeader == "computer-use-2025-01-24")
        #expect(ElementLocationDetector.computerUseVariant(forModel: "claude-sonnet-4-6").toolType == "computer_20251124")
        #expect(ElementLocationDetector.computerUseVariant(forModel: "claude-sonnet-4-6").betaHeader == "computer-use-2025-11-24")
    }

    @Test func onlyPointingActionsCanProduceATarget() {
        #expect(ElementLocationDetector.isPointingAction("left_click"))
        #expect(ElementLocationDetector.isPointingAction("mouse_move"))
        #expect(!ElementLocationDetector.isPointingAction("scroll"))
        #expect(!ElementLocationDetector.isPointingAction("left_click_drag"))
        #expect(!ElementLocationDetector.isPointingAction("screenshot"))
    }

    @Test func parsesAJsonComputerUseResponse() {
        let body: [String: Any] = [
            "content": [[
                "type": "tool_use",
                "name": "computer",
                "input": ["action": "left_click", "coordinate": [321, 654]]
            ]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: body)
        #expect(ElementLocationDetector.parseCoordinateFromResponse(data: data) == CGPoint(x: 321, y: 654))
    }

    @Test func parsesTheFundedSseComputerUseResponse() {
        let lines = [
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"computer\",\"input\":{}}}",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"action\\\":\\\"left_click\\\",\\\"coordinate\\\":[111,222]}\"}}",
            "data: {\"type\":\"content_block_stop\",\"index\":0}",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}",
            "data: [DONE]"
        ]
        let data = Data(lines.joined(separator: "\n").utf8)
        #expect(ElementLocationDetector.parseCoordinateFromResponse(data: data) == CGPoint(x: 111, y: 222))
    }

    @MainActor
    @Test func onlyExplicitUiRequestsSpendTheDedicatedSpatialCall() {
        #expect(CompanionManager.shouldUseDedicatedSpatialModel(for: "where is the install button?"))
        #expect(CompanionManager.shouldUseDedicatedSpatialModel(for: "what should i click in settings?"))
        #expect(!CompanionManager.shouldUseDedicatedSpatialModel(for: "what is 2 + 2?"))
        #expect(!CompanionManager.shouldUseDedicatedSpatialModel(for: "what is on my screen?"))
    }
}
