//
//  ElementLocationDetector.swift
//  leanring-buddy
//
//  Uses Claude's Computer Use API to identify the screen location of UI elements
//  in screenshots. When a user asks about a visible element (e.g., "click the
//  blue button"), this detects the element's coordinates so the buddy can
//  animate to it and point at it.
//

import AppKit
import Foundation

/// Detects the screen location of UI elements in screenshots using Claude's Computer Use API.
/// The Computer Use tool definition activates Claude's specialized pixel-counting training,
/// which is significantly more accurate than regular vision API coordinate extraction.
///
/// **Aspect ratio matching**: Instead of always resizing to 1024x768 (4:3), we pick the
/// Anthropic-recommended resolution closest to the display's actual aspect ratio. Most
/// Macs are 16:10 → 1280x800. This avoids distorting the image Claude sees, which
/// significantly improves X-axis coordinate accuracy.
///
/// **Credentials**: this type does not hold one. It inherited a direct
/// `apiKey` from upstream Clicky, which was a second way to attach a
/// credential that the transport layer could not see or check. Grounding is
/// about to become a real feature, so the bypass is closed before anything
/// depends on it: the caller supplies a request already built and validated
/// by `AssistantTransport`, which is the single place credentials are
/// attached and the only thing that knows which route the user is on.
class ElementLocationDetector {
    /// Builds the credentialed, transport-validated request this detector
    /// sends. Supplied by the caller so grounding automatically follows the
    /// user's tier — funded or bring-your-own-key — instead of needing a key
    /// of its own.
    private let makeValidatedRequest: () async throws -> URLRequest
    private var model: String
    private let session: URLSession

    /// Called after a response settles so the dedicated spatial call appears
    /// in Iris's existing token ledger. The detector remains route-agnostic;
    /// the request's credential shape identifies whether the call is metered.
    var reportSpend: @Sendable (String, AssistantTokenUsage, AssistantSpendRoute) -> Void = { _, _, _ in }

    /// Anthropic-recommended resolutions for Computer Use, paired with their aspect ratios.
    /// We pick the one closest to the actual display aspect ratio to avoid distortion.
    /// Higher resolutions get downsampled by the API and degrade precision, so these
    /// are intentionally small.
    private static let supportedComputerUseResolutions: [(width: Int, height: Int, aspectRatio: Double)] = [
        (1024, 768,  1024.0 / 768.0),  // 4:3   = 1.333 (legacy displays)
        (1280, 800,  1280.0 / 800.0),  // 16:10  = 1.600 (MacBook Air, MacBook Pro, most Macs)
        (1366, 768,  1366.0 / 768.0)   // ~16:9  = 1.779 (external monitors, ultrawide fallback)
    ]

    init(
        makeValidatedRequest: @escaping () async throws -> URLRequest,
        model: String = "claude-sonnet-4-6"
    ) {
        self.makeValidatedRequest = makeValidatedRequest
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }

    /// The spatial model follows the same model picker as chat. Keep this
    /// mutable so changing the picker cannot silently leave the locator on a
    /// different model (and, for Haiku, a different computer-tool version).
    func setModel(_ model: String) {
        self.model = model
    }

    /// Computer Use tool versions are model-specific. Anthropic rejects the
    /// newer tool type when Haiku is selected, so this decision lives beside
    /// the request rather than in a test-only harness.
    static func computerUseVariant(forModel model: String) -> (toolType: String, betaHeader: String) {
        if model.lowercased().contains("haiku") {
            return (
                toolType: "computer_20250124",
                betaHeader: "computer-use-2025-01-24"
            )
        }
        return (
            toolType: "computer_20251124",
            betaHeader: "computer-use-2025-11-24"
        )
    }

    /// Only actions whose coordinate identifies a thing to point at count.
    /// Scroll and drag coordinates describe an operation, not the requested
    /// control, and accepting them is how a spatial model appears to point at
    /// random places.
    static func isPointingAction(_ action: String) -> Bool {
        switch action {
        case "left_click", "double_click", "triple_click", "right_click", "middle_click", "mouse_move":
            return true
        default:
            return false
        }
    }

    /// Detects the screen location of a UI element the user is asking about.
    ///
    /// - Parameters:
    ///   - screenshotData: JPEG or PNG screenshot data from ScreenCaptureKit
    ///   - userQuestion: The user's voice transcript (e.g., "How do I add a project?")
    ///   - displayWidthInPoints: The captured display's width in screen points
    ///   - displayHeightInPoints: The captured display's height in screen points
    ///
    /// - Returns: A `CGPoint` in display-local macOS coordinates (bottom-left origin) if an
    ///   element was identified, or `nil` if no element was found or detection failed.
    func detectElementLocation(
        screenshotData: Data,
        userQuestion: String,
        displayWidthInPoints: Int,
        displayHeightInPoints: Int
    ) async -> CGPoint? {
        // Pick the Computer Use resolution that best matches this display's aspect ratio.
        // This avoids stretching the screenshot (e.g., squishing a 16:10 Mac display
        // into 4:3), which would distort the image Claude sees and degrade X-axis accuracy.
        let computerUseResolution = bestComputerUseResolution(
            forDisplayWidth: displayWidthInPoints,
            displayHeight: displayHeightInPoints
        )

        print("🎯 ElementLocationDetector: display is \(displayWidthInPoints)x\(displayHeightInPoints) " +
              "(ratio \(String(format: "%.3f", Double(displayWidthInPoints) / Double(displayHeightInPoints)))), " +
              "using Computer Use resolution \(computerUseResolution.width)x\(computerUseResolution.height)")

        // Resize the screenshot to the chosen Computer Use resolution
        guard let resizedScreenshotData = resizeScreenshotForComputerUse(
            originalImageData: screenshotData,
            targetWidth: computerUseResolution.width,
            targetHeight: computerUseResolution.height
        ) else {
            print("⚠️ ElementLocationDetector: failed to resize screenshot")
            return nil
        }

        // Make the Computer Use API call with the matching resolution declared
        guard let computerUseCoordinate = await callComputerUseAPI(
            resizedScreenshotData: resizedScreenshotData,
            userQuestion: userQuestion,
            declaredDisplayWidth: computerUseResolution.width,
            declaredDisplayHeight: computerUseResolution.height
        ) else {
            return nil
        }

        // Clamp coordinates to the valid range — Claude occasionally returns
        // values slightly outside the declared display dimensions, which would
        // map to off-screen positions after scaling.
        let clampedX = max(0, min(computerUseCoordinate.x, CGFloat(computerUseResolution.width)))
        let clampedY = max(0, min(computerUseCoordinate.y, CGFloat(computerUseResolution.height)))

        // Scale coordinates from the Computer Use resolution back to actual display point dimensions
        let scaledX = (clampedX / CGFloat(computerUseResolution.width)) * CGFloat(displayWidthInPoints)
        let scaledYTopLeftOrigin = (clampedY / CGFloat(computerUseResolution.height)) * CGFloat(displayHeightInPoints)

        // Convert from top-left origin (Computer Use / CoreGraphics) to bottom-left origin (AppKit)
        let scaledYBottomLeftOrigin = CGFloat(displayHeightInPoints) - scaledYTopLeftOrigin

        print("🎯 ElementLocationDetector: mapped (\(Int(clampedX)), \(Int(clampedY))) in " +
              "\(computerUseResolution.width)x\(computerUseResolution.height) → " +
              "(\(Int(scaledX)), \(Int(scaledYBottomLeftOrigin))) in " +
              "\(displayWidthInPoints)x\(displayHeightInPoints) display-local AppKit coords")

        return CGPoint(x: scaledX, y: scaledYBottomLeftOrigin)
    }

    // MARK: - Private Helpers

    /// Picks the Anthropic-recommended Computer Use resolution whose aspect ratio
    /// is closest to the actual display, minimizing image distortion.
    private func bestComputerUseResolution(
        forDisplayWidth displayWidth: Int,
        displayHeight: Int
    ) -> (width: Int, height: Int) {
        let displayAspectRatio = Double(displayWidth) / Double(max(1, displayHeight))

        var bestWidth = 1280
        var bestHeight = 800
        var smallestAspectRatioDifference = Double.greatestFiniteMagnitude

        for resolution in Self.supportedComputerUseResolutions {
            let difference = abs(displayAspectRatio - resolution.aspectRatio)
            if difference < smallestAspectRatioDifference {
                smallestAspectRatioDifference = difference
                bestWidth = resolution.width
                bestHeight = resolution.height
            }
        }

        return (width: bestWidth, height: bestHeight)
    }

    /// Calls the Claude Computer Use API with a resized screenshot and user question.
    /// Returns the raw coordinate from Claude's response in the declared resolution space, or nil.
    private func callComputerUseAPI(
        resizedScreenshotData: Data,
        userQuestion: String,
        declaredDisplayWidth: Int,
        declaredDisplayHeight: Int
    ) async -> CGPoint? {
        var request: URLRequest
        do {
            // Arrives with its credentials already attached and checked. This
            // detector never learns which route it is on, and never sees a key.
            request = try await makeValidatedRequest()
        } catch {
            return nil
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        // The beta header activates Computer Use capabilities and the specialized
        // pixel-counting training that makes coordinate detection accurate.
        // It is model-specific; a single hard-coded value makes Haiku fail with
        // a 400 before it can ever answer.
        let computerUseVariant = Self.computerUseVariant(forModel: model)
        // Claude Code OAuth requests already carry Anthropic's OAuth beta. Keep
        // it and add the Computer Use beta rather than replacing it, otherwise
        // the spatial call is rejected even though ordinary chat works.
        let existingBeta = request.value(forHTTPHeaderField: "anthropic-beta")
        let betaHeader = [existingBeta, computerUseVariant.betaHeader]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")

        // Detect image media type (PNG vs JPEG)
        let mediaType = detectImageMediaType(for: resizedScreenshotData)
        let base64Screenshot = resizedScreenshotData.base64EncodedString()

        let userPrompt = """
        The image is a screenshot that has already been captured. Do not call the screenshot action.

        The user asked: "\(userQuestion)"

        If the requested control is visible, respond with one computer tool call using a
        pointing action at the centre of that control. If it is not visible, respond with
        the text "not found" and make no tool call. Do not use scroll or drag as a substitute
        for a point, and do not invent a coordinate.
        """

        // The funded route pins the model server-side. Sending a model field to
        // it is misleading and can make a strict proxy reject this otherwise
        // valid computer-use request. Direct Anthropic requests must name the
        // selected model.
        let destinationIsAnthropic = request.url?.host?.lowercased() == AssistantTransport.anthropicAPIHost

        var body: [String: Any] = [
            // Haiku often writes a short preamble before its tool call. 256
            // tokens truncates that preamble and produces a false "no point";
            // the bounded 1024-token ceiling still keeps this one-purpose call
            // small while leaving room for the structured action.
            "max_tokens": 1024,
            "tools": [
                [
                    "type": computerUseVariant.toolType,
                    "name": "computer",
                    "display_width_px": declaredDisplayWidth,
                    "display_height_px": declaredDisplayHeight
                ]
            ],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": mediaType,
                                "data": base64Screenshot
                            ]
                        ],
                        [
                            "type": "text",
                            "text": userPrompt
                        ]
                    ]
                ]
            ]
        ]
        if destinationIsAnthropic {
            body["model"] = model
        }

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = bodyData

            let payloadMB = Double(bodyData.count) / 1_048_576.0
            print("🎯 ElementLocationDetector: sending \(String(format: "%.1f", payloadMB))MB request " +
                  "(declared \(declaredDisplayWidth)x\(declaredDisplayHeight))")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                print("⚠️ ElementLocationDetector: API error \(statusCode): \(errorBody.prefix(200))")
                return nil
            }

            let parsed = Self.parseResponse(data: data)
            reportSpend(model, parsed.usage, Self.spendRoute(for: request))
            return parsed.coordinate

        } catch {
            print("⚠️ ElementLocationDetector: request failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Parses both response shapes used by the two supported transports:
    /// direct Anthropic can return JSON, while publik's funded proxy streams
    /// the identical Messages response as SSE. A plain JSON-only parser made
    /// the dedicated spatial model look dead on the funded tier even when the
    /// model had returned a valid computer tool call.
    static func parseCoordinateFromResponse(data: Data) -> CGPoint? {
        parseResponse(data: data).coordinate
    }

    private struct ParsedResponse {
        let coordinate: CGPoint?
        let usage: AssistantTokenUsage
    }

    private static func parseResponse(data: Data) -> ParsedResponse {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let contentBlocks = json["content"] as? [[String: Any]] {
            return ParsedResponse(
                coordinate: coordinateFromContentBlocks(contentBlocks),
                usage: usageFromJSON(json)
            )
        }

        var accumulator = ClaudeSSEMessageAccumulator()
        let body = String(decoding: data, as: UTF8.self)
        for line in body.split(whereSeparator: \.isNewline) {
            _ = accumulator.consume(line: String(line))
        }
        let streamedMessage = accumulator.finalize()
        for toolUse in streamedMessage.toolUses {
            guard let input = toolUse.inputObject,
                  let action = input["action"] as? String,
                  isPointingAction(action),
                  let coordinate = input["coordinate"] as? [NSNumber],
                  coordinate.count == 2 else { continue }
            let point = CGPoint(x: CGFloat(coordinate[0].doubleValue), y: CGFloat(coordinate[1].doubleValue))
            print("🎯 ElementLocationDetector: raw coordinate (\(Int(point.x)), \(Int(point.y)))")
            return ParsedResponse(coordinate: point, usage: accumulator.usage)
        }

        print("🎯 ElementLocationDetector: no pointing tool call in response")
        return ParsedResponse(coordinate: nil, usage: accumulator.usage)
    }

    private static func usageFromJSON(_ json: [String: Any]) -> AssistantTokenUsage {
        guard let usage = json["usage"] as? [String: Any] else { return AssistantTokenUsage() }
        return AssistantTokenUsage(
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            cacheWriteTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0
        )
    }

    private static func spendRoute(for request: URLRequest) -> AssistantSpendRoute {
        if request.value(forHTTPHeaderField: "x-api-key") != nil {
            return .theReadersOwnAPIKey
        }
        if request.value(forHTTPHeaderField: "anthropic-beta")?.contains("oauth") == true {
            return .aFlatRateSubscription
        }
        return .publiksFundedTier
    }

    private static func coordinateFromContentBlocks(_ contentBlocks: [[String: Any]]) -> CGPoint? {
        for block in contentBlocks {
            guard block["type"] as? String == "tool_use",
                  let input = block["input"] as? [String: Any],
                  let action = input["action"] as? String,
                  isPointingAction(action),
                  let coordinate = input["coordinate"] as? [NSNumber],
                  coordinate.count == 2 else { continue }
            let point = CGPoint(x: CGFloat(coordinate[0].doubleValue), y: CGFloat(coordinate[1].doubleValue))
            print("🎯 ElementLocationDetector: raw coordinate (\(Int(point.x)), \(Int(point.y)))")
            return point
        }
        print("🎯 ElementLocationDetector: no pointing tool call in response")
        return nil
    }

    /// Resizes screenshot data to the specified Computer Use resolution.
    /// The target resolution should match the display's aspect ratio to avoid
    /// distortion that degrades coordinate accuracy.
    ///
    /// **Critical Retina fix**: Uses `NSBitmapImageRep` directly instead of
    /// `NSImage.lockFocus()`. On Retina displays (2x backing scale), lockFocus
    /// creates a bitmap at 2× the declared size (e.g., 2560×1600 for a 1280×800
    /// NSImage). This means the JPEG sent to Claude would be 2× larger than the
    /// resolution declared in the Computer Use tool definition, causing Claude's
    /// pixel-counting to return coordinates in the wrong scale.
    private func resizeScreenshotForComputerUse(
        originalImageData: Data,
        targetWidth: Int,
        targetHeight: Int
    ) -> Data? {
        guard let originalImage = NSImage(data: originalImageData) else { return nil }

        // Create a bitmap representation with exact pixel dimensions.
        // This bypasses NSImage's Retina-aware coordinate system which would
        // otherwise double the actual pixel count on 2x displays.
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        // Set the point size to match pixel dimensions (1:1, no Retina scaling).
        bitmapRep.size = NSSize(width: targetWidth, height: targetHeight)

        // Draw the original image into the exact-pixel-dimension bitmap
        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current = graphicsContext
        graphicsContext?.imageInterpolation = .high
        originalImage.draw(
            in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            from: NSRect(origin: .zero, size: originalImage.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return nil
        }

        return jpegData
    }

    /// Detects MIME type by inspecting the first bytes of image data.
    private func detectImageMediaType(for imageData: Data) -> String {
        if imageData.count >= 4 {
            let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
            let firstFourBytes = [UInt8](imageData.prefix(4))
            if firstFourBytes == pngSignature {
                return "image/png"
            }
        }
        return "image/jpeg"
    }
}
